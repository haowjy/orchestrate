#!/usr/bin/env bash
# lib/parse.sh — Usage display, agent .md parsing, argument parsing loop.
# Sourced by run-agent.sh; expects globals from the entrypoint.

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: scripts/run-agent.sh [agent] [OPTIONS]

  [agent]              Optional. Resolves to .orchestrate/agents/<name>.md

Options:
  -m, --model MODEL    Model override (default: from agent definition)
  -e, --effort EFFORT  low | medium | high (default: high)
  -t, --tools TOOLS    Allowed tools, claude-only (default: "Read,Edit,Write,Bash,Glob,Grep")
  -s, --skills LIST    Comma-separated skill names to load
  -p, --prompt TEXT    Prompt text (can also pipe via stdin)
  -v, --var KEY=VALUE  Template variable substitution (repeatable)
  -f, --file PATH      Reference file/dir to list in prompt (repeatable)
  -D, --detail LEVEL   Report detail level: brief | standard | detailed (default: standard)
      --plan NAME      Shorthand: sets PLAN_FILE=$RUNS_DIR/plans/NAME/plan.md
      --slice NAME     Shorthand: sets SLICE_FILE + SLICES_DIR (requires --plan)
      --dry-run        Print composed prompt + CLI command, don't execute
  -C, --cd DIR         Working directory for subprocess

Environment:
  ORCHESTRATE_ROOT         Canonical orchestrate root (default: <repo>/.orchestrate)
  ORCHESTRATE_PLAN         Default plan name (inherited by --slice without --plan)
  ORCHESTRATE_DEFAULT_CLI  Force all model routing to a specific CLI (claude, codex, opencode)
  ORCHESTRATE_AGENT_DIR    Override agent definition directory (highest precedence)
EOF
  exit 1
}

require_option_value() {
  local opt="$1"
  local remaining_args="$2"

  if [[ "$remaining_args" -lt 2 ]]; then
    echo "ERROR: $opt requires a value." >&2
    usage
  fi
}

preparse_work_dir_override() {
  local args=("$@")
  local idx=0
  while [[ $idx -lt ${#args[@]} ]]; do
    case "${args[$idx]}" in
      -C|--cd)
        if [[ $((idx + 1)) -ge ${#args[@]} ]]; then
          echo "ERROR: ${args[$idx]} requires a value." >&2
          usage
        fi
        WORK_DIR="${args[$((idx + 1))]}"
        idx=$((idx + 2))
        ;;
      *)
        idx=$((idx + 1))
        ;;
    esac
  done

  if [[ "$WORK_DIR" != /* ]]; then
    WORK_DIR="$(pwd -P)/$WORK_DIR"
  fi
}

resolve_agent_file() {
  local agent_name="$1"
  local candidate
  local -a dirs=()

  if [[ -n "${ORCHESTRATE_AGENT_DIR:-}" ]]; then
    dirs+=("$ORCHESTRATE_AGENT_DIR")
  fi
  dirs+=("$AGENTS_DIR")

  for candidate_dir in "${dirs[@]}"; do
    candidate="$candidate_dir/$agent_name.md"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
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
  preparse_work_dir_override "$@"
  refresh_orchestrate_paths_from_workdir

  # First arg might be an agent name (not starting with -)
  if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
    AGENT_NAME="$1"
    shift
  fi

  if [[ -n "$AGENT_NAME" ]]; then
    AGENT_FILE="$(resolve_agent_file "$AGENT_NAME" || true)"
    if [[ ! -f "$AGENT_FILE" ]]; then
      echo "ERROR: Agent not found: $AGENT_NAME" >&2
      echo "Checked: ORCHESTRATE_AGENT_DIR, $AGENTS_DIR" >&2
      exit 1
    fi
    parse_agent_md "$AGENT_FILE"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model)
        require_option_value "$1" "$#"
        MODEL="$2"
        MODEL_FROM_CLI=true
        shift 2
        ;;
      -e|--effort)
        require_option_value "$1" "$#"
        EFFORT="$2"
        EFFORT_FROM_CLI=true
        shift 2
        ;;
      -t|--tools)
        require_option_value "$1" "$#"
        TOOLS="$2"
        TOOLS_FROM_CLI=true
        shift 2
        ;;
      -s|--skills)
        require_option_value "$1" "$#"
        IFS=',' read -ra _skills <<< "$2"
        for s in "${_skills[@]}"; do SKILLS+=("$(echo "$s" | xargs)"); done
        shift 2
        ;;
      -p|--prompt)
        require_option_value "$1" "$#"
        CLI_PROMPT="$2"
        shift 2
        ;;
      -f|--file)
        require_option_value "$1" "$#"
        REF_FILES+=("$2")
        shift 2
        ;;
      -v|--var)
        require_option_value "$1" "$#"
        key="${2%%=*}"
        val="${2#*=}"
        VARS["$key"]="$val"
        HAS_VARS=true
        shift 2
        ;;
      -D|--detail)
        require_option_value "$1" "$#"
        case "$2" in
          brief|standard|detailed) DETAIL="$2" ;;
          *) echo "[run-agent] WARNING: Invalid detail level '$2', defaulting to 'standard'" >&2; DETAIL="standard" ;;
        esac
        shift 2
        ;;
      --plan)
        require_option_value "$1" "$#"
        PLAN_NAME="$2"
        shift 2
        ;;
      --slice)
        require_option_value "$1" "$#"
        SLICE_NAME="$2"
        shift 2
        ;;
      --dry-run) DRY_RUN=true; shift ;;
      -C|--cd)
        require_option_value "$1" "$#"
        WORK_DIR="$2"
        shift 2
        ;;
      -h|--help)    usage ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage
        ;;
    esac
  done

  expand_plan_slice_shorthand

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

expand_plan_slice_shorthand() {
  # Inherit plan from orchestrator env if not set via CLI flag
  if [[ -z "$PLAN_NAME" ]] && [[ -n "${ORCHESTRATE_PLAN:-}" ]]; then
    PLAN_NAME="$ORCHESTRATE_PLAN"
  fi

  # --slice without --plan is an error
  if [[ -n "$SLICE_NAME" ]] && [[ -z "$PLAN_NAME" ]]; then
    echo "ERROR: --slice requires --plan (or set ORCHESTRATE_PLAN env var)." >&2
    exit 1
  fi

  [[ -z "$PLAN_NAME" ]] && return

  # --plan X → PLAN_FILE=$RUNS_DIR/plans/X/plan.md (explicit -v wins)
  if [[ -z "${VARS[PLAN_FILE]:-}" ]]; then
    VARS[PLAN_FILE]="$RUNS_DIR/plans/$PLAN_NAME/plan.md"
    HAS_VARS=true
  fi

  # --plan X --slice Y → SLICE_FILE + SLICES_DIR (explicit -v wins)
  if [[ -n "$SLICE_NAME" ]]; then
    if [[ -z "${VARS[SLICE_FILE]:-}" ]]; then
      VARS[SLICE_FILE]="$RUNS_DIR/plans/$PLAN_NAME/slices/$SLICE_NAME/slice.md"
      HAS_VARS=true
    fi
    if [[ -z "${VARS[SLICES_DIR]:-}" ]]; then
      VARS[SLICES_DIR]="$RUNS_DIR/plans/$PLAN_NAME/slices/$SLICE_NAME"
      HAS_VARS=true
    fi
  fi
}

validate_args() {
  # ── Model fallback ─────────────────────────────────────────────────────────
  # If no model was specified (neither CLI -m nor agent definition), fall back
  # to FALLBACK_MODEL so ad-hoc runs don't fail with a cryptic error.
  if [[ -z "$MODEL" ]]; then
    echo "[run-agent] WARNING: No model specified; falling back to $FALLBACK_MODEL" >&2
    MODEL="$FALLBACK_MODEL"
  fi

  # Advisory: warn early if the routed CLI isn't installed (build_cli_command handles actual fallback).
  local routed_cli
  routed_cli="$(route_model "$MODEL" 2>/dev/null || echo "")"
  if [[ -n "$routed_cli" ]] && ! command -v "$routed_cli" >/dev/null 2>&1; then
    echo "[run-agent] WARNING: '$routed_cli' not installed for model '$MODEL'; will fall back to $FALLBACK_MODEL ($FALLBACK_CLI)" >&2
  fi

  if [[ -z "$PROMPT" ]] && [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo "ERROR: No prompt or skills specified. Use -p, -s, or an agent with a prompt." >&2
    exit 1
  fi

  # Validate that template variables referenced in the prompt are not empty.
  # Empty vars cause scope_root to resolve to "/" which breaks mkdir.
  #
  # Common caller mistake: passing -v KEY="$SHELL_VAR" where SHELL_VAR was set
  # as a command-line prefix (VAR=x ./run-agent.sh) without export, so it never
  # expands and arrives here as a literal empty string.
  if [[ "$HAS_VARS" == true ]]; then
    local key val
    for key in "${!VARS[@]}"; do
      val="${VARS[$key]}"
      if [[ -z "$val" ]]; then
        echo "ERROR: Template variable '$key' is empty." >&2
        echo "  Hint: If you set the value via a shell variable, make sure it was exported" >&2
        echo "  before the command, or use an inline value:" >&2
        echo "    export MY_VAR=/some/path && ./run-agent.sh -v $key=\"\$MY_VAR\"" >&2
        echo "    ./run-agent.sh -v $key=/some/path" >&2
        exit 1
      fi
    done
  fi
}
