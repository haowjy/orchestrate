---
name: run-agent
description: Agent execution engine — composes prompts, routes models, and writes run artifacts.
---

# Run-Agent — Execution Engine

Single entry point for agent execution. Composes a prompt from model + skills + task, routes to the correct CLI (`claude`, `codex`, `opencode`), and logs each run.

Canonical root: `.orchestrate/`

Runner path:
```bash
RUNNER=.agents/.orchestrate/skills/run-agent/scripts/run-agent.sh
```

## Ad-Hoc Mode (Primary)

Compose runs dynamically by specifying model, skills, and prompt:

```bash
# Model + skills + prompt
"$RUNNER" --model claude-sonnet-4-6 --skills review,smoke-test \
    -p "Adversarial review: write tests to break the auth code"

# Model + prompt (no skills)
"$RUNNER" --model gpt-5.3-codex -p "Investigate the failing collab tests"

# With plan/slice context
"$RUNNER" --model gpt-5.3-codex --skills smoke-test,scratchpad \
    --plan my-plan --slice slice-1

# Dry run — see composed prompt + CLI command without executing
"$RUNNER" --model claude-sonnet-4-6 --skills review -p "Review auth" --dry-run
```

## Agent Definitions (Optional Legacy)

If `agents/*.md` files exist under `.orchestrate/agents/` or the run-agent agents directory, you can still reference them by name:

```bash
"$RUNNER" review --plan my-plan --slice slice-1
"$RUNNER" implement -m claude-opus-4-6  # override model
```

Agent lookup precedence:
1. `ORCHESTRATE_AGENT_DIR/<name>.md` (if set)
2. `.orchestrate/agents/<name>.md`

This is a backwards-compatibility mechanism. The orchestrator should prefer ad-hoc composition via `--model` + `--skills` + `-p`.

## Plan/Slice Shorthand

- `--plan X` sets `PLAN_FILE=.orchestrate/runs/plans/X/plan.md`
- `--plan X --slice Y` sets:
  - `SLICE_FILE=.orchestrate/runs/plans/X/slices/Y/slice.md`
  - `SLICES_DIR=.orchestrate/runs/plans/X/slices/Y`

`--slice` requires `--plan` or `ORCHESTRATE_PLAN` env var.

## Key Flags

| Flag | Description |
|------|-------------|
| `--model MODEL` / `-m` | Model to use (auto-routes to correct CLI) |
| `--skills a,b,c` | Skills to compose into the prompt |
| `-p "prompt"` | Task prompt |
| `-f path/to/file` | Reference file appended to prompt |
| `-v KEY=VALUE` | Template variable |
| `--plan NAME` | Plan shorthand |
| `--slice NAME` | Slice shorthand |
| `-D brief\|standard\|detailed` | Report detail level (default: `standard`) |
| `--dry-run` | Show composed prompt without executing |
| `-C DIR` | Working directory for subprocess |

## Output Artifacts

Each run writes to `{scope-root}/logs/agent-runs/{label}-{PID}/`:

- `params.json` — run parameters
- `input.md` — composed prompt
- `output.json` — raw CLI output
- `stderr.log` — CLI diagnostics (also streamed to terminal)
- `report.md` — written by the subagent
- `files-touched.txt` — derived from output.json

## Scope Rules

Scope root is inferred from template variables:
1. `SLICE_FILE` → slice directory
2. `SLICES_DIR` → slices directory
3. `PLAN_FILE` → plan directory
4. fallback: `.orchestrate/runs/project`

Parallel runs are safe — PID-based log dirs keep them separate.

## Model Routing

| Pattern | CLI |
|---------|-----|
| `claude-*`, `opus*`, `sonnet*`, `haiku*` | Claude (`claude -p`) |
| `gpt-*`, `o1*`, `o3*`, `o4*`, `codex*` | Codex (`codex exec`) |
| `opencode-*`, `provider/model` | OpenCode (`opencode run`) |

Override with `ORCHESTRATE_DEFAULT_CLI`.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ORCHESTRATE_ROOT` | Override orchestrate root (default: `<repo>/.orchestrate`) |
| `ORCHESTRATE_PLAN` | Default plan name for `--slice` shorthand |
| `ORCHESTRATE_DEFAULT_CLI` | Force all routing to a specific CLI |
| `ORCHESTRATE_AGENT_DIR` | Override agent definition directory |
| `ORCHESTRATE_CODEX_HOME` | Codex state dir fallback |

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `record-commit.sh --plan NAME [--slice NAME]` | Record latest commit |
| `log-inspect.sh <output.json> [summary\|tools\|errors\|files]` | Inspect run logs |
