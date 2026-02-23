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

build_continuation_fallback_prompt() {
  local original_run_id="$1"
  local original_model="$2"
  local original_log_dir="$3"
  local follow_up_prompt="$4"
  local original_input_file="$original_log_dir/input.md"
  local original_report_file="$original_log_dir/report.md"

  if [[ ! -f "$original_input_file" ]]; then
    echo "ERROR: Cannot build continuation fallback prompt: missing $original_input_file" >&2
    return 1
  fi
  if [[ ! -f "$original_report_file" ]]; then
    echo "ERROR: Cannot build continuation fallback prompt: missing $original_report_file" >&2
    return 1
  fi

  local original_input original_report
  original_input="$(cat "$original_input_file")"
  original_report="$(cat "$original_report_file")"

  cat <<EOF
# Continuation Context

Native harness continuation was unavailable. Continue from this prior run context.

- Original run ID: $original_run_id
- Original model: $original_model

## Original Prompt

\`\`\`markdown
$original_input
\`\`\`

## Original Report

\`\`\`markdown
$original_report
\`\`\`

## Follow-Up Request

$follow_up_prompt
EOF
}

resolve_continuation_run_ref() {
  local ref="$1"
  local derived="$2"

  case "$ref" in
    @latest)
      echo "$derived" | jq -r '.[0].run_id // empty'
      ;;
    @last-failed)
      echo "$derived" | jq -r '[.[] | select(.effective_status == "failed")] | .[0].run_id // empty'
      ;;
    @last-completed)
      echo "$derived" | jq -r '[.[] | select(.effective_status == "completed")] | .[0].run_id // empty'
      ;;
    *)
      local exact
      exact="$(echo "$derived" | jq -r --arg ref "$ref" '[.[] | select(.run_id == $ref)] | .[0].run_id // empty')"
      if [[ -n "$exact" ]]; then
        echo "$exact"
        return 0
      fi

      if [[ ${#ref} -lt 8 ]]; then
        echo "ERROR: Continuation run reference prefix must be at least 8 characters (got ${#ref})." >&2
        return 1
      fi

      local matches count
      matches="$(echo "$derived" | jq -r --arg prefix "$ref" '[.[] | select(.run_id | startswith($prefix))] | map(.run_id)')"
      count="$(echo "$matches" | jq 'length')"

      if [[ "$count" -eq 0 ]]; then
        echo "ERROR: No run matching continuation ref '$ref'." >&2
        return 1
      fi
      if [[ "$count" -gt 1 ]]; then
        echo "ERROR: Ambiguous continuation ref '$ref'. Use a longer prefix." >&2
        return 1
      fi

      echo "$matches" | jq -r '.[0]'
      ;;
  esac
}

prepare_continuation() {
  [[ -z "${CONTINUE_RUN_REF:-}" ]] && return 0

  local index_file="$ORCHESTRATE_ROOT/index/runs.jsonl"
  if [[ ! -f "$index_file" ]]; then
    echo "ERROR: Cannot continue run '$CONTINUE_RUN_REF': index file not found at $index_file" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for --continue-run." >&2
    return 2
  fi

  local derived
  derived="$(
    jq -s '
      group_by(.run_id)
      | map(
          . as $rows
          | ($rows | map(select(.status == "running")) | first) as $start
          | ($rows | map(select(.status == "completed" or .status == "failed")) | first) as $fin
          | ($start // $rows[0])
          + (if $fin then $fin else {} end)
          + { effective_status: (if $fin then $fin.status else "running" end) }
        )
      | sort_by(.created_at_utc // "") | reverse
    ' "$index_file" 2>/dev/null
  )"

  local continue_run_id
  continue_run_id="$(resolve_continuation_run_ref "$CONTINUE_RUN_REF" "$derived")" || return 1
  if [[ -z "$continue_run_id" ]]; then
    echo "ERROR: Could not resolve continuation ref '$CONTINUE_RUN_REF'." >&2
    return 1
  fi

  local run_row
  run_row="$(echo "$derived" | jq --arg id "$continue_run_id" '.[] | select(.run_id == $id)')"
  if [[ -z "$run_row" ]]; then
    echo "ERROR: Could not find continuation run '$continue_run_id' in index." >&2
    return 1
  fi

  local effective_status source_harness source_model harness_session_id source_log_dir
  effective_status="$(echo "$run_row" | jq -r '.effective_status // "running"')"
  if [[ "$effective_status" == "running" ]]; then
    echo "ERROR: Cannot continue run '$continue_run_id': run has no finalize row (crashed or still in progress)." >&2
    return 1
  fi
  source_harness="$(echo "$run_row" | jq -r '.harness // empty')"
  source_model="$(echo "$run_row" | jq -r '.model // empty')"
  harness_session_id="$(echo "$run_row" | jq -r '.harness_session_id // empty')"
  source_log_dir="$(echo "$run_row" | jq -r '.log_dir // empty')"

  if [[ -z "$source_harness" || -z "$source_model" || -z "$source_log_dir" ]]; then
    echo "ERROR: Cannot continue run '$continue_run_id': missing required run metadata." >&2
    return 1
  fi

  # Continuations default to original model unless user explicitly overrides.
  if [[ "${MODEL_FROM_CLI:-false}" != true ]]; then
    MODEL="$source_model"
  fi

  local target_harness
  target_harness="$(route_model "$MODEL" 2>/dev/null || echo "")"
  if [[ -z "$target_harness" ]]; then
    echo "ERROR: Cannot continue run '$continue_run_id': model '$MODEL' does not map to a supported harness." >&2
    return 1
  fi
  if [[ "$target_harness" != "$source_harness" ]]; then
    echo "ERROR: Cannot continue run '$continue_run_id': model '$MODEL' maps to '$target_harness', expected '$source_harness'." >&2
    return 1
  fi

  CONTINUES_RUN_ID="$continue_run_id"
  CONTINUATION_FALLBACK_REASON=""

  if [[ -z "$harness_session_id" ]]; then
    CONTINUATION_MODE="fallback-prompt"
    CONTINUATION_FALLBACK_REASON="missing_session_id"
    PROMPT="$(build_continuation_fallback_prompt "$continue_run_id" "$source_model" "$source_log_dir" "$PROMPT")" || return 1
    return 0
  fi

  CONTINUE_HARNESS_SESSION_ID="$harness_session_id"

  case "$source_harness" in
    codex)
      if [[ "${CONTINUATION_FORK_EXPLICIT:-false}" == true && "${CONTINUATION_FORK:-true}" == true ]]; then
        echo "ERROR: Codex continuation does not support forking. Use --in-place or omit --fork." >&2
        return 1
      fi
      CONTINUATION_MODE="in-place"
      ;;
    claude|opencode)
      if [[ "${CONTINUATION_FORK:-true}" == true ]]; then
        CONTINUATION_MODE="fork"
      else
        CONTINUATION_MODE="in-place"
      fi
      ;;
    *)
      CONTINUATION_MODE="fallback-prompt"
      CONTINUATION_FALLBACK_REASON="unsupported_harness"
      PROMPT="$(build_continuation_fallback_prompt "$continue_run_id" "$source_model" "$source_log_dir" "$PROMPT")" || return 1
      ;;
  esac
}

build_cli_command() {
  local tool
  local normalized_tools
  local native_continuation=false
  CLI_PROMPT_MODE="stdin"

  tool="$(route_model "$MODEL" 2>/dev/null || echo "")"

  if [[ -z "$tool" ]]; then
    if [[ -n "${CONTINUE_RUN_REF:-}" ]]; then
      echo "ERROR: Unknown model family '$MODEL' for continuation run." >&2
      return 2
    fi
    echo "[run-agent] WARNING: Unknown model family '$MODEL'; falling back to $FALLBACK_MODEL ($FALLBACK_CLI)" >&2
    tool="$FALLBACK_CLI"
    MODEL="$FALLBACK_MODEL"
  elif ! command -v "$tool" >/dev/null 2>&1; then
    if [[ -n "${CONTINUE_RUN_REF:-}" ]]; then
      echo "ERROR: '$tool' CLI not found for continuation model '$MODEL'." >&2
      return 2
    fi
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
  if [[ -n "${CONTINUE_RUN_REF:-}" ]] \
    && [[ -n "${CONTINUE_HARNESS_SESSION_ID:-}" ]] \
    && [[ "${CONTINUATION_MODE:-}" != "fallback-prompt" ]]; then
    native_continuation=true
  fi

  case "$tool" in
    claude)
      CLI_CMD_ARGV=(env CLAUDECODE= claude -p - --model "$MODEL" --effort "$EFFORT" --verbose --output-format stream-json --allowedTools "$normalized_tools" --dangerously-skip-permissions)
      if [[ "$native_continuation" == true ]]; then
        CLI_CMD_ARGV+=(--resume "$CONTINUE_HARNESS_SESSION_ID")
        if [[ "${CONTINUATION_MODE:-}" == "fork" ]]; then
          CLI_CMD_ARGV+=(--fork-session)
        fi
      fi
      ;;
    codex)
      if [[ "$native_continuation" == true ]]; then
        CLI_CMD_ARGV=(codex exec resume "$CONTINUE_HARNESS_SESSION_ID" -m "$MODEL" -c "model_reasoning_effort=$EFFORT" --dangerously-bypass-approvals-and-sandbox --json -)
      else
        CLI_CMD_ARGV=(codex exec -m "$MODEL" -c "model_reasoning_effort=$EFFORT" --dangerously-bypass-approvals-and-sandbox --json -)
      fi
      ;;
    opencode)
      local effective_model
      effective_model="$(strip_model_prefix "$MODEL")"
      CLI_CMD_ARGV=(opencode run --model "$effective_model" --format json --print-logs --variant "$EFFORT")
      CLI_PROMPT_MODE="arg"
      if [[ "$native_continuation" == true ]]; then
        CLI_CMD_ARGV+=(--session "$CONTINUE_HARNESS_SESSION_ID")
        if [[ "${CONTINUATION_MODE:-}" == "fork" ]]; then
          CLI_CMD_ARGV+=(--fork)
        fi
      fi
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

  # Set up logging and write start index row for crash visibility
  setup_logging
  output_log="$LOG_DIR/output.jsonl"
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
  if [[ "${CLI_PROMPT_MODE:-stdin}" == "arg" ]]; then
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
