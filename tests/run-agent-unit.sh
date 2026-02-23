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

  PATH="$test_tmp/bin:$PATH" "$RUNNER" --model gpt-5.3-codex --prompt hi -C "$workdir" >/dev/null 2>&1

  # Verify .orchestrate runtime dirs were created under the working repository root
  [[ -d "$workdir/.orchestrate/runs/project/logs/agent-runs" ]] || fail ".orchestrate/runs/project/logs/agent-runs should be created"
  [[ -d "$workdir/.orchestrate/runs/project/.scratch/code/smoke" ]] || fail ".orchestrate/runs/project/.scratch/code/smoke should be created"
  [[ -d "$workdir/.orchestrate/session/project" ]] || fail ".orchestrate/session/project should be created"
}

test_project_local_orchestrate_agent_resolved() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-project-agent"
  mkdir -p "$workdir/.orchestrate/agents"

  cat > "$workdir/.orchestrate/agents/custom.md" <<'EOF'
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

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model ../../tmp/x/y --prompt hi -C "$workdir" >/dev/null 2>&1

  local label_dir
  label_dir="$(find "$workdir/.orchestrate/runs/project/logs/agent-runs" -mindepth 1 -maxdepth 1 -type d -name '..-..-tmp-x-y-*' | head -n 1)"
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

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt hi -C "$workdir" >/dev/null 2>&1

  assert_file_exists "$workdir/.orchestrate/session/project/index.log" "index.log should be written after a run"
  local last_line
  last_line="$(tail -1 "$workdir/.orchestrate/session/project/index.log")"
  assert_contains "$last_line" "gpt-5.3-codex" "index.log should contain model name"
  assert_contains "$last_line" " | " "index.log should be pipe-delimited"
}

test_plan_slice_shorthand_uses_runs_dir_scope() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-plan-slice-scope"
  mkdir -p "$workdir"

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt hi --plan unit-plan --slice unit-slice -C "$workdir" >/dev/null 2>&1

  [[ -d "$workdir/.orchestrate/runs/plans/unit-plan/slices/unit-slice/logs/agent-runs" ]] || \
    fail "plan/slice shorthand should scope logs under .orchestrate/runs/plans"
  [[ ! -d "$workdir/plans" ]] || \
    fail "plan/slice shorthand should not create plans/ under caller working directory"
}

test_plan_shorthand_preserves_plan_name() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-plan-scope"
  mkdir -p "$workdir"

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt hi --plan unit-plan-only -C "$workdir" >/dev/null 2>&1

  [[ -d "$workdir/.orchestrate/runs/plans/unit-plan-only/logs/agent-runs" ]] || \
    fail "--plan shorthand should scope logs under .orchestrate/runs/plans/<plan-name>"
}

test_scope_root_template_var_injected() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-scope-root-var"
  mkdir -p "$workdir"

  local expected_scope="$workdir/.orchestrate/runs/project"

  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --skills research --prompt hi --dry-run -C "$workdir"
  )"

  assert_contains "$output" "$expected_scope/.scratch/" "research prompt should resolve SCOPE_ROOT under .orchestrate/runs/project"
}

main() {
  local test_tmp
  test_tmp="$(mktemp -d)"
  trap "rm -rf '$test_tmp'" EXIT

  setup_fake_cli_bin "$test_tmp/bin"

  test_missing_option_value_is_friendly "$test_tmp"
  test_init_dirs_created "$test_tmp"
  test_project_local_orchestrate_agent_resolved "$test_tmp"
  test_claude_tool_normalization "$test_tmp"
  test_log_label_sanitized_with_pid "$test_tmp"
  test_session_index_written "$test_tmp"
  test_plan_slice_shorthand_uses_runs_dir_scope "$test_tmp"
  test_plan_shorthand_preserves_plan_name "$test_tmp"
  test_scope_root_template_var_injected "$test_tmp"

  echo "PASS: run-agent script unit tests"
}

main "$@"
