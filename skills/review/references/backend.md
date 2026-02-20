# Backend Patterns (Go + Clean Architecture)

Common patterns LLMs get wrong in this codebase. Check every backend diff against these.

## Use the Service Layer

This codebase follows Clean Architecture. LLMs often shortcut it:
- **Handlers** validate input and map HTTP ↔ domain. No business logic.
- **Services** implement business logic. They call repositories, not the other way around.
- **Repositories** do data access only. No business decisions.

If you see business logic in a handler or a handler calling a repository directly, flag it.

## Domain Errors, Not HTTP Errors

Services return domain errors (`ErrNotFound`, `ErrValidation`, `ErrForbidden`). Handlers map them to HTTP status codes. Services should never import `net/http` or know about status codes.

## Empty String Is Valid

Don't replace `""` with defaults unless the API contract requires it. A user intentionally clearing a field to `""` is different from omitting the field. Use pointer types or explicit flags to distinguish "omitted" from "intentionally empty."

## Wrap Errors With Context

Use `fmt.Errorf("loading document %s: %w", id, err)` — not bare `return err`. Every layer should add context about what it was doing when the error occurred.

## Validate at the Boundary

Validate input once in the handler. Services trust validated input. Don't scatter validation checks deep in the call chain — it adds noise and creates inconsistency about which layer "owns" validation.

## Database: Know the Pooler Limitation

Supabase PgBouncer (port 6543) doesn't support prepared statements. Connection setup auto-detects this — but if writing raw queries, be aware that `QueryExecModeCacheDescribe` is in use. See `internal/repository/postgres/connection.go`.
