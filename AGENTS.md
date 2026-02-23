# AGENTS.md

This file provides guidance when editing the orchestrate toolkit.

## Project Overview

Orchestrate is a general-purpose multi-model supervisor toolkit for Claude Code, Codex, and OpenCode. It discovers available skills at runtime and composes subagent runs dynamically — picking the right model and skills for each subtask.

A run is `model + skills + prompt`. Agent profiles are convenience aliases with default skills, model preferences, and permission settings — not a separate abstraction layer.

Two directory trees:

Source (`orchestrate/` — submodule/clone):
- `orchestrate/skills/*/SKILL.md` — self-describing capability building blocks
- `orchestrate/agents/*.md` — agent profiles (convenience aliases with permission defaults)
- `orchestrate/MANIFEST` — skill registry for install.sh
- `orchestrate/docs/` — design documents

Runtime (`.orchestrate/` — gitignored):
- `.orchestrate/runs/agent-runs/<run-id>/` — flat per-run artifacts
- `.orchestrate/index/runs.jsonl` — append-only two-row index (start + finalize)

## Core Commands

```bash
RUNNER=orchestrate/skills/run-agent/scripts/run-agent.sh
INDEX=orchestrate/skills/run-agent/scripts/run-index.sh

# Run: model + skills + prompt
"$RUNNER" --model claude-sonnet-4-6 --skills review -p "Review auth changes"

# Run with an agent profile (loads defaults from orchestrate/agents/reviewer.md)
"$RUNNER" --agent reviewer -p "Review auth changes"

# Agent with CLI overrides
"$RUNNER" --agent reviewer --model claude-opus-4-6 -p "Deep review"

# Run with labels and session grouping
"$RUNNER" --model gpt-5.3-codex --skills smoke-test \
    --session my-session --label ticket=PAY-123 \
    -p "Implement feature"

# Dry run
"$RUNNER" --model gpt-5.3-codex --skills review --dry-run -p "Review changes"

# Inspect runs
"$INDEX" list
"$INDEX" show @latest
"$INDEX" stats
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
# Core only (orchestrate + run-agent)
bash orchestrate/install.sh

# With optional skills
bash orchestrate/install.sh --include review,mermaid

# Everything
bash orchestrate/install.sh --all
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

## Conventions

- Commits: conventional commits (`feat(scope): ...`, `fix(scope): ...`, `docs(scope): ...`)
- Tool names in frontmatter: PascalCase for Claude (`Read`, `Edit`, `Write`, `Bash`, `Glob`, `Grep`)
- Template variables: generic `-v KEY=VALUE` (projects choose their own names)
- Runtime artifact directories are untracked and should not be committed
- No project-specific workflow concepts (plans, slices, handoffs) in the orchestration core
