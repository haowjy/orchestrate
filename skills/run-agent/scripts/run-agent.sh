#!/usr/bin/env bash
# run-agent.sh — Single entry point for running any agent.
# Routes models to the correct CLI tool, loads skills, composes prompts, logs everything.
#
# Usage:
#   scripts/run-agent.sh [agent] [OPTIONS]
#   scripts/run-agent.sh --model claude-sonnet-4-6 --skills review -p "Review the changes"
#   scripts/run-agent.sh review --dry-run
#
# See the run-agent skill README.md for full documentation.

set -euo pipefail

# Resolve through symlinks so SKILLS_DIR is correct even when invoked via a symlink.
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
  _dir="$(cd "$(dirname "$_source")" && pwd -P)"
  _source="$(readlink "$_source")"
  [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd "$(dirname "$_source")" && pwd -P)"
CURRENT_DIR="$(pwd -P)"
REPO_ROOT="$(git -C "$CURRENT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$CURRENT_DIR")"
ORCHESTRATE_ROOT="${ORCHESTRATE_ROOT:-}"
ORCHESTRATE_ROOT_LOCKED=false
if [[ -n "$ORCHESTRATE_ROOT" ]]; then
  ORCHESTRATE_ROOT_LOCKED=true
fi
AGENTS_DIR=""
SKILLS_DIR=""
RUNS_DIR=""
SESSION_DIR=""

refresh_orchestrate_paths() {
  local repo_base="$1"
  if [[ "$ORCHESTRATE_ROOT_LOCKED" != true ]]; then
    ORCHESTRATE_ROOT="$repo_base/.orchestrate"
  fi
  AGENTS_DIR="$ORCHESTRATE_ROOT/agents"
  # Skills live in the submodule/clone source, not the runtime dir.
  # Derive from SCRIPT_DIR (inside orchestrate/skills/run-agent/scripts/).
  SKILLS_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd -P)/skills"
  RUNS_DIR="$ORCHESTRATE_ROOT/runs"
  SESSION_DIR="$ORCHESTRATE_ROOT/session"
}

refresh_orchestrate_paths_from_workdir() {
  local candidate_repo
  candidate_repo="$(git -C "$WORK_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$WORK_DIR")"
  REPO_ROOT="$candidate_repo"
  refresh_orchestrate_paths "$REPO_ROOT"
}

# ─── Defaults ────────────────────────────────────────────────────────────────

# Default fallback when the routed CLI isn't available.
FALLBACK_CLI="codex"
FALLBACK_MODEL="gpt-5.3-codex"

MODEL=""
EFFORT="high"
TOOLS="Read,Edit,Write,Bash,Glob,Grep"
SKILLS=()
PROMPT=""
AGENT_PROMPT=""
CLI_PROMPT=""
AGENT_NAME=""
DRY_RUN=false
DETAIL="standard"   # brief | standard | detailed
WORK_DIR="$REPO_ROOT"
declare -A VARS=()  # template variables
REF_FILES=()        # reference file paths (-f flag)
HAS_VARS=false
MODEL_FROM_CLI=false
EFFORT_FROM_CLI=false
TOOLS_FROM_CLI=false
PLAN_NAME=""         # --plan shorthand
SLICE_NAME=""        # --slice shorthand

# CLI_CMD_ARGV — populated by build_cli_command() in lib/exec.sh
declare -a CLI_CMD_ARGV=()
# CLI_HARNESS — populated by build_cli_command() in lib/exec.sh (claude|codex|opencode)
CLI_HARNESS=""

refresh_orchestrate_paths "$REPO_ROOT"

# ─── Source Modules ──────────────────────────────────────────────────────────

source "$SCRIPT_DIR/lib/parse.sh"
source "$SCRIPT_DIR/lib/prompt.sh"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/exec.sh"

# ─── Init Helpers ────────────────────────────────────────────────────────────

init_work_dir() {
  if ! WORK_DIR="$(cd "$WORK_DIR" 2>/dev/null && pwd -P)"; then
    echo "ERROR: Working directory does not exist: $WORK_DIR" >&2
    exit 1
  fi

  # Prefer the git root of the working dir so relative file lookups map to the target project.
  REPO_ROOT="$(git -C "$WORK_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$WORK_DIR")"
  refresh_orchestrate_paths "$REPO_ROOT"
}

init_dirs() {
  mkdir -p "$ORCHESTRATE_ROOT"
  mkdir -p "$RUNS_DIR/project"/{.scratch/code/smoke,logs/agent-runs}
  mkdir -p "$SESSION_DIR/project"
}

inject_runtime_template_vars() {
  # Make runtime paths explicit in prompts so agents write inside the managed
  # run/session directories rather than the caller's working directory.
  [[ -z "${VARS[RUNS_DIR]:-}" ]] && VARS[RUNS_DIR]="$RUNS_DIR"
  [[ -z "${VARS[SESSION_DIR]:-}" ]] && VARS[SESSION_DIR]="$SESSION_DIR"
  [[ -z "${VARS[SCOPE_ROOT]:-}" ]] && VARS[SCOPE_ROOT]="$(infer_scope_root)"
  HAS_VARS=true
}

# ─── Main ────────────────────────────────────────────────────────────────────

parse_args "$@"
init_work_dir
validate_args
init_dirs
inject_runtime_template_vars

COMPOSED_PROMPT="$(compose_prompt)"
build_cli_command

if [[ "$DRY_RUN" == true ]]; then
  do_dry_run
  exit 0
fi

do_execute
