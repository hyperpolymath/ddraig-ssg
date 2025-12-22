# Git Hooks for ddraig-ssg

## Installation

To install the git hooks, run:

```bash
# Copy hooks to .git/hooks
cp hooks/pre-commit .git/hooks/
cp hooks/pre-push .git/hooks/

# Make them executable
chmod +x .git/hooks/pre-commit
chmod +x .git/hooks/pre-push
```

Or create symbolic links:

```bash
ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
ln -sf ../../hooks/pre-push .git/hooks/pre-push
```

## Available Hooks

### pre-commit

Runs before each commit to ensure:

1. **Language compliance** - No Python, JS, TS, or other forbidden languages in `src/`
2. **Type check** - Idris code type-checks successfully (if idris2 available)
3. **Secrets check** - Warns about potential secrets in code

### pre-push

Runs before pushing to ensure:

1. **All tests pass** - Markdown, frontmatter, and full pipeline tests

## Bypassing Hooks

In emergencies, you can bypass hooks with:

```bash
git commit --no-verify
git push --no-verify
```

**Use sparingly!** The hooks exist to maintain code quality.
