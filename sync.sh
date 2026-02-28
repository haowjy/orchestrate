#!/usr/bin/env bash
# sync.sh — Sync skills and agents between orchestrate source, .agents/, and .claude/.
#
# Default behavior (sync):
# - syncs all skills + agents found in source dir
# - applies automatically when there are no conflicts
# - blocks when conflicts exist and prints conflict list
# - use --overwrite to apply despite conflicts
#
# sync also creates runtime directories (.orchestrate/runs/, .orchestrate/index/).

set -euo pipefail

# --- Locate ourselves and the project root ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_OVERRIDE=""

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

# --- Usage ---

usage() {
  cat <<'USAGE'
Usage: sync.sh <command> [options]

Commands:
  sync     Sync orchestrate -> .agents/ + .claude/ (skills + agents)
  status   Show differences between all three locations

Filtering (sync):
  --skills skill1,skill2   Only sync specific skills (validated against MANIFEST)
  --agents agent1,agent2   Only sync specific agent profiles (validated against MANIFEST)
  --all                    Sync all skills + all agents (default behavior)
  --include-hooks          Also sync platform hooks (.cursor, .opencode) [sync only]

Default mode (sync):
- apply automatically when no conflicts are detected
- stop and print conflicting files when conflicts exist

Options:
  --workspace DIR          Project root override (default: auto-detect from git)
  --overwrite              Apply changes even if conflicts exist
  --diff                   Show quick unified diffs from submodule
  --exclude PATTERN        Exclude file/path pattern from preview/sync/diff (repeatable)
  -h, --help               Show this help
USAGE
  exit 1
}

# --- Parse args ---

COMMAND=""
OVERWRITE=false
SHOW_DIFF=false
INCLUDE_HOOKS=false
EXTRA_EXCLUDES=()
FILTER_SKILLS=""
FILTER_AGENTS=""
FILTER_ALL=false

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
    sync|status) COMMAND="$1"; shift ;;
    --overwrite) OVERWRITE=true; shift ;;
    --diff) SHOW_DIFF=true; shift ;;
    --exclude)
      require_option_value "$1" "$#"
      EXTRA_EXCLUDES+=("$2")
      shift 2
      ;;
    --workspace)
      require_option_value "$1" "$#"
      WORKSPACE_OVERRIDE="$2"
      shift 2
      ;;
    --skills)
      require_option_value "$1" "$#"
      FILTER_SKILLS="$2"
      shift 2
      ;;
    --agents)
      require_option_value "$1" "$#"
      FILTER_AGENTS="$2"
      shift 2
      ;;
    --all) FILTER_ALL=true; shift ;;
    --include-hooks) INCLUDE_HOOKS=true; shift ;;
    --include-agents)
      echo "[sync] NOTE: --include-agents is deprecated; agents are always included." >&2
      shift
      ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$COMMAND" ]] && usage

# --- Resolve project root ---

if [[ -n "$WORKSPACE_OVERRIDE" ]]; then
  PROJECT_ROOT="$(cd "$WORKSPACE_OVERRIDE" && pwd)"
else
  PROJECT_ROOT="$(find_project_root)" || {
    echo "Error: Could not find parent project git root." >&2
    echo "Use --workspace DIR to specify the project root." >&2
    exit 1
  }
fi

ORCHESTRATE_DIR="$SCRIPT_DIR"
SKILLS_SRC="$ORCHESTRATE_DIR/skills"
AGENTS_SRC="$ORCHESTRATE_DIR/agents"
MANIFEST="$ORCHESTRATE_DIR/MANIFEST"
AGENTS_SKILLS="$PROJECT_ROOT/.agents/skills"
CLAUDE_SKILLS="$PROJECT_ROOT/.claude/skills"
AGENTS_AGENTS="$PROJECT_ROOT/.agents/agents"
CLAUDE_AGENTS="$PROJECT_ROOT/.claude/agents"

# --- MANIFEST parsing ---

# Parse MANIFEST into three arrays: CORE_SKILLS, OPTIONAL_SKILLS, MANIFEST_AGENTS.
# Sections are delimited by comment lines containing "agents" (case-insensitive).
CORE_SKILLS=()
OPTIONAL_SKILLS=()
MANIFEST_AGENTS=()

parse_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    echo "Warning: MANIFEST not found at $MANIFEST; syncing all found items." >&2
    return
  fi

  local section="core"  # core -> optional -> agents

  while IFS= read -r line; do
    # Detect section transitions from comment lines
    if [[ "$line" =~ ^# ]]; then
      local lower
      lower="$(echo "$line" | tr '[:upper:]' '[:lower:]')"
      if [[ "$lower" == *"optional skills"* ]]; then
        section="optional"
      elif [[ "$lower" == *"agent"* ]]; then
        section="agents"
      fi
      continue
    fi

    # Strip remaining inline comments and whitespace
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    case "$section" in
      core)     CORE_SKILLS+=("$line") ;;
      optional) OPTIONAL_SKILLS+=("$line") ;;
      agents)   MANIFEST_AGENTS+=("$line") ;;
    esac
  done < "$MANIFEST"
}

parse_manifest

# --- Build sync lists based on filters ---

# All manifest skills = core + optional
ALL_MANIFEST_SKILLS=("${CORE_SKILLS[@]}" "${OPTIONAL_SKILLS[@]}")

# Validate a name against an allowed list. Returns 0 if found.
validate_name() {
  local name="$1"
  shift
  local allowed=("$@")
  for item in "${allowed[@]}"; do
    if [[ "$item" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

# Build SYNC_SKILLS list
build_skill_list() {
  SYNC_SKILLS=()

  if [[ -n "$FILTER_SKILLS" ]]; then
    # User specified --skills: validate each against manifest
    IFS=',' read -ra requested <<< "$FILTER_SKILLS"
    for req in "${requested[@]}"; do
      req="$(echo "$req" | xargs)"
      [[ -z "$req" ]] && continue
      if validate_name "$req" "${ALL_MANIFEST_SKILLS[@]}"; then
        SYNC_SKILLS+=("$req")
      else
        echo "Warning: skill '$req' is not in MANIFEST. Skipping." >&2
      fi
    done
  elif [[ -z "$FILTER_AGENTS" ]]; then
    # No --skills and no --agents: sync all skills (default = --all for skills)
    SYNC_SKILLS=("${ALL_MANIFEST_SKILLS[@]}")
  fi
  # If only --agents was specified (no --skills), SYNC_SKILLS stays empty
}

# Build SYNC_AGENTS list
build_agent_list() {
  SYNC_AGENTS=()

  if [[ -n "$FILTER_AGENTS" ]]; then
    # User specified --agents: validate each against manifest
    IFS=',' read -ra requested <<< "$FILTER_AGENTS"
    for req in "${requested[@]}"; do
      req="$(echo "$req" | xargs)"
      [[ -z "$req" ]] && continue
      if [[ ${#MANIFEST_AGENTS[@]} -gt 0 ]] && validate_name "$req" "${MANIFEST_AGENTS[@]}"; then
        SYNC_AGENTS+=("$req")
      else
        echo "Warning: agent '$req' is not in MANIFEST. Skipping." >&2
      fi
    done
  elif [[ -z "$FILTER_SKILLS" ]]; then
    # No --agents and no --skills: sync all agents (default = --all for agents)
    if [[ ${#MANIFEST_AGENTS[@]} -gt 0 ]]; then
      SYNC_AGENTS=("${MANIFEST_AGENTS[@]}")
    fi
  fi
  # If only --skills was specified (no --agents), SYNC_AGENTS stays empty
}

# --all is explicit: sync everything regardless of other filters
if [[ "$FILTER_ALL" == true ]]; then
  SYNC_SKILLS=("${ALL_MANIFEST_SKILLS[@]}")
  if [[ ${#MANIFEST_AGENTS[@]} -gt 0 ]]; then
    SYNC_AGENTS=("${MANIFEST_AGENTS[@]}")
  else
    SYNC_AGENTS=()
  fi
else
  build_skill_list
  build_agent_list
fi

# --- Platform hooks sync ---

# Merge orchestrate hooks into Cursor's .cursor/hooks.json using jq.
# If the file doesn't exist, copy ours directly. If it does, merge our
# hook entries into each event array (deduplicated by command path).
merge_cursor_hooks() {
  local src="$ORCHESTRATE_DIR/hooks/.cursor/hooks.json"
  local dest="$PROJECT_ROOT/.cursor/hooks.json"

  [[ -f "$src" ]] || return 0
  mkdir -p "$PROJECT_ROOT/.cursor"

  if [[ ! -f "$dest" ]]; then
    cp "$src" "$dest"
    echo "  Created .cursor/hooks.json"
    return 0
  fi

  # Merge: deep-merge our hooks into the existing file.
  # For each event key, concatenate arrays and deduplicate by .command+matcher
  # (our entries win on conflict). User hooks for other events are preserved.
  if command -v jq >/dev/null 2>&1; then
    local merged
    merged="$(jq -s '
      (.[0].hooks // {}) as $ours |
      (.[1] // {}) |
      .version //= 1 |
      .hooks = (
        (.hooks // {}) as $theirs |
        ($ours | keys) as $our_keys |
        ($theirs | keys) as $their_keys |
        ($our_keys + $their_keys | unique) |
        map({
          key: .,
          value: (
            (($ours[.] // []) + ($theirs[.] // [])) | unique_by({command, matcher})
          )
        }) | from_entries
      )
    ' "$src" "$dest" 2>/dev/null)" || {
      echo "  Warning: failed to merge .cursor/hooks.json — skipping (existing file preserved)" >&2
      return 0
    }
    echo "$merged" > "$dest"
    echo "  Merged orchestrate hooks into .cursor/hooks.json"
  else
    echo "  Warning: jq not found — cannot merge .cursor/hooks.json. Install jq or merge manually." >&2
  fi
}

sync_platform_hooks() {
  local hooks_dir="$ORCHESTRATE_DIR/hooks"
  local hooks_scripts_src="$hooks_dir/scripts"

  # Sync shared hook scripts into harness-local directories.
  if [[ -d "$hooks_scripts_src" ]]; then
    local scripts_dests=(
      "$PROJECT_ROOT/.claude/hooks/scripts"
      "$PROJECT_ROOT/.cursor/hooks/scripts"
      "$PROJECT_ROOT/.opencode/hooks/scripts"
    )
    local dest
    for dest in "${scripts_dests[@]}"; do
      mkdir -p "$dest"
      cp "$hooks_scripts_src/"*.sh "$dest/"
      chmod +x "$dest/"*.sh
    done
    echo "  Synced hook scripts to .claude/.cursor/.opencode hook directories"
  fi

  # OpenCode — copy orchestrate.ts plugin
  local oc_src="$hooks_dir/.opencode/plugins/orchestrate.ts"
  local oc_dest="$PROJECT_ROOT/.opencode/plugins/orchestrate.ts"
  if [[ -f "$oc_src" ]]; then
    mkdir -p "$PROJECT_ROOT/.opencode/plugins"
    if [[ ! -f "$oc_dest" ]]; then
      cp "$oc_src" "$oc_dest"
      echo "  Created .opencode/plugins/orchestrate.ts"
    elif diff -q "$oc_src" "$oc_dest" >/dev/null 2>&1; then
      : # Already in sync
    elif [[ "$OVERWRITE" == true ]]; then
      cp "$oc_src" "$oc_dest"
      echo "  Updated .opencode/plugins/orchestrate.ts"
    else
      echo "  Conflict: .opencode/plugins/orchestrate.ts differs. Use --overwrite to replace." >&2
    fi
  fi

  # Cursor — merge into existing hooks.json
  merge_cursor_hooks
}

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

# Copy a single agent profile (.md file)
sync_agent_file() {
  local src_file="$1" dest_dir="$2"
  mkdir -p "$dest_dir"
  cp "$src_file" "$dest_dir/$(basename "$src_file")"
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

# Collect preview for a single file (agent profile)
collect_file_preview() {
  local src_file="$1" dest_dir="$2" label="$3"
  local basename
  basename="$(basename "$src_file")"
  local dest_file="$dest_dir/$basename"

  if [[ ! -f "$dest_file" ]]; then
    printf '%s\t%s\t%s\n' "$label" "new" "$basename" >> "$PREVIEW_FILE"
  elif ! diff -q "$src_file" "$dest_file" >/dev/null 2>&1; then
    printf '%s\t%s\t%s\n' "$label" "changed" "$basename" >> "$PREVIEW_FILE"
    printf '%s\t%s\n' "$label" "$basename" >> "$CONFLICT_FILE"
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

  # Skills
  for skill_name in "${SYNC_SKILLS[@]}"; do
    local skill_path="$SKILLS_SRC/$skill_name"
    [[ -d "$skill_path" ]] || continue
    collect_pair_preview "$skill_path" "$AGENTS_SKILLS/$skill_name" "submodule->$AGENTS_SKILLS/$skill_name"
    collect_pair_preview "$skill_path" "$CLAUDE_SKILLS/$skill_name" "submodule->$CLAUDE_SKILLS/$skill_name"
  done

  # Agents
  for agent_name in "${SYNC_AGENTS[@]}"; do
    local agent_file="$AGENTS_SRC/$agent_name.md"
    [[ -f "$agent_file" ]] || continue
    collect_file_preview "$agent_file" "$AGENTS_AGENTS" "submodule->$AGENTS_AGENTS"
    collect_file_preview "$agent_file" "$CLAUDE_AGENTS" "submodule->$CLAUDE_AGENTS"
  done
}

preview_push() {
  : > "$PREVIEW_FILE"
  : > "$CONFLICT_FILE"

  # Skills
  for skill_name in "${SYNC_SKILLS[@]}"; do
    local skill_path="$CLAUDE_SKILLS/$skill_name"
    [[ -d "$skill_path" ]] || continue

    collect_pair_preview "$skill_path" "$AGENTS_SKILLS/$skill_name" ".claude->$AGENTS_SKILLS/$skill_name"

    if [[ -d "$SKILLS_SRC/$skill_name" ]]; then
      collect_pair_preview "$skill_path" "$SKILLS_SRC/$skill_name" ".claude->$SKILLS_SRC/$skill_name"
    fi
  done

  # Agents
  for agent_name in "${SYNC_AGENTS[@]}"; do
    local agent_file="$CLAUDE_AGENTS/$agent_name.md"
    [[ -f "$agent_file" ]] || continue

    collect_file_preview "$agent_file" "$AGENTS_AGENTS" ".claude->$AGENTS_AGENTS"

    if [[ -f "$AGENTS_SRC/$agent_name.md" ]]; then
      collect_file_preview "$agent_file" "$AGENTS_SRC" ".claude->$AGENTS_SRC"
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
  echo "Applying pull: submodule -> .agents/ + .claude/"

  # Skills
  local skills_copied=0
  for skill_name in "${SYNC_SKILLS[@]}"; do
    local skill_path="$SKILLS_SRC/$skill_name"
    [[ -d "$skill_path" ]] || {
      echo "  Warning: skill '$skill_name' not found at $skill_path, skipping." >&2
      continue
    }

    sync_dir "$skill_path" "$AGENTS_SKILLS/$skill_name"
    sync_dir "$skill_path" "$CLAUDE_SKILLS/$skill_name"
    ((skills_copied++)) || true
  done

  # Agents
  local agents_copied=0
  for agent_name in "${SYNC_AGENTS[@]}"; do
    local agent_file="$AGENTS_SRC/$agent_name.md"
    [[ -f "$agent_file" ]] || {
      echo "  Warning: agent '$agent_name' not found at $agent_file, skipping." >&2
      continue
    }

    sync_agent_file "$agent_file" "$AGENTS_AGENTS"
    sync_agent_file "$agent_file" "$CLAUDE_AGENTS"
    ((agents_copied++)) || true
  done

  echo "  Synced $skills_copied skills, $agents_copied agents"

  echo "Done. Custom file additions are preserved."
}

apply_push() {
  echo "Applying push: .claude/ -> .agents/ + submodule"

  # Skills
  local skills_synced=0
  for skill_name in "${SYNC_SKILLS[@]}"; do
    local skill_path="$CLAUDE_SKILLS/$skill_name"
    [[ -d "$skill_path" ]] || continue

    sync_dir "$skill_path" "$AGENTS_SKILLS/$skill_name"

    if [[ -d "$SKILLS_SRC/$skill_name" ]]; then
      sync_dir "$skill_path" "$SKILLS_SRC/$skill_name"
    fi

    ((skills_synced++)) || true
  done

  # Agents
  local agents_synced=0
  for agent_name in "${SYNC_AGENTS[@]}"; do
    local agent_file="$CLAUDE_AGENTS/$agent_name.md"
    [[ -f "$agent_file" ]] || continue

    sync_agent_file "$agent_file" "$AGENTS_AGENTS"

    if [[ -f "$AGENTS_SRC/$agent_name.md" ]]; then
      sync_agent_file "$agent_file" "$AGENTS_SRC"
    fi

    ((agents_synced++)) || true
  done

  echo "  Synced $skills_synced skills, $agents_synced agents"
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
  echo "── .claude/agents/ vs .agents/agents/ (should be identical)"
  if [[ -d "$CLAUDE_AGENTS" && -d "$AGENTS_AGENTS" ]]; then
    local diff_agents
    diff_agents="$(diff -rq "$CLAUDE_AGENTS" "$AGENTS_AGENTS" 2>/dev/null || true)"
    if [[ -z "$diff_agents" ]]; then
      echo "   ✓ In sync"
    else
      echo "$diff_agents" | sed 's/^/   /'
    fi
  else
    echo "   (agent directories not yet created)"
  fi

  echo ""
  echo "── Submodule status"
  (cd "$ORCHESTRATE_DIR" && git status --short 2>/dev/null) | sed 's/^/   /' || echo "   (not a git repo)"

  if [[ "$SHOW_DIFF" == true ]]; then
    echo ""
    print_quick_diff
  fi
}

ensure_runtime_dirs() {
  local orchestrate_rt="$PROJECT_ROOT/.orchestrate"
  mkdir -p "$orchestrate_rt/runs/agent-runs"
  mkdir -p "$orchestrate_rt/index"
  mkdir -p "$orchestrate_rt/session"
}

do_preview_or_apply_sync() {
  # Always ensure runtime directories exist on pull, even if no files changed
  ensure_runtime_dirs

  preview_pull

  if [[ "$SHOW_DIFF" == true ]]; then
    print_quick_diff
    echo ""
  fi

  # Platform hooks run independently of skill/agent sync — they have their own
  # conflict handling (merge for Cursor, diff-check for OpenCode).
  if [[ "$INCLUDE_HOOKS" == true ]]; then
    sync_platform_hooks
  fi

  if ! has_pending_changes; then
    echo "No pending skill/agent sync changes."
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

# --- Dispatch ---

case "$COMMAND" in
  sync)   do_preview_or_apply_sync ;;
  status) do_status ;;
esac
