#!/usr/bin/env bash
# run-agent.sh — Single entry point for running any agent.
# Routes models to the correct CLI tool, loads skills, composes prompts, logs everything.
#
# Usage:
#   scripts/run-agent.sh [agent] [OPTIONS]
#   scripts/run-agent.sh --model gpt-5.3-codex --skills review -p "Review the changes"
#   scripts/run-agent.sh review --dry-run
#
# See the run-agent skill README.md for full documentation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"  # -P resolves symlinks to canonical path
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd -P)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

# Runs directory — portable, defaults to .runs/ sibling of skill root
ORCHESTRATE_RUNS_DIR="${ORCHESTRATE_RUNS_DIR:-$SCRIPT_DIR/../.runs}"
ORCHESTRATE_RUNS_DIR="$(mkdir -p "$ORCHESTRATE_RUNS_DIR" && cd "$ORCHESTRATE_RUNS_DIR" && pwd -P)"

# Auto-bootstrap .runs/ on first use
[[ -d "$ORCHESTRATE_RUNS_DIR/project" ]] || mkdir -p "$ORCHESTRATE_RUNS_DIR/project"/{scratch/code/smoke,logs/agent-runs}

# ─── Defaults ────────────────────────────────────────────────────────────────

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

# CLI_CMD_ARGV — populated by build_cli_command() in lib/exec.sh
declare -a CLI_CMD_ARGV=()

# ─── Source Modules ──────────────────────────────────────────────────────────

source "$SCRIPT_DIR/lib/parse.sh"
source "$SCRIPT_DIR/lib/prompt.sh"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/exec.sh"

# ─── Main ────────────────────────────────────────────────────────────────────

parse_args "$@"
validate_args

COMPOSED_PROMPT="$(compose_prompt)"
build_cli_command

if [[ "$DRY_RUN" == true ]]; then
  do_dry_run
  exit 0
fi

do_execute
