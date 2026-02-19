# SOLID / Cleanup Plan

## Goals

1. Reduce hidden coupling across `run-agent` shell modules.
2. Eliminate duplicated agent prompt templates that are likely to drift.
3. Improve confidence with lightweight tests for parsing/routing/logging behavior.
4. Preserve user flexibility to modify agents after install for project-specific needs.

## Non-Goals

1. No changes to default model choices or agent personalities.
2. No change to the high-level orchestrator loop semantics.

## Current Pain Points

1. Global mutable variables are shared across sourced modules (`parse.sh`, `prompt.sh`, `logging.sh`, `exec.sh`), which makes behavior harder to reason about and test.
2. Implementation and research agent markdown files repeat large prompt blocks with only small metadata differences.
3. CLI-specific behaviors are spread across parsing/execution logic, increasing the chance of subtle harness regressions.

## Customization Principle

1. Installed agent markdown files must remain plain, user-editable files.
2. Any upstream dedup/generation approach must not block local edits.
3. Project-level customization is a first-class workflow, not an edge case.

## Proposed Phases

### Phase 1: Introduce a Script Context Boundary

1. Add a `lib/context.sh` module to initialize and validate runtime state (working dir, runs dir, model, effort, tools, detail).
2. Move path normalization and defaults into that module.
3. Make downstream modules consume validated context values instead of ad-hoc assumptions.

Acceptance criteria:
1. `run-agent.sh` has a single initialization path before prompt composition/execution.
2. All default/path derivation logic lives in one place.
3. Existing CLI behavior remains backward-compatible.

### Phase 2: Extract Shared Agent Prompt Templates

1. Create shared partials for duplicated prompt families:
   - Implementation (`implement`, `implement-iterative`, `implement-deliberate`)
   - Research (`research-claude`, `research-codex`, `research-kimi`)
2. Keep agent-specific differences in frontmatter (model, effort, tools) and minimal per-agent prompt overrides.
3. Use generation/check only as an upstream maintenance aid; installed outputs remain normal markdown files users can edit.
4. Treat drift checks as advisory (or upstream-only), not a hard blocker for local customized copies.

Acceptance criteria:
1. Duplicated sections are removed from agent files.
2. Regeneration/check command can detect divergence in CI/local checks.
3. Agent behavior text stays semantically identical where intended.
4. Local teams can still modify installed agent prompts without fighting tooling.

### Phase 3: Harden Harness Adapter Layer

1. Explicitly represent per-harness capabilities:
   - supports tool allowlist?
   - supports effort variant?
   - supports structured JSON output mode?
2. Keep model routing and command construction in one adapter table.
3. Ensure normalization/validation happens exactly once per run.

Acceptance criteria:
1. Unsupported `ORCHESTRATE_DEFAULT_CLI` values fail with clear errors.
2. Harness capabilities are documented and enforced in code.
3. Dry-run output accurately reflects transformed settings.

### Phase 4: Add Focused Script Tests

1. Add shell tests (bats or POSIX-shell harness) for:
   - CLI arg validation (`-m` missing value, invalid detail, unknown args)
   - model routing to harness
   - log label sanitization and scope root inference
   - tool normalization for Claude allowlist casing
2. Add golden tests for composed prompt sections and report instruction suffix.

Acceptance criteria:
1. Core script behaviors are test-covered.
2. Regressions in parsing/routing/logging fail tests quickly.
3. Tests run locally without external network dependencies.

## Suggested Execution Order

1. Phase 1
2. Phase 3
3. Phase 2
4. Phase 4

Rationale: stabilize runtime contracts first, then adapters, then reduce prompt duplication, then lock behavior with tests.
