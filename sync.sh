#!/usr/bin/env bash
# sync.sh — Sync skills between submodule, .agents/skills/, and .claude/skills/.
#
# Default behavior (pull/push):
# - applies automatically when there are no conflicts
# - blocks when conflicts exist and prints conflict list
# - use --overwrite to apply despite conflicts

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
  cat <<'USAGE'
Usage: sync.sh <command> [options]

Commands:
  pull     Sync submodule -> .agents/skills/ + .claude/skills/
  push     Sync .claude/skills/ -> .agents/skills/ + submodule
  status   Show differences between all three locations

Default mode (pull/push):
- apply automatically when no conflicts are detected
- stop and print conflicting files when conflicts exist

Options:
  --overwrite          Apply changes even if conflicts exist
  --diff               Show quick unified diffs from submodule
  --exclude PATTERN    Exclude file/path pattern from preview/sync/diff (repeatable)
  --include-agents     Deprecated no-op (agents are always included)
  -h, --help           Show this help
USAGE
  exit 1
}

# --- Parse args ---

COMMAND=""
OVERWRITE=false
SHOW_DIFF=false
EXTRA_EXCLUDES=()

require_option_value() {
  local opt="$1"
  local remaining="$2"
  if [[ "$remaining" -lt 2 ]]; then
    echo "ERROR: $opt requires a value." >&2
    usage
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    pull|push|status) COMMAND="$1"; shift ;;
    --overwrite) OVERWRITE=true; shift ;;
    --diff) SHOW_DIFF=true; shift ;;
    --exclude)
      require_option_value "$1" "$#"
      EXTRA_EXCLUDES+=("$2")
      shift 2
      ;;
    --include-agents)
      echo "[sync] NOTE: --include-agents is deprecated; agents are always included." >&2
      shift
      ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$COMMAND" ]] && usage

# --- Helpers ---

PREVIEW_FILE="$(mktemp)"
CONFLICT_FILE="$(mktemp)"
trap 'rm -f "$PREVIEW_FILE" "$CONFLICT_FILE"' EXIT

RSYNC_EXCLUDES=(--exclude='.*/')
DIFF_EXCLUDES=(-x '.*')
for pat in "${EXTRA_EXCLUDES[@]}"; do
  RSYNC_EXCLUDES+=(--exclude="$pat")
  DIFF_EXCLUDES+=(-x "$pat")
done

sync_dir() {
  local src="$1" dest="$2"
  mkdir -p "$dest"
  rsync -a "${RSYNC_EXCLUDES[@]}" "$src"/ "$dest"/ 2>/dev/null || \
    cp -r "$src"/* "$dest"/ 2>/dev/null || true
}

collect_pair_preview() {
  local src="$1" dest="$2" label="$3"

  mkdir -p "$dest"

  if command -v rsync >/dev/null 2>&1; then
    local out
    out="$(rsync -ani "${RSYNC_EXCLUDES[@]}" "$src"/ "$dest"/ 2>/dev/null || true)"

    if [[ -n "$out" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local code path
        code="${line%% *}"
        path="${line#* }"
        printf '%s\t%s\t%s\n' "$label" "$code" "$path" >> "$PREVIEW_FILE"

        # Existing file changed. New file creations are not conflicts.
        if [[ "$code" == \>f* && "$code" != *"+++++++++"* ]]; then
          printf '%s\t%s\n' "$label" "$path" >> "$CONFLICT_FILE"
        fi
      done <<< "$out"
    fi
  else
    local out
    out="$(diff -rq "${DIFF_EXCLUDES[@]}" "$src" "$dest" 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf '%s\t%s\t%s\n' "$label" "diff" "$line" >> "$PREVIEW_FILE"
        if [[ "$line" == Files* && "$line" == *" differ" ]]; then
          printf '%s\t%s\n' "$label" "$line" >> "$CONFLICT_FILE"
        fi
      done <<< "$out"
    fi
  fi
}

has_pending_changes() {
  [[ -s "$PREVIEW_FILE" ]]
}

has_conflicts() {
  [[ -s "$CONFLICT_FILE" ]]
}

preview_pull() {
  : > "$PREVIEW_FILE"
  : > "$CONFLICT_FILE"

  for skill_path in "$SKILLS_SRC"/*/; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_path")"
    collect_pair_preview "$skill_path" "$AGENTS_SKILLS/$skill_name" "submodule->$AGENTS_SKILLS/$skill_name"
    collect_pair_preview "$skill_path" "$CLAUDE_SKILLS/$skill_name" "submodule->$CLAUDE_SKILLS/$skill_name"
  done
}

preview_push() {
  : > "$PREVIEW_FILE"
  : > "$CONFLICT_FILE"

  for skill_path in "$CLAUDE_SKILLS"/*/; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_path")"

    collect_pair_preview "$skill_path" "$AGENTS_SKILLS/$skill_name" ".claude->$AGENTS_SKILLS/$skill_name"

    if [[ -d "$SKILLS_SRC/$skill_name" ]]; then
      collect_pair_preview "$skill_path" "$SKILLS_SRC/$skill_name" ".claude->$SKILLS_SRC/$skill_name"
    fi
  done
}

print_preview_summary() {
  if ! has_pending_changes; then
    echo "No pending sync changes."
    return
  fi

  echo "Pending sync changes:"
  awk -F'\t' '{ printf "  [%s] %s %s\n", $1, $2, $3 }' "$PREVIEW_FILE"

  if has_conflicts; then
    echo ""
    echo "Conflicting files (existing files with content changes):"
    awk -F'\t' '{ printf "  [%s] %s\n", $1, $2 }' "$CONFLICT_FILE"
  fi
}

print_quick_diff() {
  echo "═══ Quick Diff (from submodule) ═══"
  echo ""

  echo "── submodule vs .agents/skills"
  diff -ru "${DIFF_EXCLUDES[@]}" "$SKILLS_SRC" "$AGENTS_SKILLS" || true

  echo ""
  echo "── submodule vs .claude/skills"
  diff -ru "${DIFF_EXCLUDES[@]}" "$SKILLS_SRC" "$CLAUDE_SKILLS" || true
}

apply_pull() {
  echo "Applying pull: submodule -> .agents/skills + .claude/skills"

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
  echo "Done. Custom file additions are preserved."
}

apply_push() {
  echo "Applying push: .claude/skills -> .agents/skills + submodule"

  local synced=0
  for skill_path in "$CLAUDE_SKILLS"/*/; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_path")"

    sync_dir "$skill_path" "$AGENTS_SKILLS/$skill_name"

    if [[ -d "$SKILLS_SRC/$skill_name" ]]; then
      sync_dir "$skill_path" "$SKILLS_SRC/$skill_name"
    fi

    ((synced++)) || true
  done

  echo "  Synced $synced skills"
  echo "Done. Custom file additions are preserved."
  echo "To commit submodule changes:"
  echo "  cd $ORCHESTRATE_DIR && git add -A && git commit -m 'sync' && git push"
}

do_status() {
  echo "═══ Sync Status ═══"
  echo ""

  echo "── .claude/skills/ vs .agents/skills/ (should be identical)"
  local diff_ca
  diff_ca="$(diff -rq "${DIFF_EXCLUDES[@]}" "$CLAUDE_SKILLS" "$AGENTS_SKILLS" 2>/dev/null || true)"
  if [[ -z "$diff_ca" ]]; then
    echo "   ✓ In sync"
  else
    echo "$diff_ca" | sed 's/^/   /'
  fi

  echo ""
  echo "── .agents/skills/ vs submodule (project customizations)"
  local diff_as
  diff_as="$(diff -rq "${DIFF_EXCLUDES[@]}" "$AGENTS_SKILLS" "$SKILLS_SRC" 2>/dev/null || true)"
  if [[ -z "$diff_as" ]]; then
    echo "   ✓ In sync"
  else
    echo "$diff_as" | sed 's/^/   /'
  fi

  echo ""
  echo "── Submodule status"
  (cd "$ORCHESTRATE_DIR" && git status --short 2>/dev/null) | sed 's/^/   /' || echo "   (not a git repo)"

  if [[ "$SHOW_DIFF" == true ]]; then
    echo ""
    print_quick_diff
  fi
}

do_preview_or_apply_pull() {
  preview_pull

  if [[ "$SHOW_DIFF" == true ]]; then
    print_quick_diff
    echo ""
  fi

  if ! has_pending_changes; then
    echo "No pending sync changes."
    echo "No action required."
    return
  fi

  if has_conflicts && [[ "$OVERWRITE" == false ]]; then
    print_preview_summary
    echo ""
    echo "Conflicts detected. No files were changed."
    echo "Use --overwrite to apply all updates anyway."
    echo "Use --diff for quick content diffs."
    exit 2
  fi

  if has_conflicts && [[ "$OVERWRITE" == true ]]; then
    echo "Conflicts detected; applying because --overwrite was provided."
  else
    echo "No conflicts detected; applying sync updates."
  fi

  apply_pull
}

do_preview_or_apply_push() {
  preview_push

  if [[ "$SHOW_DIFF" == true ]]; then
    print_quick_diff
    echo ""
  fi

  if ! has_pending_changes; then
    echo "No pending sync changes."
    echo "No action required."
    return
  fi

  if has_conflicts && [[ "$OVERWRITE" == false ]]; then
    print_preview_summary
    echo ""
    echo "Conflicts detected. No files were changed."
    echo "Use --overwrite to apply all updates anyway."
    echo "Use --diff for quick content diffs."
    exit 2
  fi

  if has_conflicts && [[ "$OVERWRITE" == true ]]; then
    echo "Conflicts detected; applying because --overwrite was provided."
  else
    echo "No conflicts detected; applying sync updates."
  fi

  apply_push
}

# --- Dispatch ---

case "$COMMAND" in
  pull)   do_preview_or_apply_pull ;;
  push)   do_preview_or_apply_push ;;
  status) do_status ;;
esac
