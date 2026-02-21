#!/usr/bin/env bash
# log-inspect.sh — jq-based conversation log inspector.
#
# Usage:
#   scripts/log-inspect.sh <output.json> [summary|tools|errors|files]
#
# Modes:
#   summary  (default) — cost, tokens, turns, duration, models
#   tools    — tool call names + counts
#   errors   — is_error flags, permission denials
#   files    — delegates to extract-files-touched.sh

set -euo pipefail

# Resolve through symlinks
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
  _dir="$(cd "$(dirname "$_source")" && pwd -P)"
  _source="$(readlink "$_source")"
  [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd "$(dirname "$_source")" && pwd -P)"

# ─── Args ────────────────────────────────────────────────────────────────────

LOG_FILE="${1:-}"
MODE="${2:-summary}"

if [[ -z "$LOG_FILE" ]]; then
  cat <<'EOF'
Usage: scripts/log-inspect.sh <output.json> [summary|tools|errors|files]

Modes:
  summary  (default)  Cost, tokens, turns, duration, models
  tools               Tool call names + counts from result text
  errors              is_error flags, permission denials
  files               Delegates to extract-files-touched.sh
EOF
  exit 1
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "ERROR: File not found: $LOG_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed." >&2
  echo "  Install: sudo apt-get install jq  (or brew install jq on macOS)" >&2
  exit 1
fi

# ─── Format Detection ───────────────────────────────────────────────────────
# Single JSON (Claude) vs JSONL (Codex)

detect_format() {
  local first_char
  first_char="$(head -c 1 "$LOG_FILE")"

  # If it starts with { and the entire file is one JSON object → single JSON
  if [[ "$first_char" == "{" ]] && jq empty "$LOG_FILE" 2>/dev/null; then
    echo "json"
  else
    echo "jsonl"
  fi
}

FORMAT="$(detect_format)"

# ─── Summary Mode ───────────────────────────────────────────────────────────

do_summary() {
  echo "═══ Log Summary ═══"
  echo "File: $LOG_FILE"
  echo "Format: $FORMAT"
  echo ""

  if [[ "$FORMAT" == "json" ]]; then
    # Claude single-JSON format
    # Claude output: cost is total_cost_usd, models are in modelUsage (object with model keys)
    jq -r '
      "Models:     " + (if .modelUsage then (.modelUsage | keys | join(", ")) elif .model then .model else "unknown" end),
      "Session ID: " + (.session_id // "unknown"),
      "Cost (USD): $" + ((.total_cost_usd // .cost_usd // 0) | tostring),
      "Duration:   " + (if .duration_ms then ((.duration_ms / 1000 * 100 | round / 100) | tostring) + "s" else "unknown" end),
      "Turns:      " + (if .num_turns then (.num_turns | tostring) else "unknown" end),
      "Result:     " + (.subtype // .stop_reason // "unknown"),
      "",
      "Tokens:",
      "  Input:  " + (if .usage.input_tokens then (.usage.input_tokens | tostring) else "unknown" end),
      "  Output: " + (if .usage.output_tokens then (.usage.output_tokens | tostring) else "unknown" end),
      "  Cache read:  " + (if .usage.cache_read_input_tokens then (.usage.cache_read_input_tokens | tostring) else "n/a" end),
      "  Cache write: " + (if .usage.cache_creation_input_tokens then (.usage.cache_creation_input_tokens | tostring) else "n/a" end)
    ' "$LOG_FILE" 2>/dev/null || echo "(Could not extract summary fields)"
  else
    # JSONL format — aggregate across lines
    jq -sr '
      map(select(.model)) | first | .model // "unknown"
    ' "$LOG_FILE" 2>/dev/null | xargs -I{} echo "Model: {}"

    local line_count
    line_count="$(wc -l < "$LOG_FILE")"
    echo "Lines: $line_count"
    echo "(JSONL format — limited summary available)"
  fi
}

# ─── Tools Mode ──────────────────────────────────────────────────────────────

do_tools() {
  echo "═══ Tool Calls ═══"

  if [[ "$FORMAT" == "json" ]]; then
    # Claude result can be a string or an array. Try array first, then grep text.
    local tool_output
    tool_output="$(jq -r '
      if (.result | type) == "array" then
        [.result[] | select(.type == "tool_use") | .name] |
        group_by(.) | map({name: .[0], count: length}) |
        sort_by(-.count)[] |
        "\(.count)\t\(.name)"
      else
        empty
      end
    ' "$LOG_FILE" 2>/dev/null || true)"

    if [[ -n "$tool_output" ]]; then
      echo "$tool_output"
    else
      # Fall back: extract tool names from result text (e.g., "Tool: Read", "Tool: Edit")
      jq -r '.result // ""' "$LOG_FILE" 2>/dev/null |
        grep -oE '\b(Read|Write|Edit|Bash|Glob|Grep|WebSearch|WebFetch|Task|NotebookEdit)\b' |
        sort | uniq -c | sort -rn | awk '{printf "%s\t%s\n", $1, $2}' ||
        echo "(No tool calls found in result text)"
    fi
  else
    # JSONL: look for tool_use entries
    jq -r 'select(.type == "tool_use") | .name // empty' "$LOG_FILE" 2>/dev/null |
      sort | uniq -c | sort -rn | awk '{printf "%s\t%s\n", $1, $2}' ||
      echo "(No tool calls found)"
  fi
}

# ─── Errors Mode ─────────────────────────────────────────────────────────────

do_errors() {
  echo "═══ Errors ═══"

  if [[ "$FORMAT" == "json" ]]; then
    # Check top-level is_error
    local is_error
    is_error="$(jq -r '.is_error // false' "$LOG_FILE" 2>/dev/null)"
    echo "Top-level is_error: $is_error"
    echo ""

    # Permission denials (structured field in Claude output)
    echo "Permission denials:"
    jq -r '
      if .permission_denials then
        (.permission_denials | tostring)
      else
        "  0"
      end
    ' "$LOG_FILE" 2>/dev/null || echo "  (could not extract)"

    # Check result for error patterns
    echo ""
    echo "Error patterns in result:"
    local err_count
    err_count="$(jq -r '.result // ""' "$LOG_FILE" 2>/dev/null | grep -ciE 'error|failed|exception' || echo "0")"
    echo "  Matches: $err_count"
  else
    echo "(JSONL format — scanning for error patterns)"
    jq -r 'select(.is_error == true) | .content // .message // "error entry"' "$LOG_FILE" 2>/dev/null |
      head -20 || echo "  (none found)"
  fi
}

# ─── Files Mode ──────────────────────────────────────────────────────────────

do_files() {
  local extractor="$SCRIPT_DIR/extract-files-touched.sh"
  if [[ -x "$extractor" ]]; then
    "$extractor" "$LOG_FILE"
  else
    echo "ERROR: extract-files-touched.sh not found at $extractor" >&2
    exit 1
  fi
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$MODE" in
  summary) do_summary ;;
  tools)   do_tools ;;
  errors)  do_errors ;;
  files)   do_files ;;
  *)
    echo "ERROR: Unknown mode: $MODE" >&2
    echo "Valid modes: summary, tools, errors, files" >&2
    exit 1
    ;;
esac
