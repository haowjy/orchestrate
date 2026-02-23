# Model Guidance Overrides

Add one or more `*.md` files in this directory to customize model guidance.

## Concatenation Behavior

Unlike skill policy (which replaces defaults), model guidance uses **concatenation**:

1. `../default-model-guidance.md` is **always loaded** as the base.
2. If any `.md` files exist here (besides this README), they are **concatenated** with the default in bytewise-lexicographic filename order.
3. This lets you add project-specific model preferences without losing the defaults.

## Example

Create `my-project.md`:

```markdown
## Project-Specific Model Notes

- For database migrations, prefer claude-opus-4-6 (needs careful reasoning)
- For frontend components, prefer claude-sonnet-4-6 (fast iteration)
```

This will be appended after the default guidance when loaded.
