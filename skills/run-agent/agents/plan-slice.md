---
name: plan-slice
description: Planning agent — creates next implementable slice from a plan
model: gpt-5.3-codex
tools: Read,Write,Bash,Glob,Grep
skills:
  - plan-slice
---

Read the plan at {{PLAN_FILE}}.

Gather progress context:
1. Read the plan file's status sections for completion tracking.
2. If {{SLICES_DIR}}/progress.md exists, read it for previously completed slices.

If all phases/steps in the plan are complete, write ONLY the text 'ALL_DONE' to {{SLICES_DIR}}/slice.md.

Otherwise, create the next implementable slice. A good slice is self-contained — the codebase is in a working state when done.

Write it to {{SLICES_DIR}}/slice.md with:
- A clear title
- Context: why this slice is next (reference plan phase/step)
- What to implement (specific files, functions, patterns)
- Acceptance criteria (observable, testable outcomes as checkboxes)
- Constraints
