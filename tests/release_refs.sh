#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
export PATH="$temp:$PATH"
export GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main GITHUB_REPOSITORY=example/usagebar
export GITHUB_REF_PROTECTED=true
export GITHUB_ACTOR_ID=42 GITHUB_REPOSITORY_OWNER_ID=42
export GITHUB_TRIGGERING_ACTOR=example GITHUB_REPOSITORY_OWNER=example
export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
export MAC_OBJECT=1111111111111111111111111111111111111111 WIN_OBJECT=2222222222222222222222222222222222222222

cat > "$temp/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$2" in
  */ref/heads/main) echo "${REMOTE_MAIN:-$GITHUB_SHA}" ;;
  */ref/tags/v2.5.0|*/ref/tags/windows-v2.5.0)
    tag=${2##*/}
    [[ -z "${EXPECTED_TAG:-}" || "$tag" == "$EXPECTED_TAG" ]] || {
      touch "$MOCK_UNEXPECTED_TAG"
      exit 1
    }
    case "${TAG_STATE:-}" in
      missing) exit 1 ;;
      lightweight) exit 0 ;;
    esac
    if [[ "$tag" == v2.5.0 ]]; then echo "$MAC_OBJECT"; else echo "$WIN_OBJECT"; fi
    ;;
  */tags/"$MAC_OBJECT"|*/tags/"$WIN_OBJECT")
    if [[ "$2" == */"$MAC_OBJECT" ]]; then tag=v2.5.0; else tag=windows-v2.5.0; fi
    jq -n --arg sha "${TAG_SHA:-$GITHUB_SHA}" --arg tag "${TAG_NAME:-$tag}" \
      --arg type "${TAG_TARGET_TYPE:-commit}" --argjson verified "${TAG_VERIFIED:-true}" \
      '{tag:$tag,verification:{verified:$verified},object:{type:$type,sha:$sha}}'
    ;;
  */environments/macos-production-signing)
    case "${ENVIRONMENT:-}" in
      missing) exit 1 ;;
      reviewers) echo '{"deployment_branch_policy":{"custom_branch_policies":true,"protected_branches":false},"protection_rules":[{"type":"required_reviewers","reviewers":[{}]}]}' ;;
      unrestricted) echo '{"deployment_branch_policy":null,"protection_rules":[]}' ;;
      protected-branches) echo '{"deployment_branch_policy":{"custom_branch_policies":false,"protected_branches":true},"protection_rules":[]}' ;;
      *) echo '{"deployment_branch_policy":{"custom_branch_policies":true,"protected_branches":false},"protection_rules":[{"type":"branch_policy"}]}' ;;
    esac
    ;;
  */deployment-branch-policies)
    case "${ENVIRONMENT:-}" in
      wrong-ref) echo '{"total_count":1,"branch_policies":[{"name":"main","type":"tag"}]}' ;;
      extra-ref) echo '{"total_count":2,"branch_policies":[{"name":"main","type":"branch"},{"name":"*","type":"tag"}]}' ;;
      *) echo '{"total_count":1,"branch_policies":[{"name":"main","type":"branch"}]}' ;;
    esac
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$temp/gh"

reject() {
  if "$@" > "$temp/last.log" 2>&1; then
    echo 'Expected release validation to reject this case.' >&2
    exit 1
  fi
}

export MOCK_UNEXPECTED_TAG="$temp/unexpected-tag"
# Each platform can release with only its own tag available.
for platform in macos windows; do
  tag=v2.5.0
  if [[ "$platform" == windows ]]; then tag=windows-v2.5.0; fi
  verify=(bash scripts/verify-release-refs.sh "$platform" "$tag")
  EXPECTED_TAG="$tag" "${verify[@]}" "$GITHUB_SHA"
  for state in missing lightweight; do
    reject env TAG_STATE="$state" "${verify[@]}" "$GITHUB_SHA"
  done
  reject env TAG_VERIFIED=false "${verify[@]}" "$GITHUB_SHA"
  reject env TAG_TARGET_TYPE=tag "${verify[@]}" "$GITHUB_SHA"
  reject env TAG_SHA="$WIN_OBJECT" "${verify[@]}" "$GITHUB_SHA"
  reject env TAG_NAME=v9.9.9 "${verify[@]}" "$GITHUB_SHA"
  reject env GITHUB_EVENT_NAME=pull_request "${verify[@]}" "$GITHUB_SHA"
  reject env GITHUB_REF=refs/heads/topic "${verify[@]}" "$GITHUB_SHA"
  reject env GITHUB_REF_PROTECTED=false "${verify[@]}" "$GITHUB_SHA"
  reject env REMOTE_MAIN="$WIN_OBJECT" "${verify[@]}" "$GITHUB_SHA"
  reject env GITHUB_ACTOR_ID=99 "${verify[@]}" "$GITHUB_SHA"
  reject env GITHUB_TRIGGERING_ACTOR=collaborator "${verify[@]}" "$GITHUB_SHA"
  reject "${verify[@]}"
  reject "${verify[@]}" "${GITHUB_SHA:0:7}"
  reject "${verify[@]}" "$WIN_OBJECT"
done
test ! -e "$MOCK_UNEXPECTED_TAG"
reject bash scripts/verify-release-refs.sh macos windows-v2.5.0 "$GITHUB_SHA"
reject bash scripts/verify-release-refs.sh windows v2.5.0 "$GITHUB_SHA"
reject bash scripts/verify-release-refs.sh linux v2.5.0 "$GITHUB_SHA"
bash scripts/verify-signing-environment.sh
for environment in missing unrestricted protected-branches reviewers wrong-ref extra-ref; do
  reject env ENVIRONMENT="$environment" bash scripts/verify-signing-environment.sh
done
echo 'Release ref and environment tests passed.'
