#!/usr/bin/env bash
# lib/parse.sh — Usage display, agent .md parsing, argument parsing loop.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: scripts/run-agent.sh [agent] [OPTIONS]

  [agent]              Optional. Resolves to agents/<name>.md (sibling dir)

Options:
  -m, --model MODEL    Model override (default: from agent definition)
  -e, --effort EFFORT  low | medium | high (default: high)
  -t, --tools TOOLS    Allowed tools, claude-only (default: "Read,Edit,Write,Bash,Glob,Grep")
  -s, --skills LIST    Comma-separated skill names to load
  -p, --prompt TEXT    Prompt text (can also pipe via stdin)
  -v, --var KEY=VALUE  Template variable substitution (repeatable)
  -f, --file PATH      Reference file/dir to list in prompt (repeatable)
  -D, --detail LEVEL   Report detail level: brief | standard | detailed (default: standard)
      --dry-run        Print composed prompt + CLI command, don't execute
  -C, --cd DIR         Working directory for subprocess

Environment:
  ORCHESTRATE_RUNS_DIR   Where to store run data (default: .runs/ next to skill root)
  ORCHESTRATE_LOG_DIR    Where to write logs (default: auto-derived from scope)
  ORCHESTRATE_DEFAULT_CLI  Force all model routing to a specific CLI (claude, codex, opencode)
EOF
  exit 1
}

# ─── Agent .md Parsing ──────────────────────────────────────────────────────
# Parses YAML frontmatter between --- delimiters. Body after second --- = prompt.

parse_agent_md() {
  local file="$1"
  local in_frontmatter=false
  local past_frontmatter=false
  local frontmatter=""
  local body=""

  while IFS= read -r line; do
    if [[ "$past_frontmatter" == true ]]; then
      body+="$line"$'\n'
    elif [[ "$line" == "---" ]]; then
      if [[ "$in_frontmatter" == true ]]; then
        past_frontmatter=true
      else
        in_frontmatter=true
      fi
    elif [[ "$in_frontmatter" == true ]]; then
      frontmatter+="$line"$'\n'
    fi
  done < "$file"

  # Parse frontmatter fields (simple YAML key: value)
  local val

  val=$(echo "$frontmatter" | grep -E '^model:' | head -1 | sed 's/^model:[[:space:]]*//' || true)
  [[ -n "$val" ]] && [[ "$MODEL_FROM_CLI" == false ]] && MODEL="$val"

  val=$(echo "$frontmatter" | grep -E '^tools:' | head -1 | sed 's/^tools:[[:space:]]*//' || true)
  [[ -n "$val" ]] && [[ "$TOOLS_FROM_CLI" == false ]] && TOOLS="$val"

  val=$(echo "$frontmatter" | grep -E '^effort:' | head -1 | sed 's/^effort:[[:space:]]*//' || true)
  [[ -n "$val" ]] && [[ "$EFFORT_FROM_CLI" == false ]] && EFFORT="$val"

  # Skills: YAML list (  - name) or inline [name1, name2]
  local skills_raw
  skills_raw=$(echo "$frontmatter" | sed -n '/^skills:/,/^[^ -]/{ /^skills:/d; /^[^ -]/d; p; }' || true)
  if [[ -n "$skills_raw" ]]; then
    while IFS= read -r sline; do
      sline=$(echo "$sline" | sed 's/^[[:space:]]*-[[:space:]]*//' | xargs)
      [[ -n "$sline" ]] && SKILLS+=("$sline")
    done <<< "$skills_raw"
  else
    # Try inline format: skills: [review, plan-slice] or skills: []
    val=$(echo "$frontmatter" | grep -E '^skills:' | head -1 | sed 's/^skills:[[:space:]]*//' || true)
    if [[ "$val" =~ ^\[.*\]$ ]]; then
      val="${val#[}"
      val="${val%]}"
      val=$(echo "$val" | sed 's/,/ /g; s/"//g; s/'\''//g')
      for s in $val; do
        s=$(echo "$s" | xargs)
        [[ -n "$s" ]] && SKILLS+=("$s")
      done
    fi
  fi

  # Body after frontmatter = agent prompt
  if [[ -n "$body" ]]; then
    AGENT_PROMPT="$body"
  fi
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

parse_args() {
  # First arg might be an agent name (not starting with -)
  if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
    AGENT_NAME="$1"
    shift
  fi

  if [[ -n "$AGENT_NAME" ]]; then
    AGENT_FILE="$AGENTS_DIR/$AGENT_NAME.md"
    if [[ ! -f "$AGENT_FILE" ]]; then
      echo "ERROR: Agent not found: $AGENT_FILE" >&2
      exit 1
    fi
    parse_agent_md "$AGENT_FILE"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model)   MODEL="$2"; MODEL_FROM_CLI=true; shift 2 ;;
      -e|--effort)  EFFORT="$2"; EFFORT_FROM_CLI=true; shift 2 ;;
      -t|--tools)   TOOLS="$2"; TOOLS_FROM_CLI=true; shift 2 ;;
      -s|--skills)
        IFS=',' read -ra _skills <<< "$2"
        for s in "${_skills[@]}"; do SKILLS+=("$(echo "$s" | xargs)"); done
        shift 2
        ;;
      -p|--prompt)  CLI_PROMPT="$2"; shift 2 ;;
      -f|--file)    REF_FILES+=("$2"); shift 2 ;;
      -v|--var)
        key="${2%%=*}"
        val="${2#*=}"
        VARS["$key"]="$val"
        HAS_VARS=true
        shift 2
        ;;
      -D|--detail)
        case "$2" in
          brief|standard|detailed) DETAIL="$2" ;;
          *) echo "[run-agent] WARNING: Invalid detail level '$2', defaulting to 'standard'" >&2; DETAIL="standard" ;;
        esac
        shift 2
        ;;
      --dry-run) DRY_RUN=true; shift ;;
      -C|--cd)      WORK_DIR="$2"; shift 2 ;;
      -h|--help)    usage ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage
        ;;
    esac
  done

  normalize_var_aliases

  # ─── Read prompt from stdin if not provided via -p ─────────────────────────
  if [[ -z "$CLI_PROMPT" ]] && [[ ! -t 0 ]]; then
    CLI_PROMPT="$(cat)"
  fi

  # Agent prompt from .md body + optional CLI prompt/stdin
  if [[ -n "$AGENT_PROMPT" ]] && [[ -n "$CLI_PROMPT" ]]; then
    PROMPT="${AGENT_PROMPT}${CLI_PROMPT}"
  elif [[ -n "$AGENT_PROMPT" ]]; then
    PROMPT="$AGENT_PROMPT"
  else
    PROMPT="$CLI_PROMPT"
  fi
}

normalize_var_aliases() {
  # Allow both SLICE_* and TASK_* keys.
  if [[ -n "${VARS[TASK_FILE]:-}" ]] && [[ -z "${VARS[SLICE_FILE]:-}" ]]; then
    VARS[SLICE_FILE]="${VARS[TASK_FILE]}"
    HAS_VARS=true
  fi
  if [[ -n "${VARS[SLICE_FILE]:-}" ]] && [[ -z "${VARS[TASK_FILE]:-}" ]]; then
    VARS[TASK_FILE]="${VARS[SLICE_FILE]}"
    HAS_VARS=true
  fi

  if [[ -n "${VARS[TASKS_DIR]:-}" ]] && [[ -z "${VARS[SLICES_DIR]:-}" ]]; then
    VARS[SLICES_DIR]="${VARS[TASKS_DIR]}"
    HAS_VARS=true
  fi
  if [[ -n "${VARS[SLICES_DIR]:-}" ]] && [[ -z "${VARS[TASKS_DIR]:-}" ]]; then
    VARS[TASKS_DIR]="${VARS[SLICES_DIR]}"
    HAS_VARS=true
  fi
}

validate_args() {
  if [[ -z "$MODEL" ]]; then
    echo "ERROR: No model specified. Use -m MODEL or an agent definition with a model field." >&2
    exit 1
  fi

  if [[ -z "$PROMPT" ]] && [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo "ERROR: No prompt or skills specified. Use -p, -s, or an agent with a prompt." >&2
    exit 1
  fi
}
