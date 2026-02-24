# Install Orchestrate

You are an LLM agent helping a user install orchestrate into their project. Follow these instructions exactly.

## Step 1: Gather information

Ask the user the following. Present all questions at once, with your recommendations:

1. **Where is the target project?** — The project root where orchestrate will be installed. Default to the current working directory.
2. **Submodule or clone?** — Recommend submodule (version-pinned, tracked by parent repo, collaborators get it automatically). Clone is simpler but untracked.
3. **Where should orchestrate live?** — Default is `<project-root>/orchestrate/`. If the user wants it outside the repo (e.g. a shared install), they can specify a different path — `sync.sh pull --workspace <project-root>` handles this.
4. **All skills/agents or selective?** — After cloning, read `orchestrate/MANIFEST` to see what's available. Check what already exists in `.agents/skills/` and `.claude/skills/` in the target project. Note any overlaps. Recommend `--all` for coding projects. For non-coding use cases (e.g. just building custom agents/skills), suggest selective install with `--skills` and/or `--agents`.

Wait for the user to confirm before proceeding.

## Step 2: Clone

Submodule:
```bash
git submodule add https://github.com/haowjy/orchestrate <orchestrate-path>
```

Clone:
```bash
git clone https://github.com/haowjy/orchestrate <orchestrate-path>
echo '<orchestrate-path>/' >> .gitignore
```

## Step 3: Sync

Run `bash <orchestrate-path>/sync.sh --help` to confirm available options, then run the sync command matching the user's choices:

```bash
bash <orchestrate-path>/sync.sh pull                              # all (default)
bash <orchestrate-path>/sync.sh pull --all                        # explicit all
bash <orchestrate-path>/sync.sh pull --skills review,mermaid      # selective skills
bash <orchestrate-path>/sync.sh pull --agents reviewer            # selective agents
```

If orchestrate lives outside the project repo, add `--workspace <project-root>`.

## Step 4: Verify

Confirm skills and agents were copied:
```bash
ls .agents/skills/ .claude/skills/ .agents/agents/ .claude/agents/
```

## Step 5: Output maintenance instructions

After a successful install, output instructions **directly to the user** (do NOT write them to a file). The instructions should cover:

- **How to update**: pull latest from submodule/clone, then re-run `sync.sh pull`
- **How to sync after editing skills locally**: `sync.sh push` to push changes back to the submodule
- **How to check sync status**: `sync.sh status`
- **How to uninstall**: remove the submodule/clone, then `rm -rf .agents/skills/ .claude/skills/ .agents/agents/ .claude/agents/ .orchestrate/`

Tailor the instructions to the choices the user made (submodule vs clone, orchestrate path, workspace path). The user can then paste these wherever they keep project notes.
