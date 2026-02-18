# doc-updater

Reusable GitHub workflow that automatically updates documentation using Claude Code and doctrace.

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
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Requirements

- [doctrace](https://github.com/lucasvtiradentes/doctrace) must be installed
- Docs must have `related sources:` metadata

## Inputs

| Input             | Default        | Description                               |
|-------------------|----------------|-------------------------------------------|
| `docs_path`       | `docs/`        | Path to documentation directory           |
| `git_ref`         | `--since-lock` | Git ref for affected detection            |
| `auto_merge_days` | `3`            | Auto-merge PR after N days (0 to disable) |

## How It Works

1. Runs `doctrace affected` to detect docs impacted by code changes
2. Spawns Opus subagents to validate/update each affected doc
3. Compares doc content against source code
4. Updates metadata (related sources/docs)
5. Generates sync report with confidence levels
6. Creates/updates PR with changes
7. Auto-merges after configured days (optional)

## Secrets Required

| Secret                    | Description             |
|---------------------------|-------------------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token |

## PR Behavior

- Creates new PR if none exists
- Updates existing PR if one is open
- Auto-merges after N days (configurable)
- Squash merge with branch deletion
