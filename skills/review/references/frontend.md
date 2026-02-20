# Frontend Rules (React + Zustand + CodeMirror)

These rules apply to all code under `frontend/`. Check every diff against them.

## Async & Race Conditions

1. **Staleness guards after every await**: Any async store action that writes state after an await MUST verify the request is still current before writing. Use `get().activeId === requestId` or a monotonic request counter. Apply to success, catch, AND finally paths.
2. **Functional set() for merges**: When merging async results into existing state (e.g., pagination), use `set((current) => ...)` — never merge against a pre-await snapshot, which drops concurrent updates (streaming deltas, other actions).
3. **AbortSignal end-to-end**: Pass `signal` through the entire call chain to the final `fetch`. Don't stop at an intermediate function. If a function accepts `signal`, it must forward it.
4. **Dual-signal coordination**: When a store action creates its own AbortController AND accepts an external signal, chain them: `signal.addEventListener('abort', () => controller.abort(), { once: true })`. Check `signal.aborted` before adding the listener (handles already-aborted signals).
5. **Clear loading flags on abort**: Abort catch paths MUST clear loading flags (`isLoading: false`). A stuck loading flag is worse than a flash — it permanently blocks the UI.
6. **No isMounted anti-pattern**: Use `AbortController` + signal, not `let isMounted = true` booleans. AbortController integrates with fetch cancellation; isMounted only prevents setState.

## State Management (Zustand)

7. **Selector-first subscriptions**: Use `useStore((s) => s.field)` or `useShallow` — never subscribe to the whole store object. Whole-store subscriptions cause unnecessary re-renders.
8. **One store = one domain**: Don't mix unrelated concerns (e.g., layout state + thread reference queue + proposal hints). Split when domains diverge.
9. **Guard stale activeDocument**: When accessing `activeDocument` in hooks/effects, always verify `activeDocument.id === documentId` before reading its properties. Stale `activeDocument` from a previous navigation is a common source of bugs.

## Loading & Empty States

10. **Content-first, not loading-first**: If cached/stale data exists, show it immediately. Only show loading indicators when there is genuinely no data to display. Pattern: `hasData ? <Content /> : <Skeleton />`, with background refresh updating content in place.
11. **Blank area over spinner for brief waits**: For transitions under ~200ms (document switches, collab sync), use a blank placeholder — not a spinner. Spinners for brief waits create visual noise.
12. **Empty string/array is valid data**: `""` and `[]` mean "present but empty." Only `undefined`/`null` mean "absent." A document with empty content should render an empty editor, not a loading state.

## Nullish & Falsy Checks

13. **`??` not `||` for defaults**: Use nullish coalescing (`??`) when empty string or 0 are valid values. `||` coerces `""`, `0`, `false` to the fallback.
14. **`== null` for absence checks**: Use `value == null` (catches both null and undefined) instead of `!value` (catches `""`, `0`, `false`). Exception: IDs and keys are never empty string, so `!id` is acceptable for ID checks.
15. **Mixed intent in fallback chains**: When one variable uses `??` semantics and another uses `||`, make it explicit: `text ?? (selectedText || "default")` — not all-`??` or all-`||`.

## Error Handling

16. **Consistent error surfaces**: Use `ErrorPanel` for full-page load failures (document failed to load at all). Use `InlineError` for recoverable failures (save failed, content still visible). Never render plain text errors without retry affordance for load/save operations.
17. **Catch on every async chain**: Every `.then()` needs a `.catch()` or the promise must be awaited inside try/catch. Unhandled rejections on abort paths are especially common and must be handled.
18. **Don't clobber newer state from error handlers**: Error/abort catch paths must check staleness before writing error state. A stale error writing to the store can corrupt the active request's UI.

## Cleanup & Effects

19. **Effects that create must destroy**: WebSocket connections, IndexedDB instances, event listeners, timers — if created in useEffect, they must be cleaned up in the cleanup function.
20. **Feature-flag cleanup**: When a feature is disabled (collab off, etc.), the disabled path must clean up any state or subscriptions from the previous enabled state.
21. **Timer refs**: `setTimeout`/`setInterval` in components must be tracked via refs and cleared on unmount. Don't leave orphan timers.

## Confirmation & Destructive Actions

22. **Shared dialog for destructive actions**: Use `DeleteConfirmationDialog` (or equivalent shared component) for all delete/destructive confirmations. Never use browser `window.confirm()` or `window.prompt()`.
