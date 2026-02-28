#!/usr/bin/env bash
# session-start.sh — SessionStart hook (packaged with orchestrate plugin)
#
# Reloads sticky skills from the previous session after context loss.
#
# Triggers:
# - compact: context compressed, skills may be lost. Scans current transcript.
# - clear: only if the previous session ended with ExitPlanMode (plan acceptance).
#   Reads the previous transcript path from .orchestrate/session/prev-transcript
#   (written by session-end.sh), checks last ~20 lines for ExitPlanMode.
#   Manual /clear (no ExitPlanMode) is treated as intentional reset — no reload.
#
# Sticky set is reconstructed by replaying transcript events in order:
# - activation signals add skills
# - explicit unpin signals remove skills
#
# Optional allowlist file (repo-local, not synced by sync.sh):
# - .orchestrate/config/sticky-skills.json
# - format: { "allowlist": ["run-agent", "mermaid", "orchestrate"] }
# - case-insensitive; values may include leading "/"
#
# Input: JSON on stdin with { transcript_path, source, cwd, ... }
# Output: JSON with additionalContext on stdout (exit 0)

set -euo pipefail

# --- Source shared helpers ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# ============================================================================
# Parse hook input
# ============================================================================
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only fire on compact or clear. startup: no prior session. resume: skills already in context.
case "$SOURCE" in
  compact|clear) ;;
  *) exit 0 ;;
esac

# Resolve project root from CWD
PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")" || exit 0

# Optional sticky-skill allowlist (repo-local customization).
ALLOWLIST_FILE="$PROJECT_ROOT/.orchestrate/config/sticky-skills.json"
declare -A ALLOWED_SKILLS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r skill || [[ -n "$skill" ]]; do
      skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]' | xargs)"
      skill="${skill#/}"  # Allow "/skill" syntax in file.
      [[ -n "$skill" ]] || continue
      ALLOWED_SKILLS["$skill"]=1
    done < <(jq -r '.allowlist // [] | .[] | select(type=="string")' "$ALLOWLIST_FILE" 2>/dev/null || true)
  fi
fi

# On clear, use the previous transcript saved by session-end.sh.
# Only reload if the previous session ended with ExitPlanMode (plan acceptance).
# Manual /clear has no ExitPlanMode — treated as intentional reset.
BREADCRUMB="$PROJECT_ROOT/.orchestrate/session/prev-transcript"
if [[ "$SOURCE" == "clear" ]]; then
  if [[ -f "$BREADCRUMB" ]]; then
    PREV_TRANSCRIPT="$(cat "$BREADCRUMB")"
    rm -f "$BREADCRUMB"
    # Check last ~20 lines for ExitPlanMode — plan acceptance signal
    if [[ -f "$PREV_TRANSCRIPT" ]] && tail -20 "$PREV_TRANSCRIPT" | grep -qE '"name"\s*:\s*"ExitPlanMode"' 2>/dev/null; then
      TRANSCRIPT_PATH="$PREV_TRANSCRIPT"
    else
      exit 0  # Manual /clear — no reload
    fi
  else
    exit 0  # No breadcrumb — no reload
  fi
fi

# Need a transcript to scan
if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# ============================================================================
# Extract and replay sticky skill events from transcript
# ============================================================================
extract_skill_events() {
  local transcript_path="$1"
  local line line_no=0 seq=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    # Activation signal #1: "Launching skill: <name>"
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      local skill
      skill="$(echo "$match" | sed -E 's/^Launching skill:[[:space:]]*//')"
      skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]')"
      seq=$((seq + 1))
      printf '%d\t%d\t%s\t%s\n' "$line_no" "$seq" "add" "$skill"
    done < <(printf '%s\n' "$line" | grep -oE 'Launching skill:[[:space:]]*[A-Za-z0-9._-]+' || true)

    # Activation signal #2: "Base directory for this skill: .../skills/<name>"
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      local skill
      skill="$(echo "$match" | sed -E 's#.*skills/([A-Za-z0-9._-]+).*#\1#')"
      skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]')"
      seq=$((seq + 1))
      printf '%d\t%d\t%s\t%s\n' "$line_no" "$seq" "add" "$skill"
    done < <(printf '%s\n' "$line" | grep -oE 'Base directory for this skill:.*skills/[A-Za-z0-9._-]+' || true)

    # Activation signal #3: Skill tool invocation payload on one line
    if printf '%s\n' "$line" | grep -qE '"name"[[:space:]]*:[[:space:]]*"Skill"'; then
      while IFS= read -r match; do
        [[ -n "$match" ]] || continue
        local skill
        skill="$(echo "$match" | sed -E 's/^"skill"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]+)"/\1/')"
        skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]')"
        seq=$((seq + 1))
        printf '%d\t%d\t%s\t%s\n' "$line_no" "$seq" "add" "$skill"
      done < <(printf '%s\n' "$line" | grep -oE '"skill"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]+"' || true)
    fi

    # Unpin signal #1: "/unpin <name>"
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      local skill
      skill="$(echo "$match" | sed -E 's#^/unpin[[:space:]]+([A-Za-z0-9._-]+)$#\1#')"
      skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]')"
      seq=$((seq + 1))
      printf '%d\t%d\t%s\t%s\n' "$line_no" "$seq" "remove" "$skill"
    done < <(printf '%s\n' "$line" | grep -oE '/unpin[[:space:]]+[A-Za-z0-9._-]+' || true)

    # Unpin signal #2: "unpin skill: <name>"
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      local skill
      skill="$(echo "$match" | sed -E 's/^[Uu]npin[[:space:]]+skill:[[:space:]]*([A-Za-z0-9._-]+)$/\1/')"
      skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]')"
      seq=$((seq + 1))
      printf '%d\t%d\t%s\t%s\n' "$line_no" "$seq" "remove" "$skill"
    done < <(printf '%s\n' "$line" | grep -oE '[Uu]npin[[:space:]]+skill:[[:space:]]*[A-Za-z0-9._-]+' || true)

    # Unpin signal #3: "SKILL_UNPIN:<name>"
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      local skill
      skill="$(echo "$match" | sed -E 's/^SKILL_UNPIN:([A-Za-z0-9._-]+)$/\1/')"
      skill="$(echo "$skill" | tr '[:upper:]' '[:lower:]')"
      seq=$((seq + 1))
      printf '%d\t%d\t%s\t%s\n' "$line_no" "$seq" "remove" "$skill"
    done < <(printf '%s\n' "$line" | grep -oE 'SKILL_UNPIN:[A-Za-z0-9._-]+' || true)
  done < "$transcript_path"
}

declare -A ACTIVE_SKILLS=()
declare -A SEEN_SKILLS=()
ORDERED_SKILLS=()

while IFS=$'\t' read -r _line _seq action skill; do
  [[ -n "$skill" ]] || continue
  case "$action" in
    add)
      ACTIVE_SKILLS["$skill"]=1
      if [[ -z "${SEEN_SKILLS[$skill]+x}" ]]; then
        ORDERED_SKILLS+=("$skill")
        SEEN_SKILLS["$skill"]=1
      fi
      ;;
    remove)
      unset 'ACTIVE_SKILLS[$skill]'
      ;;
  esac
done < <(extract_skill_events "$TRANSCRIPT_PATH")

DETECTED_SKILLS=()
for skill in "${ORDERED_SKILLS[@]}"; do
  if [[ -n "${ACTIVE_SKILLS[$skill]+x}" ]]; then
    if [[ ${#ALLOWED_SKILLS[@]} -gt 0 && -z "${ALLOWED_SKILLS[$skill]+x}" ]]; then
      continue
    fi
    DETECTED_SKILLS+=("$skill")
  fi
done

if [[ ${#DETECTED_SKILLS[@]} -eq 0 ]]; then
  exit 0
fi

# ============================================================================
# Check for active orchestration session (non-complete) as extra context
# ============================================================================
ACTIVE_PLAN=""
SESSION_DIR="$PROJECT_ROOT/.orchestrate/session/plans"
if [[ -d "$SESSION_DIR" ]]; then
  while IFS= read -r handoff; do
    if [[ -f "$handoff" ]] && ! grep -q "PLAN COMPLETE" "$handoff" 2>/dev/null; then
      ACTIVE_PLAN=$(echo "$handoff" | sed "s|$SESSION_DIR/||" | sed 's|/handoffs/.*||')
      break
    fi
  done < <(find "$SESSION_DIR" -name "latest.md" -type f 2>/dev/null | sort -r)
fi

# ============================================================================
# Build additionalContext
# ============================================================================
LINES=()
LINES+=("**Sticky skills from previous session — load these before proceeding:**")
for skill in "${DETECTED_SKILLS[@]}"; do
  LINES+=("- \`/$skill\` remains in the sticky reload set from the previous conversation.")
done

if [[ -n "$ACTIVE_PLAN" ]]; then
  LINES+=("")
  LINES+=("**Active orchestration plan:** \`$ACTIVE_PLAN\` (not yet complete). Check handoff at \`.orchestrate/session/plans/$ACTIVE_PLAN/handoffs/latest.md\`.")
fi

# Join lines
CONTEXT=""
for line in "${LINES[@]}"; do
  CONTEXT+="$line\n"
done

jq -n --arg ctx "$(echo -e "$CONTEXT")" '{ "additionalContext": $ctx }'
