#!/usr/bin/env bash
# lib/logging.sh — Log directory setup, params.json writing, scope inference, path helpers.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Path Helpers ─────────────────────────────────────────────────────────────

resolve_repo_or_work_path() {
  local path="$1"

  if [[ "$path" == /* ]]; then
    echo "$path"
    return
  fi

  # Runtime scope shorthand should always resolve under RUNS_DIR, even when
  # the path doesn't exist yet. This prevents accidental writes to repo-root
  # paths like ./plans/* when callers use plan/slice shorthand.
  if [[ "$path" == plans/* || "$path" == project/* ]]; then
    echo "$RUNS_DIR/$path"
    return
  fi

  # Prefer an existing path under RUNS_DIR (shortest paths), then WORK_DIR, then REPO_ROOT.
  # This lets callers write e.g. "plans/my-plan/slices/my-slice/slice.md" instead of the
  # full ".claude/skills/run-agent/.runs/plans/..." path.
  if [[ -e "$RUNS_DIR/$path" ]]; then
    echo "$RUNS_DIR/$path"
    return
  fi
  if [[ -e "$WORK_DIR/$path" ]]; then
    echo "$WORK_DIR/$path"
    return
  fi
  if [[ -e "$REPO_ROOT/$path" ]]; then
    echo "$REPO_ROOT/$path"
    return
  fi

  # Fallback: resolve relative to WORK_DIR.
  echo "$WORK_DIR/$path"
}

path_dir_or_self() {
  local path="$1"
  if [[ -d "$path" ]]; then
    echo "$path"
  else
    dirname -- "$path"
  fi
}

derive_plan_root_from_plan_file() {
  local plan_file="$1"

  # If PLAN_FILE already points inside RUNS_DIR/plans, preserve that exact
  # runtime plan root instead of collapsing to basename "plan".
  if [[ "$plan_file" == "$RUNS_DIR"/plans/*/plan.md ]]; then
    dirname -- "$plan_file"
    return
  fi

  local base
  base="$(basename -- "$plan_file")"
  base="${base%.md}"
  base="${base// /-}"
  base="$(echo "$base" | sed 's#[^A-Za-z0-9._-]#-#g')"
  [[ -z "$base" ]] && base="unnamed-plan"
  echo "$RUNS_DIR/plans/$base"
}

sanitize_log_label() {
  local label="$1"
  label="${label// /-}"
  label="$(echo "$label" | sed 's#[^A-Za-z0-9._-]#-#g')"
  label="$(echo "$label" | sed 's/^-*//; s/-*$//')"
  [[ -z "$label" ]] && label="run"
  echo "$label"
}

# ─── Scope Inference ──────────────────────────────────────────────────────────

infer_scope_root() {
  local value=""
  local first=""
  local resolved=""

  # Highest confidence signals first.
  # Prefer slice-oriented vars, with TASK_* aliases for compatibility.
  value="${VARS[SLICE_FILE]:-${VARS[TASK_FILE]:-}}"
  if [[ -n "$value" ]]; then
    resolved="$(resolve_repo_or_work_path "$value")"
    path_dir_or_self "$resolved"
    return
  fi

  value="${VARS[SLICES_DIR]:-${VARS[TASKS_DIR]:-}}"
  if [[ -n "$value" ]]; then
    resolved="$(resolve_repo_or_work_path "$value")"
    path_dir_or_self "$resolved"
    return
  fi

  value="${VARS[BREADCRUMBS]:-}"
  if [[ -n "$value" ]]; then
    IFS=',' read -r first _ <<< "$value"
    first="$(echo "$first" | sed 's/^ *//; s/ *$//')"
    if [[ -n "$first" ]]; then
      resolved="$(resolve_repo_or_work_path "$first")"
      path_dir_or_self "$resolved"
      return
    fi
  fi

  value="${VARS[PLAN_FILE]:-}"
  if [[ -n "$value" ]]; then
    resolved="$(resolve_repo_or_work_path "$value")"
    derive_plan_root_from_plan_file "$resolved"
    return
  fi

  # Global default for ad-hoc runs.
  echo "$RUNS_DIR/project"
}

# ─── Log Setup ────────────────────────────────────────────────────────────────

setup_logging() {
  local label
  label="$(sanitize_log_label "${AGENT_NAME:-$MODEL}")"

  if [[ -z "${LOG_DIR:-}" ]]; then
    local scope_root
    scope_root="$(infer_scope_root)"

    # Guard: scope_root must not be "/" or empty — that would cause mkdir at filesystem root.
    # This usually means a required variable (SLICE_FILE, SLICES_DIR, etc.) was empty or
    # resolved to a root-level path, which is always a caller bug.
    if [[ -z "$scope_root" || "$scope_root" == "/" ]]; then
      echo "ERROR: scope_root resolved to '${scope_root:-<empty>}' — refusing to create log dirs at filesystem root." >&2
      echo "  This usually means a required variable (SLICE_FILE, SLICES_DIR, PLAN_FILE) is empty or invalid." >&2
      echo "  Check that -v KEY=VALUE arguments have non-empty values." >&2
      exit 1
    fi

    # Append PID for parallel safety — multiple runs of the same agent get separate dirs.
    LOG_DIR="$scope_root/logs/agent-runs/${label}-$$"
  fi
  mkdir -p "$LOG_DIR"
}

write_log_params() {
  local cli_cmd="$1"
  local skills_json
  skills_json="$(build_skills_json)"
  cat > "$LOG_DIR/params.json" <<EOF
{
  "agent": "$(json_escape "${AGENT_NAME:-ad-hoc}")",
  "model": "$(json_escape "$MODEL")",
  "effort": "$(json_escape "$EFFORT")",
  "tools": "$(json_escape "$TOOLS")",
  "skills": $skills_json,
  "cli": "$(json_escape "$cli_cmd")",
  "harness": "$(json_escape "$(route_model "$MODEL")")",
  "invoked_via": "$(json_escape "$0")",
  "script_dir": "$(json_escape "$SCRIPT_DIR")",
  "detail": "$(json_escape "$DETAIL")",
  "cwd": "$(json_escape "$WORK_DIR")",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "log_dir": "$(json_escape "$LOG_DIR")"
}
EOF
}

# ─── Session Index ───────────────────────────────────────────────────────────

update_session_index() {
  local scope_root
  scope_root="$(infer_scope_root)"
  # Map scope root from RUNS_DIR to SESSION_DIR
  local session_scope="${scope_root/$RUNS_DIR/$SESSION_DIR}"
  mkdir -p "$session_scope"
  echo "${AGENT_NAME:-ad-hoc} | $MODEL | $$ | $EXIT_CODE | $LOG_DIR" \
    >> "$session_scope/index.log"
}
