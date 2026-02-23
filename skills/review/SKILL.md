---
name: review
description: Review code against project rules. Loads stack-specific rule files based on files in scope.
---

# Code Review

Review code against curated project rules and create cleanup subtasks. Flag all violations found, not just things introduced by recent changes.

## When Invoked

### Step 1: Detect Scope

Determine which files to review:
- If `{{SLICES_DIR}}` is set, read `slice.md` and `files-touched.txt` to understand intent and file scope
- If reference files (`-f`) were provided, use those as scope
- Otherwise, review based on the prompt context — the caller should specify what to review

### Step 2: Load Rules

1. **Always** load `references/general.md`
2. **Read project instruction files** — look for `CLAUDE.md` or `AGENTS.md` at the repo root (whichever exists). Read any stack-specific instruction files in directories relevant to the files in scope (e.g., `backend/CLAUDE.md`, `frontend/AGENTS.md`).
3. **Load matching reference files** — if additional `references/*.md` files exist beyond `general.md`, load any whose name matches a top-level directory in the files being reviewed (e.g., files under `backend/` -> load `references/backend.md` if it exists).

### Step 3: Review Against Categories

Read and review each file in scope. Flag **all violations found** — not just things introduced by recent changes. If a file has pre-existing issues, flag them too.

Categories:
1. **Correctness** — logic errors, edge cases, missing branches, wrong comparisons, off-by-one
2. **Security** — hardcoded secrets, injection risks, missing auth checks, sensitive data in logs
3. **Reliability** — error handling, race conditions, resource cleanup, missing guards
4. **Architecture** — SOLID violations, import boundaries, coupling, cross-file breakage
5. **Dead code & Complexity** — unused code/imports, overly nested logic, premature abstractions
6. **Project conventions** — violations of rules from the loaded rule files and project instruction files

### Step 4: Create Subtasks

For each issue found, create a cleanup file in `{{SLICES_DIR}}/cleanup-NNN.md` (if `{{SLICES_DIR}}` is available) or `{{SCOPE_ROOT}}/.scratch/review/cleanup-NNN.md` under the scope root (for interactive use), describing:
- The category (from Step 3)
- The file and location
- What's wrong and why
- Suggested fix

### Step 5: Report

Summarize findings grouped by category. If no issues, say so.
