#!/bin/bash
set -euo pipefail

case "${1:-}" in
  macos) prefix=v ;;
  windows) prefix=windows-v ;;
  *) echo 'Expected release platform: macos or windows.' >&2; exit 1 ;;
esac
tag=${2:-}
release_sha=${3:-}
[[ "$GITHUB_EVENT_NAME" == workflow_dispatch &&
   "$GITHUB_REF" == refs/heads/main && "$GITHUB_REF_PROTECTED" == true ]] ||
  { echo 'Production releases require a manual run on protected main.' >&2; exit 1; }
[[ "$GITHUB_ACTOR_ID" == "$GITHUB_REPOSITORY_OWNER_ID" &&
   "$GITHUB_TRIGGERING_ACTOR" == "$GITHUB_REPOSITORY_OWNER" ]] ||
  { echo 'Only the personal repository owner may start or retry production releases.' >&2; exit 1; }
[[ "$release_sha" =~ ^[0-9a-f]{40}$ && "$release_sha" == "$GITHUB_SHA" ]] ||
  { echo 'Enter the full approved SHA that matches this workflow run.' >&2; exit 1; }
[[ "$tag" =~ ^${prefix}[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  { echo 'Expected a version tag for this platform.' >&2; exit 1; }

repo="repos/$GITHUB_REPOSITORY/git"
main=$(gh api "$repo/ref/heads/main" --jq '.object.sha')
[[ "$main" == "$GITHUB_SHA" ]] ||
  { echo 'main moved since this run started. Review the new tip before releasing.' >&2; exit 1; }

object=$(gh api "$repo/ref/tags/$tag" --jq 'select(.object.type == "tag") | .object.sha')
[[ "$object" =~ ^[0-9a-f]{40}$ ]] ||
  { echo "$tag must be an annotated tag." >&2; exit 1; }
gh api "$repo/tags/$object" |
  jq -e --arg sha "$GITHUB_SHA" --arg tag "$tag" \
    '.verification.verified == true and .tag == $tag and .object.type == "commit" and .object.sha == $sha' >/dev/null ||
  { echo "$tag must have a verified signature and point directly to this main commit." >&2; exit 1; }
