#!/bin/bash
set -euo pipefail

environment="repos/$GITHUB_REPOSITORY/environments/macos-production-signing"
gh api "$environment" | jq -e '
  .deployment_branch_policy.custom_branch_policies == true and
  .deployment_branch_policy.protected_branches == false and
  all(.protection_rules[]; .type != "required_reviewers")
' >/dev/null || {
  echo 'Configure macos-production-signing with selected branches and tags and leave Required reviewers unset.' >&2
  exit 1
}

gh api "$environment/deployment-branch-policies" | jq -e '
  .total_count == 1 and [.branch_policies[] | {name,type}] == [{name:"main",type:"branch"}]
' >/dev/null || {
  echo 'Only the main branch may deploy to macos-production-signing.' >&2
  exit 1
}
