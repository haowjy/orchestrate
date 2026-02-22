---
name: scratchpad
description: Conventions for scratch notes and scope-based file organization.
user-invocable: false
---

# Scratchpad Conventions

Scratch files and notes live under `{{SCOPE_ROOT}}/.scratch/` (equivalently `.scratch/` inside the active scope root). The scope root is whichever runtime directory you are working in (project, plan, phase, or slice).

## Directory Layout

- `.scratch/` — scratch notes
- `.scratch/code/` — scratch code
- `logs/agent-runs/` — agent run logs

## Rules

- Use descriptive filenames (e.g., `.scratch/findings.md`, `.scratch/notes.md`) — the scope hierarchy provides context, not the filename
- Do not store secrets or raw tokens in scratch files (`.env` values, JWTs, API keys, cookies)
- Keep scratch content concise and scope-focused; delete stale notes when a slice is fully complete
