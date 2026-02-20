# Frontend Patterns (React + Zustand)

Common patterns LLMs get wrong in this codebase. Check every frontend diff against these.

## Show Content First, Not Spinners

LLMs love adding loading spinners. This app prefers **content-first** rendering:
- If cached/stale data exists, show it immediately — refresh in the background
- For brief transitions (document switches, tab changes), use a blank placeholder — not a spinner. Spinners for sub-200ms waits create visual noise
- Only show a loading indicator when there is genuinely no data and the wait will be noticeable
- An empty editor is better than a loading spinner for an empty document

Pattern: `hasData ? <Content /> : isInitialLoad ? <Skeleton /> : <EmptyState />`

## Async Operations Must Be Cancellation-Safe

Every async operation that writes state after an await must handle:
1. **Staleness**: verify the request is still relevant before writing (user may have navigated away)
2. **Abort**: handle AbortError gracefully (silent return, not unhandled rejection)
3. **Cleanup in ALL paths**: success, error, AND abort paths must clean up loading flags. A stuck `isLoading: true` permanently blocks UI

When merging async results into existing state, use functional updates (`set((current) => ...)`) — never merge against a pre-await snapshot, which drops concurrent updates.

## Empty Is Valid Data

`""` is a valid document. `[]` is a valid list. `0` is a valid count. Only `undefined`/`null` means "absent."

- Use `??` not `||` for defaults (empty string triggers `||` fallback)
- Use `value == null` not `!value` for absence checks
- An empty document should render an empty editor, not a "no content" state

## Use Shared UI Components

Don't reinvent error/confirmation/feedback patterns:
- `ErrorPanel` for full-page load failures, `InlineError` for recoverable errors — not ad-hoc error text
- `DeleteConfirmationDialog` for destructive actions — not `window.confirm()`
- Check `shared/components/` before creating new UI primitives

## Zustand: Selectors Over Whole-Store

Subscribe to specific fields, not the whole store:
- `useStore((s) => s.field)` or `useShallow` for object picks
- Never `const store = useStore()` — causes re-renders on any state change

## Guard Stale References Across Navigation

When hooks receive an entity ID (documentId, threadId), always verify that store state matches before using it. A common bug: `activeDocument` still holds the *previous* document's data during navigation — reading `.content` or `.extension` without checking `.id === documentId` produces stale data.
