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

test_runs_gitignore_auto_created() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-runs"
  mkdir -p "$workdir"

  PATH="$test_tmp/bin:$PATH" "$RUNNER" --model gpt-5.3-codex --prompt hi -C "$workdir" --dry-run >/dev/null

  assert_file_exists "$workdir/.runs/.gitignore" ".runs/.gitignore should be auto-created"
  local contents
  contents="$(cat "$workdir/.runs/.gitignore")"
  if [[ "$contents" != $'*\n!.gitignore' ]]; then
    fail "unexpected .runs/.gitignore contents"$'\n'"$contents"
  fi
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

test_log_label_sanitized() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-log-sanitize"
  local runs_dir="$test_tmp/runs-log-sanitize"
  mkdir -p "$workdir"

  ORCHESTRATE_DEFAULT_CLI=codex \
  ORCHESTRATE_RUNS_DIR="$runs_dir" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model ../../tmp/x/y --prompt hi -C "$workdir" >/dev/null 2>&1

  local label_dir
  label_dir="$(find "$runs_dir/project/logs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  assert_file_exists "$label_dir/params.json" "sanitized log label directory should exist"
  assert_contains "$label_dir" "..-..-tmp-x-y" "log label should be sanitized to a safe directory name"
}

main() {
  local test_tmp
  test_tmp="$(mktemp -d)"
  trap "rm -rf '$test_tmp'" EXIT

  setup_fake_cli_bin "$test_tmp/bin"

  test_missing_option_value_is_friendly "$test_tmp"
  test_runs_gitignore_auto_created "$test_tmp"
  test_project_local_agent_override "$test_tmp"
  test_env_agent_dir_takes_precedence "$test_tmp"
  test_claude_tool_normalization "$test_tmp"
  test_log_label_sanitized "$test_tmp"

  echo "PASS: run-agent script unit tests"
}

main "$@"
