# Orchestrate

Intent-first multi-model primary-agent toolkit for Claude Code, Codex, and OpenCode.

A run is `model + skills + prompt`. Skills are discovered at runtime from `orchestrate/skills/*/SKILL.md` frontmatter — no static agent definitions.

## What's Inside

### Core skills (always installed)

| Skill | Description |
|---|---|
| `orchestrate` | Multi-model primary agent that discovers skills, picks models, and composes runs. Use when executing multi-step plans across multiple models |
| `run-agent` | Agent execution engine that composes prompts, routes models, and writes run artifacts. Use when launching subagent runs |

### Optional skills

| Skill | Description |
|---|---|
| `reviewing` | Reviews code against project rules and curated reference files. Use when auditing files for violations, reviewing changes, or generating cleanup tasks |
| `researching` | Explores codebases and evaluates approaches before planning. Use when investigating a problem space, comparing alternatives, or gathering context for a plan |
| `scratchpad` | Conventions for disposable scratch code and verification scripts. Use when writing smoke tests, quick probes, or temporary artifacts during task execution |
| `plan-task` | Breaks the next task from a plan into an implementable task file. Use when decomposing a multi-step plan into ordered work units |
| `mermaid` | Rules and validation for Mermaid diagrams. Use when creating or editing Mermaid diagrams in documentation |

### Agent profiles

| Agent | Description |
|---|---|
| `coder` | Implementation agent with full tool access |
| `researcher` | Research and investigation with read-only access and web lookup |
| `reviewer` | Code review with read-only access and web lookup |

## Installation

Tell your LLM agent:

> Fetch and follow instructions from `https://raw.githubusercontent.com/haowjy/orchestrate/refs/heads/main/INSTALL.md`

This works with any agent that can fetch URLs — Claude Code, Codex, OpenCode, Cursor, etc. The install guide walks the agent through setup interactively (submodule vs clone, location, skill/agent selection).

### Alternative: plugin install

Plugin install discovers skills and agents but skips runtime directory setup and MANIFEST-based filtering.

**Claude Code:**
```bash
/plugin marketplace add haowjy/orchestrate
/plugin install orchestrate@orchestrate-marketplace
```

**Cursor:**
```text
/plugin-add orchestrate
```

### Manual install

1. Add orchestrate as a submodule (recommended) or clone:

```bash
# Submodule (tracked by parent repo, collaborators get it automatically)
git submodule add https://github.com/haowjy/orchestrate orchestrate

# Or clone (simpler, but untracked)
git clone https://github.com/haowjy/orchestrate orchestrate
echo 'orchestrate/' >> .gitignore
```

2. Sync skills and agents:

```bash
bash orchestrate/sync.sh pull              # all skills + agents (default)
bash orchestrate/sync.sh pull --skills reviewing,mermaid   # selective
bash orchestrate/sync.sh pull --agents reviewer         # selective
bash orchestrate/sync.sh --help            # see all options
```

If orchestrate lives outside the repo: `bash /path/to/orchestrate/sync.sh pull --workspace /path/to/project`

3. Update:

```bash
# Submodule
git submodule update --remote orchestrate && bash orchestrate/sync.sh pull

# Clone
cd orchestrate && git pull && cd - && bash orchestrate/sync.sh pull
```

### Uninstall

```bash
# If submodule:
git submodule deinit -f orchestrate
git rm -f orchestrate
rm -rf .git/modules/orchestrate

# If clone:
rm -rf orchestrate

# Remove synced files:
rm -rf .agents/skills/ .claude/skills/ .agents/agents/ .claude/agents/ .orchestrate/
```

## Directory Layout

Source (`orchestrate/` — submodule/clone):
- `orchestrate/skills/*/SKILL.md` — self-describing capability building blocks
- `orchestrate/agents/*.md` — agent profiles (convenience aliases with permission defaults)
- `orchestrate/MANIFEST` — skill & agent registry for sync.sh
- `orchestrate/docs/` — design documents

Runtime (`.orchestrate/` — gitignored):
- `.orchestrate/runs/agent-runs/<run-id>/` — flat per-run artifacts
- `.orchestrate/index/runs.jsonl` — append-only two-row index (start + finalize)
- `.orchestrate/config.toml` — optional runtime config (auto-created with commented defaults)

### Runtime Config (`.orchestrate/config.toml`)

`run-agent.sh` auto-creates `.orchestrate/config.toml` on first use.  
By default it is commented out; uncomment and edit as needed.

Example pinned skills:

```toml
[skills]
pinned = ["orchestrate", "run-agent", "mermaid"]
```

Pinned skills are merged with agent default skills and CLI `--skills` (deduplicated by skill name).

## Quick Start

```bash
RUNNER=orchestrate/skills/run-agent/scripts/run-agent.sh
INDEX=orchestrate/skills/run-agent/scripts/run-index.sh

# Run: model + skills + prompt
"$RUNNER" --model claude-sonnet-4-6 --skills reviewing -p "Review auth changes"

# Run with an agent profile
"$RUNNER" --agent reviewer -p "Review auth changes"

# Run with labels and session grouping
"$RUNNER" --model gpt-5.3-codex --skills scratchpad \
    --session my-session --label ticket=PAY-123 \
    -p "Implement feature"

# Variant control (default: high)
"$RUNNER" --model claude-sonnet-4-6 --variant medium -p "Quick check"

# Dry run
"$RUNNER" --model gpt-5.3-codex --skills reviewing --dry-run -p "Review changes"

# Inspect runs
"$INDEX" list
"$INDEX" show @latest
"$INDEX" logs @latest
"$INDEX" stats
```

## Harness Routing

`run-agent.sh` auto-detects the CLI harness from the model name:

| Model prefix | Harness | `--variant` maps to |
|---|---|---|
| `claude-*` | Claude Code | `--effort $VARIANT` |
| `gpt-*`, `o1-*`, `o3-*`, `codex-*` | Codex | `-c "model_reasoning_effort=$VARIANT"` |
| `*/` (e.g. `google/...`, `kimi/...`) | OpenCode | `--variant $VARIANT` (passthrough) |

The `--variant` flag is a passthrough — the runner translates it to each harness's native flag. Common presets (`low`, `medium`, `high`) work across all harnesses. Provider-specific values (`xhigh`, `max`, `none`, `minimal`) are passed as-is; the harness decides what to do with them.

**Claude Code** and **Codex** work out of the box with standard API keys.

**OpenCode** is the harness for everything else — see [OpenCode Setup](#opencode-setup) below.

## OpenCode Setup

OpenCode is used for models that don't have a native CLI — Google Gemini, Kimi K2.5, GLM, and other third-party providers. Any model passed to `run-agent.sh` with a `provider/model` name (containing `/`) routes through OpenCode.

### Prerequisites

OpenCode requires an `opencode.json` config in the project root (or `~/.config/opencode/config.json` globally) with provider definitions and API keys. Without this, **every OpenCode run will fail** with `ProviderModelNotFoundError`.

See [OpenCode Models docs](https://opencode.ai/docs/models/) for full config format and provider setup.

### Built-in Variant Presets

OpenCode has built-in variant presets for some providers:

| Provider | Built-in `--variant` values |
|---|---|
| Anthropic | `high`, `max` |
| OpenAI | `none`, `minimal`, `low`, `medium`, `high`, `xhigh` |
| Google | `low`, `high` |

For these providers, `--variant high` just works out of the box.

### Providers Without Built-in Variants

Providers like Kimi, GLM, and others **do not have built-in variant presets**. If you pass `--variant high` for these models, it will be silently ignored unless you define custom variants in `opencode.json`.

To make variants work for these providers, add variant definitions to your config:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "kimi": {
      "models": {
        "k2.5": {
          "variants": {
            "high": {
              // provider-specific reasoning params go here
            }
          }
        }
      }
    }
  }
}
```

If a provider doesn't support reasoning effort at all, `--variant` is a no-op for that model — the value is still recorded in `params.json` for observability.

## Agent Profiles

Agent profiles are convenience aliases with default skills, model preferences, and permission settings. They are markdown files with YAML frontmatter at `orchestrate/agents/*.md`.

```yaml
---
name: reviewer
description: Code review with read-only access and web lookup
model: gpt-5.3-codex
variant: high
skills: [reviewing]
tools: [Read, Glob, Grep, Bash, WebSearch, WebFetch]
sandbox: danger-full-access
variant-models:
  - claude-opus-4-6
  - gpt-5.3-codex
---

Review code against project conventions.
```

### Usage

```bash
# Use an agent profile
"$RUNNER" --agent reviewer -p "Review auth changes"

# CLI flags override profile defaults
"$RUNNER" --agent reviewer --model claude-opus-4-6 -p "Deep review"

# Without --agent = same behavior as before (unrestricted)
"$RUNNER" --model gpt-5.3-codex -p "Implement feature"
```

### Frontmatter Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Unique identifier (required) |
| `description` | string | When to use this agent (required) |
| `model` | string | Default model. CLI `--model` overrides. |
| `variant` | string | Default variant. CLI `--variant` overrides. |
| `skills` | list | Default skills merged with CLI `--skills` |
| `tools` | list | LLM tool allowlist. Claude Code: `--allowedTools`. Codex: inferred sandbox. |
| `sandbox` | string | Codex sandbox tier: `read-only`, `workspace-write`, `danger-full-access` |
| `variant-models` | list | Models for fan-out (future) |

CLI option: pass `--strict-skills` to fail fast when any listed skill is unknown.

### Harness Behavior

- **Claude Code**: `--agent` flag passed natively. Tools/permissions enforced via `--allowedTools`.
- **OpenCode**: `--agent` flag passed natively. Reads `.agents/agents/<name>.md`.
- **Codex**: No native `--agent`. Agent body injected into prompt. `sandbox` field translated to `--sandbox` CLI flag.

### Codex Sandbox Inference

When an agent has a `tools` list but no explicit `sandbox`, the runner infers the Codex sandbox tier:

| Tools present | Inferred sandbox | Reason |
|---|---|---|
| No `tools` field | unrestricted (bypass) | No restrictions declared |
| Read-only (`Read, Glob, Grep`) | `read-only` | No writes, no network |
| Includes web (`WebSearch, WebFetch`) | `danger-full-access` | Needs network access |
| Write tools, no web (`Edit, Write`) | `workspace-write` | Writes to workspace, no network |
| Unrestricted `Bash` | `danger-full-access` | Bash can do anything |

Explicit `sandbox:` field always overrides inference.

### Discovery Order

`--agent <name>` searches these directories in order (first match wins):

1. `orchestrate/agents/<name>.md` — bundled source
2. `.agents/agents/<name>.md` — installed copies + user-created (OpenCode reads this)
3. `.claude/agents/<name>.md` — installed copies + user-created (Claude Code reads this)

To create a custom agent, add a `.md` file in `.claude/agents/` or `.agents/agents/`.

## Security

All harnesses run in **unrestricted mode** when no `--agent` is specified:
- Claude Code: `--dangerously-skip-permissions`
- Codex: `--dangerously-bypass-approvals-and-sandbox`

Both Anthropic and OpenAI recommend these flags only in externally sandboxed environments. For local dev use this is an accepted tradeoff, but be aware that subagent runs have full filesystem and network access.

When `--agent` is specified, the runner passes the agent profile to harnesses that support it natively (Claude Code, OpenCode) and translates permissions for Codex. See [Agent Profiles](#agent-profiles) above for details.

## Orchestration Model

The orchestrator is a multi-model routing layer:
1. Discover available skills
2. Understand what needs to happen
3. Pick the best model for each subtask (via model-guidance)
4. Pick the right skills to attach
5. Launch via `run-agent.sh` with `--label` and `--session` for grouping
6. Evaluate outputs (via `run-index.sh report @latest`)
7. Repeat until user objective is satisfied

## Run Artifacts

Each run produces a flat directory at `.orchestrate/runs/agent-runs/<run-id>/`:
- `params.json` — model, skills, variant, labels
- `input.md` — composed prompt
- `output.jsonl` — raw harness output
- `stderr.log` — harness stderr
- `report.md` — extracted report
- `files-touched.txt` — files modified

## Testing

```bash
bash orchestrate/tests/run-agent-unit.sh
bash orchestrate/tests/resource-loaders-unit.sh
```

## License

MIT
