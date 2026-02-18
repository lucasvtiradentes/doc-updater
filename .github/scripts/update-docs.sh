#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_MERGE_DAYS="${AUTO_MERGE_DAYS:-3}"
GIT_REF="${GIT_REF:---since-lock}"
BRANCH=""
IS_NEW_PR=true
PR_NUMBER=""
PR_AGE_DAYS=0

setup_git() {
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
}

find_existing_pr() {
  local pr
  pr=$(gh pr list --search "docs: update documentation" --state open --json number,headRefName,createdAt --jq '.[0]' 2>/dev/null || echo "")

  if [[ -n "$pr" && "$pr" != "null" ]]; then
    PR_NUMBER=$(echo "$pr" | jq -r '.number')
    BRANCH=$(echo "$pr" | jq -r '.headRefName')
    IS_NEW_PR=false

    local created_at created_ts
    created_at=$(echo "$pr" | jq -r '.createdAt')
    created_ts=$(date -d "$created_at" +%s)
    PR_AGE_DAYS=$(( ($(date +%s) - created_ts) / 86400 ))

    echo "Found existing docs PR #$PR_NUMBER on branch: $BRANCH (${PR_AGE_DAYS} days old)"
  else
    BRANCH="docs/auto-update-$(date +%Y%m%d-%H%M%S)"
    echo "No existing docs PR found, will create branch: $BRANCH"
  fi
}

checkout_existing_branch() {
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git merge -X theirs origin/main --no-edit
}

run_claude_update() {
  "$SCRIPT_DIR/run-claude.sh" "/update-docs $GIT_REF"
}

commit_changes() {
  if git diff --quiet && git diff --staged --quiet; then
    echo "No changes detected, skipping"
    return 1
  fi

  git add -A
  git commit -m "docs: update documentation"
}

push_and_create_pr() {
  git checkout -b "$BRANCH" 2>/dev/null || true
  git push origin "$BRANCH"

  local stat
  stat=$(git diff HEAD~1 --stat)
  gh pr create \
    --title "docs: update documentation" \
    --body "Automated docs update"$'\n\n'"\`\`\`"$'\n'"$stat"$'\n'"\`\`\`" \
    --base main \
    --head "$BRANCH"
  echo "Created new PR"
}

push_to_existing_pr() {
  git push origin "$BRANCH"
  echo "Pushed updates to existing PR"

  if [[ "$AUTO_MERGE_DAYS" -gt 0 && "$PR_AGE_DAYS" -ge "$AUTO_MERGE_DAYS" ]]; then
    echo "PR #$PR_NUMBER is ${PR_AGE_DAYS} days old, auto-merging into main"
    gh pr merge "$PR_NUMBER" --squash --delete-branch
  fi
}

main() {
  setup_git
  find_existing_pr

  if [[ "$IS_NEW_PR" == false ]]; then
    checkout_existing_branch
  fi

  run_claude_update
  commit_changes || exit 0

  if [[ "$IS_NEW_PR" == true ]]; then
    push_and_create_pr
  else
    push_to_existing_pr
  fi
}

main
