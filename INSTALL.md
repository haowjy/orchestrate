# Install Orchestrate — LLM Guide

This file is for LLMs helping users install orchestrate. Follow these instructions to drive `install.sh` based on user preference.

## Before you start

Ask the user two questions:

1. **Submodule or clone?**
   - **Submodule** — version is pinned and tracked by the parent repo; collaborators get it automatically with `git clone --recurse-submodules`; update with `git submodule update --remote`
   - **Clone** — simpler; just a nested git repo; update with `git pull`; not tracked by the parent repo so each developer manages their own version

2. **Symlink or copy?**
   - **Symlink** (default) — skill directories are symlinked; updates to orchestrate are reflected immediately; saves disk space
   - **Copy** — skill directories are copied; required on Windows or filesystems that don't support symlinks; must re-run install after updating orchestrate

## Step 1: Add orchestrate

### If submodule:

```bash
git submodule add https://github.com/haowjy/orchestrate .agents/skills/orchestrate
```

### If clone:

```bash
mkdir -p .agents/skills
git clone https://github.com/haowjy/orchestrate .agents/skills/orchestrate
```

## Step 2: Run setup

Compose the `install.sh` command based on the user's answers:

```bash
bash .agents/skills/orchestrate/install.sh --method <submodule|clone> --link <symlink|copy>
```

Examples:
- Submodule + symlink (most common): `bash .agents/skills/orchestrate/install.sh --method submodule --link symlink`
- Clone + copy (Windows): `bash .agents/skills/orchestrate/install.sh --method clone --link copy`

## Step 3: Verify

```bash
ls -la .agents/skills/
ls -la .claude/skills/
```

Both directories should contain entries for each skill (symlinks or directories depending on `--link` choice).

## Updating

### If submodule:

```bash
git submodule update --remote .agents/skills/orchestrate
```

### If clone:

```bash
cd .agents/skills/orchestrate && git pull && cd -
```

If `--link copy` was used, re-run install to refresh copies:

```bash
bash .agents/skills/orchestrate/install.sh --method <submodule|clone> --link copy
```

## Uninstalling

### If submodule:

```bash
git submodule deinit -f .agents/skills/orchestrate
git rm -f .agents/skills/orchestrate
rm -rf .git/modules/.agents/skills/orchestrate
```

### If clone:

```bash
rm -rf .agents/skills/orchestrate
```

Then remove skill links from both directories:

```bash
# Remove symlinks
find .agents/skills -maxdepth 1 -type l -delete
find .claude/skills -maxdepth 1 -type l -delete

# Or if --link copy was used, remove the copied skill directories
for skill in .agents/skills/orchestrate/skills/*/; do
  name="$(basename "$skill")"
  rm -rf ".agents/skills/$name" ".claude/skills/$name"
done
```
