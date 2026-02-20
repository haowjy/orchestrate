# Frontend Patterns (React + Zustand)

Common patterns LLMs get wrong in this codebase. Check every frontend diff against these.

## Show Content First, Not Spinners

**Why**: This is a writing app. Writers open it to *write*, not to watch spinners. Every loading spinner is a moment where the writer loses focus. The product philosophy is "writer-first" — the UI should feel like opening a notebook, not loading a web app. Cached content from IndexedDB/Zustand is available in milliseconds; blocking on a network round-trip to show a spinner wastes that advantage.

**The pattern**:
- If cached/stale data exists, show it immediately — refresh in the background
- For brief transitions (document switches, tab changes), use a blank placeholder — not a spinner. Spinners for sub-200ms waits create visual noise
- Only show a loading indicator when there is genuinely no data and the wait will be noticeable
- An empty editor is better than a loading spinner for an empty document

`hasData ? <Content /> : isInitialLoad ? <Skeleton /> : <EmptyState />`

## Async Operations Must Be Cancellation-Safe

**Why**: Writers navigate fast — switching between documents, threads, and branches in rapid succession. Every async operation (fetch, WebSocket sync, IndexedDB read) can complete *after* the user has already moved on. Without staleness guards, stale responses overwrite the new context: the wrong document appears, the wrong thread's turns render, loading flags get stuck permanently. We've had bugs where a slow fetch from document A overwrote document B's editor content, and where an aborted request left `isLoading: true` forever, blocking the entire UI.

**The pattern**:
1. **Staleness**: verify the request is still relevant before writing (user may have navigated away)
2. **Abort**: handle AbortError gracefully (silent return, not unhandled rejection)
3. **Cleanup in ALL paths**: success, error, AND abort paths must clean up loading flags

When merging async results into existing state, use functional updates (`set((current) => ...)`) — never merge against a pre-await snapshot, which drops concurrent updates (e.g., streaming deltas that arrived while a paginate was in flight).

## Empty, Null, and Undefined Are Three Different Things

**Why**: JavaScript has no built-in way to distinguish these — and LLMs collapse them constantly. But they mean different things in this app:
- `undefined` = field was **never set** (omitted from response, not loaded yet)
- `null` = field was **explicitly cleared** (user set system prompt to null, document moved to root)
- `""` = field has a **valid empty value** (new empty document, cleared text field)

A writer creates a new document — it has content `""`. That's a real document they're about to type in, not missing state. If code checks `if (!content)` it treats that empty document as absent, triggering loading states, skipping saves, or dropping streaming deltas. JavaScript's falsy coercion (`""`, `0`, `false`, `null`, `undefined` all falsy) makes this easy to get wrong — the language doesn't distinguish "empty" from "absent" unless you're explicit.

The backend uses `optional.Optional[T]` for tri-state PATCH semantics (omitted vs null vs value). The frontend must respect this — sending `null` means "clear the field", sending `undefined`/omitting means "don't change", and sending `""` means "set to empty string". These are different API calls with different results.

**The pattern**:
- Use `??` not `||` for defaults (`""` triggers `||` fallback, `??` only triggers on `null`/`undefined`)
- Use `value == null` not `!value` for absence checks (`== null` catches both null and undefined)
- Use `value !== undefined` when you need to distinguish null (clear) from undefined (omit)
- An empty document should render an empty editor, not a "no content" state

## Use Shared UI Components

**Why**: Consistency is trust. If delete confirmations look different in every feature, the user can't build muscle memory. If some errors have retry buttons and others don't, the experience feels broken. Shared components enforce consistency automatically — you can't accidentally use the wrong pattern if there's only one way to do it.

**The pattern**:
- `ErrorPanel` for full-page load failures, `InlineError` for recoverable errors — not ad-hoc error text
- `DeleteConfirmationDialog` for destructive actions — not `window.confirm()`
- Check `shared/components/` before creating new UI primitives

## Zustand: Selectors Over Whole-Store

**Why**: Zustand re-renders every subscriber when any state field changes. A component that subscribes to the whole store re-renders on every keystroke, every streaming delta, every background refresh — even if it only reads `status`. In a writing app with real-time collab and streaming AI responses, this means hundreds of unnecessary re-renders per second. Selectors let React skip re-renders when the selected field hasn't changed.

**The pattern**:
- `useStore((s) => s.field)` or `useShallow` for object picks
- Never `const store = useStore()` — causes re-renders on any state change

## Guard Stale References Across Navigation

**Why**: React state updates are asynchronous and Zustand stores are global singletons. When a user navigates from document A to document B, the store's `activeDocument` doesn't update atomically — there's a window where hooks for document B are running but `activeDocument` still holds A's data. Reading `.content` or `.extension` without checking `.id === documentId` silently produces wrong data. We've had bugs where the editor loaded with document A's extension (wrong syntax highlighting) and where saves wrote content to document A's ID instead of B's.

**The pattern**: When hooks receive an entity ID (documentId, threadId), always verify that store state matches before using it: `if (activeDocument?.id !== documentId) return`.
