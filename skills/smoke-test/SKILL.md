---
name: smoke-test
description: Conventions for ad-hoc smoke tests and curl probes.
user-invocable: false
---

# Smoke Test Conventions

Smoke tests are disposable scripts used to verify API endpoints and integrations.

Store smoke tests in `scratch/code/smoke/` under the active scope root. The scope root is whichever runtime directory you are working in (project, plan, phase, or slice).

## Rules

- Treat smoke tests as scratch code artifacts — never commit them
- Do not store secrets or raw tokens in smoke files (`.env` values, JWTs, API keys, cookies)
- Check project instruction files (`CLAUDE.md` or `AGENTS.md`) for auth token scripts and API base URL
- Use any project-provided token/auth helpers for authenticated requests
