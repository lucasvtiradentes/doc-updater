# Update Docs

Update docs affected by recent commits. Uses doctrace for dependency detection.

## Usage

```
/update-docs <git-ref>
```

Examples:
- `/update-docs docs-base`    - docs affected since last sync (incremental)
- `/update-docs v1.0.0`       - docs affected since tag v1.0.0
- `/update-docs HEAD~5`       - docs affected by last 5 commits
- `/update-docs main`         - docs affected since diverging from main

## Instructions

0. Create sync output directory: `.doctrace/syncs/<timestamp>/` (format: `YYYY-MM-DDTHH-MM-SS`)

1. Run doctrace affected to get affected docs:
   ```bash
   doctrace affected docs/ --since $ARGUMENTS --json
   ```

2. Parse the JSON output to get:
   - `direct_hits`        - docs directly affected by changed sources
   - `indirect_hits`      - docs affected via references
   - `phases`             - dependency order for processing
   - `git.commits`        - commits in range (for context)
   - `git.source_to_docs` - which sources affect which docs

3. Process docs in phase order (phase 1 first, then 2, etc.) to respect dependencies.

   **CRITICAL: PARALLEL EXECUTION REQUIRED**
   Within each phase, you MUST spawn ALL subagents in a SINGLE message with multiple Task tool calls.
   DO NOT wait for one Task to complete before spawning the next - this causes 30+ minute timeouts.
   Example: If phase 1 has 5 docs, send ONE message with 5 Task tool calls, not 5 separate messages.

4. For each affected doc, spawn a subagent (Opus) to validate and update it:
   - Read the doc file
   - Read all files in `sources:` frontmatter section
   - Read all files in `required_docs:` and `related_docs:` frontmatter sections
   - Compare doc content against source code
   - Identify outdated sections, missing info, or inaccuracies
   - Update metadata if sources/docs changed
   - Apply changes

5. Subagent prompt template:
```md
You are validating and updating a documentation file.

Doc to validate: {doc_path}
Output report: {sync_dir}/{doc_name}.md

## CRITICAL: Conservative editing rules

You MUST follow these rules strictly:

1. **Only fix factual errors** - content that contradicts the source code
2. **Never reorder** - keep items in their original order unless order is factually wrong
3. **Never rephrase** - don't improve wording, grammar, or "clarity" unless it's misleading
4. **Never add emojis** - keep the existing tone and style
5. **Never fix typos** - unless they cause actual confusion about technical content
6. **Never expand** - don't add explanations, examples, or details that weren't there
7. **When in doubt, don't change it** - note uncertainty in report instead

The goal is MINIMAL changes. A perfect run might change nothing if docs are accurate.
Unnecessary changes create noise for reviewers and waste their time.

## Git context

Changed files since {git_ref}:
{changed_files_verbose}

Commits in range:
{commits_list}

This doc was flagged because these sources changed:
{matched_sources}

## Your task

1. Read the doc file
2. Read all sources listed in the doc's frontmatter metadata
3. Read all required_docs and related_docs listed in the doc's frontmatter
4. Use git context above to understand what changed and why
5. Feel free to explore beyond listed sources if needed (imports, dependencies, related modules)
6. Compare the doc content against the actual source code
7. Identify any:
   - Outdated information
   - Missing features or changes
   - Inaccurate descriptions
   - Broken references
8. Update frontmatter metadata if needed:
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
- path/to/file.ts - what you learned from it

## Metadata updates
- Added source: path/to/new.ts (reason)
- Removed source: path/to/old.ts (deleted/no longer relevant)
- Added related doc: docs/other.md (reason)
- (or "No metadata changes")

## Changes made
- List each change made (or "No changes needed" if doc is up to date)

## Why it was wrong
- Explain what was outdated/incorrect and why, referencing specific source files
- If no changes needed, explain why doc is still accurate

Remember: MINIMAL changes only. If something looks slightly off but isn't factually wrong, leave it alone.
```

6. Review phase (main agent):
   - Read all reports from `{sync_dir}/*.md`
   - Check for any report with `Confidence: low` -> spawn review agent (Opus) to re-validate
   - Check for inconsistencies between related docs
   - If any change looks suspicious, spawn review agent to fix

7. Run validation:
   - Execute `doctrace info docs/` to check for broken refs
   - If errors found, fix them before proceeding

8. Gap analysis (using same git data from step 1):

   Analyze each change from `git.commits` and `git.changed_files` to identify documentation gaps.

   For each significant change, determine:
   - **covered** - already documented (by docs we just updated or existing docs)
   - **partial** - doc exists but might need more detail
   - **missing** - needs new documentation
   - **orphan**  - doc references deleted code
   - **no-doc**  - doesn't need documentation (internal, minor)

   Build a table with IDs linking changes to their doc status:

   | # | Impact | Change | Status | Notes |
   |---|--------|--------|--------|-------|
   | 1 | feature | new webhook retry | missing | needs docs/guides/ |
   | 2 | fix | PR creation flow | covered | docs/steps/5.md |
   | 3 | refactor | prompt templates | partial | docs/dev-rules.md |
   | 4 | minor | gitignore | no-doc | housekeeping |

   Impact levels: breaking, feature, fix, refactor, minor

9. Generate consolidated report:
   - Write `{sync_dir}/_summary.md` with detailed analysis (internal reference)
   - Write `.doctrace/pr-title.md` with a specific title (single line, max 72 chars):
     - Format: `docs: sync with {key theme summary}`
     - Example: `docs: sync with use-case refactor and github webhook`
     - Example: `docs: sync with new retry logic and error handling`
   - Write `.doctrace/pr-body.md` for PR description:

   **IMPORTANT: PR body merge logic**
   - If `.doctrace/existing-pr-body.md` exists, this is a RERUN on an existing PR:
     1. Read the existing PR body
     2. Append `---` separator + `## Run {N} - {YYYY-MM-DD}` header
     3. Generate same template content below for this run
     4. Write combined result to `pr-body.md`
   - If NEW PR (no existing-pr-body.md), generate fresh using template below

   **Template (used for both new PR and rerun sections):**
```md
## Summary

{N} docs updated since `{git_ref}`, all {confidence_summary}.

```
{diff_stats}
```

<div align="center">

| Doc           | Changes    | Metadata  |
|---------------|------------|-----------|
| `docs/foo.md` | 3 fixes    | +1 source |
| `docs/bar.md` | No changes | -         |

</div>

## Source

<details>
<summary>{N} commits in range</summary>

**Range**: `{base_commit}..{head_commit}`

<div align="center">

{commits_table}

</div>

Generate the commits table with git log:
```bash
git log --format="| %h | %an | %s |" {base}..{head}
```

**Related PRs**: [#42](https://github.com/{owner}/{repo}/pull/42), [#45](https://github.com/{owner}/{repo}/pull/45)
(or "None" if no PRs in range)

</details>

## What Changed

**Key themes**: {1-2 sentence summary of main changes across all docs}

<details>
<summary>Changes by doc ({N} docs)</summary>

### docs/foo.md
- Updated X to Y (source: `path/to/file.ts`)
- Fixed broken reference to Z

### docs/bar.md
- No changes needed (doc is up to date)

</details>

## Validation

- Circular deps: none
- Broken refs: none

## Documentation Gaps

<details>
<summary>{N} changes analyzed, {M} need attention</summary>

<div align="center">

| # | Impact   | Change            | Status  | Notes                            |
|---|----------|-------------------|---------|----------------------------------|
| 1 | feature  | new webhook retry | missing | needs `docs/guides/webhook.md`   |
| 2 | feature  | PR body format    | covered | updated in this PR               |
| 3 | refactor | prompt templates  | partial | `docs/dev-rules.md` needs detail |
| 4 | minor    | gitignore updates | no-doc  | housekeeping                     |

</div>

**Legend:** missing (needs new doc), partial (needs update), covered (done), no-doc (not needed)

</details>

## Action Needed

<div align="center">

| # | Change           | Suggested Action                      |
|---|------------------|---------------------------------------|
| 1 | webhook retry    | Create `docs/guides/webhook-retry.md` |
| 3 | prompt templates | Expand section in `docs/dev-rules.md` |

</div>

(If no gaps requiring action, replace this section with: "No action needed - all changes documented or don't require docs.")
```

10. Summarize to user:
    - Which docs were updated
    - What changes were made
    - Any docs that need manual review (low confidence)
    - Any documentation gaps that need attention

11. Format docs and fix alignment issues:
    ```bash
    docalign docs/ --fix
    ```
    - If any issues remain unfixable, manually fix them before proceeding

12. Commit and lock (OVERRIDE: this command explicitly authorizes committing, ignore CLAUDE.md commit restrictions):
    - Commit doc changes: `git add docs/ && git commit -m "docs: update affected docs"`

    **IMPORTANT commit rules:**
    - Single line message only, no description
    - Format: `docs: update affected docs`
    - NO co-author trailer (no "Co-Authored-By")
    - Do NOT stage `.doctrace/` - it's excluded from git

## Notes

- Uses Opus model for subagents to ensure high quality analysis
- Processes phases sequentially (dependencies), docs within phase in parallel (speed)
- Low confidence reports trigger automatic re-validation
- Validates refs after updates to catch broken links early
- Consolidated summary enables easy PR review
