# Orchestrate

Multi-agent toolkit for Claude Code, Codex, and OpenCode.

- **`run-agent.sh`** — Script wrapper that routes agents to the right CLI based on model name. Normalizes prompt composition, tool allowlists, and output across Claude Code, Codex, and OpenCode.
- **Skills** — Composable methodology files (review, research, planning, etc.) that get loaded into agent prompts. The `orchestrate` skill composes them into a supervisor loop.
- **Agents** — 13 curated agent definitions for research, implementation, review, and utility tasks. Each specifies a model, tools, skills, and prompt. User-extensible.
- **Logging** — Every agent run captures input prompt, raw output, human-readable report, files touched, and execution params. Raw artifacts under `run-agent/.runs/`, coordination state under `orchestrate/.session/`.

## Install

### Quick start

Paste this into any LLM-powered coding CLI (Claude Code, Codex, OpenCode):

```
Fetch and follow instructions from https://raw.githubusercontent.com/haowjy/orchestrate/main/INSTALL.md
```

### Manual install

**1. Add orchestrate**

As a submodule:
```bash
git submodule add https://github.com/haowjy/orchestrate .agents/.orchestrate
```

Or as a clone:
```bash
mkdir -p .agents
git clone https://github.com/haowjy/orchestrate .agents/.orchestrate
echo '.agents/.orchestrate/' >> .gitignore   # keep the clone out of parent repo
```

**2. Run install**

```bash
bash .agents/.orchestrate/install.sh
```

Or manually copy skills:
```bash
mkdir -p .agents/skills .claude/skills
for skill in .agents/.orchestrate/skills/*/; do
  cp -r "$skill" ".agents/skills/$(basename "$skill")"
  cp -r "$skill" ".claude/skills/$(basename "$skill")"
done
```

**3. Verify**

```bash
ls -la .agents/skills/
ls -la .claude/skills/
```

Result:
```
.agents/
├── .orchestrate/         # submodule or clone (hidden)
└── skills/
    ├── orchestrate/      # copied from .orchestrate/skills/orchestrate
    ├── run-agent/        # copied from .orchestrate/skills/run-agent
    ├── review/
    ├── research/
    └── ...

.claude/skills/
├── orchestrate/
├── run-agent/
├── review/
└── ...
```

### Native harness installers

**Claude Code** (plugin marketplace — recommend project scope):
```bash
/plugin marketplace add haowjy/orchestrate
/plugin install orchestrate@haowjy-orchestrate --scope project
```
`--scope project` installs into `.claude/settings.json` so all collaborators get the plugin automatically. Use `--scope local` for personal-only.

**Codex** (built-in skill installer):
```
$skill-installer install https://github.com/haowjy/orchestrate
```
Installs to `~/.codex/skills/orchestrate`. Requires `codex --enable skills` feature flag.

**OpenCode** — no native skill installer. Use the per-repo approach above.

### Updating

If installed as submodule:
```bash
git submodule update --remote .agents/.orchestrate
```

If installed as clone:
```bash
cd .agents/.orchestrate && git pull && cd -
```

Re-run `install.sh` after updating to refresh skill copies. Re-running preserves any custom agents or files you added.

### Syncing

After updating the submodule or editing skills locally, use `sync.sh` to keep all three locations in sync:

```bash
# After git submodule update — pull upstream changes into project
bash .agents/.orchestrate/sync.sh pull

# After editing skills in .claude/skills/ — push changes back
bash .agents/.orchestrate/sync.sh push

# Check what's different between all three locations
bash .agents/.orchestrate/sync.sh status
```

**Three locations:**
- `.agents/.orchestrate/skills/` — upstream defaults (submodule)
- `.agents/skills/` — project copy (used by Codex/OpenCode)
- `.claude/skills/` — project copy (used by Claude Code)

Both project copies (`.agents/skills/` and `.claude/skills/`) should be identical. Custom files (project-only agents, review references) are preserved in both directions. Agent definitions (`agents/*.md`) are skipped by default — use `--include-agents` to sync them.

### Customizing agents per-repo

Add new agent definitions alongside the shipped ones:

```bash
# Add a project-specific agent
vi .agents/skills/run-agent/agents/implement-backend.md
vi .agents/skills/run-agent/agents/review-security.md
```

Re-running `install.sh` after an update will overwrite shipped files but never delete your additions. If you need to customize a shipped agent, create a new one instead of editing it — edits to shipped files will be lost on re-install.

## Quick Start

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

## Agents

### Research

| Agent | Model | Focus |
|---|---|---|
| `research` | gpt-5.3-codex | Codebase exploration + web research + approach evaluation |

Launch with `-m` overrides for multi-model perspectives:

```bash
run-agent.sh research -v PLAN_FILE=my-plan.md &
run-agent.sh research -v PLAN_FILE=my-plan.md -m claude-sonnet-4-6 &
wait
```

### Implementation

| Agent | Model | Best For |
|---|---|---|
| `implement` | gpt-5.3-codex | Default — most slices |
| `implement-iterative` | claude-sonnet-4-6 | Fast UI iteration loops |
| `implement-deliberate` | claude-opus-4-6 | Complex logic, subtle bugs |

### Review

| Agent | Model | Effort | Personality |
|---|---|---|---|
| `review` | gpt-5.3-codex | high | Thorough reviewer — SOLID, consistency, clean code |
| `review-quick` | gpt-5.3-codex | low | Fast sanity check — obvious bugs and blockers only |
| `review-adversarial` | claude-sonnet-4-6 | high | Adversarial tester — writes scratch tests to break the code |

For large changes, launch `review` with multiple models in parallel to get different perspectives:

```bash
run-agent.sh review --slice slice-1 &
run-agent.sh review --slice slice-1 -m claude-opus-4-6 &
wait
```

All review agents support **dual mode**: given a plan, they review the plan; given implemented code, they review the code.

### Utility

| Agent | Model | Purpose |
|---|---|---|
| `plan-slice` | gpt-5.3-codex | Creates next implementable slice from a plan |
| `cleanup` | gpt-5.3-codex | Targeted fix from review findings |
| `commit` | claude-haiku-4-5 | Clean commit message from working tree |

## Running Agents Directly

```bash
# From this repo root:
AGENT_RUNNER=skills/run-agent/scripts/run-agent.sh

# If installed into a project:
# AGENT_RUNNER=.agents/skills/run-agent/scripts/run-agent.sh

# Run an agent by name
"$AGENT_RUNNER" review -v SLICES_DIR=path/to/slices/01-foo

# Override model on any agent
"$AGENT_RUNNER" implement -m claude-opus-4-6

# Ad-hoc (no agent definition)
"$AGENT_RUNNER" --model claude-sonnet-4-6 --skills review -p "Review the changes"

# Dry run — see composed prompt + CLI command without executing
"$AGENT_RUNNER" review --dry-run -v SLICES_DIR=/tmp/test

# Use a provider/model format (auto-routes to opencode)
"$AGENT_RUNNER" --model anthropic/claude-sonnet-4-6 -p "Review the changes" --dry-run

# Force all agents through opencode
ORCHESTRATE_DEFAULT_CLI=opencode "$AGENT_RUNNER" implement --dry-run

# 3-way parallel research — PID-based log dirs keep them separate automatically
"$AGENT_RUNNER" research-claude -v PLAN_FILE=my-plan.md &
"$AGENT_RUNNER" research-codex -v PLAN_FILE=my-plan.md &
"$AGENT_RUNNER" research-kimi -v PLAN_FILE=my-plan.md &
wait
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `ORCHESTRATE_DEFAULT_CLI` | Force all model routing to a specific CLI (`claude`, `codex`, `opencode`) | Auto-detect from model name |
| `ORCHESTRATE_AGENT_DIR` | Override agent definition directory | unset |

### Model Overrides

Every agent has a default model in its frontmatter. Override per-run:

```bash
AGENT_RUNNER=skills/run-agent/scripts/run-agent.sh

# Use a specific model for one run
"$AGENT_RUNNER" implement -m claude-opus-4-6

# Use provider/model format (routes to opencode automatically)
"$AGENT_RUNNER" implement -m anthropic/claude-sonnet-4-6

# Force all agents through claude CLI (even if model name suggests codex)
ORCHESTRATE_DEFAULT_CLI=claude "$AGENT_RUNNER" implement
```

### Custom Agents

Create `skills/run-agent/agents/my-agent.md` (or `.agents/skills/run-agent/agents/my-agent.md` in your project) with YAML frontmatter:

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

Agent definitions are intentionally user-editable after install. Common patterns:
- Modify built-in agents in your project (for example `.agents/skills/run-agent/agents/implement.md`) to encode codebase-specific rules.
- Add new project-specific agents (for example `implement-backend.md`, `review-security.md`) and run them directly with `run-agent.sh`.
- Keep team conventions in project `AGENTS.md`/`CLAUDE.md`; the agent prompts already instruct subagents to read those files.

Agent lookup precedence for `run-agent.sh <agent-name>`:
1. `ORCHESTRATE_AGENT_DIR/<agent>.md` (if set)
2. `<workdir>/.agents/skills/run-agent/agents/<agent>.md`
3. `<workdir>/.claude/skills/run-agent/agents/<agent>.md`
4. bundled `skills/run-agent/agents/<agent>.md`

### Custom Review Rules

Add rules to `skills/review/references/` (or `.agents/skills/review/references/` in your project):
- `general.md` — always loaded (ships with the plugin)
- `<directory>.md` — loaded when reviewing files under that top-level directory

The review skill also reads `CLAUDE.md`/`AGENTS.md` from the project root for project-specific conventions.

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
| **Codex** | `.agents/skills/*/SKILL.md` (walks to git root) | Native Codex skills installer |
| **OpenCode** | `.agents/skills/` + `.claude/skills/` (walks up) | Native OpenCode skills installer |

Model routing is automatic — agent definitions specify a model name, and `run-agent.sh` routes to the correct CLI:

| Model Pattern | CLI | Examples |
|---------------|-----|----------|
| `claude-*`, `opus*`, `sonnet*`, `haiku*` | `claude` | `claude-sonnet-4-6`, `opus` |
| `gpt-*`, `o1*`, `o3*`, `o4*`, `codex*` | `codex` | `gpt-5.3-codex`, `o4-mini` |
| `opencode-*`, `provider/model` | `opencode` | `opencode/kimi-k2.5-free`, `anthropic/claude-sonnet-4-6` |

Override routing with `ORCHESTRATE_DEFAULT_CLI=opencode` to force all agents through a specific CLI.

## Logging

Every agent run is logged under `run-agent/.runs/`, with coordination state under `orchestrate/.session/`:

```
{skills-dir}/run-agent/.runs/                    # raw per-run artifacts
├── project/logs/agent-runs/{agent}-{PID}/       # ad-hoc runs
└── plans/{plan-name}/
    └── slices/{slice}/
        └── logs/agent-runs/{agent}-{PID}/
            ├── input.md          # composed prompt
            ├── output.json       # raw CLI output
            ├── report.md         # agent's summary
            ├── params.json       # execution metadata
            └── files-touched.txt # extracted file list

{skills-dir}/orchestrate/.session/               # coordination state
├── project/index.log                            # ad-hoc run index
└── plans/{plan-name}/
    ├── index.log
    ├── handoffs/                 # progress snapshots
    └── commits/                  # commit records
```

## Execution Mode and Safety

`run-agent.sh` launches each harness in autonomous mode:
- Claude CLI uses `--dangerously-skip-permissions`
- Codex CLI uses `--full-auto`

Tool allowlists are currently applied only for Claude (`--allowedTools`). Codex and OpenCode do not expose equivalent allowlist flags in `exec/run`.

Runtime artifact directories (`run-agent/.runs/` and `orchestrate/.session/`) are kept untracked via per-skill `.gitignore` entries.

Use this only in trusted repos/worktrees. Prefer reviewing `--dry-run` output when testing new agent prompts.

## CLI Requirements

- **Required**: At least one of `claude`, `codex`, or `opencode` CLI
- **Optional**: `claude` CLI (Claude Code) — for `claude-*` model agents
- **Optional**: `codex` CLI — for `gpt-*`/`codex-*` model agents
- **Optional**: `opencode` CLI — for `provider/model` format or `opencode-*` model agents

## License

MIT
