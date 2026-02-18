# Update Docs (Smart Mode)

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

1. Run doctrace to get affected docs:
   - If argument is `--since-lock`: `doctrace affected docs/ --since-lock --verbose --json`
   - Otherwise: `doctrace affected docs/ --since $ARGUMENTS --verbose --json`
   - If doctrace is not installed, fall back to legacy mode (read all docs)

2. Parse the JSON output to get:
   - `direct_hits` - docs directly affected by changed sources
   - `indirect_hits` - docs affected via references
   - `phases` - dependency order for processing
   - `git.commits` - commits in range (for context)

3. For each affected doc:
   - Read the doc file
   - Read all files in `related sources:` section
   - Read all files in `related docs:` section
   - Compare doc content against source code
   - Identify outdated sections, missing info, or inaccuracies
   - Update the doc content
   - Update metadata if sources/docs changed

4. For each doc, follow this validation process:
   - Identify every table, list, or reference to source code
   - Compare EACH field/value/function name against the actual code
   - Check for missing items (new features not in docs)
   - Check for removed items (features that no longer exist)

5. Style rules:
   - Keep docs concise, no fluff
   - Tables must be aligned (equal column spacing)
   - Use existing format as reference
   - No emojis unless already present
   - English only

6. After updates:
   - Run `doctrace validate docs/` to check for broken refs
   - Fix any errors before finishing
   - List what changed in each file

## Output

Summarize:
- Which docs were updated
- What changes were made
- Any docs that need manual review
