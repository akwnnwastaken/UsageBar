#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
export PATH="$temp:$PATH"
export GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main GITHUB_REPOSITORY=example/usagebar
export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
export MAC_OBJECT=1111111111111111111111111111111111111111 WIN_OBJECT=2222222222222222222222222222222222222222

cat > "$temp/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$2" in
  */ref/heads/main) echo "${REMOTE_MAIN:-$GITHUB_SHA}" ;;
  */ref/tags/v2.5.0) echo "$MAC_OBJECT" ;;
  */ref/tags/windows-v2.5.0)
    case "${WINDOWS:-}" in
      missing) exit 1 ;;
      lightweight) exit 0 ;;
    esac
    echo "$WIN_OBJECT"
    ;;
  */tags/"$MAC_OBJECT")
    jq -n --arg sha "$GITHUB_SHA" '{tag:"v2.5.0",verification:{verified:true},object:{type:"commit",sha:$sha}}'
    ;;
  */tags/"$WIN_OBJECT")
    jq -n --arg sha "${WINDOWS_SHA:-$GITHUB_SHA}" --arg tag "${WINDOWS_TAG:-windows-v2.5.0}" \
      --argjson verified "${WINDOWS_VERIFIED:-true}" \
      '{tag:$tag,verification:{verified:$verified},object:{type:"commit",sha:$sha}}'
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

bash scripts/verify-release-refs.sh v2.5.0
reject bash scripts/verify-release-refs.sh windows-v2.5.0
reject env GITHUB_EVENT_NAME=pull_request bash scripts/verify-release-refs.sh v2.5.0
reject env GITHUB_REF=refs/heads/topic bash scripts/verify-release-refs.sh v2.5.0
reject env REMOTE_MAIN="$WIN_OBJECT" bash scripts/verify-release-refs.sh v2.5.0
reject env WINDOWS=missing bash scripts/verify-release-refs.sh v2.5.0
reject env WINDOWS=lightweight bash scripts/verify-release-refs.sh v2.5.0
reject env WINDOWS_VERIFIED=false bash scripts/verify-release-refs.sh v2.5.0
reject env WINDOWS_SHA="$WIN_OBJECT" bash scripts/verify-release-refs.sh v2.5.0
reject env WINDOWS_TAG=v2.5.0 bash scripts/verify-release-refs.sh v2.5.0
echo 'Release ref tests passed.'
