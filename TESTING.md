# Testing

All commands below are meant to be run from the repository root.

## Unit tests

Run the run-agent script unit test suite:

```bash
bash tests/run-agent-unit.sh
```

Expected success output includes:

```text
PASS: run-agent script unit tests
```

## Dry-run smoke tests

Use dry-run to preview prompt composition and CLI routing without executing a live model run.

```bash
AGENT_RUNNER=skills/run-agent/scripts/run-agent.sh
```

Named agent dry-run:

```bash
"$AGENT_RUNNER" review --dry-run -v SLICES_DIR=/tmp/test
```

Ad-hoc dry-run with explicit model + prompt:

```bash
"$AGENT_RUNNER" --model anthropic/claude-sonnet-4-6 --prompt "Review the changes" --dry-run
```

Dry-run prints the composed prompt and final CLI command only.

## Live agent runs

Run a named agent without `--dry-run` to execute for real:

```bash
AGENT_RUNNER=skills/run-agent/scripts/run-agent.sh
"$AGENT_RUNNER" review -v SLICES_DIR=.runs/plans/my-plan/slices/01-foo
```

This writes run artifacts under `.runs/` (or `ORCHESTRATE_RUNS_DIR` if set).

## Troubleshooting / prerequisites

- Install at least one supported CLI: `claude`, `codex`, or `opencode`.
- Ensure your selected CLI is authenticated before live runs.
- If a command cannot find an agent by name, verify agent lookup paths or set `ORCHESTRATE_AGENT_DIR`.
- Use `--dry-run` first when validating new prompts or variables.
