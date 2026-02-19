---
name: scratchpad
description: Conventions for scratch notes and scope-based file organization.
user-invocable: false
---

# Scratchpad Conventions

Scratch files and notes live under `scratch/` within the active scope root. The scope root is whichever runtime directory you are working in (project, plan, phase, or slice).

## Directory Layout

- `scratch/` — scratch notes
- `scratch/code/` — scratch code
- `logs/agent-runs/` — agent run logs

## Rules

- Prefer small dated markdown notes (e.g., `scratch/2026-02-16-topic.md`) so context survives compaction
- Do not store secrets or raw tokens in scratch files (`.env` values, JWTs, API keys, cookies)
- Keep scratch content concise and slice-focused; delete stale notes when a slice is fully complete
