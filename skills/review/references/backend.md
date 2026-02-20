# Backend Patterns (Go + Clean Architecture)

Common patterns LLMs get wrong in this codebase. Check every backend diff against these.

## Use the Service Layer

**Why**: Clean Architecture exists so that business logic is testable, portable, and independent of transport. When an LLM puts validation logic in a handler or has a handler call a repository directly, it couples business rules to HTTP — making them untestable without spinning up a server, unreusable from other entry points (CLI, workers, WebSocket handlers), and harder to reason about. The service layer is the single place where "what the app does" lives.

**The pattern**:
- **Handlers** validate input and map HTTP ↔ domain. No business logic.
- **Services** implement business logic. They call repositories, not the other way around.
- **Repositories** do data access only. No business decisions.

If you see business logic in a handler or a handler calling a repository directly, flag it.

## Domain Errors, Not HTTP Errors

**Why**: Services don't know they're behind HTTP. Today it's a REST API; tomorrow it could be gRPC, a CLI tool, or a WebSocket handler. If services return `http.StatusNotFound`, every new transport has to understand HTTP semantics. Domain errors (`ErrNotFound`, `ErrValidation`) are transport-agnostic — each handler maps them to its own protocol. This also makes error handling testable without HTTP fixtures.

**The pattern**: Services return domain errors. Handlers map them to HTTP status codes. Services should never import `net/http` or know about status codes.

## Null vs Empty Are Different Things

**Why**: A user clearing their system prompt to `""` means "I want no system prompt." A user who never set one has `null`. These are different user intents that produce different behavior — one is an explicit action, the other is a default. If the backend collapses both to the same value (e.g., replacing `""` with a default template), it silently overrides the user's explicit choice. Go's type system can represent this distinction precisely — use it.

**The pattern**:
- `*string` being `nil` = field was **omitted** (not provided, use default/no-op)
- `*string` pointing to `""` = field was **intentionally cleared** (user wants empty)
- `string` being `""` = could be either — ambiguous, avoid for optional fields

Same for slices: `nil` slice = absent, `[]T{}` = present but empty.

Use pointer types for optional/nullable fields in request structs so JSON `null` vs `""` vs omitted are distinguishable. Apply the same principle in database models — `sql.NullString` or `*string` for nullable columns.

## Wrap Errors With Context

**Why**: When a production error shows `"record not found"`, you don't know if it was a user lookup, a document fetch, a thread load, or a skill query. Every layer in the call chain knows *what it was trying to do* — that context is lost if you return bare errors. Wrapped errors create a breadcrumb trail: `"loading thread abc123: fetching turns: record not found"` tells you exactly where to look.

**The pattern**: `fmt.Errorf("loading document %s: %w", id, err)` — not bare `return err`. Every layer adds context about what it was doing.

## Validate at the Boundary

**Why**: If handlers validate, services validate, and repositories validate the same constraints, you get three places to update when rules change, three places where validation can diverge, and unnecessary overhead on internal calls. The handler is the boundary — it's the one place where untrusted input enters the system. After that, services trust that input is valid. This keeps the service layer focused on business logic, not re-checking what the handler already checked.

**The pattern**: Validate input once in the handler. Services trust validated input. Don't scatter validation checks deep in the call chain.

## Database: Know the Pooler Limitation

**Why**: Supabase routes connections through PgBouncer (port 6543) for connection pooling. PgBouncer's transaction mode doesn't support PostgreSQL's extended query protocol (prepared statements), because prepared statements are per-connection and PgBouncer reassigns connections between queries. If code uses the default query mode, queries silently fail or produce wrong results. The codebase auto-detects this and uses `QueryExecModeCacheDescribe` — but you need to be aware of it when writing raw queries or configuring new database connections.

**The pattern**: See `internal/repository/postgres/connection.go` for the auto-detection logic.
