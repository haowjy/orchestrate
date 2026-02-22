# Install Orchestrate — LLM Guide

This file is for LLMs helping users install orchestrate. Follow these instructions to drive `install.sh` based on user preference.

## Before you start

Ask the user one question:

1. **Submodule or clone?**
   - **Submodule** — version is pinned and tracked by the parent repo; collaborators get it automatically with `git clone --recurse-submodules`; update with `git submodule update --remote`
   - **Clone** — simpler; just a nested git repo; update with `git pull`; not tracked by the parent repo so each developer manages their own version

## Step 1: Add orchestrate

### If submodule:

```bash
git submodule add https://github.com/haowjy/orchestrate orchestrate
```

### If clone:

```bash
git clone https://github.com/haowjy/orchestrate orchestrate
```

## Step 2: Run setup

```bash
bash orchestrate/install.sh
```

The script auto-detects whether you used submodule or clone. To override:

```bash
bash orchestrate/install.sh --method submodule
bash orchestrate/install.sh --method clone
```

## Step 3: Verify

```bash
ls -la .agents/skills/
ls -la .claude/skills/
```

Both directories should contain skill directories (orchestrate, run-agent, review, etc.).

## Updating

### If submodule:

```bash
git submodule update --remote orchestrate
```

### If clone:

```bash
cd orchestrate && git pull && cd -
```

Then re-run install to update skill copies:

```bash
bash orchestrate/install.sh
```

Re-running install overwrites shipped files but preserves any custom agents or files you added.

## Uninstalling

### If submodule:

```bash
git submodule deinit -f orchestrate
git rm -f orchestrate
rm -rf .git/modules/orchestrate
```

### If clone:

```bash
rm -rf orchestrate
```

Then remove copied skill directories:

```bash
for skill in orchestrate/skills/*/; do
  name="$(basename "$skill")"
  rm -rf ".agents/skills/$name" ".claude/skills/$name"
done
```
