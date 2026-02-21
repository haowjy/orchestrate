#!/usr/bin/env bash
# sync.sh — Sync skills between submodule, .agents/skills/, and .claude/skills/.
#
# Handles two directions:
#   pull:  submodule → .agents/skills/ + .claude/skills/  (after git pull)
#   push:  .claude/skills/ → .agents/skills/ + submodule  (after local edits)
#
# Preserves user additions (custom files) in both directions.
# Agent definitions (agents/*.md) are treated as customizable — pull warns
# about overwrites and offers to skip them.
#
# Usage:
#   bash .agents/.orchestrate/sync.sh pull    # after updating submodule
#   bash .agents/.orchestrate/sync.sh push    # after editing .claude/skills/
#   bash .agents/.orchestrate/sync.sh status  # show what's different
#
# Safe to re-run (idempotent). User-added files are never deleted.

set -euo pipefail

# --- Locate ourselves and the project root ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  exit 1
}

ORCHESTRATE_DIR="$SCRIPT_DIR"
SKILLS_SRC="$ORCHESTRATE_DIR/skills"
AGENTS_SKILLS="$PROJECT_ROOT/.agents/skills"
CLAUDE_SKILLS="$PROJECT_ROOT/.claude/skills"

# --- Usage ---

usage() {
  cat <<'EOF'
Usage: sync.sh <command>

Commands:
  pull     Sync submodule → .agents/skills/ + .claude/skills/
           Use after: git submodule update --remote
           Preserves custom files (agents, review references, etc.)

  push     Sync .claude/skills/ → .agents/skills/ + submodule
           Use after: editing skills in .claude/skills/
           Only syncs scripts and SKILL.md (not agent definitions)

  status   Show differences between all three locations

Options:
  --include-agents   Also sync agent definitions (pull/push)
  -h, --help         Show this help
EOF
  exit 1
}

# --- Parse args ---

COMMAND=""
INCLUDE_AGENTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    pull|push|status) COMMAND="$1"; shift ;;
    --include-agents) INCLUDE_AGENTS=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$COMMAND" ]] && usage

# --- Helpers ---

# rsync wrapper: copies files, excludes hidden runtime dirs (.runs/, .session/)
sync_dir() {
  local src="$1" dest="$2"
  local excludes=(--exclude='.*/')

  if [[ "$INCLUDE_AGENTS" == false ]]; then
    excludes+=(--exclude='agents/')
  fi

  mkdir -p "$dest"
  rsync -a "${excludes[@]}" "$src"/ "$dest"/ 2>/dev/null || \
    cp -r "$src"/* "$dest"/ 2>/dev/null || true
}

# --- Pull: submodule → project ---

do_pull() {
  echo "Pulling from submodule → .agents/skills/ + .claude/skills/"

  if [[ "$INCLUDE_AGENTS" == false ]]; then
    echo "  (skipping agents/*.md — use --include-agents to overwrite)"
  fi

  local copied=0
  for skill_path in "$SKILLS_SRC"/*/; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_path")"

    sync_dir "$skill_path" "$AGENTS_SKILLS/$skill_name"
    sync_dir "$skill_path" "$CLAUDE_SKILLS/$skill_name"
    ((copied++)) || true
  done

  echo "  Synced $copied skills"
  echo ""
  echo "Done. Custom files (review references, project-only skills) preserved."
}

# --- Push: .claude → .agents + submodule ---

do_push() {
  echo "Pushing from .claude/skills/ → .agents/skills/ + submodule"

  if [[ "$INCLUDE_AGENTS" == false ]]; then
    echo "  (skipping agents/*.md — use --include-agents to include)"
  fi

  local synced=0
  for skill_path in "$CLAUDE_SKILLS"/*/; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_path")"

    # Always sync to .agents/skills/ (full copy, respecting exclude)
    sync_dir "$skill_path" "$AGENTS_SKILLS/$skill_name"

    # Only sync to submodule if the skill exists there (don't push project-only skills)
    if [[ -d "$SKILLS_SRC/$skill_name" ]]; then
      sync_dir "$skill_path" "$SKILLS_SRC/$skill_name"
    fi

    ((synced++)) || true
  done

  echo "  Synced $synced skills"
  echo ""
  echo "Done. To commit submodule changes:"
  echo "  cd $ORCHESTRATE_DIR && git add -A && git commit -m 'sync' && git push"
}

# --- Status ---

do_status() {
  echo "═══ Sync Status ═══"
  echo ""

  echo "── .claude/skills/ vs .agents/skills/ (should be identical)"
  local diff_ca
  diff_ca="$(diff -rq "$CLAUDE_SKILLS" "$AGENTS_SKILLS" --exclude='.*' 2>/dev/null || true)"
  if [[ -z "$diff_ca" ]]; then
    echo "   ✓ In sync"
  else
    echo "$diff_ca" | sed 's/^/   /'
  fi

  echo ""
  echo "── .agents/skills/ vs submodule (project customizations)"
  local diff_as
  diff_as="$(diff -rq "$AGENTS_SKILLS" "$SKILLS_SRC" --exclude='.*' 2>/dev/null || true)"
  if [[ -z "$diff_as" ]]; then
    echo "   ✓ In sync"
  else
    echo "$diff_as" | sed 's/^/   /'
  fi

  echo ""
  echo "── Submodule status"
  (cd "$ORCHESTRATE_DIR" && git status --short 2>/dev/null) | sed 's/^/   /' || echo "   (not a git repo)"
}

# --- Dispatch ---

case "$COMMAND" in
  pull)   do_pull ;;
  push)   do_push ;;
  status) do_status ;;
esac
