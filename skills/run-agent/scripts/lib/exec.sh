#!/usr/bin/env bash
# lib/exec.sh — CLI command building (argv array), execution, files-touched extraction.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Build CLI Command (argv array) ──────────────────────────────────────────
# Populates global CLI_CMD_ARGV array instead of building a string.
# This avoids eval and shell-injection risks.

# Normalize tool names for the target CLI harness.
# Agent definitions use PascalCase (Read,Edit,Write) — some CLIs need different casing.
normalize_tools_for_harness() {
  local tool="$1" tools="$2"
  case "$tool" in
    claude)   echo "$tools" ;;                              # PascalCase passthrough
    codex)    echo "" ;;                                    # codex ignores tool allowlists
    opencode) echo "$tools" | tr '[:upper:]' '[:lower:]' ;; # lowercase for opencode
  esac
}

build_cli_command() {
  local tool

  # ORCHESTRATE_DEFAULT_CLI forces all model routing to a specific CLI.
  # Useful when you want all agents to run through one tool regardless of model name.
  # Example: ORCHESTRATE_DEFAULT_CLI=claude forces even gpt-* models to route through claude.
  if [[ -n "${ORCHESTRATE_DEFAULT_CLI:-}" ]]; then
    tool="$ORCHESTRATE_DEFAULT_CLI"
  else
    tool=$(route_model "$MODEL") || exit 1
  fi

  # Pre-flight: verify the CLI binary exists before building the command.
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' CLI not found (needed for model $MODEL). Install $tool or try a different model with -m." >&2
    return 1
  fi

  CLI_CMD_ARGV=()
  case "$tool" in
    claude)
      # CLAUDECODE= unsets nested session check (env sets it for the subprocess)
      CLI_CMD_ARGV=(env CLAUDECODE= claude -p - --model "$MODEL" --effort "$EFFORT" --output-format json --allowedTools "$TOOLS" --dangerously-skip-permissions)
      ;;
    codex)
      CLI_CMD_ARGV=(codex exec -m "$MODEL" -c "model_reasoning_effort=$EFFORT" --full-auto --json -)
      ;;
    opencode)
      # opencode takes message as positional args (or reads from stdin via process substitution).
      # --variant maps effort levels. No tool allowlist support.
      local effective_model
      effective_model="$(strip_model_prefix "$MODEL")"
      CLI_CMD_ARGV=(opencode run --model "$effective_model" --format json --variant "$EFFORT")
      ;;
  esac
}

# Format the argv array as a display string for logging/dry-run output.
format_cli_cmd() {
  local out=""
  for arg in "${CLI_CMD_ARGV[@]}"; do
    if [[ "$arg" == *" "* || "$arg" == *"="* ]]; then
      out+="\"$arg\" "
    else
      out+="$arg "
    fi
  done
  # Trim trailing space
  echo "${out% }"
}

# ─── Files-Touched Extraction ────────────────────────────────────────────────

write_files_touched_from_log() {
  local output_log="$1"
  local touched_file="$2"
  local extractor="$SCRIPT_DIR/extract-files-touched.sh"

  if [[ -x "$extractor" ]]; then
    if ! "$extractor" "$output_log" "$touched_file"; then
      echo "[run-agent] WARNING: files-touched extraction failed" >&2
      echo "# extraction failed" > "$touched_file"
    fi
  else
    : > "$touched_file"
  fi
}

# ─── Dry Run ─────────────────────────────────────────────────────────────────

do_dry_run() {
  local cli_display
  cli_display="$(format_cli_cmd)"

  echo "═══ DRY RUN ═══"
  echo ""
  echo "── Agent: ${AGENT_NAME:-ad-hoc}"
  echo "── Model: $MODEL (${ORCHESTRATE_DEFAULT_CLI:-$(route_model "$MODEL")})"
  echo "── Effort: $EFFORT"
  echo "── Tools: $TOOLS"
  echo "── Report: $DETAIL"
  if [[ ${#SKILLS[@]} -gt 0 ]]; then echo "── Skills: ${SKILLS[*]}"; else echo "── Skills: none"; fi
  if [[ ${#REF_FILES[@]} -gt 0 ]]; then echo "── Ref files: ${REF_FILES[*]}"; else echo "── Ref files: none"; fi
  echo "── Working dir: $WORK_DIR"
  echo ""
  echo "── CLI Command (argv):"
  echo "  $cli_display"
  echo ""
  echo "── Composed Prompt:"
  echo "────────────────────────────────────────"
  echo "$COMPOSED_PROMPT"
  echo ""
  echo "[report instruction would be appended with LOG_DIR path at $DETAIL detail]"
  echo "────────────────────────────────────────"
}

# ─── Execute ─────────────────────────────────────────────────────────────────

do_execute() {
  local cli_display
  cli_display="$(format_cli_cmd)"

  # Set up logging (always on)
  setup_logging
  write_log_params "$cli_display"

  # Append report instruction now that LOG_DIR is known
  COMPOSED_PROMPT+="$(build_report_instruction "$LOG_DIR/report.md" "$DETAIL")"

  # Save composed prompt
  echo "$COMPOSED_PROMPT" > "$LOG_DIR/input.md"

  echo "[run-agent] Agent: ${AGENT_NAME:-ad-hoc} | Model: $MODEL | Effort: $EFFORT | Log: $LOG_DIR" >&2

  # Execute via argv array — no eval needed
  cd "$WORK_DIR"
  set +e
  "${CLI_CMD_ARGV[@]}" <<< "$COMPOSED_PROMPT" > "$LOG_DIR/output.json" 2>&1
  EXIT_CODE=$?
  set -e

  # Derive touched files from this run's session log.
  write_files_touched_from_log "$LOG_DIR/output.json" "$LOG_DIR/files-touched.txt"

  # Output report to stdout if it was written by the subagent
  if [[ -f "$LOG_DIR/report.md" ]]; then
    cat "$LOG_DIR/report.md"
  fi

  echo "[run-agent] Done (exit=$EXIT_CODE). Log: $LOG_DIR" >&2
  exit $EXIT_CODE
}
