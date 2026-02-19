---
name: model-guidance
description: Model tendencies and selection guidance for the orchestrator
---

# Model Guidance

Reference for choosing the right agent variant. Used by the orchestrate skill when deciding which agent to launch.

## Model Tendencies

| Model | Strengths | Weaknesses | Best For |
|---|---|---|---|
| **gpt-5.3-codex** | Deep, exhaustive code generation; strong at multi-file changes; thorough verification | Slower; higher cost | Default implementation, review, planning |
| **claude-sonnet-4-6** | Fast iteration; good UI intuition; strong at incremental changes | Less exhaustive on large refactors | UI loops, rapid iteration, frontend tweaks |
| **claude-opus-4-6** | Deep reasoning; careful architectural decisions; nuanced trade-offs | Slower than Sonnet; higher cost | Complex logic, architectural changes, subtle bugs |
| **claude-haiku-4-5** | Very fast; low cost; good at straightforward tasks | Limited depth on complex reasoning | Commit messages, simple transformations |

## Agent Variant Selection

### Implementation Agents

### `implement` (gpt-5.3-codex)
**Default choice.** Use for most slices — especially cross-stack changes, new features, and backend work. Exhaustive and thorough.

### `implement-iterative` (claude-sonnet-4-6)
Use when:
- Doing rapid UI iteration (tweak -> check -> tweak)
- Frontend-only changes with quick feedback loops
- The slice is well-defined and doesn't need deep exploration

### `implement-deliberate` (claude-opus-4-6)
Use when:
- The slice involves subtle correctness concerns (race conditions, state machines)
- Architectural decisions need careful reasoning
- Previous implementation attempts failed or produced bugs

### Review Agents

### `review` (claude-opus-4-6) — **Default**
Thoughtful senior dev with strong design sense. Catches real issues without noise. Good balance of thoroughness and signal-to-noise ratio. Use for most slices.

### `review-thorough` (gpt-5.3-codex, high effort)
Exhaustive auditor — leave-no-stone-unturned. Use for:
- Important or high-risk slices (auth, payments, data migrations)
- Final review before a major release
- When you want security + perf + architecture deep-dive

### `review-quick` (gpt-5.3-codex, low effort)
Fast mechanical sanity check. Use for:
- Trivial slices (docs, config, simple renames)
- Quick pass before committing when you're confident in the implementation
- When speed matters more than depth

### `review-adversarial` (claude-sonnet-4-6, high effort)
Adversarial tester — actively writes scratch tests to break the code. Use for:
- Concurrency-sensitive code (race conditions, shared state)
- Security-critical paths (auth, input validation, API boundaries)
- When a standard review passed but you want extra confidence

### Research Agents

### `research-claude` (claude-sonnet-4-6)
Research via claude. Use when:
- Exploring an unfamiliar codebase before writing a plan
- Need fast, intuitive pattern recognition and web research
- Good at connecting codebase patterns to broader ecosystem best practices

### `research-codex` (gpt-5.3-codex)
Research via codex. Use when:
- Need exhaustive, methodical code exploration
- Want a different perspective from the claude research agent
- Good at deep code path tracing and thorough architecture mapping

### `research-kimi` (opencode/kimi-k2.5-free)
Research via kimi. Use when:
- Want a third perspective from a different model family
- Need to validate findings from claude/codex research
- Good for cross-referencing approaches across model providers

All research agents have the same goal: explore the codebase, research best practices, evaluate alternative approaches, and recommend the best solution with reasoning. The difference is the model — different models notice different things.

**Parallel research:** Run `research-claude`, `research-codex`, and `research-kimi` in parallel for different perspectives, then synthesize.

### General Rules

1. **Start with `implement`** (default) unless you have a specific reason to use a variant.
2. **Switch to `implement-iterative`** if the slice is UI-focused and you want faster cycles.
3. **Escalate to `implement-deliberate`** if a slice fails on the first attempt or involves tricky logic.
4. **Use `review`** (default) for most slices. Escalate to `review-thorough` or `review-adversarial` for important changes.
5. **Use `review-quick`** for trivial slices where a fast sanity check suffices.
6. **Use `-m MODEL` override** on any agent when you want to temporarily switch models without changing the agent definition.
