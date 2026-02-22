# AGENTS.md

This file provides guidance when editing the orchestrate toolkit.

## Project Overview

Orchestrate is a multi-model supervisor toolkit for Claude Code, Codex, and OpenCode. It discovers available skills at runtime and composes subagent runs dynamically — picking the right model and skills for each subtask.

The runtime is centered on a canonical project root:
- `.orchestrate/skills/*/SKILL.md` — self-describing capability building blocks
- `.orchestrate/runs/` — per-run artifacts
- `.orchestrate/session/` — coordination state
- `.orchestrate/references/` — stack-specific review rules

## Core Command

```bash
RUNNER=orchestrate/skills/run-agent/scripts/run-agent.sh

# Ad-hoc: model + skills + prompt (primary mode)
"$RUNNER" --model claude-sonnet-4-6 --skills review -p "Review auth changes"

# With plan/slice context
"$RUNNER" --model gpt-5.3-codex --skills smoke-test,scratchpad \
    --plan demo --slice slice-1

# Dry run
"$RUNNER" --model gpt-5.3-codex --skills review --dry-run -p "Review changes"
```

## Runtime Rules

1. Skills are discovered from `.orchestrate/skills/` — each `SKILL.md` has `name:` and `description:` frontmatter.
2. `run-agent.sh` composes prompts from model + skills + task and routes to the correct CLI.
3. Runtime artifacts are written to `.orchestrate/runs/` and `.orchestrate/session/`.
4. The `model-guidance` skill provides model selection heuristics and skill-composition patterns.
5. Agent definitions (`.orchestrate/agents/*.md`) are an optional legacy mechanism — ad-hoc composition is preferred.

## Orchestration Model

The orchestrator is a multi-model routing layer:
1. Discover available skills
2. Understand what needs to happen
3. Pick the best model for each subtask (via model-guidance)
4. Pick the right skills to attach
5. Launch via `run-agent.sh`
6. Evaluate outputs
7. Repeat until user objective is satisfied

## Conventions

- Commits: conventional commits (`feat(scope): ...`, `fix(scope): ...`, `docs(scope): ...`)
- Tool names in frontmatter: PascalCase for Claude (`Read`, `Edit`, `Write`, `Bash`, `Glob`, `Grep`)
- Template variables: `{{PLAN_FILE}}`, `{{SLICE_FILE}}`, `{{SLICES_DIR}}`, `{{SCOPE_ROOT}}`
- Runtime artifact directories are untracked and should not be committed
