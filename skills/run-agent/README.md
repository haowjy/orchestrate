# Run-Agent — Execution Engine

Single entry point for agent execution. Composes prompts from model + skills + task, routes to the correct CLI tool, and logs each run.

Canonical runtime root: `.orchestrate/`

## Runner

```bash
RUNNER=.agents/.orchestrate/skills/run-agent/scripts/run-agent.sh
```

## Quick Start

```bash
# Ad-hoc: model + skills + prompt (primary mode)
"$RUNNER" --model claude-sonnet-4-6 --skills review -p "Review these changes"

# Ad-hoc with plan/slice context
"$RUNNER" --model gpt-5.3-codex --skills smoke-test,scratchpad \
    --plan demo --slice slice-1

# Named agent (optional legacy — if agents/*.md files exist)
"$RUNNER" review --plan demo --slice slice-1

# Dry run — see composed prompt without executing
"$RUNNER" --model gpt-5.3-codex --skills review --dry-run -p "Review auth"
```

## How It Works

1. Parse model, skills, prompt, and context flags
2. Route model to the correct CLI (`claude`, `codex`, `opencode`)
3. Load skill bodies from `.orchestrate/skills/*/SKILL.md`
4. Compose the final prompt (skills + template vars + reference files + task prompt)
5. Execute the CLI command
6. Log artifacts to `{scope-root}/logs/agent-runs/{label}-{PID}/`

## Output Artifacts

Each run writes:
- `params.json` — run parameters
- `input.md` — composed prompt
- `output.json` — raw CLI output
- `stderr.log` — CLI diagnostics
- `report.md` — written by the subagent
- `files-touched.txt` — derived from output.json

Location:
- Ad-hoc: `.orchestrate/runs/project/logs/agent-runs/...`
- Plan/slice: `.orchestrate/runs/plans/<plan>/slices/<slice>/logs/agent-runs/...`

## Agent Definitions (Optional)

If you want pre-configured agent templates, create `.orchestrate/agents/<name>.md` with YAML frontmatter:

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

Your prompt template here. Use {{TEMPLATE_VARS}} for dynamic values.
```

The orchestrator prefers dynamic composition (`--model` + `--skills` + `-p`) over static agent definitions. Agent files are a convenience for frequently-used combinations.

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `scripts/record-commit.sh` | Record latest commit for a plan/slice |
| `scripts/log-inspect.sh` | Inspect run logs without loading full output |
| `scripts/extract-files-touched.sh` | Parse touched files from a run log |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ORCHESTRATE_ROOT` | Override orchestrate root (default: `<repo>/.orchestrate`) |
| `ORCHESTRATE_PLAN` | Default plan name for `--slice` shorthand |
| `ORCHESTRATE_DEFAULT_CLI` | Force all routing to a specific CLI |
| `ORCHESTRATE_AGENT_DIR` | Override agent definition directory |
| `ORCHESTRATE_CODEX_HOME` | Codex state dir fallback |

## Tests

```bash
tests/run-agent-unit.sh
```
