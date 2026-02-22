# Orchestrate

Intent-first multi-agent toolkit for Claude Code, Codex, and OpenCode.

## Canonical Root

Orchestration state lives in one place:

- `.orchestrate/config.yaml`
- `.orchestrate/agents/*.md`
- `.orchestrate/skills/*/SKILL.md`
- `.orchestrate/references/*.md`
- `.orchestrate/runs/`
- `.orchestrate/session/`

The submodule at `orchestrate/` provides scripts and baseline assets.

## Core Runner

```bash
RUNNER=orchestrate/skills/run-agent/scripts/run-agent.sh
```

## Quick Start

```bash
# 1) create next slice
"$RUNNER" plan-slice -v PLAN_FILE=_docs/plans/my-plan.md --plan my-plan --slice slice-1

# 2) implement
"$RUNNER" implement --plan my-plan --slice slice-1

# 3) review (single or multi-model)
"$RUNNER" review --plan my-plan --slice slice-1
"$RUNNER" review --plan my-plan --slice slice-1 -m claude-opus-4-6

# 4) test
"$RUNNER" test --plan my-plan --slice slice-1

# 5) commit
"$RUNNER" commit --plan my-plan --slice slice-1
orchestrate/skills/run-agent/scripts/record-commit.sh --plan my-plan --slice slice-1
```

## Agent Set

Default agents are intentionally small:

- `design`
- `investigate`
- `research`
- `plan-slice`
- `implement`
- `review`
- `test`
- `commit`

`cleanup` is not a standalone agent. Use `review -> implement -> test` loops.

## Orchestration Style

Use an intent-first loop, not a rigid pipeline:

1. assess current state/risk
2. select next action(s)
3. run agent(s)
4. evaluate reports/artifacts
5. repeat until stop criteria are met

Model selection and review fan-out defaults come from:
- `.orchestrate/config.yaml`
- `.orchestrate/skills/model-guidance/SKILL.md`

These defaults are advisory. User intent and task constraints come first.

## Review Fan-Out

Default policy:

- low risk: 1 reviewer
- medium risk: 2 reviewers (distinct model families)
- high risk: 3 reviewers (distinct model families)
- material disagreement: tie-break review

## Paths and Artifacts

Run artifacts:
- `.orchestrate/runs/project/logs/agent-runs/<agent>-<pid>/...`
- `.orchestrate/runs/plans/<plan>/slices/<slice>/logs/agent-runs/<agent>-<pid>/...`

Session artifacts:
- `.orchestrate/session/project/index.log`
- `.orchestrate/session/plans/<plan>/...`

Common files per run:
- `params.json`
- `input.md`
- `output.json`
- `stderr.log`
- `report.md`
- `files-touched.txt`

## Install Notes

If your harness discovers skills from `.agents/skills` or `.claude/skills`, keep those synced from this repo's skill sources.

Typical sync:

```bash
# default: auto-apply when no conflicts, stop when conflicts exist
bash orchestrate/sync.sh pull

# quick submodule diffs
bash orchestrate/sync.sh pull --diff

# force apply even when conflicts exist
bash orchestrate/sync.sh pull --overwrite

# exclude patterns from sync/preview
bash orchestrate/sync.sh pull --exclude 'review/references/*'
```

## Testing

```bash
bash tests/run-agent-unit.sh
```

## License

MIT
