# Orchestrate Future Directions

Out of scope for the current simplification but worth tracking for later.

## Agent Profiles

### Background

The current model is `model + skills + prompt` with no "agent" abstraction. This works well for ad-hoc composition but leaves a gap: there's no way to encode reusable roles with default skills, permissions, model preferences, and variant configurations.

The permission problem drove this design: all harnesses currently run in unrestricted mode (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`). Putting permissions in skills doesn't work — skills are untrusted prompt content (can come from marketplace, internet, or be composed by the LLM). Permissions need to be a separate, trusted layer.

### Design: `.agents/agents/*.md`

Agent profiles are markdown files with YAML frontmatter, discovered at runtime from `.agents/agents/`:

```yaml
---
name: reviewer
description: Code review with read-only access
skills: [review]
default-model: claude-sonnet-4-6
variant: high
permissions:
  claude:
    allowed-tools: ["Read", "Glob", "Grep"]
  codex:
    sandbox: read-only
  opencode:
    permission:
      "*": "deny"
      read: "allow"
      glob: "allow"
      grep: "allow"
variant-models:
  - claude-opus-4-6
  - gpt-5.3-codex
  - google/gemini-2.5-pro
---

Review code against project conventions and SOLID principles.
Focus on correctness, security, and maintainability.
```

### Key properties

- **`skills`**: Default skill set loaded for this agent. Additional skills can still be composed via `--skills`.
- **`permissions`**: Per-harness permission config. The runner translates these to native flags. This is the trusted policy layer — skills cannot override it.
- **`default-model`**: Model used when `--model` isn't specified.
- **`variant-models`**: For fan-out patterns. `run-agent.sh --agent reviewer --fan-out` would launch parallel runs across all variant models, giving multiple perspectives (e.g., 3 different reviewers from 3 model families).
- **`variant`**: Default variant (reasoning effort) level.

### How it works

```bash
# Single agent run — uses default model, skills, permissions
"$RUNNER" --agent reviewer -p "Review auth changes"

# Fan-out — parallel runs across variant-models
"$RUNNER" --agent reviewer --fan-out -p "Review auth changes"
# → launches 3 runs in parallel: claude-opus-4-6, gpt-5.3-codex, google/gemini-2.5-pro

# Override model but keep agent's skills + permissions
"$RUNNER" --agent reviewer --model claude-opus-4-6 -p "Deep review"

# Ad-hoc still works — no agent required
"$RUNNER" --model claude-sonnet-4-6 --skills review -p "Quick check"
```

### Trust model

- **Agent profiles** (committed to repo in `.agents/agents/`): trusted — they define the permission boundary.
- **Skills** (`.agents/skills/`, marketplace, internet): untrusted prompt content — they declare what tools they'd like, but the agent profile's permissions are the ceiling.
- **Environment**: Can further constrain via a project-level deny list (e.g., `.orchestrate/policy.toml`) that caps all agents regardless of their declared permissions.

Layered: `environment policy` > `agent profile permissions` > `skill allowed-tools requests`.

### Per-harness permission translation

| Agent declares | Claude Code | Codex | OpenCode |
|---|---|---|---|
| `allowed-tools: [Read, Glob, Grep]` | `--allowedTools "Read,Glob,Grep"` | `--sandbox read-only` | `permission: {read: allow, glob: allow, grep: allow}` |
| `allowed-tools: [Read, Edit, Write, Bash]` | `--allowedTools "Read,Edit,Write,Bash,..."` | `--full-auto` | `permission: {*: allow}` |
| `allowed-tools: [Read, Bash(git *)]` | `--allowedTools "Read,Bash(git *)"` | `--full-auto` | `permission: {read: allow, bash: {git *: allow}}` |

Claude Code and OpenCode get precise tool-level mapping. Codex maps to the closest sandbox tier (lossy but Codex's limitation, not ours).

### Relationship to current architecture

A run is still `model + skills + prompt`. An agent profile is just a **named default** for those fields plus permissions. The `--agent` flag is sugar — it loads defaults that can all be overridden by explicit flags. Ad-hoc composition (`--model X --skills Y -p "..."`) remains the fast path and requires no agent profile.

## Runtime Language

### Decision: Shell + jq

Orchestrate uses shell (bash) + jq for all runtime scripts. This maximizes portability across harness ecosystems — Claude Code (Node), Codex (Python), OpenCode (Go), and any future CLI tool. No runtime dependencies beyond bash and jq, which are available on virtually every dev machine.

### Tradeoffs Acknowledged

Shell + jq is fighting its limits in some areas:

- **JSONL index querying** — complex `jq` pipelines for filtering, aggregation, and pagination
- **Harness output parsing** — 3 different JSON stream formats (Claude stream-json, Codex JSONL, OpenCode JSON events) for report extraction, session ID extraction, token counting
- **Row validation and sanitization** — ensuring schema correctness without types
- **Testing** — shell scripts are harder to unit test than code in a typed language

These are manageable with careful `jq` and good integration tests. If JSON parsing correctness becomes a recurring pain point, consider:

**Near-term option**: Keep shell entrypoints (`run-agent.sh`, `run-index.sh`), move heavy JSON/JSONL processing to zero-dependency Node modules under `lib/node/`. Shell calls into Node where needed (`node lib/node/extract.js session-id --harness claude output.jsonl`). No external dependencies — just ES module files that run with bare `node`.

**Longer-term option**: Full rewrite of entrypoints in Node (or another language) for native cross-platform support (Windows without WSL). Eliminates the bash dependency entirely but is a larger scope change.

**Dependency tradeoff**: Node is guaranteed for Claude Code users but not for Codex-only (Python) or OpenCode-only (Go) users, or users of future CLIs (Kilo, Aider, Cline, etc.). If orchestrate stays a dev toolkit used alongside Claude Code, Node is a safe assumption. If it becomes a standalone general-purpose tool, the Node dependency limits portability. An alternative would be a single compiled binary (Go or Rust) for the heavy helpers, but that's significantly more build complexity.

## Sync Workflow Redesign

`sync.sh` currently handles bidirectional sync across three file copies (`.claude/skills/`, `.agents/skills/`, `orchestrate/skills/`). This three-copy problem is the messiest part of the current system and deserves its own design pass. For this simplification, `sync.sh` is left as-is — only `install.sh` gets the manifest-based update. A future effort should research whether sync can be simplified or replaced entirely (e.g., symlinks, single-copy-with-discovery, or a different sync model).

## Cross-Harness Permission Reference

See [Agent Profiles](#agent-profiles) above for the design that addresses permissions. Reference table of harness capabilities:

| Harness | Permission granularity | Tool-level control | Config location |
|---|---|---|---|
| Claude Code | Per-tool allowlists with glob patterns (`--allowedTools "Read,Edit,Bash(npm run *)"`) | Yes | CLI flags or `settings.json` |
| Codex | Sandbox modes (`read-only`, `workspace-write`, `danger-full-access`) + approval policy | Sandbox-level only, not individual tools | CLI flags or `codex.toml` |
| OpenCode | Per-tool allow/ask/deny with glob patterns (`"bash": {"git *": "allow", "rm *": "deny"}`) | Yes | `opencode.json` `permission` key |
