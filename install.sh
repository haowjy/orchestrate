#!/usr/bin/env bash
# install.sh — post-clone/submodule setup for orchestrate
#
# Copies skills into .agents/skills/ and .claude/skills/ under the workspace root.
# Rewrites runner paths in copied skills to match where orchestrate is installed.
#
# On first run: copies all skill directories.
# On re-run: overwrites orchestrate-defined files, preserves user additions.
#
# Usage:
#   bash orchestrate/install.sh [OPTIONS]
#
# Options:
#   --workspace DIR   Project root (default: auto-detect from git root)
#
# Safe to re-run (idempotent). User-added files are never deleted.

set -euo pipefail

WORKSPACE=""

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE="$2"; shift 2
      ;;
    -h|--help)
      sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2; exit 1
      ;;
  esac
done

# --- Locate ourselves and the project root ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$WORKSPACE" ]]; then
  PROJECT_ROOT="$(cd "$WORKSPACE" && pwd)"
else
  # Find git root of the *parent* project (not orchestrate's own repo)
  find_project_root() {
    local dir="$SCRIPT_DIR"
    while [[ "$dir" != "/" ]]; do
      if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
        # Skip orchestrate's own git root
        if [[ "$dir" != "$SCRIPT_DIR" ]]; then
          echo "$dir"
          return 0
        fi
      fi
      dir="$(dirname "$dir")"
    done
    return 1
  }

  PROJECT_ROOT="$(find_project_root)" || {
    echo "Error: Could not find parent project git root." >&2
    echo "Use --workspace DIR to specify the project root." >&2
    exit 1
  }
fi

ORCHESTRATE_DIR="$SCRIPT_DIR"
SKILLS_SRC="$ORCHESTRATE_DIR/skills"

# Relative path from workspace to orchestrate (e.g. "orchestrate", "tools/orchestrate")
ORCH_REL="${ORCHESTRATE_DIR#$PROJECT_ROOT/}"

echo "Workspace: $PROJECT_ROOT"
echo "Orchestrate: $ORCH_REL/"

# --- Copy targets ---

AGENTS_SKILLS="$PROJECT_ROOT/.agents/skills"
CLAUDE_SKILLS="$PROJECT_ROOT/.claude/skills"

# --- Copy skills (overwrite ours, preserve user additions) ---

copy_skills() {
  local target_dir="$1"
  local copied=0
  local updated=0

  mkdir -p "$target_dir"

  for skill_path in "$SKILLS_SRC"/*/; do
    [[ -d "$skill_path" ]] || continue
    skill_name="$(basename "$skill_path")"
    dest="$target_dir/$skill_name"

    if [[ -L "$dest" ]]; then
      # Replace old symlinks from previous install method
      rm "$dest"
    fi

    if [[ -d "$dest" ]]; then
      # Skill dir exists — overwrite orchestrate-defined files, keep user additions.
      # Exclude hidden dirs (runtime artifacts like .runs/) but include .gitignore.
      rsync -a --exclude='.*/' "$skill_path"/ "$dest"/ 2>/dev/null || \
        cp -r "$skill_path"/* "$dest"/ 2>/dev/null || true
      ((updated++)) || true
    else
      # First install — copy entire skill directory (exclude runtime artifact dirs).
      rsync -a --exclude='.*/' "$skill_path"/ "$dest" 2>/dev/null || \
        cp -r "$skill_path" "$dest"
      ((copied++)) || true
    fi
  done

  echo "  $target_dir: $copied new, $updated updated"
}

echo "Installing skills..."
copy_skills "$AGENTS_SKILLS"
copy_skills "$CLAUDE_SKILLS"

# --- Rewrite source paths to match install location ---
# Skill files use "orchestrate/" as the default source path prefix.
# If installed elsewhere, rewrite all "orchestrate/" references to the actual path.
# Only rewrites the source path prefix — ".orchestrate/" (runtime) is left untouched.

if [[ "$ORCH_REL" != "orchestrate" ]]; then
  echo "Rewriting source paths: orchestrate/ -> $ORCH_REL/"
  for dir in "$AGENTS_SKILLS" "$CLAUDE_SKILLS"; do
    while IFS= read -r -d '' file; do
      # Replace "orchestrate/" but not ".orchestrate/"
      # Strategy: replace all, then restore any ".orchestrate/" that got mangled
      sed -i "s|orchestrate/|${ORCH_REL}/|g; s|\\.${ORCH_REL}/|.orchestrate/|g" "$file"
    done < <(find "$dir" -name '*.md' -print0 -o -name '*.sh' -print0)
  done
fi

# --- Summary ---

echo ""
echo "Done! Orchestrate is ready."
echo ""
echo "Verify:"
echo "  ls -la $AGENTS_SKILLS/"
echo "  ls -la $CLAUDE_SKILLS/"
