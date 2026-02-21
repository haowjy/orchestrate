#!/usr/bin/env bash
# lib/exec.sh — CLI command building (argv array), execution, files-touched extraction.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Build CLI Command (argv array) ──────────────────────────────────────────
# Populates global CLI_CMD_ARGV array instead of building a string.
# This avoids eval and shell-injection risks.

# Normalize tool names for the target CLI harness.
# Agent definitions may use inconsistent casing; Claude expects PascalCase names.
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
    codex)    echo "" ;;                                    # codex ignores tool allowlists
    opencode) echo "" ;;                                    # opencode run has no allowlist flag
  esac
}

build_cli_command() {
  local tool
  local normalized_tools

  # Route model → CLI automatically: claude-* → claude, gpt-* → codex, else → opencode.
  # ORCHESTRATE_DEFAULT_CLI can override this if set (e.g., force all to claude).
  if [[ -n "${ORCHESTRATE_DEFAULT_CLI:-}" ]]; then
    tool="$ORCHESTRATE_DEFAULT_CLI"
  else
    tool="$(route_model "$MODEL" 2>/dev/null || echo "")"
  fi

  # If route_model failed (unknown family) or CLI binary not installed, fall back:
  # try the routed CLI first, then fall back to claude + FALLBACK_MODEL.
  if [[ -z "$tool" ]]; then
    echo "[run-agent] WARNING: Unknown model family '$MODEL'; falling back to $FALLBACK_MODEL ($FALLBACK_CLI)" >&2
    tool="$FALLBACK_CLI"
    MODEL="$FALLBACK_MODEL"
  elif ! command -v "$tool" >/dev/null 2>&1; then
    echo "[run-agent] WARNING: '$tool' CLI not found for model '$MODEL'; falling back to $FALLBACK_MODEL ($FALLBACK_CLI)" >&2
    tool="$FALLBACK_CLI"
    MODEL="$FALLBACK_MODEL"
  fi

  # Final check: the fallback CLI itself must exist.
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' CLI not found. Install it or try a different model with -m." >&2
    return 1
  fi

  CLI_CMD_ARGV=()
  CLI_HARNESS="$tool"
  normalized_tools="$(normalize_tools_for_harness "$tool" "$TOOLS")"
  case "$tool" in
    claude)
      # CLAUDECODE= unsets nested session check (env sets it for the subprocess)
      CLI_CMD_ARGV=(env CLAUDECODE= claude -p - --model "$MODEL" --effort "$EFFORT" --verbose --output-format stream-json --allowedTools "$normalized_tools" --dangerously-skip-permissions)
      ;;
    codex)
      CLI_CMD_ARGV=(codex exec -m "$MODEL" -c "model_reasoning_effort=$EFFORT" --dangerously-bypass-approvals-and-sandbox --json -)
      ;;
    opencode)
      # opencode --format json emits structured JSON events on stdout.
      # --print-logs mirrors progress/diagnostics to stderr for real-time visibility.
      # Prompt text is passed as a positional arg at execution time.
      # --variant maps effort levels. No tool allowlist support.
      local effective_model
      effective_model="$(strip_model_prefix "$MODEL")"
      CLI_CMD_ARGV=(opencode run --model "$effective_model" --format json --print-logs --variant "$EFFORT")
      ;;
    *)
      echo "ERROR: Unsupported CLI harness: $tool" >&2
      return 1
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
  echo "── Model: $MODEL ($(route_model "$MODEL" 2>/dev/null || echo "fallback"))"
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

auto_create_scope_dirs() {
  # Auto-create scratch and log directories under the scope root so that
  # agents and orchestrators don't have to mkdir manually before launching.
  local scope_root
  scope_root="$(infer_scope_root)"

  # Guard: never create dirs at filesystem root.
  if [[ -z "$scope_root" || "$scope_root" == "/" ]]; then
    return
  fi

  mkdir -p "$scope_root/scratch/code/smoke" 2>/dev/null || true
  mkdir -p "$scope_root/logs/agent-runs" 2>/dev/null || true
}

do_execute() {
  local cli_display
  cli_display="$(format_cli_cmd)"

  # Set up logging (always on)
  setup_logging
  write_log_params "$cli_display"

  # Auto-create scope directories (scratch, logs) so agents don't fail on missing dirs.
  auto_create_scope_dirs

  # Append report instruction now that LOG_DIR is known
  COMPOSED_PROMPT+="$(build_report_instruction "$LOG_DIR/report.md" "$DETAIL")"

  # Save composed prompt
  echo "$COMPOSED_PROMPT" > "$LOG_DIR/input.md"

  echo "[run-agent] Agent: ${AGENT_NAME:-ad-hoc} | Model: $MODEL | Effort: $EFFORT | Log: $LOG_DIR" >&2

  # Execute via argv array — no eval needed.
  # stdout → output.json (structured JSON/JSONL), stderr → tee to terminal + stderr.log.
  # Claude/Codex read prompt from stdin; OpenCode takes prompt as positional arg.
  cd "$WORK_DIR"
  set +e
  if [[ "$CLI_HARNESS" == "opencode" ]]; then
    "${CLI_CMD_ARGV[@]}" "$COMPOSED_PROMPT" \
      > "$LOG_DIR/output.json" \
      2> >(tee "$LOG_DIR/stderr.log" >&2)
  else
    "${CLI_CMD_ARGV[@]}" <<< "$COMPOSED_PROMPT" \
      > "$LOG_DIR/output.json" \
      2> >(tee "$LOG_DIR/stderr.log" >&2)
  fi
  EXIT_CODE=$?
  set -e

  # Derive touched files from this run's session log.
  write_files_touched_from_log "$LOG_DIR/output.json" "$LOG_DIR/files-touched.txt"

  # Append to orchestrate session index
  update_session_index

  # ── Report output ──────────────────────────────────────────────────────────
  # Always print report to stdout so the orchestrator can read it.
  # If the subagent wrote report.md, cat it. Otherwise, emit a diagnostic
  # summary so the caller never gets silent zero output.
  if [[ -f "$LOG_DIR/report.md" ]] && [[ -s "$LOG_DIR/report.md" ]]; then
    cat "$LOG_DIR/report.md"
  else
    echo "---" >&2
    echo "[run-agent] WARNING: Agent did not produce a report at $LOG_DIR/report.md" >&2
    echo "[run-agent] Exit code: $EXIT_CODE" >&2
    echo "[run-agent] Output log: $LOG_DIR/output.json" >&2
    # Print the last 40 lines of output.json to stderr for diagnostics.
    if [[ -f "$LOG_DIR/output.json" ]] && [[ -s "$LOG_DIR/output.json" ]]; then
      echo "[run-agent] Last 40 lines of output:" >&2
      tail -n 40 "$LOG_DIR/output.json" >&2
    else
      echo "[run-agent] Output log is empty — the CLI may have failed to start." >&2
    fi
    echo "---" >&2
  fi

  echo "[run-agent] Done (exit=$EXIT_CODE). Log: $LOG_DIR" >&2
  exit $EXIT_CODE
}
