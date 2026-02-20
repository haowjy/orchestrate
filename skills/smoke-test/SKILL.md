---
name: smoke-test
description: Conventions for ad-hoc smoke tests and verification code.
user-invocable: false
---

# Smoke Test Conventions

Smoke tests are **any disposable code** used to quickly verify that something works. They are not limited to curl/HTTP probes.

Store smoke tests in `scratch/code/smoke/` under the active scope root. The scope root is whichever runtime directory you are working in (project, plan, phase, or slice).

## What Smoke Tests Are

Smoke tests are ad-hoc verification scripts — quick, disposable, and focused on proving a specific behavior works. Use them liberally after implementing changes.

| Type | When to use | Example |
|------|-------------|---------|
| **Logic verification** | Verify guard patterns, state machines, edge cases | `vitest` test asserting a staleness guard rejects stale responses |
| **API/endpoint probes** | Verify endpoints respond correctly | `curl` scripts hitting local dev server |
| **Integration checks** | Verify two systems work together | Script that creates a resource then reads it back |
| **Regression probes** | Verify a specific bug is fixed | Minimal repro of the bug, now passing |

### Examples

```typescript
// Logic smoke test — verifying a race guard pattern works
describe("staleness guard", () => {
  it("discards stale response when ID changed", () => {
    let currentId = "A";
    const requestId = "A";
    currentId = "B"; // user navigated away
    expect(currentId !== requestId).toBe(true); // guard fires
  });
});
```

```bash
# API smoke test — verifying an endpoint
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/projects | jq '.data | length'
```

## Smoke Tests vs Unit Tests vs Ad-Hoc Tests

| | Smoke tests | Unit tests |
|---|---|---|
| **Location** | `scratch/code/smoke/` | `tests/` or co-located `*.test.ts` |
| **Committed** | Never | Always |
| **Purpose** | Quick proof it works right now | Durable regression protection |
| **Scope** | Any — logic, API, integration | Focused on specific units |
| **When to write** | During/after implementation | For critical and complex logic |

**Guidance:**
- **Always** write smoke tests after implementing a slice — they verify your work immediately
- **Prefer unit tests** for the most important and critical areas (race conditions, state machines, security guards, data integrity) — these need durable regression protection
- **Use ad-hoc smoke tests** for everything else — pattern verification, quick integration checks, one-off probes
- When a smoke test catches a real issue, consider promoting it to a committed unit test

## Rules

- Treat smoke tests as scratch code artifacts — never commit them
- Do not store secrets or raw tokens in smoke files (`.env` values, JWTs, API keys, cookies)
- Check project instruction files (`CLAUDE.md` or `AGENTS.md`) for auth token scripts and API base URL
- Use any project-provided token/auth helpers for authenticated requests
- Name files descriptively: `{feature}-{what}.test.ts` or `{endpoint}.sh`
- Use the project's existing test runner (vitest, jest, etc.) for logic smoke tests
