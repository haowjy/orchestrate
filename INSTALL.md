# Install Orchestrate — LLM Guide

This file is for LLMs helping users install orchestrate. Follow these instructions to drive `install.sh` based on user preference.

## Before you start

Ask the user two questions:

1. **Submodule or clone?**
   - **Submodule** (recommended) — version is pinned and tracked by the parent repo; collaborators get it automatically with `git clone --recurse-submodules`; update with `git submodule update --remote`
   - **Clone** — simpler; just a nested git repo; update with `git pull`; not tracked by the parent repo so each developer manages their own version

2. **Install path?** — where to put orchestrate in the repo (default: `orchestrate`). Examples: `orchestrate`, `tools/orchestrate`, `.tools/orchestrate`

## Step 1: Add orchestrate

In the examples below, replace `<path>` with the chosen install path (e.g. `orchestrate`).

### If submodule:

```bash
git submodule add https://github.com/haowjy/orchestrate <path>
```

### If clone:

```bash
git clone https://github.com/haowjy/orchestrate <path>
echo '<path>/' >> .gitignore
```

## Step 2: Run setup

```bash
bash <path>/install.sh
```

The script auto-detects the workspace root from git. To override:

```bash
bash <path>/install.sh --workspace /path/to/project
```

If the install path is not `orchestrate`, the script automatically rewrites runner paths in copied skills to match.

## Step 3: Verify

```bash
ls -la .agents/skills/
ls -la .claude/skills/
```

Both directories should contain skill directories (orchestrate, run-agent, review, etc.).

## Updating

### If submodule:

```bash
git submodule update --remote <path>
```

### If clone:

```bash
cd <path> && git pull && cd -
```

Then re-run install to update skill copies:

```bash
bash <path>/install.sh
```

Re-running install overwrites shipped files but preserves any custom files you added.

## Uninstalling

### If submodule:

```bash
git submodule deinit -f <path>
git rm -f <path>
rm -rf .git/modules/<path>
```

### If clone:

```bash
rm -rf <path>
```

Then remove copied skill directories:

```bash
for skill in <path>/skills/*/; do
  name="$(basename "$skill")"
  rm -rf ".agents/skills/$name" ".claude/skills/$name"
done
```
