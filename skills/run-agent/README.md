# Run-Agent — Execution Engine

Single entry point for running any agent. Routes models to the correct CLI tool, loads skills, composes prompts, and logs each run.

## Quick Start

```bash
# Run an agent by name
run-agent/scripts/run-agent.sh review -v SLICES_DIR=.runs/plans/my-plan/slices/01-foo

# Override model on any agent
run-agent/scripts/run-agent.sh implement -m claude-opus-4-6

# Ad-hoc (no agent definition)
run-agent/scripts/run-agent.sh --model claude-sonnet-4-6 --skills review -p "Review the changes"

# Dry run — see composed prompt + CLI command without executing
run-agent/scripts/run-agent.sh review --dry-run -v SLICES_DIR=/tmp/test
```

## Agent Definitions (`agents/`)

Markdown files with YAML frontmatter. Each defines model, tools, skills, and prompt for one agent.

### Implementation

| Agent | Model | Best For |
|---|---|---|
| `implement` | gpt-5.3-codex | Default — most slices |
| `implement-iterative` | claude-sonnet-4-6 | Fast UI iteration loops |
| `implement-deliberate` | claude-opus-4-6 | Complex logic, subtle bugs |

### Review

| Agent | Model | Effort | Personality |
|---|---|---|---|
| `review` | claude-opus-4-6 | high | Thoughtful senior dev |
| `review-thorough` | gpt-5.3-codex | high | Exhaustive auditor |
| `review-quick` | gpt-5.3-codex | low | Fast sanity check |
| `review-adversarial` | claude-sonnet-4-6 | high | Adversarial tester |

### Research

| Agent | Model | Focus |
|---|---|---|
| `research-claude` | claude-sonnet-4-6 | Web + codebase exploration |
| `research-codex` | gpt-5.3-codex | Deep codebase analysis + web search |
| `research-kimi` | opencode/kimi-k2.5-free | Alternative perspective via Kimi |

### Utility

| Agent | Model | Purpose |
|---|---|---|
| `plan-slice` | gpt-5.3-codex | Creates next implementable slice from a plan |
| `cleanup` | gpt-5.3-codex | Targeted fix from review findings |
| `commit` | claude-haiku-4-5 | Clean commit message from working tree |

## Scripts

### `scripts/run-agent.sh`

Main entry point. See `SKILL.md` for full documentation.

### `scripts/extract-files-touched.sh`

Parses a single run log and extracts touched file paths:

```bash
scripts/extract-files-touched.sh <output-log> [output-file]
```

### `scripts/save-handoff.sh`

Snapshots `handoffs/latest.md` into a timestamped file:

```bash
scripts/save-handoff.sh .runs/plans/my-plan
```

## Script Unit Tests

```bash
tests/run-agent-unit.sh
```

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `ORCHESTRATE_RUNS_DIR` | Runtime data (plans, logs, scratch) | `.runs/` under working directory |
| `ORCHESTRATE_LOG_DIR` | Override log directory for a single run | Auto-derived from scope |
| `ORCHESTRATE_DEFAULT_CLI` | Force all model routing to a specific CLI | Auto-detect from model name |
| `ORCHESTRATE_AGENT_DIR` | Override agent definition directory | unset |

Tool allowlists are applied only when routed to Claude (`--allowedTools`). Codex and OpenCode currently do not expose equivalent allowlist flags in `exec/run`.

## Custom Agents

Create `agents/my-agent.md` with YAML frontmatter:

```yaml
---
name: my-agent
description: What this agent does
model: claude-sonnet-4-6
effort: high
tools: Read,Edit,Write,Bash,Glob,Grep
skills:
  - review
---

Your prompt here. Use {{TEMPLATE_VARS}} for dynamic values.
```

Agent files are meant to be edited per project after install. You can:
- tune built-in prompts for your codebase conventions,
- add new agent variants for specific stacks/workflows,
- keep shared rules in root `AGENTS.md`/`CLAUDE.md` that agents are instructed to read.

Agent lookup precedence:
1. `ORCHESTRATE_AGENT_DIR/<agent>.md` (if set)
2. `<workdir>/.agents/skills/run-agent/agents/<agent>.md`
3. `<workdir>/.claude/skills/run-agent/agents/<agent>.md`
4. bundled `agents/<agent>.md`

See the `model-guidance` skill for guidance on when to use each variant.
