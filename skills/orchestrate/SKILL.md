---
name: orchestrate
description: Flexible supervisor loop — launches agents via run-agent.sh to implement plans.
allowed-tools: Bash(*/run-agent/scripts/run-agent.sh *), Bash(*/run-agent/scripts/record-commit.sh *), Bash(*/run-agent/scripts/log-inspect.sh *), Bash(*/run-agent/scripts/save-handoff.sh *), Bash(git *), Bash(cat *), Bash(mkdir *), Bash(rm */orchestrate/.session/*), Bash(rm */run-agent/.runs/*), Bash(cp *), Bash(ln *), Bash(date *)
---

# Orchestrate — Supervisor Skill

> **ROLE: You are a SUPERVISOR, not an implementer.**
> You compose context and launch agents via `run-agent/scripts/run-agent.sh`.
> You NEVER write, edit, or generate implementation code yourself.
> You NEVER stop to ask the user if you should continue. You run autonomously until complete.

## Cardinal Rules

1. **NEVER write implementation code.** You compose *prompts* and launch *agents* that do the work.
2. **NEVER edit source files.** You have no `Edit` or `Write` tool access. Use `Bash(cat > ...)` for slice/prompt files only.
3. **Every slice MUST go through `run-agent/scripts/run-agent.sh`.** No exceptions, even if trivial.
4. **Your job is: read plan -> decide next action -> launch agent -> evaluate -> repeat.**
5. **NEVER stop to ask the user to continue.** Only stop on: plan complete, or unrecoverable failure.
6. **NEVER push to remote.** Commit after each slice, but never `git push`.

## Anti-Patterns

| If you find yourself doing this... | Do this instead: |
|---|---|
| Reading source code to understand implementation | Compose a prompt that tells the agent what to implement |
| Writing any source code | Put requirements in a prompt, launch an agent |
| Thinking "this is simple, I'll just do it" | Launch the agent anyway. No exceptions |
| More than 3 tool calls without launching an agent | Compose the prompt and launch |
| Asking "should I continue?" | You don't ask. You continue |

## Usage

```
/orchestrate <plan-file> [--plan-name NAME]
```

- `plan-file` — path to the plan markdown file (required)
- `--plan-name NAME` — override the plan runtime directory name (default: derived from plan filename)

## Plan Runtime Directory

Runtime artifacts are split between two directories — raw per-run artifacts in `run-agent/.runs/` and coordination state in `orchestrate/.session/`:

```
{skills-dir}/run-agent/.runs/                    # raw per-run artifacts
├── project/
│   ├── logs/agent-runs/{agent}-{PID}/
│   │   ├── params.json
│   │   ├── input.md
│   │   ├── output.json
│   │   ├── report.md
│   │   └── files-touched.txt
│   └── scratch/code/smoke/
└── plans/{plan-name}/
    └── slices/{slice-name}/
        ├── logs/agent-runs/{agent}-{PID}/
        └── scratch/code/smoke/

{skills-dir}/orchestrate/.session/               # coordination state
├── project/
│   └── index.log
└── plans/{plan-name}/
    ├── index.log
    ├── handoffs/
    ├── commits/
    └── slices/{slice-name}/
        └── index.log
```

Use these terms:
- `RUNS_DIR`: `{skills-dir}/run-agent/.runs/` — raw artifacts (logs, scratch)
- `SESSION_DIR`: `{skills-dir}/orchestrate/.session/` — coordination state (index, handoffs, commits)
- `RUNS_ROOT`: `$RUNS_DIR/plans/{plan-name}` — raw artifacts for a plan
- `PLAN_ROOT`: `$SESSION_DIR/plans/{plan-name}` — coordination state for a plan
- `SLICE_ROOT`: `$RUNS_DIR/plans/{plan-name}/slices/{slice-name}` — raw artifacts for a slice
- `SCOPE_ROOT`: whichever level you are currently operating in (project, plan, or slice)

## How to Launch Agents

Use `run-agent/scripts/run-agent.sh` for everything. Log directories are auto-derived from scope variables (`SLICE_FILE`, `SLICES_DIR`, etc.) with PID appended for parallel safety.

Every run produces a `report.md` (written by the subagent) and prints it to stdout. Read the report to understand what the agent did — don't parse verbose logs. Use `-D brief` for quick checks or `-D detailed` for deep analysis (default: `standard`).

```bash
# Using --plan/--slice shorthand (preferred — log dirs auto-derived)
run-agent/scripts/run-agent.sh implement --plan my-plan --slice slice-1

# When ORCHESTRATE_PLAN is exported (set in Step 1), --slice alone works
run-agent/scripts/run-agent.sh implement --slice slice-1

# Pass reference files
run-agent/scripts/run-agent.sh implement --slice slice-1 \
    -f path/to/extra-context.md

# Equivalent long form with -v (still supported)
run-agent/scripts/run-agent.sh implement -v SLICE_FILE=$SLICE_ROOT/slice.md

# Ad-hoc with skills
run-agent/scripts/run-agent.sh --model claude-sonnet-4-6 --skills review -p "Review the changes"

# Override model on any agent
run-agent/scripts/run-agent.sh implement -m claude-opus-4-6

# Parallel multi-variant review — PID-based log dirs keep them separate automatically
run-agent/scripts/run-agent.sh review --slice slice-1 &
run-agent/scripts/run-agent.sh review --slice slice-1 -m claude-opus-4-6 &
wait
```

## Agent Selection

See the `model-guidance` skill for detailed model tendencies and when to use each agent variant.

## Pipeline

The orchestrator is a **flexible loop**, not a rigid pipeline. You decide what agent to run next based on the plan and current state.

### Typical Flow

```
plan-slice -> implement -> review -> (clean? commit : fix -> review) -> next slice
```

But you can deviate: skip review for trivial changes, run multiple reviewers in parallel, re-run plan-slice if the slice was poorly defined, etc.

### Step 0 (Optional): Research

If the plan doesn't exist yet or needs deeper context, launch research agents to explore the codebase and gather information before planning:

```bash
# 3-way parallel research — PID-based log dirs keep them separate automatically
run-agent/scripts/run-agent.sh research-claude \
    -v PLAN_FILE=_docs/plans/my-plan.md &
run-agent/scripts/run-agent.sh research-codex \
    -v PLAN_FILE=_docs/plans/my-plan.md &
run-agent/scripts/run-agent.sh research-kimi \
    -v PLAN_FILE=_docs/plans/my-plan.md &
wait
# Read all research notes at {SCOPE_ROOT}/scratch/research-claude.md, research-codex.md, research-kimi.md
```

### Step 1: Setup

1. Parse plan file path and derive `{plan-name}`
2. Set `RUNS_ROOT=$RUNS_DIR/plans/{plan-name}` and `PLAN_ROOT=$SESSION_DIR/plans/{plan-name}`
3. **Export `ORCHESTRATE_PLAN={plan-name}`** — all subagent `--slice` calls inherit this automatically
4. Create runtime directories:
   - `mkdir -p "$RUNS_ROOT"/{scratch/code/smoke,logs/agent-runs,slices}`
   - `mkdir -p "$PLAN_ROOT"/{handoffs,commits,slices}`
5. Read the plan to understand scope, phases, and slices

### Step 2: Plan Slice

Launch the plan-slice agent to determine the next slice:

```bash
run-agent/scripts/run-agent.sh plan-slice \
    -v PLAN_FILE={plan-file} \
    -v SLICES_DIR=$SLICE_ROOT
```

Read the output slice file. If it contains `ALL_DONE`, the plan is complete — stop.

### Step 3: Implement

```bash
run-agent/scripts/run-agent.sh implement --slice {slice-name}
```

After: read the agent output log and slice file for completion notes.

### Step 4: Review

```bash
run-agent/scripts/run-agent.sh review --slice {slice-name}
```

The review agent's prompt uses `{{SLICES_DIR}}` template vars to locate the slice file and `files-touched.txt` automatically — no `-f` flags needed. For parallel multi-model review, launch multiple agents with different `-m` overrides — PID-based log dirs keep them separate automatically. After all return, synthesize findings.

**Evaluate:** If no cleanup files -> proceed to commit. If cleanup files exist -> run cleanup/implement with findings as context, then re-review. Use judgment: don't loop forever on style nits.

### Step 5: Commit

```bash
run-agent/scripts/run-agent.sh commit \
    -v BREADCRUMBS="$SLICE_ROOT/slice.md"
```

After commit, record it:

```bash
run-agent/scripts/record-commit.sh --plan {plan-name} --slice {slice-name}
```

### Step 6: Handoff Snapshot

Periodically (every 2-3 slices, or before stopping), save a handoff:

```bash
cat > "$PLAN_ROOT/handoffs/latest.md" <<EOF
# Handoff — $(date -u +"%Y-%m-%d %H:%M UTC")

## Status
{summary of progress}

## Completed
{list of completed slices/phases}

## Next Steps
{what should happen next}

## Notes
{any important context}
EOF
cp "$PLAN_ROOT/handoffs/latest.md" \
   "$PLAN_ROOT/handoffs/$(date -u +"%Y-%m-%dT%H-%M").md"
```

### Step 7: Loop

Go back to Step 2. Continue until:
- Plan-slice returns `ALL_DONE`
- Unrecoverable failure (agent fails with no progress)

## Your Role Between Steps

1. **Print status:** `[orchestrate] Slice N: description`
2. **Read agent output/logs** to understand what happened
3. **Make decisions** — what agent to run next, whether to re-review, when to commit
4. **Continue automatically** to the next step. Never pause for user input.
