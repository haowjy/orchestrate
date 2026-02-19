#!/usr/bin/env bash
# lib/prompt.sh — Skill loading, template substitution, prompt composition.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Skill Loading ───────────────────────────────────────────────────────────
# Reads SKILL.md, strips YAML frontmatter, returns body.

load_skill() {
  local name="$1"
  local skill_file="$SKILLS_DIR/$name/SKILL.md"

  if [[ ! -f "$skill_file" ]]; then
    echo "ERROR: Skill not found: $skill_file" >&2
    return 1
  fi

  # Strip YAML frontmatter (--- ... ---)
  awk '
    BEGIN { in_frontmatter=0; past_frontmatter=0 }
    /^---$/ {
      if (!past_frontmatter) {
        if (in_frontmatter) { past_frontmatter=1; next }
        else { in_frontmatter=1; next }
      }
    }
    past_frontmatter || !in_frontmatter { if (past_frontmatter || NR > 1 || !/^---$/) print }
  ' "$skill_file"
}

# ─── Model Routing ───────────────────────────────────────────────────────────
# Returns the CLI tool family for a given model name.

route_model() {
  local model="$1"
  case "$model" in
    opus*|sonnet*|haiku*|claude-*)
      echo "claude"
      ;;
    gpt-*|o1*|o3*|o4*|codex*)
      echo "codex"
      ;;
    opencode-*|*/*)
      echo "opencode"
      ;;
    *)
      echo "ERROR: Unknown model family: $model" >&2
      echo "  Supported: claude-*, gpt-*/codex*, opencode-*, provider/model" >&2
      return 1
      ;;
  esac
}

# Strip opencode- prefix before passing to the CLI.
# provider/model format (e.g. opencode/kimi-k2.5-free) is passed through unchanged.
strip_model_prefix() {
  echo "${1#opencode-}"
}

# ─── Template Substitution ───────────────────────────────────────────────────

apply_template_vars() {
  local text="$1"
  for key in "${!VARS[@]}"; do
    text="${text//\{\{$key\}\}/${VARS[$key]}}"
  done
  echo "$text"
}

json_escape() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\r'/\\r}"
  text="${text//$'\t'/\\t}"
  echo "$text"
}

build_skills_json() {
  local json=""
  local skill
  for skill in "${SKILLS[@]}"; do
    [[ -n "$json" ]] && json+=", "
    json+="\"$(json_escape "$skill")\""
  done
  echo "[$json]"
}

# ─── Compose Prompt ──────────────────────────────────────────────────────────

compose_prompt() {
  local composed=""

  # Load skills
  if [[ ${#SKILLS[@]} -gt 0 ]]; then
    composed+="# Skills"$'\n\n'
    for skill in "${SKILLS[@]}"; do
      composed+="## $skill"$'\n'
      composed+="$(load_skill "$skill")"$'\n\n'
    done
  fi

  # Task prompt
  if [[ -n "$PROMPT" ]]; then
    composed+="# Task"$'\n\n'
    composed+="$PROMPT"$'\n'
  fi

  # Reference files section
  if [[ ${#REF_FILES[@]} -gt 0 ]]; then
    composed+=$'\n'"# Reference Files"$'\n\n'
    for ref in "${REF_FILES[@]}"; do
      # Apply template vars to paths too
      local resolved_ref="$ref"
      if [[ "$HAS_VARS" == true ]]; then
        resolved_ref="$(apply_template_vars "$ref")"
      fi
      composed+="- $resolved_ref"$'\n'
    done
  fi

  # Apply template variables
  if [[ "$HAS_VARS" == true ]]; then
    composed="$(apply_template_vars "$composed")"
  fi

  echo "$composed"
}

# ─── Report Instruction ─────────────────────────────────────────────────────
# Appended to prompt so the subagent writes a report file the orchestrator can read.

build_report_instruction() {
  local report_path="$1"
  local level="$2"
  local detail_guide=""

  case "$level" in
    brief)
      detail_guide="Keep the report concise. Focus on: what was done, pass/fail status, any blockers."
      ;;
    standard)
      detail_guide="Include: what was done, key decisions made, files created/modified, verification results, and any issues or blockers."
      ;;
    detailed)
      detail_guide="Be thorough: what was done, reasoning behind decisions, all files touched with descriptions, full verification results, issues found, and recommendations for next steps."
      ;;
  esac

  cat <<EOF

# Report

**IMPORTANT — As your FINAL action**, write a report of your work to: \`$report_path\`

$detail_guide

Use plain markdown. This file is read by the orchestrator to understand what you did without parsing verbose logs.
EOF
}
