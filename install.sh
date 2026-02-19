#!/usr/bin/env bash
# install.sh — post-clone/submodule setup for orchestrate
#
# Assumes orchestrate is already at .agents/skills/orchestrate (via clone or submodule).
# Creates per-skill links (symlink or copy) into .agents/skills/ and .claude/skills/.
#
# Usage:
#   bash .agents/skills/orchestrate/install.sh [OPTIONS]
#
# Options:
#   --method submodule|clone   How orchestrate was added (default: auto-detect)
#                              clone: adds .agents/skills/orchestrate to .gitignore
#   --link   symlink|copy      Link strategy (default: symlink)
#                              copy: use on Windows or when symlinks aren't available
#
# Safe to re-run (idempotent).

set -euo pipefail

# --- Defaults ---

METHOD=""    # auto-detect
LINK="symlink"

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)
      METHOD="$2"; shift 2
      if [[ "$METHOD" != "submodule" && "$METHOD" != "clone" ]]; then
        echo "Error: --method must be 'submodule' or 'clone'" >&2; exit 1
      fi
      ;;
    --link)
      LINK="$2"; shift 2
      if [[ "$LINK" != "symlink" && "$LINK" != "copy" ]]; then
        echo "Error: --link must be 'symlink' or 'copy'" >&2; exit 1
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
  echo "Make sure orchestrate is inside a git repository at .agents/skills/orchestrate"
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

# --- Link targets ---

AGENTS_SKILLS="$PROJECT_ROOT/.agents/skills"
CLAUDE_SKILLS="$PROJECT_ROOT/.claude/skills"

# --- Create skill links (symlink or copy) ---

link_skills() {
  local target_dir="$1"
  local created=0
  local skipped=0

  mkdir -p "$target_dir"

  for skill_path in "$SKILLS_SRC"/*/; do
    [[ -d "$skill_path" ]] || continue
    skill_name="$(basename "$skill_path")"
    dest="$target_dir/$skill_name"

    if [[ "$LINK" == "symlink" ]]; then
      # Compute relative path from target_dir to skill_path
      rel_path="$(python3 -c "import os.path; print(os.path.relpath('$skill_path', '$target_dir'))" 2>/dev/null)" \
        || rel_path="$(realpath --relative-to="$target_dir" "$skill_path")"

      if [[ -L "$dest" ]]; then
        existing="$(readlink "$dest")"
        if [[ "$existing" == "$rel_path" ]]; then
          ((skipped++)); continue
        fi
        rm "$dest"
      elif [[ -e "$dest" ]]; then
        echo "  skip $dest (exists and is not a symlink)"
        ((skipped++)); continue
      fi

      ln -s "$rel_path" "$dest"
      ((created++))
    else
      # Copy mode
      if [[ -d "$dest" && ! -L "$dest" ]]; then
        # Already a real directory — overwrite contents
        rm -rf "$dest"
      elif [[ -L "$dest" ]]; then
        rm "$dest"
      fi

      cp -r "$skill_path" "$dest"
      ((created++))
    fi
  done

  echo "  $target_dir: $created ${LINK}ed, $skipped unchanged"
}

echo "Installing skills (${LINK})..."
link_skills "$AGENTS_SKILLS"
link_skills "$CLAUDE_SKILLS"

# --- Clone method: add orchestrate dir to .gitignore ---

if [[ "$METHOD" == "clone" ]]; then
  GITIGNORE="$PROJECT_ROOT/.gitignore"
  ENTRY=".agents/skills/orchestrate/"
  if [[ -f "$GITIGNORE" ]] && grep -qxF "$ENTRY" "$GITIGNORE"; then
    echo ".gitignore: '$ENTRY' already present"
  else
    echo "$ENTRY" >> "$GITIGNORE"
    echo ".gitignore: added '$ENTRY'"
  fi
fi

# --- Summary ---

echo ""
echo "Done! Orchestrate is ready (method=$METHOD, link=$LINK)."
echo ""
echo "Verify:"
echo "  ls -la $AGENTS_SKILLS/"
echo "  ls -la $CLAUDE_SKILLS/"
