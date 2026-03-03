#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
GIT_REF="${GIT_REF:-docs-base}"
BRANCH=""
IS_NEW_PR=true
PR_NUMBER=""

setup_git() {
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  mkdir -p .git/info
  echo ".doctrace/" >> .git/info/exclude
}

install_skill() {
  echo "Looking for skill at: $SCRIPT_DIR/commands/update-docs.md"
  if [[ -f "$SCRIPT_DIR/commands/update-docs.md" ]]; then
    mkdir -p .claude/commands
    cp "$SCRIPT_DIR/commands/update-docs.md" .claude/commands/update-docs.md
    echo "Installed skill to .claude/commands/update-docs.md"
  else
    echo "WARNING: Skill file not found!"
    ls -la "$SCRIPT_DIR/" || true
    ls -la "$SCRIPT_DIR/commands/" || true
  fi
}

find_existing_pr() {
  local pr
  pr=$(gh pr list --state open --json number,headRefName --jq '[.[] | select(.headRefName | startswith("docs/auto-update"))][0]' 2>/dev/null || echo "")

  if [[ -n "$pr" && "$pr" != "null" ]]; then
    PR_NUMBER=$(echo "$pr" | jq -r '.number')
    BRANCH=$(echo "$pr" | jq -r '.headRefName')
    IS_NEW_PR=false
    echo "Found existing docs PR #$PR_NUMBER on branch: $BRANCH"
  else
    BRANCH="docs/auto-update-$(date +%Y%m%d-%H%M%S)"
    echo "No existing docs PR found, will create branch: $BRANCH"
  fi
}

save_existing_pr_body() {
  if [[ "$IS_NEW_PR" == false && -n "$PR_NUMBER" ]]; then
    echo "Saving existing PR #$PR_NUMBER body for merge..."
    mkdir -p .doctrace
    gh pr view "$PR_NUMBER" --json body --jq '.body' > .doctrace/existing-pr-body.md 2>/dev/null || true
  fi
}

checkout_existing_branch() {
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git merge -X theirs origin/main --no-edit || {
    git diff --name-only --diff-filter=U | while read -r file; do
      if git show origin/main:"$file" &>/dev/null; then
        git checkout --theirs "$file"
        git add "$file"
      else
        git rm "$file"
      fi
    done
    git commit --no-edit
  }
}

run_claude_update() {
  echo "=== Running Claude update ==="
  echo "GIT_REF: $GIT_REF"
  echo "Command: /update-docs $GIT_REF"
  ls -la .claude/commands/ || true
  echo "=== Claude output start ==="
  claudep --model claude-opus-4-6 -p "/update-docs $GIT_REF"
  echo "=== Claude output end ==="
}

update_base_tag() {
  local current_base head_sha
  current_base=$(git rev-parse docs-base 2>/dev/null || echo "none")
  head_sha=$(git rev-parse HEAD)

  if [[ "$current_base" != "$head_sha" ]]; then
    git tag -f docs-base HEAD
    git push -f origin docs-base 2>/dev/null || echo "Warning: Could not push docs-base tag"
    echo "Updated docs-base tag: ${current_base:0:7} -> ${head_sha:0:7}"
  else
    echo "docs-base tag already at HEAD"
  fi
}

append_no_changes_to_pr() {
  local existing_body run_date new_body
  existing_body=$(gh pr view "$PR_NUMBER" --json body --jq '.body' 2>/dev/null || echo "")
  run_date=$(date -u +"%Y-%m-%d %H:%M UTC")

  new_body="${existing_body}

---

## Run - ${run_date}

No changes needed - docs are up to date."

  gh pr edit "$PR_NUMBER" --body "$new_body" 2>/dev/null || echo "Warning: Could not update PR description"
  echo "Appended no-change note to PR #$PR_NUMBER"

  local unpushed
  unpushed=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "0")
  if [[ "$unpushed" != "0" ]]; then
    git push origin "$BRANCH"
  fi
  update_base_tag
}

get_pr_title() {
  local pr_title_file=".doctrace/pr-title.md"
  if [[ -f "$pr_title_file" ]]; then
    cat "$pr_title_file"
  else
    echo "docs: update documentation"
  fi
}

get_pr_body() {
  local pr_body_file=".doctrace/pr-body.md"

  if [[ -f "$pr_body_file" ]]; then
    cat "$pr_body_file"
  else
    echo "Automated docs update"
  fi
}

push_and_create_pr() {
  git checkout -b "$BRANCH" 2>/dev/null || true
  git tag -f docs-base HEAD
  git push origin "$BRANCH"
  git push -f origin docs-base 2>/dev/null || echo "Warning: Could not push docs-base tag"

  local title body pr_url
  title=$(get_pr_title)
  body=$(get_pr_body)

  pr_url=$(gh pr create \
    --title "$title" \
    --body "$body" \
    --base main \
    --head "$BRANCH" 2>&1) || true

  local existing_pr
  existing_pr=$(gh pr view "$BRANCH" --json url --jq '.url' 2>/dev/null || echo "")

  if [[ -n "$existing_pr" ]]; then
    echo "PR created: $existing_pr"
  else
    echo "Error: Failed to create PR and no existing PR found"
    exit 1
  fi
}

push_to_existing_pr() {
  git tag -f docs-base HEAD
  git push origin "$BRANCH"
  git push -f origin docs-base 2>/dev/null || echo "Warning: Could not push docs-base tag"

  local title body
  title=$(get_pr_title)
  body=$(get_pr_body)

  gh pr edit "$PR_NUMBER" --title "$title" --body "$body" 2>/dev/null || echo "Warning: Could not update PR description"
  echo "Pushed updates to existing PR #$PR_NUMBER"
}

main() {
  setup_git
  find_existing_pr
  save_existing_pr_body

  if [[ "$IS_NEW_PR" == false ]]; then
    checkout_existing_branch
  fi

  install_skill

  local head_before
  head_before=$(git rev-parse HEAD)

  run_claude_update

  local head_after
  head_after=$(git rev-parse HEAD)

  if [[ "$head_before" != "$head_after" ]]; then
    if [[ "$IS_NEW_PR" == true ]]; then
      push_and_create_pr
    else
      push_to_existing_pr
    fi
  else
    if [[ "$IS_NEW_PR" == true ]]; then
      echo "No changes detected, updating base tag only"
      update_base_tag
    else
      echo "No new changes from Claude"
      append_no_changes_to_pr
    fi
  fi
}

main
