---
name: run-agent
description: Agent execution engine — composes prompts, routes models, and writes run artifacts.
---

# Run-Agent — Execution Engine

Single entry point for agent execution. A run is `model + skills + prompt` — no "agent" abstraction. Routes to the correct CLI (`claude`, `codex`, `opencode`), logs everything, and writes structured index entries.

Skills source: sibling skills (`../`). Runtime artifacts: `.orchestrate/`.

Runner path:
```bash
RUNNER=scripts/run-agent.sh
INDEX=scripts/run-index.sh
```

## Run Composition

Compose runs dynamically by specifying model, skills, and prompt:

```bash
# Model + skills + prompt
"$RUNNER" --model claude-sonnet-4-6 --skills review,smoke-test \
    -p "Adversarial review: write tests to break the auth code"

# Model + prompt (no skills)
"$RUNNER" --model gpt-5.3-codex -p "Investigate the failing collab tests"

# With labels and session grouping
"$RUNNER" --model gpt-5.3-codex --skills smoke-test \
    --session my-session --label task-type=coding --label ticket=PAY-123 \
    -p "Implement the feature"

# With template variables for project-specific paths
"$RUNNER" --model gpt-5.3-codex \
    -v PLAN_FILE=path/to/plan.md -v SLICE_FILE=path/to/slice.md \
    -p "Implement {{SLICE_FILE}} from {{PLAN_FILE}}"

# Dry run — see composed prompt + CLI command without executing
"$RUNNER" --model claude-sonnet-4-6 --skills review -p "Review auth" --dry-run
```

## Key Flags

| Flag | Description |
|------|-------------|
| `--model MODEL` / `-m` | Model to use (auto-routes to correct CLI) |
| `--skills a,b,c` | Skills to compose into the prompt |
| `-p "prompt"` | Task prompt |
| `-f path/to/file` | Reference file appended to prompt |
| `-v KEY=VALUE` | Template variable substitution (repeatable) |
| `--session ID` | Session ID for grouping related runs |
| `--label KEY=VALUE` | Run metadata label (repeatable) |
| `--task-type TYPE` | Shorthand for `--label task-type=TYPE` (default: `coding`) |
| `-D brief\|standard\|detailed` | Report detail level (default: `standard`) |
| `--continue-run REF` | Continue a previous run's harness session |
| `--fork` | Fork the session on continuation (default where supported) |
| `--in-place` | Resume without forking (always for Codex) |
| `--dry-run` | Show composed prompt without executing |
| `-C DIR` | Working directory for subprocess |

## Output Artifacts

Each run writes to `.orchestrate/runs/agent-runs/<run-id>/`:

- `params.json` — run parameters and metadata
- `input.md` — composed prompt
- `output.jsonl` — raw CLI output (stream-json or JSONL)
- `stderr.log` — CLI diagnostics (also streamed to terminal)
- `report.md` — written by the subagent (or extracted as fallback)
- `files-touched.nul` — NUL-delimited file paths (canonical machine format)
- `files-touched.txt` — newline-delimited file paths (human-readable)

## Run Index

Two-row append-only index at `.orchestrate/index/runs.jsonl`:
- **Start row** (written before execution): `status: "running"` — provides crash visibility.
- **Finalize row** (written after execution): `status: "completed"|"failed"` with exit code, duration, token usage, git metadata.

A start row with no matching finalize row means the run crashed or is still in progress.

## Structured Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Agent/model error (bad output, task failure) |
| 2 | Infrastructure error (CLI not found, harness crash) |
| 3 | Timeout |
| 130 | Interrupted (SIGINT / user cancel) |
| 143 | Terminated (SIGTERM) |

## Model Routing

| Pattern | CLI |
|---------|-----|
| `claude-*`, `opus*`, `sonnet*`, `haiku*` | Claude (`claude -p`) |
| `gpt-*`, `o1*`, `o3*`, `o4*`, `codex*` | Codex (`codex exec`) |
| `opencode-*`, `provider/model` | OpenCode (`opencode run`) |

Routing is automatic from the selected model.

## Run Explorer CLI

`run-index.sh` provides index-based run inspection:

```bash
"$INDEX" list                          # List recent runs
"$INDEX" list --failed --json          # Failed runs as JSON
"$INDEX" show @latest                  # Show last run details
"$INDEX" report @latest                # Read last run's report
"$INDEX" logs @latest --tools          # Tool call summary
"$INDEX" files @latest                 # Files touched
"$INDEX" stats                         # Aggregate statistics
"$INDEX" continue @latest -p "fix X"   # Continue a run's session
"$INDEX" retry @last-failed            # Retry a failed run
"$INDEX" maintain --compact            # Archive old index entries
```

Run references: full ID, unique prefix (8+ chars), `@latest`, `@last-failed`, `@last-completed`.

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `run-index.sh` | Run explorer CLI (list, show, report, logs, files, stats, continue, retry, maintain) |
| `log-inspect.sh` | Inspect run logs (summary, tools, errors, files, search) |
| `extract-files-touched.sh` | Extract file paths from run output |
| `extract-harness-session-id.sh` | Extract harness session/thread ID from output |
| `extract-report-fallback.sh` | Extract last assistant message as report fallback |
| `load-model-guidance.sh` | Load model guidance with override precedence |
