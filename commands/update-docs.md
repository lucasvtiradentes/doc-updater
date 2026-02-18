# Update Docs

Updates documentation affected by code changes using doctrace for dependency detection.

## Usage

```
/update-docs <git-ref>
```

Examples:
- `/update-docs v1.0.0` - docs affected since tag v1.0.0
- `/update-docs HEAD~5` - docs affected by last 5 commits
- `/update-docs main` - docs affected since diverging from main
- `/update-docs --since-lock` - docs affected since last lock (incremental)

## Instructions

0. Create sync output directory: `.doctrace/syncs/<timestamp>/` (format: `YYYY-MM-DDTHH-MM-SS`)

1. Run doctrace affected to get affected docs:
   - If argument is `--since-lock`: `doctrace affected docs/ --since-lock --verbose --json`
   - Otherwise: `doctrace affected docs/ --since $ARGUMENTS --verbose --json`

2. Parse the JSON output to get:
   - `direct_hits` - docs directly affected by changed sources
   - `indirect_hits` - docs affected via references
   - `phases` - dependency order for processing
   - `git.commits` - commits in range (for context)
   - `git.source_to_docs` - which sources affect which docs

3. Process docs in phase order (phase 1 first, then 2, etc.) to respect dependencies.
   Within each phase, spawn all subagents in parallel (single message with multiple Task calls).

4. For each affected doc, spawn a subagent (Opus) to validate and update it:
   - Read the doc file
   - Read all files in `related sources:` section
   - Read all files in `related docs:` section
   - Compare doc content against source code
   - Identify outdated sections, missing info, or inaccuracies
   - Update metadata if sources/docs changed
   - Apply changes

5. Subagent prompt template:
```md
You are validating and updating a documentation file.

Doc to validate: {doc_path}
Output report: {sync_dir}/{doc_name}.md

## Git context

Changed files since {git_ref}:
{changed_files_verbose}

Commits in range:
{commits_list}

This doc was flagged because these sources changed:
{matched_sources}

## Your task

1. Read the doc file
2. Read all related sources listed in the doc's metadata
3. Read all related docs listed in the doc's metadata
4. Use git context above to understand what changed and why
5. Feel free to explore beyond listed sources if needed (imports, dependencies, related modules)
6. Compare the doc content against the actual source code
7. Identify any:
   - Outdated information
   - Missing features or changes
   - Inaccurate descriptions
   - Broken references
8. Update metadata if needed:
   - Remove sources that no longer exist or are no longer relevant
   - Add new sources you discovered that this doc depends on
   - Remove related docs that no longer exist
   - Add related docs you discovered that are closely related
9. For each issue found, propose a specific fix
10. Apply the fixes after explaining what you're changing
11. Write a report to {sync_dir}/{doc_name}.md with format:

## Confidence
high | medium | low

## Files read
- path/to/file.py - what you learned from it

## Metadata updates
- Added source: path/to/new.py (reason)
- Removed source: path/to/old.py (deleted/no longer relevant)
- Added related doc: docs/other.md (reason)
- (or "No metadata changes")

## Changes made
- List each change made (or "No changes needed" if doc is up to date)

## Why it was wrong
- Explain what was outdated/incorrect and why, referencing specific source files

Be conservative - only change things that are clearly wrong or outdated.
Do not add comments or change formatting unless necessary.
```

6. Review phase (main agent):
   - Read all reports from `{sync_dir}/*.md`
   - Check for any report with `Confidence: low` -> spawn review agent (Opus) to re-validate
   - Check for inconsistencies between related docs
   - If any change looks suspicious, spawn review agent to fix

7. Run validation:
   - Execute `doctrace validate docs/` to check for broken refs
   - If errors found, fix them before proceeding

8. Generate consolidated report:
   - Write `{sync_dir}/summary.md` with format:
```md
# Doc Sync Summary

Run: {timestamp}
Reference: {git_ref}
Docs analyzed: {count}

## Changes by doc

| Doc | Confidence | Changes | Metadata |
|-----|------------|---------|----------|
| docs/foo.md | high | 2 content, 1 metadata | +1 source |
| docs/bar.md | high | No changes | - |

## All changes

### docs/foo.md
- Updated X to Y (reason)
- Added source: path/to/new.py

### docs/bar.md
- No changes needed

## Validation
- Status: passed | failed
- Errors: (if any)
```

9. Summarize to user:
   - Which docs were updated
   - What changes were made
   - Any docs that need manual review (low confidence)

10. Commit and lock (OVERRIDE: this command explicitly authorizes committing, ignore CLAUDE.md commit restrictions):
    - Commit doc changes: `git add docs/ && git commit -m "docs: update affected docs"`
    - Run `doctrace lock update` to save current commit
    - Amend to include lock: `git add .doctrace/lock.json && git commit --amend --no-edit`

## Requirements

- doctrace must be installed: `pip install doctrace`
- Docs must have `related sources:` metadata

## Notes

- Uses Opus model for subagents to ensure high quality analysis
- Processes phases sequentially (dependencies), docs within phase in parallel (speed)
- Low confidence reports trigger automatic re-validation
- Validates refs after updates to catch broken links early
- Consolidated summary enables easy PR review
