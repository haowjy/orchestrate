---
name: research
description: Research methodology for exploring codebases and evaluating approaches before planning.
---

# Research

Explore a codebase, research best practices, evaluate alternative approaches, and recommend the best solution with clear reasoning. Produce structured research notes that a planning agent or human can use.

## When Invoked

You are researching to understand a problem space and codebase before writing or refining a plan.

### Step 1: Understand the Problem

1. If `{{PLAN_FILE}}` is provided, read it to understand what's being planned.
2. Read `CLAUDE.md` or `AGENTS.md` at the repo root for project conventions, architecture, and directory structure.
3. Read any stack-specific instruction files mentioned (e.g., `backend/CLAUDE.md`, `frontend/CLAUDE.md`).
4. Clearly define the problem to solve — what does the codebase need?

### Step 2: Explore the Codebase

1. **Directory structure** — Map the top-level layout. Understand where things live.
2. **Existing patterns** — Search for implementations similar to what's needed. How do existing features work? What patterns are established?
3. **Shared utilities** — Identify reusable code (hooks, services, components, helpers) that should be leveraged rather than recreated.
4. **Integration points** — Where would new code connect to existing systems? What interfaces, stores, or services are involved?
5. **Constraints** — Dependencies, version limits, existing abstractions that must be respected.

### Step 3: Research Best Practices

Use web search to research the problem space:

1. **Best practices** — How do well-regarded projects solve this problem? What do official docs recommend?
2. **Libraries and tools** — Are there established libraries that handle this well? Compare options.
3. **Patterns** — What architectural patterns are commonly used? (e.g., optimistic updates, event sourcing, CQRS, etc.)
4. **Pitfalls** — What common mistakes do people make with this approach? What are known footguns?

### Step 4: Evaluate Alternatives

Identify 2-3 viable approaches and evaluate each:

1. **Describe each approach** — What would the implementation look like?
2. **Pros and cons** — Be specific, not generic. "Faster" isn't useful; "avoids N+1 queries on the tree endpoint" is.
3. **Fit with codebase** — How well does each approach align with existing patterns, conventions, and architecture?
4. **Complexity** — How much new code, new dependencies, or new concepts does each introduce?
5. **Recommend one** — State which approach is best for *this specific codebase* and explain WHY. The recommendation should account for existing patterns, team conventions, and project philosophy — not just theoretical best practice.

### Step 5: Write Research Notes

Write structured research notes to `{SCOPE_ROOT}/scratch/research-{variant}.md` where `{variant}` identifies your agent (e.g., `claude`, `codex`).

```markdown
# Research Notes — {topic}

## Problem Statement
What we're solving and why.

## Codebase Context
How the relevant parts of the codebase are structured today.
Existing patterns, utilities, and integration points.
Include file paths.

## Best Practices
What the industry recommends. Link sources.

## Alternative Approaches

### Approach A: {name}
Description, pros, cons, codebase fit.

### Approach B: {name}
Description, pros, cons, codebase fit.

### Approach C: {name} (if applicable)
Description, pros, cons, codebase fit.

## Recommendation
Which approach and WHY it's the best fit for this codebase.
How it aligns with existing patterns and project philosophy.

## Open Questions
Anything that needs clarification before planning.
```

### Guidelines

- **Search before suggesting** — Always check if something already exists before recommending a new implementation.
- **Be specific** — Include file paths, function names, line numbers. Vague findings aren't useful.
- **Justify with WHY** — Every recommendation needs reasoning tied to the specific codebase, not generic advice.
- **Focus on what matters** — Prioritize findings relevant to the problem. Skip tangential observations.
- **Note conventions** — If the codebase has a strong pattern, call it out explicitly so the plan follows it.
