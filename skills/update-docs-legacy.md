# Update Docs (Legacy Mode)

Read ALL source files and update documentation accordingly. Use this mode when doctrace is not set up.

## Usage

```
/update-docs
```

## Instructions

1. Read ALL source files in the repository (in parallel):
   - All code directories (src/, lib/, app/, etc.)
   - Configuration files (*.json, *.yaml, *.toml)
   - Test files for understanding behavior

2. Also read root files:
   - README.md
   - CLAUDE.md (if exists)

3. Read ALL docs in `docs/` folder

4. Compare docs vs code field-by-field, update outdated sections

## Folders to Skip

- `.git/`, `.claude/`, `node_modules/`, `.venv/`, `__pycache__/`
- Build outputs, cache directories
- Binary files (images, videos)

## What to Update

- File structure diagrams (must match actual folders/files)
- CLI commands and flags
- Configuration options
- Function names and entry points
- API references
- New features or removed features

## How to Compare (CRITICAL)

Do NOT just eyeball docs and conclude "looks correct". For each doc file:

1. Identify every table, list, or reference to source code
2. Open the referenced source file
3. Compare EACH field/value/function name against the actual code
4. Check for missing items (new features not in docs)
5. Check for removed items (features that no longer exist in code)

## Style Rules

- Keep docs concise, no fluff
- Tables must be aligned (equal column spacing)
- Use existing format as reference
- No emojis unless already present
- English only

## Table Format Example

```md
| Column One | Column Two | Column Three |
|------------|------------|--------------|
| value      | value      | value        |
| longer val | short      | medium value |
```

## Output

After updates, list what changed in each file.
