#!/usr/bin/env bash
# install.sh — post-clone/submodule setup for orchestrate
#
# Copies skills into .agents/skills/ and .claude/skills/ under the workspace root.
# Reads the skill list from MANIFEST — only core skills are installed by default.
#
# Usage:
#   bash orchestrate/install.sh [OPTIONS]
#
# Options:
#   --workspace DIR           Project root (default: auto-detect from git root)
#   --include skill1,skill2   Install specific optional skills alongside core
#   --all                     Install all skills from the manifest
#   -h, --help                Show this help
#
# Safe to re-run (idempotent). User-added files are never deleted.

set -euo pipefail

WORKSPACE=""
INCLUDE_SKILLS=""
INSTALL_ALL=false

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE="$2"; shift 2
      ;;
    --include)
      INCLUDE_SKILLS="$2"; shift 2
      ;;
    --all)
      INSTALL_ALL=true; shift
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
  find_project_root() {
    local dir="$SCRIPT_DIR"
    while [[ "$dir" != "/" ]]; do
      if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
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

SKILLS_SRC="$SCRIPT_DIR/skills"
MANIFEST="$SCRIPT_DIR/MANIFEST"

echo "Workspace: $PROJECT_ROOT"

# --- Read manifest ---

if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: MANIFEST not found at $MANIFEST" >&2
  exit 1
fi

# Parse manifest: core skills (before blank line / "Available" comment) and optional skills (after).
CORE_SKILLS=()
OPTIONAL_SKILLS=()
in_optional=false

while IFS= read -r line; do
  # Strip comments and whitespace
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [[ -z "$line" ]] && continue

  # Detect transition to optional section
  if [[ "$in_optional" == false ]]; then
    # Core skills are the first non-comment entries until we hit an "Available" marker
    # or a skill that isn't orchestrate/run-agent
    if [[ "$line" == "orchestrate" ]] || [[ "$line" == "run-agent" ]]; then
      CORE_SKILLS+=("$line")
    else
      in_optional=true
      OPTIONAL_SKILLS+=("$line")
    fi
  else
    OPTIONAL_SKILLS+=("$line")
  fi
done < "$MANIFEST"

# Build install list
INSTALL_LIST=("${CORE_SKILLS[@]}")

if [[ "$INSTALL_ALL" == true ]]; then
  INSTALL_LIST+=("${OPTIONAL_SKILLS[@]}")
elif [[ -n "$INCLUDE_SKILLS" ]]; then
  IFS=',' read -ra requested <<< "$INCLUDE_SKILLS"
  for req in "${requested[@]}"; do
    req="$(echo "$req" | xargs)"
    [[ -z "$req" ]] && continue

    # Validate it's in the manifest
    found=false
    for opt in "${OPTIONAL_SKILLS[@]}"; do
      if [[ "$opt" == "$req" ]]; then
        found=true
        break
      fi
    done

    if [[ "$found" == true ]]; then
      INSTALL_LIST+=("$req")
    else
      echo "Warning: '$req' is not in the manifest optional skills list. Skipping." >&2
    fi
  done
fi

echo ""
echo "Core skills: ${CORE_SKILLS[*]}"
if [[ "$INSTALL_ALL" == true ]]; then
  echo "Installing: ALL (${#INSTALL_LIST[@]} skills)"
elif [[ -n "$INCLUDE_SKILLS" ]]; then
  echo "Installing: core + $INCLUDE_SKILLS (${#INSTALL_LIST[@]} skills)"
else
  echo "Installing: core only (${#INSTALL_LIST[@]} skills)"
  echo "  Use --include or --all to add optional skills."
fi
echo ""

# --- Copy targets ---

AGENTS_SKILLS="$PROJECT_ROOT/.agents/skills"
CLAUDE_SKILLS="$PROJECT_ROOT/.claude/skills"

# --- Copy skills (overwrite ours, preserve user additions) ---

copy_skills() {
  local target_dir="$1"
  shift
  local skill_names=("$@")
  local copied=0
  local updated=0

  mkdir -p "$target_dir"

  for skill_name in "${skill_names[@]}"; do
    local skill_path="$SKILLS_SRC/$skill_name"

    if [[ ! -d "$skill_path" ]]; then
      echo "  Warning: skill '$skill_name' not found at $skill_path, skipping." >&2
      continue
    fi

    local dest="$target_dir/$skill_name"

    if [[ -L "$dest" ]]; then
      rm "$dest"
    fi

    if [[ -d "$dest" ]]; then
      rsync -a --exclude='.*/' "$skill_path"/ "$dest"/ 2>/dev/null || \
        cp -r "$skill_path"/* "$dest"/ 2>/dev/null || true
      ((updated++)) || true
    else
      rsync -a --exclude='.*/' "$skill_path"/ "$dest" 2>/dev/null || \
        cp -r "$skill_path" "$dest"
      ((copied++)) || true
    fi
  done

  echo "  $target_dir: $copied new, $updated updated"
}

echo "Installing skills..."
copy_skills "$AGENTS_SKILLS" "${INSTALL_LIST[@]}"
copy_skills "$CLAUDE_SKILLS" "${INSTALL_LIST[@]}"

# --- Runtime directory setup ---

ORCHESTRATE_RT="$PROJECT_ROOT/.orchestrate"
mkdir -p "$ORCHESTRATE_RT/runs/agent-runs"
mkdir -p "$ORCHESTRATE_RT/index"

# --- Summary ---

echo ""
echo "Done! Installed ${#INSTALL_LIST[@]} skills: ${INSTALL_LIST[*]}"
echo ""
echo "Verify:"
echo "  ls -la $AGENTS_SKILLS/"
echo "  ls -la $CLAUDE_SKILLS/"
