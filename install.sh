#!/usr/bin/env bash
# install.sh — post-clone/submodule setup for orchestrate
#
# Assumes orchestrate is already at orchestrate/ (via clone or submodule).
# Copies skills into .agents/skills/ and .claude/skills/.
#
# On first run: copies all skill directories.
# On re-run: overwrites orchestrate-defined files, preserves user additions.
#
# Usage:
#   bash orchestrate/install.sh [OPTIONS]
#
# Options:
#   --method submodule|clone   How orchestrate was added (default: auto-detect)
#                              clone: adds orchestrate/ to .gitignore
#
# Safe to re-run (idempotent). User-added files are never deleted.

set -euo pipefail

# --- Defaults ---

METHOD=""    # auto-detect

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)
      METHOD="$2"; shift 2
      if [[ "$METHOD" != "submodule" && "$METHOD" != "clone" ]]; then
        echo "Error: --method must be 'submodule' or 'clone'" >&2; exit 1
      fi
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
  echo "Error: Could not find parent project git root."
  echo "Make sure orchestrate is inside a git repository at orchestrate/"
  exit 1
}

ORCHESTRATE_DIR="$SCRIPT_DIR"
SKILLS_SRC="$ORCHESTRATE_DIR/skills"

# --- Auto-detect method ---

if [[ -z "$METHOD" ]]; then
  if [[ -f "$ORCHESTRATE_DIR/.git" ]] && grep -q "gitdir:" "$ORCHESTRATE_DIR/.git" 2>/dev/null; then
    METHOD="submodule"
  else
    METHOD="clone"
  fi
  echo "Auto-detected method: $METHOD"
fi

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

# --- Clone method: add orchestrate dir to .gitignore ---
# Each skill's .gitignore (copied above) already ignores hidden runtime dirs.

if [[ "$METHOD" == "clone" ]]; then
  GITIGNORE="$PROJECT_ROOT/.gitignore"
  ENTRY="orchestrate/"
  if [[ -f "$GITIGNORE" ]] && grep -qxF "$ENTRY" "$GITIGNORE"; then
    echo ".gitignore: '$ENTRY' already present"
  else
    echo "$ENTRY" >> "$GITIGNORE"
    echo ".gitignore: added '$ENTRY'"
  fi
fi

# --- Summary ---

echo ""
echo "Done! Orchestrate is ready (method=$METHOD)."
echo ""
echo "Verify:"
echo "  ls -la $AGENTS_SKILLS/"
echo "  ls -la $CLAUDE_SKILLS/"
