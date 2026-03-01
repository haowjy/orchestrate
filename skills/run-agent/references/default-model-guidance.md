# Default Model Guidance

Use this default only when no custom files exist in `references/model-guidance/*.md`.

## Baseline picks

codex as an alias for `gpt-5.3-codex`
opus as an alias for `claude-opus-4-6`

- Implementation: `gpt-5.3-codex`
- Review (medium/high risk): fan out across model families, prefer `gpt-5.3-codex` for most reviews to be cheaper and more thorough.
- Nuanced correctness/architecture: `claude-opus-4-6` and/or `gpt-5.2` with high variant
- UI/frontend loops: `claude-opus-4-6`
- Lightweight commit/message tasks: `claude-haiku-4-5` to help create commits for the changes

## Practical rules

1. Prefer the smallest model choice that controls risk.
2. Use multiple reviewers only when risk justifies it.
3. Keep skill sets minimal and task-relevant.
