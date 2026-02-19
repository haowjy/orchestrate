# Orchestrate Skill

Supervisor loop that reads a plan and autonomously launches agents to implement it — planning slices, writing code, reviewing, fixing issues, and committing.

## How It Works

The orchestrator is a **flexible loop**, not a rigid pipeline:

```
[research] -> plan-slice -> implement -> review -> (clean? commit : fix -> review) -> next slice
```

You write a plan (markdown). The orchestrator reads it and loops through agents until complete.

## Usage

```
/orchestrate <plan-file> [--plan-name NAME]
```

## Agent Execution

All agents are launched via `run-agent/scripts/run-agent.sh`. See the `run-agent` skill for:
- Agent definitions and formats (`run-agent/agents/`)
- Script documentation (`run-agent/scripts/`)
- Environment variables and configuration

## Agent Selection

See the `model-guidance` skill for guidance on when to use each agent variant (implement, review, research, etc.).

## Pipeline Details

See `SKILL.md` for the full supervisor loop documentation including:
- Plan runtime directory structure
- Step-by-step pipeline (setup → plan-slice → implement → review → commit → loop)
- Handoff snapshots
- Research (optional Step 0)
