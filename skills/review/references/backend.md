# Backend Rules (Go + net/http + PostgreSQL)

These rules apply to all code under `backend/`. Check every diff against them.

## Error Handling

1. **Domain errors over HTTP errors**: Business logic should return domain errors (`ErrNotFound`, `ErrValidation`). Handlers map domain errors to HTTP status codes — services should not know about HTTP.
2. **Wrap errors with context**: Use `fmt.Errorf("operation: %w", err)` to add context. Don't return raw errors from called functions.
3. **No silent error swallowing**: Every error must be handled — logged, returned, or explicitly documented as intentional best-effort.

## Data Handling

4. **Empty string is valid**: Don't replace `""` with default values unless the API contract explicitly states the field is required. Use pointer types or explicit flags to distinguish "omitted" from "intentionally empty."
5. **Validate at boundaries**: Validate input in handlers (HTTP layer). Services trust validated input. Don't re-validate deep in the call chain.

## Architecture

6. **Clean Architecture boundaries**: `domain/` defines interfaces. `service/` implements business logic. `repository/` implements data access. `handler/` maps HTTP to domain. No cross-layer imports that skip levels.
7. **Interface segregation**: Prefer small, focused interfaces (`Reader`, `Writer`) over large ones (`Repository` with 20 methods). Consumers should depend on the minimum interface they need.

## Database

8. **Prepared statement compatibility**: Supabase PgBouncer (port 6543) doesn't support prepared statements. Use `QueryExecModeCacheDescribe` for pooled connections. See `internal/repository/postgres/connection.go`.
9. **Transactions for multi-step mutations**: Operations that touch multiple tables must use transactions. Don't rely on sequential queries being atomic.

## API Conventions

10. **Consistent response shapes**: Follow existing `api.ts` patterns for response envelopes, pagination, and error shapes. Don't introduce new response formats.
11. **AbortSignal support**: API handler functions that accept options should support `signal` for cancellation. Match the pattern in existing endpoints.
