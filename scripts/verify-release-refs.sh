#!/bin/bash
set -euo pipefail

tag=${1:-}
[[ "$GITHUB_EVENT_NAME" == workflow_dispatch && "$GITHUB_REF" == refs/heads/main ]] ||
  { echo 'Production releases require a manual run on main.' >&2; exit 1; }
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  { echo 'Expected a macOS version tag (vX.Y.Z).' >&2; exit 1; }

repo="repos/$GITHUB_REPOSITORY/git"
main=$(gh api "$repo/ref/heads/main" --jq '.object.sha')
[[ "$main" == "$GITHUB_SHA" ]] ||
  { echo 'main moved since this run started. Review the new tip before releasing.' >&2; exit 1; }

for ref in "$tag" "windows-$tag"; do
  object=$(gh api "$repo/ref/tags/$ref" --jq 'select(.object.type == "tag") | .object.sha')
  [[ "$object" =~ ^[0-9a-f]{40}$ ]] ||
    { echo "$ref must be an annotated tag." >&2; exit 1; }
  gh api "$repo/tags/$object" |
    jq -e --arg sha "$GITHUB_SHA" --arg ref "$ref" \
      '.verification.verified == true and .tag == $ref and .object.type == "commit" and .object.sha == $sha' >/dev/null ||
    { echo "$ref must have a verified signature and point directly to this main commit." >&2; exit 1; }
done
