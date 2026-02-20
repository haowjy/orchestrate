---
name: run-agent
description: Agent execution engine — routes models to CLIs, composes prompts, logs runs.
---

# Run-Agent — Execution Engine

Single entry point for running any agent. Routes models to the correct CLI tool (`claude -p`, `codex exec`, `opencode run`), loads skills, composes prompts, and logs each run.

## Usage

```bash
# Using an agent definition
run-agent/scripts/run-agent.sh review

# Ad-hoc (no agent definition)
run-agent/scripts/run-agent.sh --model claude-sonnet-4-6 --skills review -p "Review the changes"

# Agent with model override
run-agent/scripts/run-agent.sh implement -m claude-opus-4-6

# Dry run — see composed prompt + CLI command without executing
run-agent/scripts/run-agent.sh review --dry-run

# With template variables
run-agent/scripts/run-agent.sh implement -v SLICE_FILE=.runs/plans/my-plan/slices/slice-1/slice.md

# Brief report (default: standard)
run-agent/scripts/run-agent.sh review -D brief

# Pass reference files (appended as "Reference Files" section in prompt)
run-agent/scripts/run-agent.sh implement \
    -v SLICE_FILE=path/to/slice.md \
    -f path/to/extra-context.md
```

## Report Detail (`-D/--detail`)

Every run appends a report instruction to the prompt. The subagent writes `report.md` as its final action.

| Level | Description |
|-------|-------------|
| `brief` | Concise: what was done, pass/fail, blockers |
| `standard` | (default) Decisions, files, verification, issues |
| `detailed` | Thorough: reasoning, all files, full verification, recommendations |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ORCHESTRATE_RUNS_DIR` | Where to store run data (plans, logs, scratch) | `.runs/` under working directory |
| `ORCHESTRATE_LOG_DIR` | Override log directory for a single run | Auto-derived from scope |
| `ORCHESTRATE_DEFAULT_CLI` | Force all model routing to a specific CLI (`claude`, `codex`, `opencode`) | Auto-detect from model name |
| `ORCHESTRATE_AGENT_DIR` | Override agent definition directory | unset |

## Model Routing

Models are automatically routed to the correct CLI based on naming conventions:

| Pattern | CLI | Examples |
|---------|-----|----------|
| `claude-*`, `opus*`, `sonnet*`, `haiku*` | `claude` | `claude-sonnet-4-6` |
| `gpt-*`, `o1*`, `o3*`, `o4*`, `codex*` | `codex` | `gpt-5.3-codex` |
| `opencode-*`, `provider/model` | `opencode` | `opencode/kimi-k2.5-free`, `anthropic/claude-sonnet-4-6` |

The `opencode-` prefix is stripped before passing to the CLI. The `provider/model` format (containing `/`) is passed through as-is.

Tool names in agent definitions are normalized for Claude's `--allowedTools` casing (e.g., `read` -> `Read`, `websearch` -> `WebSearch`). Codex and OpenCode currently do not expose tool allowlist flags in `exec/run`.

## Available Agents

`cleanup`, `commit`, `implement`, `implement-deliberate`, `implement-iterative`, `plan-slice`, `research-claude`, `research-codex`, `research-kimi`, `review`, `review-adversarial`, `review-quick`, `review-thorough`

See the `model-guidance` skill for detailed descriptions, model assignments, and selection guidance.

## Agent Definition Format

Agent definitions live in `agents/*.md` — markdown with YAML frontmatter:

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

These agent files are intentionally editable by end users after install. Customizing built-in prompts for a specific codebase is a supported workflow.

Lookup precedence for `run-agent.sh <agent-name>`:
1. `ORCHESTRATE_AGENT_DIR/<agent>.md` (if set)
2. `<workdir>/.agents/skills/run-agent/agents/<agent>.md`
3. `<workdir>/.claude/skills/run-agent/agents/<agent>.md`
4. bundled `agents/<agent>.md`

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Agent identifier (matches filename without `.md`) |
| `description` | yes | One-line description |
| `model` | yes | Default model (can be overridden with `-m`) |
| `effort` | no | `low` or `high` (default: `high`) |
| `tools` | no | Comma-separated tool list (default: `Read,Edit,Write,Bash,Glob,Grep`) |
| `skills` | no | List of skill names to load |

## Log Artifacts

Each run writes to `{scope-root}/logs/agent-runs/{agent-name}/`:

- `params.json` — run parameters
- `input.md` — composed prompt
- `output.json` — raw CLI output
- `report.md` — written by the subagent (the orchestrator reads this)
- `files-touched.txt` — derived from `output.json`

## Scope Roots

Log directories are auto-derived from scope variables (`SLICE_FILE`, `SLICES_DIR`, `BREADCRUMBS`, `PLAN_FILE`):

- project scope: `.runs/project/`
- plan scope: `.runs/plans/{plan-name}/`
- phase scope: `.runs/plans/{plan-name}/phases/{phase-name}/`
- slice scope: `.runs/plans/{plan-name}/slices/{slice-name}/` (or via phase)

For any scope root: `{scope-root}/scratch/`, `{scope-root}/scratch/code/smoke/`, `{scope-root}/logs/agent-runs/`
