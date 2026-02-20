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

## Null vs Empty vs Omitted Are Three Different Things

**Why**: Go's standard `encoding/json` has no way to distinguish "field was absent from JSON" from "field was `null`" — both result in a nil pointer. But for PATCH semantics (RFC 7396), these are three distinct user intents:
- **Omitted**: "don't change this field"
- **`null`**: "clear this field" (e.g., move document to root, clear system prompt)
- **`""`**: "set this field to empty string" (valid value, different from clearing)

Collapsing these loses user intent. A user clearing their system prompt (`null`) is not the same as never setting one (omitted), and neither is the same as setting it to `""`.

**The pattern**: This codebase uses `optional.Optional[T]` (see `internal/optional/optional.go`) for tri-state PATCH fields:

```go
type Optional[T any] struct {
    Present bool  // true = field was in JSON (even if null)
    Value   *T    // nil = JSON null, non-nil = has value
}
```

| JSON input | `Present` | `Value` | Meaning |
|------------|-----------|---------|---------|
| field absent | `false` | `nil` | Don't change |
| `"field": null` | `true` | `nil` | Clear/set to NULL |
| `"field": ""` | `true` | `&""` | Set to empty string |
| `"field": "hello"` | `true` | `&"hello"` | Set to value |

Use `optional.Optional[T]` for any PATCH request field where the user might want to clear a value. Don't use bare `*string` for PATCH fields — it can't distinguish omitted from null. See `handler/project.go`, `handler/document.go`, `handler/folder.go` for usage examples.

## Wrap Errors With Context

**Why**: When a production error shows `"record not found"`, you don't know if it was a user lookup, a document fetch, a thread load, or a skill query. Every layer in the call chain knows *what it was trying to do* — that context is lost if you return bare errors. Wrapped errors create a breadcrumb trail: `"loading thread abc123: fetching turns: record not found"` tells you exactly where to look.

**The pattern**: `fmt.Errorf("loading document %s: %w", id, err)` — not bare `return err`. Every layer adds context about what it was doing.

## Validate at the Boundary

**Why**: If handlers validate, services validate, and repositories validate the same constraints, you get three places to update when rules change, three places where validation can diverge, and unnecessary overhead on internal calls. The handler is the boundary — it's the one place where untrusted input enters the system. After that, services trust that input is valid. This keeps the service layer focused on business logic, not re-checking what the handler already checked.

**The pattern**: Validate input once in the handler. Services trust validated input. Don't scatter validation checks deep in the call chain.

## Database: Know the Pooler Limitation

**Why**: Supabase routes connections through PgBouncer (port 6543) for connection pooling. PgBouncer's transaction mode doesn't support PostgreSQL's extended query protocol (prepared statements), because prepared statements are per-connection and PgBouncer reassigns connections between queries. If code uses the default query mode, queries silently fail or produce wrong results. The codebase auto-detects this and uses `QueryExecModeCacheDescribe` — but you need to be aware of it when writing raw queries or configuring new database connections.

**The pattern**: See `internal/repository/postgres/connection.go` for the auto-detection logic.

## WebSocket Auth: JWT as First Message

**Why**: The WebSocket upgrade handshake doesn't reliably support custom headers across all browsers. This codebase authenticates WS connections by sending the raw JWT token as the **first message** after connection, with a 5-second read timeout. The auth middleware explicitly skips `/ws/projects/*` routes — WS auth is handled in-handler, not via middleware.

**The pattern**:
- Frontend sends raw JWT as the first WS message after `onopen`
- Backend reads first message with a 5-second deadline, validates JWT, extracts user ID
- Auth middleware (`middleware/auth.go`) skips WS routes — don't add WS paths to the middleware chain
- Don't try to pass JWT as a query parameter or HTTP header during the upgrade
