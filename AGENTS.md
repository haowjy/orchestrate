# AGENTS.md

This file provides guidance when editing the orchestrate toolkit.

## Project Overview

Orchestrate is a general-purpose multi-model supervisor toolkit for Claude Code, Codex, and OpenCode. It discovers available skills at runtime and composes subagent runs dynamically — picking the right model and skills for each subtask.

A run is `model + skills + prompt`. Agent profiles are convenience aliases with default skills, model preferences, and permission settings — not a separate abstraction layer.

Two directory trees:

Source (`orchestrate/` — submodule/clone):
- `orchestrate/skills/*/SKILL.md` — self-describing capability building blocks
- `orchestrate/agents/*.md` — agent profiles (convenience aliases with permission defaults)
- `orchestrate/MANIFEST` — skill & agent registry for sync.sh
- `orchestrate/docs/` — design documents

Runtime (`.orchestrate/` — gitignored):
- `.orchestrate/runs/agent-runs/<run-id>/` — flat per-run artifacts
- `.orchestrate/index/runs.jsonl` — append-only two-row index (start + finalize)

## Core Commands

```bash
# Run: model + skills + prompt
skills/run-agent/scripts/run-agent.sh --model MODEL --skills SKILL1,SKILL2 -p "PROMPT"

# Run with an agent profile
skills/run-agent/scripts/run-agent.sh --agent AGENT -p "PROMPT"

# With labels and session grouping
skills/run-agent/scripts/run-agent.sh --model MODEL --skills SKILLS \
    --session SESSION_ID --label KEY=VALUE -p "PROMPT"

# Dry run
skills/run-agent/scripts/run-agent.sh --model MODEL --skills SKILLS --dry-run -p "PROMPT"

# Inspect runs
skills/run-agent/scripts/run-index.sh list
skills/run-agent/scripts/run-index.sh show @latest
skills/run-agent/scripts/run-index.sh stats
```

## Runtime Rules

1. Skills are discovered from `orchestrate/skills/` — each `SKILL.md` has `name:` and `description:` frontmatter.
2. `run-agent.sh` composes prompts from model + skills + task and routes to the correct CLI.
3. Runtime artifacts are written to `.orchestrate/runs/agent-runs/<run-id>/`.
4. The append-only index at `.orchestrate/index/runs.jsonl` enables fast filtering and observability.
5. Model guidance is loaded from `run-agent/references/` with custom concatenation support.
6. No environment variables control runtime behavior — all configuration is via explicit flags.

## Install

```bash
# Sync all skills + agents (default)
bash orchestrate/sync.sh pull

# Selective: specific skills only
bash orchestrate/sync.sh pull --skills review,mermaid

# Selective: specific agents only
bash orchestrate/sync.sh pull --agents reviewer

# Explicit all
bash orchestrate/sync.sh pull --all
```

## Orchestration Model

The orchestrator is a multi-model routing layer:
1. Discover available skills
2. Understand what needs to happen
3. Pick the best model for each subtask (via model-guidance)
4. Pick the right skills to attach
5. Launch via `run-agent.sh` with `--label` and `--session` for grouping
6. Evaluate outputs (via `run-index.sh report @latest`)
7. Repeat until user objective is satisfied

## Before Reading Script Source

All scripts support `--help`. Run that first before reading source code to understand usage, flags, and behavior.

## Conventions

- Commits: conventional commits (`feat(scope): ...`, `fix(scope): ...`, `docs(scope): ...`)
- Tool names in frontmatter: PascalCase for Claude (`Read`, `Edit`, `Write`, `Bash`, `Glob`, `Grep`)
- Template variables: generic `-v KEY=VALUE` (projects choose their own names)
- Runtime artifact directories are untracked and should not be committed
- No project-specific workflow concepts (plans, tasks, handoffs) in the orchestration core
