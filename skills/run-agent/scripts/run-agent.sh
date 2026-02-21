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
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd -P)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RUNS_DIR="$SKILLS_DIR/run-agent/.runs"
SESSION_DIR="$SKILLS_DIR/orchestrate/.session"

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
}

init_dirs() {
  mkdir -p "$RUNS_DIR/project"/{scratch/code/smoke,logs/agent-runs}
  mkdir -p "$SESSION_DIR/project"
}

# ─── Main ────────────────────────────────────────────────────────────────────

parse_args "$@"
init_work_dir
validate_args
init_dirs

COMPOSED_PROMPT="$(compose_prompt)"
build_cli_command

if [[ "$DRY_RUN" == true ]]; then
  do_dry_run
  exit 0
fi

do_execute
