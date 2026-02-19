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

  # Paths starting with .runs/ resolve relative to ORCHESTRATE_RUNS_DIR.
  if [[ "$path" == .runs/* ]] || [[ "$path" == ./.runs/* ]]; then
    local rel="${path#./}"
    rel="${rel#.runs/}"
    echo "$ORCHESTRATE_RUNS_DIR/$rel"
    return
  fi

  # Prefer an existing path under WORK_DIR, then REPO_ROOT.
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
  local base
  base="$(basename -- "$plan_file")"
  base="${base%.md}"
  base="${base// /-}"
  base="$(echo "$base" | sed 's#[^A-Za-z0-9._-]#-#g')"
  [[ -z "$base" ]] && base="unnamed-plan"
  echo "$ORCHESTRATE_RUNS_DIR/plans/$base"
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
  echo "$ORCHESTRATE_RUNS_DIR/project"
}

# ─── Log Setup ────────────────────────────────────────────────────────────────

setup_logging() {
  local label
  label="$(sanitize_log_label "${AGENT_NAME:-$MODEL}")"

  # External interface: ORCHESTRATE_LOG_DIR. Internal shorthand: LOG_DIR.
  LOG_DIR="${ORCHESTRATE_LOG_DIR:-${LOG_DIR:-}}"
  if [[ -z "${LOG_DIR:-}" ]]; then
    local scope_root
    scope_root="$(infer_scope_root)"
    LOG_DIR="$scope_root/logs/agent-runs/${label}"
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
  "harness": "$(json_escape "${ORCHESTRATE_DEFAULT_CLI:-$(route_model "$MODEL")}")",
  "invoked_via": "$(json_escape "$0")",
  "script_dir": "$(json_escape "$SCRIPT_DIR")",
  "detail": "$(json_escape "$DETAIL")",
  "cwd": "$(json_escape "$WORK_DIR")",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "log_dir": "$(json_escape "$LOG_DIR")"
}
EOF
}
