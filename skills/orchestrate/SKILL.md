---
name: orchestrate
description: Multi-model supervisor that discovers skills, picks models, and composes runs. Use when executing multi-step plans across multiple models.
allowed-tools: Bash(*/run-agent/scripts/run-agent.sh *), Bash(*/run-agent/scripts/run-index.sh *), Bash(*/run-agent/scripts/log-inspect.sh *), Bash(*/run-agent/scripts/load-model-guidance.sh *), Bash(*/orchestrate/scripts/load-skill-policy.sh *), Bash(git *), Bash(cat *), Bash(mkdir *), Bash(cp *), Bash(date *)
---

# Orchestrate — Multi-Model Supervisor

> **ROLE: You are a supervisor.** Your primary tool is `run-agent.sh`. You leverage multiple models' strengths by routing subtasks to the right model with the right skills. You NEVER write implementation code yourself.

## Canonical Paths

Skill-local:

- sibling skills (resolved by explicit name): `../<skill-name>/SKILL.md`
- orchestration policy references: `references/*.md`
- skill policy loader: `scripts/load-skill-policy.sh`
- model guidance loader: `../run-agent/scripts/load-model-guidance.sh` (run-agent skill)
- run explorer: `../run-agent/scripts/run-index.sh` (run-agent skill)

Runtime: `.orchestrate/` (gitignored)

- runs: `.orchestrate/runs/agent-runs/<run-id>/`
- index: `.orchestrate/index/runs.jsonl`
- session: `.orchestrate/session/plans/`
- tracked skills config: `.orchestrate/tracked-skills`

Runner scripts (relative to this skill directory):

- `../run-agent/scripts/run-agent.sh` — launch a subagent run
- `../run-agent/scripts/run-index.sh` — inspect and manage runs

## Skill Set Policy

There is **no hierarchy** of skills. Use a flat, explicit skill set as a recommendation baseline.

1. Load active policy content via `scripts/load-skill-policy.sh` (default mode: `concat`).
2. Resolve active skill names via `scripts/load-skill-policy.sh --mode skills`.
3. Resolve each listed skill as `../<skill-name>/SKILL.md` and skip missing entries.
4. Treat the resolved active skill set as the default recommendation for `--skills`.
5. You may add other skills when the task clearly needs them.

Policy file format:
- One skill name per line (plain text) or bullet item (e.g., `- review`).
- `#` comments are allowed.
- Unknown skill names should be ignored.

## Skill Discovery

At startup, discover available capabilities:

1. Load orchestration policy via `scripts/load-skill-policy.sh` (see Skill Set Policy above).
2. Resolve only the listed skill names to `../<skill-name>/SKILL.md`.
3. Read each resolved `SKILL.md` frontmatter for `name:` and `description:`.
4. Match the current task against the resolved active skill set first, then add extras only when justified.

Skills are your building blocks. A run is `model + skills + prompt` — no named agent definitions needed.

## Model Selection

Load model guidance via `../run-agent/scripts/load-model-guidance.sh` before choosing models. This loader enforces precedence:
- `../run-agent/references/default-model-guidance.md` is used as the base
- if any files exist under `../run-agent/references/model-guidance/*.md`, they replace the default entirely

Use the loaded guidance to decide:
- Model strengths and weaknesses
- Which model to pick for which task type
- How to combine skills for variant behaviors

## Run Composition

Your primary tool is `run-agent.sh`. Compose runs by picking:
1. **Model** (`--model` or `-m`) — based on model-guidance for the task type
2. **Skills** (`--skills`) — comma-separated skill names to load into the subagent's prompt
3. **Prompt** (`-p`) — what the subagent should do
4. **Context files** (`-f`) — extra files appended to the prompt
5. **Template vars** (`-v KEY=VALUE`) — injected into skill templates
6. **Labels** (`--label KEY=VALUE`) — run metadata for filtering/grouping
7. **Session** (`--session ID`) — group related runs in one orchestration pass

Key flags:
```
--model MODEL        Model to use (routes to correct CLI automatically)
--agent NAME         Agent profile for defaults + permissions
--skills a,b,c       Skills to compose into the prompt
-p "prompt"          Task prompt
-f path/to/file      Reference file (appended to prompt)
-v KEY=VALUE         Template variable
--label KEY=VALUE    Run metadata label (repeatable)
--session ID         Session grouping for related runs
-D brief|standard|detailed   Report detail level
--dry-run            Show composed prompt without executing
```

## Run Explorer

Use `run-index.sh` to inspect and manage runs:

```bash
../run-agent/scripts/run-index.sh list                          # List recent runs
../run-agent/scripts/run-index.sh list --failed                 # List failed runs
../run-agent/scripts/run-index.sh show @latest                  # Show last run details
../run-agent/scripts/run-index.sh report @latest                # Read last run's report
../run-agent/scripts/run-index.sh stats --session $SESSION_ID   # Session statistics
../run-agent/scripts/run-index.sh continue @latest -p "fix X"   # Follow up on a run
../run-agent/scripts/run-index.sh retry @last-failed            # Retry a failed run
```

## Cardinal Rules

1. **During planning:** Stop and collaborate with the user. Get alignment before executing.
2. **During execution:** Run autonomously. Never stop to ask unless unrecoverably blocked.
3. **Never push** to remote. Commit is fine, push is not.
4. **Primary tool is `run-agent.sh`** — compose prompts and launch subagents. Do trivial things directly only when a subagent would be wasteful.
5. **Evaluate subagent output** — read reports, decide if quality is sufficient or if rework is needed.
6. **Never write implementation code.** You compose prompts and launch agents that do the work.

## Core Loop

1. Understand what needs to happen
2. Pick the best model for the subtask (via model-guidance)
3. Pick the right skills to attach (via skill discovery)
4. Launch via `run-agent.sh`
5. Evaluate the subagent's output (read `report.md` or use `run-index.sh report @latest`)
6. Decide what to do next

## Worked Example: Task Execution

```bash
SESSION_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"

# 1. Implement — codex for cross-stack, sonnet for UI iteration
../run-agent/scripts/run-agent.sh --agent coder --skills scratchpad \
    --session "$SESSION_ID" \
    -p "Implement the feature described in the plan." \
    -f path/to/plan.md

# 2. Review — fan out to multiple model families for confidence
../run-agent/scripts/run-agent.sh --agent reviewer --model gpt-5.3-codex \
    --session "$SESSION_ID" &
../run-agent/scripts/run-agent.sh --agent reviewer --model claude-opus-4-6 \
    --session "$SESSION_ID" &
wait
# Read both reports, synthesize findings

# 3. Commit — haiku for fast, clean commit messages
../run-agent/scripts/run-agent.sh --model claude-haiku-4-5 \
    --session "$SESSION_ID" \
    -p "Stage and commit changes with a concise message."

# 4. Check session stats
../run-agent/scripts/run-index.sh stats --session "$SESSION_ID"
```

Adapt freely: skip review for trivial changes, run research before implementing unfamiliar code, add adversarial testing for security-critical paths.

## Review Fan-Out

When to fan out:
- **Low risk** (docs, config, renames): 1 reviewer
- **Medium risk** (feature work, refactors): 2 reviewers from distinct model families
- **High risk** (auth, concurrency, data migration): 3 reviewers from distinct model families

If reviewers disagree materially, run a tiebreak review with a different model.

## Parallel Runs

PID-based log directories keep parallel runs separate automatically. Use `&` + `wait`:

```bash
../run-agent/scripts/run-agent.sh --model gpt-5.3-codex --skills researching -p "Research approach A" &
../run-agent/scripts/run-agent.sh --model claude-sonnet-4-6 --skills researching -p "Research approach B" &
wait
```

## Usage

```
/orchestrate [task description or plan file]
```

### Completion

Stop when:
- User's intent is fully satisfied
- Unrecoverable failure (no progress after retry)
- All subtasks in scope are done
