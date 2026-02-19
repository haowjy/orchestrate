#!/usr/bin/env bash
# Extract likely touched files from a single agent run log.
# Uses structured JSON extraction when possible, with text-pattern fallback.
#
# Usage:
#   scripts/extract-files-touched.sh <output-log> [output-file]

set -euo pipefail

OUTPUT_LOG="${1:?Usage: scripts/extract-files-touched.sh <output-log> [output-file]}"
OUTPUT_FILE="${2:-/dev/stdout}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

TMP_TEXT="$(mktemp)"
TMP_RAW_PATHS="$(mktemp)"
trap 'rm -f "$TMP_TEXT" "$TMP_RAW_PATHS"' EXIT

# Seed with raw log text (handles non-JSON and error output).
cat "$OUTPUT_LOG" > "$TMP_TEXT"

# If output is JSON or JSONL, flatten all string values for better extraction.
if command -v jq >/dev/null 2>&1; then
  jq -r '.. | strings' "$OUTPUT_LOG" 2>/dev/null >> "$TMP_TEXT" || true
  jq -Rr 'fromjson? | .. | strings' "$OUTPUT_LOG" 2>/dev/null >> "$TMP_TEXT" || true
fi

# Extract candidates from common tool/log formats.
perl -ne '
  while (/\*\*\* (?:Add|Update|Delete) File:\s*([^\r\n]+)/g) { print "$1\n"; }
  while (/\*\*\* Move to:\s*([^\r\n]+)/g) { print "$1\n"; }
  while (/"(?:path|file_path|filepath|filename|target_file|source_file|new_path|old_path|file)"\s*:\s*"((?:\\.|[^"\\])+)"/g) {
    print "$1\n";
  }
  while (/(?:^|[\s`\x22\x27])(\.gitignore|AGENTS\.md|CLAUDE\.md|README\.md)(?=$|[\s`\x22\x27,:;])/g) {
    print "$1\n";
  }
' "$TMP_TEXT" > "$TMP_RAW_PATHS"

# Normalize and filter to repo-relevant paths.
awk -v root="$REPO_ROOT/" '
{
  path = $0
  gsub(/\r/, "", path)
  sub(/^[[:space:]]+/, "", path)
  sub(/[[:space:]]+$/, "", path)

  sub(/\\n.*/, "", path)
  sub(/\\r.*/, "", path)
  gsub(/\\\//, "/", path)
  gsub(/\\\\/, "\\", path)

  gsub(/^["`]+/, "", path)
  gsub(/["`]+$/, "", path)
  sub(/:[0-9]+(:[0-9]+)?$/, "", path)
  sub(/^\.\//, "", path)

  if (index(path, root) == 1) {
    path = substr(path, length(root) + 1)
  }

  if (path == "") next
  if (path ~ /^https?:\/\//) next
  if (path ~ /^[A-Za-z]+:\/\//) next
  if (path ~ /^\/(tmp|dev|proc|sys)\//) next
  if (path ~ /[<>|*?]/) next
  if (path ~ /( \(|\)$)/) next
  if (path ~ /[[:space:]]/) next
  if (path ~ /^(true|false|null)$/) next

  # Reject absolute paths (not repo-relative) and common dependency/build dirs.
  if (path ~ /^\//) next
  if (path ~ /^(node_modules|vendor|\.git|__pycache__|dist|build|target)\//) next

  # Accept any remaining path with a directory separator or file extension.
  if (path ~ /\// || path ~ /\.[a-zA-Z0-9]+$/) { print path; next }
}
' "$TMP_RAW_PATHS" | sort -u > "$OUTPUT_FILE"
