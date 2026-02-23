#!/usr/bin/env bash
# lib/exec.sh — CLI command building (argv array), execution, structured exit codes.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Structured Exit Codes ────────────────────────────────────────────────────
# 0 = success, 1 = agent error, 2 = infra error, 3 = timeout, 130 = SIGINT, 143 = SIGTERM

# ─── Build CLI Command (argv array) ──────────────────────────────────────────

normalize_claude_tool_token() {
  local token="$1"
  local base="$token"
  local suffix=""

  if [[ "$token" == *"("* ]]; then
    base="${token%%(*}"
    suffix="${token#"$base"}"
  fi

  case "$(echo "$base" | tr '[:upper:]' '[:lower:]')" in
    read) base="Read" ;;
    write) base="Write" ;;
    edit) base="Edit" ;;
    bash) base="Bash" ;;
    glob) base="Glob" ;;
    grep) base="Grep" ;;
    websearch) base="WebSearch" ;;
    webfetch) base="WebFetch" ;;
    *) ;;
  esac

  echo "${base}${suffix}"
}

normalize_tools_for_harness() {
  local tool="$1" tools="$2"
  case "$tool" in
    claude)
      local normalized=()
      local raw token
      IFS=',' read -ra raw <<< "$tools"
      for token in "${raw[@]}"; do
        token="$(echo "$token" | xargs)"
        [[ -z "$token" ]] && continue
        normalized+=("$(normalize_claude_tool_token "$token")")
      done
      if [[ ${#normalized[@]} -eq 0 ]]; then
        echo "$tools"
      else
        local joined
        joined="$(IFS=','; echo "${normalized[*]}")"
        echo "$joined"
      fi
      ;;
    codex)    echo "" ;;
    opencode) echo "" ;;
  esac
}

build_cli_command() {
  local tool
  local normalized_tools

  tool="$(route_model "$MODEL" 2>/dev/null || echo "")"

  if [[ -z "$tool" ]]; then
    echo "[run-agent] WARNING: Unknown model family '$MODEL'; falling back to $FALLBACK_MODEL ($FALLBACK_CLI)" >&2
    tool="$FALLBACK_CLI"
    MODEL="$FALLBACK_MODEL"
  elif ! command -v "$tool" >/dev/null 2>&1; then
    echo "[run-agent] WARNING: '$tool' CLI not found for model '$MODEL'; falling back to $FALLBACK_MODEL ($FALLBACK_CLI)" >&2
    tool="$FALLBACK_CLI"
    MODEL="$FALLBACK_MODEL"
  fi

  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' CLI not found. Install it or try a different model with -m." >&2
    return 2
  fi

  CLI_CMD_ARGV=()
  CLI_HARNESS="$tool"
  normalized_tools="$(normalize_tools_for_harness "$tool" "$TOOLS")"
  case "$tool" in
    claude)
      CLI_CMD_ARGV=(env CLAUDECODE= claude -p - --model "$MODEL" --effort "$EFFORT" --verbose --output-format stream-json --allowedTools "$normalized_tools" --dangerously-skip-permissions)
      ;;
    codex)
      CLI_CMD_ARGV=(codex exec -m "$MODEL" -c "model_reasoning_effort=$EFFORT" --dangerously-bypass-approvals-and-sandbox --json -)
      ;;
    opencode)
      local effective_model
      effective_model="$(strip_model_prefix "$MODEL")"
      CLI_CMD_ARGV=(opencode run --model "$effective_model" --format json --print-logs --variant "$EFFORT")
      ;;
    *)
      echo "ERROR: Unsupported CLI harness: $tool" >&2
      return 2
      ;;
  esac
}

format_cli_cmd() {
  local out=""
  for arg in "${CLI_CMD_ARGV[@]}"; do
    if [[ "$arg" == *" "* || "$arg" == *"="* ]]; then
      out+="\"$arg\" "
    else
      out+="$arg "
    fi
  done
  echo "${out% }"
}

# ─── Files-Touched Extraction ────────────────────────────────────────────────

write_files_touched_from_log() {
  local output_log="$1"
  local log_dir="$2"
  local extractor="$SCRIPT_DIR/extract-files-touched.sh"

  if [[ -x "$extractor" ]]; then
    # Produce NUL-delimited canonical format
    if ! "$extractor" "$output_log" "$log_dir/files-touched.nul" --nul 2>/dev/null; then
      # Fallback: try without --nul for backward compat during transition
      "$extractor" "$output_log" "$log_dir/files-touched.txt" 2>/dev/null || true
      return
    fi
    # Derive newline-delimited from NUL-delimited
    if [[ -f "$log_dir/files-touched.nul" ]]; then
      tr '\0' '\n' < "$log_dir/files-touched.nul" > "$log_dir/files-touched.txt"
    fi
  else
    : > "$log_dir/files-touched.txt"
    : > "$log_dir/files-touched.nul"
  fi
}

# ─── Dry Run ─────────────────────────────────────────────────────────────────

do_dry_run() {
  local cli_display
  cli_display="$(format_cli_cmd)"

  echo "═══ DRY RUN ═══"
  echo ""
  echo "── Model: $MODEL ($(route_model "$MODEL" 2>/dev/null || echo "fallback"))"
  echo "── Effort: $EFFORT"
  echo "── Tools: $TOOLS"
  echo "── Report: $DETAIL"
  if [[ ${#SKILLS[@]} -gt 0 ]]; then echo "── Skills: ${SKILLS[*]}"; else echo "── Skills: none"; fi
  if [[ -n "${SESSION_ID:-}" ]]; then echo "── Session: $SESSION_ID"; fi
  if [[ "$HAS_LABELS" == true ]]; then
    local k
    echo "── Labels:"
    for k in "${!LABELS[@]}"; do
      echo "   - $k=${LABELS[$k]}"
    done
  else
    echo "── Labels: none"
  fi
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

# ─── Signal Handling ──────────────────────────────────────────────────────────

_run_interrupted=false
_run_start_epoch=0

_handle_signal() {
  local sig_code="$1"
  _run_interrupted=true

  # Write finalize row for observability before exiting
  if [[ -n "${RUN_ID:-}" ]] && [[ -n "${LOG_DIR:-}" ]]; then
    local duration=0
    if [[ "$_run_start_epoch" -gt 0 ]]; then
      local now_epoch
      now_epoch="$(date +%s)"
      duration=$((now_epoch - _run_start_epoch))
    fi
    append_finalize_row "$sig_code" "$duration" 2>/dev/null || true
  fi

  exit "$sig_code"
}

# ─── Execute ─────────────────────────────────────────────────────────────────

do_execute() {
  local cli_display output_log
  cli_display="$(format_cli_cmd)"
  output_log="$LOG_DIR/output.jsonl"

  # Set up logging and write start index row for crash visibility
  setup_logging
  write_log_params "$cli_display"

  # Capture git HEAD before execution (best-effort)
  HEAD_BEFORE=""
  if command -v git >/dev/null 2>&1; then
    HEAD_BEFORE="$(git -C "$WORK_DIR" rev-parse HEAD 2>/dev/null || echo "")"
  fi

  # Write start row immediately (crash visibility)
  append_start_row

  # Install signal traps
  trap '_handle_signal 130' INT
  trap '_handle_signal 143' TERM

  # Record start time for duration tracking
  _run_start_epoch="$(date +%s)"

  # Append report instruction now that LOG_DIR is known
  COMPOSED_PROMPT+="$(build_report_instruction "$LOG_DIR/report.md" "$DETAIL")"

  # Save composed prompt
  echo "$COMPOSED_PROMPT" > "$LOG_DIR/input.md"

  echo "[run-agent] Model: $MODEL | Effort: $EFFORT | Log: $LOG_DIR" >&2

  # Execute via argv array — no eval needed.
  cd "$WORK_DIR"
  local harness_exit=0
  set +e
  if [[ "$CLI_HARNESS" == "opencode" ]]; then
    "${CLI_CMD_ARGV[@]}" "$COMPOSED_PROMPT" \
      > "$output_log" \
      2> >(tee "$LOG_DIR/stderr.log" >&2)
  else
    "${CLI_CMD_ARGV[@]}" <<< "$COMPOSED_PROMPT" \
      > "$output_log" \
      2> >(tee "$LOG_DIR/stderr.log" >&2)
  fi
  harness_exit=$?
  set -e

  # Map harness exit to structured exit code
  local exit_code="$harness_exit"
  # Exit codes 0, 1, 2, 3 pass through as-is (already structured).
  # 130/143 are handled by signal traps above.
  # Other non-zero codes map to 1 (agent error).
  if [[ "$exit_code" -gt 3 ]] && [[ "$exit_code" -ne 130 ]] && [[ "$exit_code" -ne 143 ]]; then
    exit_code=1
  fi

  # Derive files touched
  write_files_touched_from_log "$output_log" "$LOG_DIR"

  # Report fallback: if no report.md, try to extract last assistant message
  if [[ ! -f "$LOG_DIR/report.md" ]] || [[ ! -s "$LOG_DIR/report.md" ]]; then
    local fallback_extractor="$SCRIPT_DIR/extract-report-fallback.sh"
    if [[ -x "$fallback_extractor" ]]; then
      "$fallback_extractor" "$CLI_HARNESS" "$output_log" "$LOG_DIR/stderr.log" "$exit_code" \
        > "$LOG_DIR/report.md" 2>/dev/null || true
    fi
  fi

  # Compute duration
  local end_epoch duration_seconds
  end_epoch="$(date +%s)"
  duration_seconds=$((_run_start_epoch > 0 ? end_epoch - _run_start_epoch : 0))

  # Write finalize row
  EXIT_CODE="$exit_code"
  append_finalize_row "$exit_code" "$duration_seconds"

  # Print report to stdout for the orchestrator
  if [[ -f "$LOG_DIR/report.md" ]] && [[ -s "$LOG_DIR/report.md" ]]; then
    cat "$LOG_DIR/report.md"
  else
    echo "---" >&2
    echo "[run-agent] WARNING: Agent did not produce a report at $LOG_DIR/report.md" >&2
    echo "[run-agent] Exit code: $exit_code" >&2
    echo "[run-agent] Output log: $output_log" >&2
    if [[ -f "$output_log" ]] && [[ -s "$output_log" ]]; then
      echo "[run-agent] Last 40 lines of output:" >&2
      tail -n 40 "$output_log" >&2
    else
      echo "[run-agent] Output log is empty — the CLI may have failed to start." >&2
    fi
    echo "---" >&2
  fi

  echo "[run-agent] Done (exit=$exit_code, duration=${duration_seconds}s). Log: $LOG_DIR" >&2
  exit "$exit_code"
}
