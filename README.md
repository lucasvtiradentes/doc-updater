# doc-updater

Reusable GitHub workflow that automatically updates documentation using Claude Code.

## Quick Start

Add this workflow to your repo:

```yaml
# .github/workflows/update-docs.yml
name: Update Docs

on:
  schedule:
    - cron: "0 0 * * *"  # daily
  workflow_dispatch:

jobs:
  update:
    uses: lucasvtiradentes/doc-updater/.github/workflows/update-docs.yml@main
    with:
      docs_path: docs/
      mode: smart
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `docs_path` | `docs/` | Path to documentation directory |
| `mode` | `smart` | `smart`, `legacy`, or `custom` |
| `custom_skill` | `.claude/commands/update-docs.md` | Path to custom skill (when mode=custom) |
| `auto_merge_days` | `3` | Auto-merge PR after N days (0 to disable) |
| `git_ref` | `--since-lock` | Git ref for smart mode |

## Modes

### Smart Mode (recommended)

Uses [doctrace](https://github.com/lucasvtiradentes/doctrace) to detect which docs are affected by code changes. Only updates what's needed.

Requirements:
- `pip install doctrace`
- Docs must have `related sources:` metadata

### Legacy Mode

Reads ALL source files and compares against ALL docs. Use when doctrace is not set up.

### Custom Mode

Uses a skill file from your own repo. Useful when you have project-specific update logic.

```yaml
jobs:
  update:
    uses: lucasvtiradentes/doc-updater/.github/workflows/update-docs.yml@main
    with:
      mode: custom
      custom_skill: .claude/commands/my-update-docs.md
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## How It Works

1. Workflow runs on schedule or manual trigger
2. Downloads scripts from this repo
3. Loads skill (from this repo or custom from caller repo)
4. Runs Claude Code with the update-docs skill
5. Creates/updates PR with changes
6. Auto-merges after configured days (optional)

## Secrets Required

| Secret | Description |
|--------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token |

## PR Behavior

- Creates new PR if none exists
- Updates existing PR if one is open
- Auto-merges after N days (configurable)
- Squash merge with branch deletion
