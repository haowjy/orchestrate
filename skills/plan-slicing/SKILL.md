---
name: plan-slicing
description: Breaks the next slice from a plan into an implementable slice file. Use when decomposing a multi-step plan into ordered work units.
---

# Plan Slice

Create the next implementable slice from a plan.

## When Invoked

### Step 1: Read Inputs

Use these prompt variables:
- `{{PLAN_FILE}}` — source plan to read
- `{{SLICES_DIR}}` — runtime slice directory (write outputs here)

### Step 2: Read Progress

Gather context on what is already completed:

1. Read `{{PLAN_FILE}}` and inspect status/phase tracking sections.
2. If `{{SLICES_DIR}}/progress.md` exists, read it for prior completed slices.
3. If `{{SLICES_DIR}}/slice.md` exists, use it as context for continuity.

### Step 3: Determine Completion

If all phases/steps in the plan are complete:
- Write **only** the text `ALL_DONE` to `{{SLICES_DIR}}/slice.md`.
- Stop here.

### Step 4: Create Slice File

Determine the next logical slice from the plan.

Write `{{SLICES_DIR}}/slice.md`. Include whatever structure makes sense, but the slice file should give an implementing agent everything it needs:

- **Context**: why this slice is next
- **Scope**: what to implement — files, functions, integration points
- **Acceptance criteria**: how to verify it's done
- **Constraints**: architectural limits, gotchas

A good slice is **self-contained**: the codebase must be in a working state when done. Size is secondary — focus on logical completeness, not line count.
