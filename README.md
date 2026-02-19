# Orchestrate

Stop satisficing with one CLI. Use Claude Code, Codex, and OpenCode together — each doing what it's best at.

Orchestrate is a multi-agent supervisor that routes specialized agents across CLI harnesses. Codex writes the code, Opus reviews it, Haiku commits it. You write a plan, it handles the rest.

## Why

### `run-agent.sh` — one wrapper, every CLI

Agents are just markdown files with a model name in YAML frontmatter. `run-agent.sh` inspects the model string and routes to the right CLI — Claude Code, Codex, or OpenCode — normalizing prompt composition, tool allowlists, and execution along the way.

Each CLI has strengths: Codex for exhaustive code generation, Claude Opus for thoughtful review, Sonnet for fast iteration. You shouldn't have to care about the plumbing differences between them — different tool name conventions (PascalCase vs lowercase), different effort flags, different JSON output formats. `run-agent.sh` handles all of it so agents are portable across harnesses.

### LLM-controlled agent loops

Most multi-agent setups are fixed pipelines: step A, then B, then C. Orchestrate is closer to [aider's architect mode](https://aider.chat/docs/usage/modes.html) or [Ralph](https://github.com/snarktank/ralph)-style bash loops, but the supervisor is an LLM, not a script.

The supervisor reads your plan, decides what agent to run next, reads the report back, and adapts — choosing which agent variant to use, whether to re-review, when to escalate from `implement` to `implement-deliberate`. It can skip research if the plan is clear, run parallel reviewers for risky slices, or switch implementation strategy mid-plan.

The structured loop (plan-slice, implement, review, fix/commit, repeat) gives it a framework, but the LLM makes the judgment calls within it.

## Install

### Claude Code (recommended)

```bash
# Plugin marketplace
/plugin marketplace add jimmyyao/orchestrate

# Or load directly
claude --plugin-dir /path/to/orchestrate
```

### Codex

```bash
# Clone into your project, then install
git clone https://github.com/jimmyyao/orchestrate.git /tmp/orchestrate
/tmp/orchestrate/scripts/install.sh codex
```

### OpenCode

```bash
# Clone into your project, then install
git clone https://github.com/jimmyyao/orchestrate.git /tmp/orchestrate
/tmp/orchestrate/scripts/install.sh opencode
```

Both Codex and OpenCode discover skills via `.agents/skills/` — the install script symlinks them there.

## Getting Started

1. Write a plan file (e.g., `_docs/my-plan.md`) describing what to build
2. Run `/orchestrate:orchestrate _docs/my-plan.md`
3. The orchestrator runs autonomously until complete

## How It Works

```mermaid
flowchart LR
    R["Research\n(optional)"] --> PS[Plan-Slice]
    PS --> I[Implement]
    I --> Rev[Review]
    Rev -->|clean| C[Commit]
    Rev -->|issues| F[Fix]
    F --> Rev
    C -->|more slices| PS
    C -->|done| D((Done))
```

You write a plan (markdown). The orchestrator reads it and autonomously loops through:

1. **Research** (optional) — explores the codebase and web to inform planning
2. **Plan-slice** — determines the next self-contained unit of work
3. **Implement** — writes the code
4. **Review** — checks for issues
5. **Cleanup** — fixes any violations found
6. **Commit** — stages and commits with a clean message
7. **Repeat** until the plan is done

## Cross-Harness Architecture

```mermaid
flowchart TB
    S[Supervisor LLM] -->|"chooses agent + params"| R["run-agent.sh"]
    A["Agent Definitions\n(markdown + YAML frontmatter)"] -->|"model, tools, prompt"| R
    R -->|"claude-*, opus*, sonnet*, haiku*"| CC[Claude Code]
    R -->|"gpt-*, o1*, o3*, o4*, codex*"| CX[Codex]
    R -->|"provider/model, opencode-*"| OC[OpenCode]
```

The skill structure works natively across all three CLIs:

| CLI | Discovery | Install |
|-----|-----------|---------|
| **Claude Code** | `.claude-plugin/plugin.json` → `skills/` | Marketplace or `--plugin-dir` |
| **Codex** | `.agents/skills/*/SKILL.md` (walks to git root) | `scripts/install.sh codex` |
| **OpenCode** | `.agents/skills/` + `.claude/skills/` (walks up) | `scripts/install.sh opencode` |

Model routing is automatic — agent definitions specify a model name, and `run-agent.sh` routes to the correct CLI:

| Model Pattern | CLI | Examples |
|---------------|-----|----------|
| `claude-*`, `opus*`, `sonnet*`, `haiku*` | `claude` | `claude-sonnet-4-6`, `opus` |
| `gpt-*`, `o1*`, `o3*`, `o4*`, `codex*` | `codex` | `gpt-5.3-codex`, `o4-mini` |
| `opencode-*`, `provider/model` | `opencode` | `opencode/kimi-k2.5-free`, `anthropic/claude-sonnet-4-6` |

Override routing with `ORCHESTRATE_DEFAULT_CLI=opencode` to force all agents through a specific CLI.

## Repository Structure

```
orchestrate/
├── .claude-plugin/          # Plugin manifest
│   ├── plugin.json
│   └── marketplace.json
├── scripts/
│   └── install.sh           # Cross-CLI install helper
├── skills/
│   ├── orchestrate/         # Supervisor brain (loop logic only)
│   │   ├── SKILL.md
│   │   └── README.md
│   ├── run-agent/           # Execution engine
│   │   ├── SKILL.md
│   │   ├── README.md
│   │   ├── agents/          # All agent definitions
│   │   └── scripts/         # run-agent.sh, lib/, utilities
│   ├── research/            # Research methodology skill
│   │   └── SKILL.md
│   ├── plan-slice/          # Slice planning skill
│   │   └── SKILL.md
│   ├── review/              # Code review skill + rules
│   │   ├── SKILL.md
│   │   └── references/
│   └── model-guidance/      # Model selection guidance
│       └── SKILL.md
├── README.md
└── LICENSE
```

## Agent Types

### Research

| Agent | Model | Focus |
|---|---|---|
| `research-claude` | claude-sonnet-4-6 | Web + codebase exploration |
| `research-codex` | gpt-5.3-codex | Deep codebase analysis + web search |
| `research-kimi` | opencode/kimi-k2.5-free | Alternative perspective via Kimi |

### Implementation

| Agent | Model | Best For |
|---|---|---|
| `implement` | gpt-5.3-codex | Default — most slices |
| `implement-iterative` | claude-sonnet-4-6 | Fast UI iteration loops |
| `implement-deliberate` | claude-opus-4-6 | Complex logic, subtle bugs |

### Review

| Agent | Model | Effort | Personality |
|---|---|---|---|
| `review` | claude-opus-4-6 | high | Thoughtful senior dev — SOLID, consistency, clean code |
| `review-thorough` | gpt-5.3-codex | high | Exhaustive auditor — SOLID, consistency, clean code deep-dive |
| `review-quick` | gpt-5.3-codex | low | Fast sanity check — obvious bugs and blockers only |
| `review-adversarial` | claude-sonnet-4-6 | high | Adversarial tester — writes scratch tests to break the code |

All review agents support **dual mode**: given a plan, they review the plan; given implemented code, they review the code.

### Utility

| Agent | Model | Purpose |
|---|---|---|
| `plan-slice` | gpt-5.3-codex | Creates next implementable slice from a plan |
| `cleanup` | gpt-5.3-codex | Targeted fix from review findings |
| `commit` | claude-haiku-4-5 | Clean commit message from working tree |

## Running Agents Directly

```bash
# Run an agent by name
run-agent/scripts/run-agent.sh review -v SLICES_DIR=.runs/plans/my-plan/slices/01-foo

# Override model on any agent
run-agent/scripts/run-agent.sh implement -m claude-opus-4-6

# Ad-hoc (no agent definition)
run-agent/scripts/run-agent.sh --model claude-sonnet-4-6 --skills review -p "Review the changes"

# Dry run — see composed prompt + CLI command without executing
run-agent/scripts/run-agent.sh review --dry-run -v SLICES_DIR=/tmp/test

# Use a provider/model format (auto-routes to opencode)
run-agent/scripts/run-agent.sh --model anthropic/claude-sonnet-4-6 -p "Review the changes" --dry-run

# Force all agents through opencode
ORCHESTRATE_DEFAULT_CLI=opencode run-agent/scripts/run-agent.sh implement --dry-run

# 3-way parallel research
ORCHESTRATE_LOG_DIR=.runs/project/logs/agent-runs/research-claude \
  run-agent/scripts/run-agent.sh research-claude -v PLAN_FILE=my-plan.md &
ORCHESTRATE_LOG_DIR=.runs/project/logs/agent-runs/research-codex \
  run-agent/scripts/run-agent.sh research-codex -v PLAN_FILE=my-plan.md &
ORCHESTRATE_LOG_DIR=.runs/project/logs/agent-runs/research-kimi \
  run-agent/scripts/run-agent.sh research-kimi -v PLAN_FILE=my-plan.md &
wait
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `ORCHESTRATE_RUNS_DIR` | Runtime data (plans, logs, scratch) | `.runs/` next to skill root |
| `ORCHESTRATE_LOG_DIR` | Override log directory for a single run | Auto-derived from scope |
| `ORCHESTRATE_DEFAULT_CLI` | Force all model routing to a specific CLI (`claude`, `codex`, `opencode`) | Auto-detect from model name |

### Model Overrides

Every agent has a default model in its frontmatter. Override per-run:

```bash
# Use a specific model for one run
run-agent/scripts/run-agent.sh implement -m claude-opus-4-6

# Use provider/model format (routes to opencode automatically)
run-agent/scripts/run-agent.sh implement -m anthropic/claude-sonnet-4-6

# Force all agents through claude CLI (even if model name suggests codex)
ORCHESTRATE_DEFAULT_CLI=claude run-agent/scripts/run-agent.sh implement
```

### Custom Agents

Create `run-agent/agents/my-agent.md` with YAML frontmatter:

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

### Custom Review Rules

Add rules to `skills/review/references/`:
- `general.md` — always loaded (ships with the plugin)
- `<directory>.md` — loaded when reviewing files under that top-level directory

The review skill also reads `CLAUDE.md`/`AGENTS.md` from the project root for project-specific conventions.

## CLI Requirements

- **Required**: At least one of `claude`, `codex`, or `opencode` CLI
- **Optional**: `claude` CLI (Claude Code) — for `claude-*` model agents
- **Optional**: `codex` CLI — for `gpt-*`/`codex-*` model agents
- **Optional**: `opencode` CLI — for `provider/model` format or `opencode-*` model agents

## License

MIT
