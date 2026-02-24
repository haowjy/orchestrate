#!/usr/bin/env bash
# session-start.sh — SessionStart hook (packaged with orchestrate plugin)
#
# Reloads skills that were active in the previous session after context loss.
#
# Triggers:
# - compact: context compressed, skills may be lost. Scans current transcript.
# - clear: only if the previous session ended with ExitPlanMode (plan acceptance).
#   Reads the previous transcript path from .orchestrate/session/prev-transcript
#   (written by session-end.sh), checks last ~20 lines for ExitPlanMode.
#   Manual /clear (no ExitPlanMode) is treated as intentional reset — no reload.
#
# Detection is based on actual activation signals in the transcript, not
# just mentions. This catches both user-initiated (/skill) and LLM-initiated
# (Skill tool) activations.
#
# Tracked skills are read from .orchestrate/tracked-skills (one per line,
# # comments). Falls back to (orchestrate, run-agent) if the file is missing.
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
# Load tracked skills from config
# ============================================================================
mapfile -t TRACKED_SKILLS < <(load_tracked_skills "$PROJECT_ROOT")

if [[ ${#TRACKED_SKILLS[@]} -eq 0 ]]; then
  exit 0
fi

# ============================================================================
# Detect which tracked skills were actually activated in the previous session
# ============================================================================
DETECTED_SKILLS=()

for skill in "${TRACKED_SKILLS[@]}"; do
  # Detection signals (ordered by reliability):
  #
  # 1. "Launching skill: <name>" — tool result confirming the skill was loaded.
  #    Definitive activation marker for both user-initiated (/skill) and
  #    LLM-initiated (Skill tool) activations.
  #
  # 2. "Base directory for this skill: .../skills/<name>" — the isMeta message
  #    that injects the SKILL.md content. Confirms the skill instructions were
  #    actually loaded into context.
  #
  # 3. "name":"Skill" + "skill":"<name>" — the Skill tool invocation itself.
  #    May appear even if activation failed, but useful as a fallback signal.
  #
  # We check all three to be robust against transcript format variations.

  if grep -qF "Launching skill: ${skill}" "$TRANSCRIPT_PATH" 2>/dev/null; then
    DETECTED_SKILLS+=("$skill")
  elif grep -q "Base directory for this skill:.*skills/${skill}" "$TRANSCRIPT_PATH" 2>/dev/null; then
    DETECTED_SKILLS+=("$skill")
  elif grep -qE "\"name\":\s*\"Skill\"" "$TRANSCRIPT_PATH" 2>/dev/null && \
       grep -qE "\"skill\":\s*\"${skill}\"" "$TRANSCRIPT_PATH" 2>/dev/null; then
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
LINES+=("**Auto-detected skills from previous session — load these before proceeding:**")
for skill in "${DETECTED_SKILLS[@]}"; do
  LINES+=("- \`/$skill\` was active in the previous conversation. Load it now with the Skill tool.")
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
