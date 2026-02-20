#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RUNNER="$REPO_ROOT/skills/run-agent/scripts/run-agent.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$msg"$'\n'"Expected to find: $needle"$'\n'"In output:"$'\n'"$haystack"
  fi
}

assert_file_exists() {
  local file="$1"
  local msg="$2"
  [[ -f "$file" ]] || fail "$msg: $file"
}

setup_fake_cli_bin() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null || true
echo "{}"
EOF

  cat > "$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null || true
echo "{}"
EOF

  cat > "$bin_dir/opencode" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null || true
echo "{}"
EOF

  chmod +x "$bin_dir/claude" "$bin_dir/codex" "$bin_dir/opencode"
}

test_missing_option_value_is_friendly() {
  local test_tmp="$1"
  local output
  output="$(
    cd "$REPO_ROOT"
    PATH="$test_tmp/bin:$PATH" "$RUNNER" -m 2>&1 || true
  )"

  assert_contains "$output" "ERROR: -m requires a value." "missing option value should emit explicit error"
  assert_contains "$output" "Usage: scripts/run-agent.sh" "missing option value should print usage"
}

test_init_dirs_created() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-init-dirs"
  mkdir -p "$workdir"

  ORCHESTRATE_DEFAULT_CLI=codex \
  PATH="$test_tmp/bin:$PATH" "$RUNNER" --model gpt-5.3-codex --prompt hi -C "$workdir" >/dev/null 2>&1

  # Verify run-agent/.runs/project was created
  local skills_dir
  skills_dir="$(cd "$REPO_ROOT/skills" && pwd -P)"
  [[ -d "$skills_dir/run-agent/.runs/project/logs/agent-runs" ]] || fail "run-agent/.runs/project/logs/agent-runs should be created"
  [[ -d "$skills_dir/run-agent/.runs/project/scratch/code/smoke" ]] || fail "run-agent/.runs/project/scratch/code/smoke should be created"
  [[ -d "$skills_dir/orchestrate/.session/project" ]] || fail "orchestrate/.session/project should be created"
}

test_project_local_agent_override() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-project-agent"
  mkdir -p "$workdir/.agents/skills/run-agent/agents"

  cat > "$workdir/.agents/skills/run-agent/agents/custom.md" <<'EOF'
---
name: custom
description: project custom
model: gpt-5.3-codex
---
Project custom agent.
EOF

  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" "$RUNNER" custom -C "$workdir" --dry-run
  )"

  assert_contains "$output" "── Model: gpt-5.3-codex (codex)" "project-local custom agent model should be loaded"
  assert_contains "$output" "Project custom agent." "project-local custom agent prompt should be used"
}

test_env_agent_dir_takes_precedence() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-env-agent"
  local env_agents="$test_tmp/env-agents"
  mkdir -p "$workdir/.agents/skills/run-agent/agents" "$env_agents"

  cat > "$workdir/.agents/skills/run-agent/agents/custom.md" <<'EOF'
---
name: custom
description: project custom
model: gpt-5.3-codex
---
Project custom agent.
EOF

  cat > "$env_agents/custom.md" <<'EOF'
---
name: custom
description: env custom
model: claude-sonnet-4-6
---
Env custom agent.
EOF

  local output
  output="$(
    ORCHESTRATE_AGENT_DIR="$env_agents" PATH="$test_tmp/bin:$PATH" "$RUNNER" custom -C "$workdir" --dry-run
  )"

  assert_contains "$output" "── Model: claude-sonnet-4-6 (claude)" "ORCHESTRATE_AGENT_DIR should override project-local agent"
  assert_contains "$output" "Env custom agent." "env-specified agent prompt should be used"
}

test_claude_tool_normalization() {
  local test_tmp="$1"
  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --model claude-sonnet-4-6 --tools read,websearch,bash --prompt hi --dry-run
  )"

  assert_contains "$output" "--allowedTools Read,WebSearch,Bash" "Claude allowlist tools should be normalized to expected casing"
}

test_log_label_sanitized_with_pid() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-log-sanitize"
  mkdir -p "$workdir"

  local skills_dir
  skills_dir="$(cd "$REPO_ROOT/skills" && pwd -P)"
  local runs_dir="$skills_dir/run-agent/.runs"

  ORCHESTRATE_DEFAULT_CLI=codex \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model ../../tmp/x/y --prompt hi -C "$workdir" >/dev/null 2>&1

  local label_dir
  label_dir="$(find "$runs_dir/project/logs/agent-runs" -mindepth 1 -maxdepth 1 -type d -name '..-..-tmp-x-y-*' | head -n 1)"
  assert_file_exists "$label_dir/params.json" "sanitized log label directory with PID should exist"
  # Verify PID is appended (pattern: label-PID)
  local dirname
  dirname="$(basename "$label_dir")"
  if [[ ! "$dirname" =~ -[0-9]+$ ]]; then
    fail "log dir should end with PID: $dirname"
  fi
}

test_session_index_written() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-session-index"
  mkdir -p "$workdir"

  local skills_dir
  skills_dir="$(cd "$REPO_ROOT/skills" && pwd -P)"
  local session_dir="$skills_dir/orchestrate/.session"

  ORCHESTRATE_DEFAULT_CLI=codex \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt hi -C "$workdir" >/dev/null 2>&1

  assert_file_exists "$session_dir/project/index.log" "index.log should be written after a run"
  local last_line
  last_line="$(tail -1 "$session_dir/project/index.log")"
  assert_contains "$last_line" "gpt-5.3-codex" "index.log should contain model name"
  assert_contains "$last_line" " | " "index.log should be pipe-delimited"
}

main() {
  local test_tmp
  test_tmp="$(mktemp -d)"
  trap "rm -rf '$test_tmp'" EXIT

  setup_fake_cli_bin "$test_tmp/bin"

  test_missing_option_value_is_friendly "$test_tmp"
  test_init_dirs_created "$test_tmp"
  test_project_local_agent_override "$test_tmp"
  test_env_agent_dir_takes_precedence "$test_tmp"
  test_claude_tool_normalization "$test_tmp"
  test_log_label_sanitized_with_pid "$test_tmp"
  test_session_index_written "$test_tmp"

  echo "PASS: run-agent script unit tests"
}

main "$@"
