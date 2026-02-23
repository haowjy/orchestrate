# Orchestrate Future Directions

Out of scope for the current simplification but worth tracking for later.

## Native Harness Agent Integration

All three harnesses have real agent abstractions beyond prompt composition:

- **Claude**: Subagents (separate sessions, context isolation) and Agent Teams (direct teammate communication, shared task lists)
- **Codex**: Multi-agent roles (`[agents.*]` config table, per-role model/permissions, experimental)
- **OpenCode**: Primary/subagent taxonomy (model/prompt/tools/permissions/mode per agent, CLI creation/selection)

The current orchestrate "agent" concept (named presets in markdown files) doesn't map to any of these. A future design could add an optional role registry that compiles to harness-native agent configs — enabling parallel teams, sandboxed roles, and delegation policies while keeping ad-hoc `model + skills + prompt` as the fast default.

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

## Cross-Harness Permission Model

Each harness has different permission/sandbox semantics. A unified permission model that compiles to `--allowedTools` (Claude), task permissions (Codex), or role sandbox settings (OpenCode) could improve safety for multi-agent workflows.
