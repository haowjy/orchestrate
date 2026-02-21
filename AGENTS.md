# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Orchestrate is a multi-agent toolkit for Claude Code, Codex, and OpenCode. It implements a supervisor loop that takes a markdown plan and autonomously orchestrates specialized agents (research, planning, implementation, review, cleanup) to build it.

## Commands

```bash
# Unit tests
bash tests/run-agent-unit.sh

# Dry-run — preview composed prompt + CLI command without executing
AGENT_RUNNER=skills/run-agent/scripts/run-agent.sh
"$AGENT_RUNNER" review --dry-run -v SLICES_DIR=/tmp/test

# Live agent run
"$AGENT_RUNNER" review -v SLICES_DIR=path/to/slices/01-foo

# Three-way sync after updating submodule or editing skills
bash .agents/.orchestrate/sync.sh pull    # upstream → project
bash .agents/.orchestrate/sync.sh push    # project → upstream
bash .agents/.orchestrate/sync.sh status  # diff all three locations
```

## Architecture

### Skills

Skills are composable methodology files (`skills/*/SKILL.md`) loaded into agent prompts at runtime. They are markdown instructions, not code libraries. Each skill has YAML frontmatter (`name`, `description`, optional `allowed-tools`, `user-invocable`) and a markdown body with step-by-step methodology.

Core skills: `orchestrate` (supervisor loop), `run-agent` (execution engine), `review`, `research`, `plan-slice`, `smoke-test`, `scratchpad`, `model-guidance`, `mermaid`.

### Agent Definitions

Agents live in `skills/run-agent/agents/*.md` as markdown files with YAML frontmatter:

```yaml
---
name: implement
description: Implementation agent
model: gpt-5.3-codex
effort: high
tools: Read,Edit,Write,Bash,Glob,Grep
skills:
  - smoke-test
  - scratchpad
---
# Prompt body with {{TEMPLATE_VARS}} for dynamic values
```

Agent lookup precedence: `ORCHESTRATE_AGENT_DIR` → `.agents/skills/run-agent/agents/` → `.claude/skills/run-agent/agents/` → bundled `skills/run-agent/agents/`.

### run-agent.sh Pipeline

`skills/run-agent/scripts/run-agent.sh` is the single entry point for all agent execution. It:
1. Parses args and resolves the agent definition (`lib/parse.sh`)
2. Loads skills and composes the prompt with template variable substitution (`lib/prompt.sh`)
3. Routes to the correct CLI based on model name and builds the command (`lib/exec.sh`)
4. Sets up PID-based log directories for parallel safety (`lib/logging.sh`)

Model routing: `claude-*`/`opus*`/`sonnet*`/`haiku*` → claude CLI, `gpt-*`/`o1*`/`codex*` → codex CLI, `provider/model` or `opencode-*` → opencode CLI. Override with `ORCHESTRATE_DEFAULT_CLI`.

### Supervisor Loop (orchestrate skill)

The orchestrator is a supervisor, never an implementer. Pipeline: `[research] → plan-slice → implement → review → (clean? commit : fix → review) → next slice`. Every slice must go through `run-agent.sh`, no exceptions.

### Logging

Two separate logging trees:
- `run-agent/.runs/` — raw per-run artifacts (`input.md`, `output.json`, `report.md`, `params.json`, `files-touched.txt`)
- `orchestrate/.session/` — coordination state (`index.log`, `handoffs/`, `commits/`)

Both are scoped by plan and slice: `plans/{plan-name}/slices/{slice}/logs/agent-runs/{agent}-{PID}/`.

### Three-Way Sync

When installed into a project, skills exist in three locations kept in sync by `sync.sh`:
- `.agents/.orchestrate/skills/` — upstream (submodule/clone)
- `.agents/skills/` — project copy (Codex/OpenCode)
- `.claude/skills/` — project copy (Claude Code)

## Conventions

- **Commits**: conventional commits — `feat(scope): description`, `fix(scope): description`, `docs(scope): description`
- **Tool names in agent definitions**: PascalCase for Claude (`Read`, `Edit`, `Write`, `Bash`, `Glob`, `Grep`)
- **Template variables**: `{{PLAN_FILE}}`, `{{SLICE_FILE}}`, `{{SLICES_DIR}}`, `{{BREADCRUMBS}}` — substituted at prompt composition time
- **Runtime artifacts** (`run-agent/.runs/`, `orchestrate/.session/`) are gitignored and never committed
- **Scratch code** goes in `scratch/code/smoke/` — ad-hoc verification, never committed
