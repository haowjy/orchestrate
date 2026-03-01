#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RUNNER="$REPO_ROOT/skills/run-agent/scripts/run-agent.sh"
INDEX="$REPO_ROOT/skills/run-agent/scripts/run-index.sh"

source "$SCRIPT_DIR/lib/assert.sh"
parse_test_flags "$@"

setup_fake_cli_bin() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_ARGS_LOG:?}"
: "${FAKE_STDIN_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_ARGS_LOG"
stdin_payload="$(cat || true)"
printf '<<<\n%s\n>>>\n' "$stdin_payload" >> "$FAKE_STDIN_LOG"
if [[ "${1:-}" == "exec" && "${2:-}" == "resume" ]]; then
  echo '{"thread_id":"thread-resume"}'
  echo '{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"text","text":"continued"}]}}'
else
  echo '{"thread_id":"thread-base"}'
  echo '{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"text","text":"base"}]}}'
fi
EOF

  cat > "$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null || true

mode="${FAKE_CLAUDE_MODE:-ok}"
case "$mode" in
  ok)
    echo '{"type":"result","session_id":"claude-session","result":{"text":"ok"}}'
    ;;
  empty)
    # Simulate a misbehaving/hung CLI that exits 0 but prints nothing.
    exit 0
    ;;
  *)
    echo "unknown FAKE_CLAUDE_MODE=$mode" >&2
    exit 1
    ;;
esac
EOF

  cat > "$bin_dir/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# OpenCode uses arg mode (prompt as CLI arg, not stdin), so no stdin drain needed.

mode="${FAKE_OPENCODE_MODE:-ok}"
case "$mode" in
  ok)
    echo '{"type":"assistant","sessionID":"opencode-session","content":"ok"}'
    ;;
  error)
    # Simulate an OpenCode JSON error event with exit=0.
    echo '{"type":"error","timestamp":0,"sessionID":"opencode-session","error":{"name":"UnknownError","data":{"message":"Model not found: openai/gpt-4o-mini."}}}'
    ;;
  *)
    echo "unknown FAKE_OPENCODE_MODE=$mode" >&2
    exit 1
    ;;
esac
EOF

  chmod +x "$bin_dir/codex" "$bin_dir/claude" "$bin_dir/opencode"
}

test_missing_option_value_is_friendly() {
  local test_tmp="$1"
  local output
  output="$(
    cd "$REPO_ROOT"
    PATH="$test_tmp/bin:$PATH" "$RUNNER" -m 2>&1 || true
  )"

  assert_contains "$output" "ERROR: -m requires a value." "missing option value should emit explicit error"
  assert_contains "$output" "Usage: run-agent.sh [OPTIONS]" "missing option value should print usage"
}

test_run_writes_output_log_under_run_dir() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-log-path"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  assert_file_exists "$run_dir/output.jsonl" "run should write output.jsonl inside the run directory"
}

test_continuation_uses_codex_resume_and_sets_metadata() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-continue"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-continue.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-continue.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "first prompt" -C "$workdir" >/dev/null 2>/dev/null

  sleep 1

  (
    cd "$workdir"
    FAKE_ARGS_LOG="$test_tmp/args-continue.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-continue.log" \
    PATH="$test_tmp/bin:$PATH" \
    "$INDEX" continue @latest -p "follow up"
  ) >/dev/null 2>/dev/null

  local args_log
  args_log="$(cat "$test_tmp/args-continue.log")"
  assert_contains "$args_log" "exec resume thread-base" "continuation should call codex resume with previous session ID"

  local finalize_json
  finalize_json="$(jq -s '[.[] | select(.status != "running")] | .[1]' "$workdir/.orchestrate/index/runs.jsonl")"
  assert_contains "$finalize_json" "\"continuation_mode\": \"in-place\"" "codex continuation should record in-place mode"
  assert_contains "$finalize_json" "\"continues\":" "continuation should link to original run"
}

test_retry_uses_original_prompt_and_records_retries() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-retry"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-retry.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-retry.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "original prompt" -C "$workdir" >/dev/null 2>/dev/null

  sleep 1

  (
    cd "$workdir"
    FAKE_ARGS_LOG="$test_tmp/args-retry.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-retry.log" \
    PATH="$test_tmp/bin:$PATH" \
    "$INDEX" retry @latest
  ) >/dev/null 2>/dev/null

  local latest_dir
  latest_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1)"
  local input_md
  input_md="$(cat "$latest_dir/input.md")"
  assert_contains "$input_md" "original prompt" "retry should preserve the original prompt content"
  local report_count
  report_count="$(grep -c '^# Report$' <<< "$input_md" || true)"
  assert_eq "$report_count" "1" "retry should not duplicate generated report sections"
  assert_not_contains "$input_md" $'\n-\n' "retry prompt should not degrade to a literal dash"

  local latest_finalize
  latest_finalize="$(jq -s '[.[] | select(.status != "running")] | .[1]' "$workdir/.orchestrate/index/runs.jsonl")"
  assert_contains "$latest_finalize" "\"retries\":" "retry should link to original run via retries metadata"
}

test_codex_explicit_fork_fails_fast() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-codex-fork"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-fork.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-fork.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "first prompt" -C "$workdir" >/dev/null 2>/dev/null

  local run_id
  run_id="$(jq -s -r '[.[] | select(.status != "running")] | .[0].run_id' "$workdir/.orchestrate/index/runs.jsonl")"

  local output
  output="$(
    FAKE_ARGS_LOG="$test_tmp/args-fork.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-fork.log" \
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model gpt-5.3-codex --continue-run "$run_id" --fork --prompt "follow up" -C "$workdir" 2>&1 || true
  )"
  assert_contains "$output" "Codex continuation does not support forking" "explicit codex fork should error clearly"
}

test_claude_empty_output_fails_fast() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-claude-empty"
  mkdir -p "$workdir"

  local output exit_code
  output="$(
    FAKE_CLAUDE_MODE=empty \
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model claude-sonnet-4-6 --prompt "hello" -C "$workdir" 2>&1
  )" || exit_code=$?
  exit_code="${exit_code:-0}"

  if [[ "$exit_code" -ne 2 ]]; then
    fail "claude empty output should fail with exit 2 (infra error), got $exit_code"$'\n'"Output:"$'\n'"$output"
  fi

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  assert_file_exists "$run_dir/report.md" "claude empty output should write report.md"
  assert_contains "$(cat "$run_dir/report.md")" "No harness output captured" "claude empty output report should explain failure"
}

test_opencode_error_event_fails_fast() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-opencode-error"
  mkdir -p "$workdir"

  local output exit_code
  output="$(
    FAKE_OPENCODE_MODE=error \
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model openai/gpt-4o-mini --prompt "hello" -C "$workdir" 2>&1
  )" || exit_code=$?
  exit_code="${exit_code:-0}"

  if [[ "$exit_code" -ne 1 ]]; then
    fail "opencode error event should fail with exit 1 (agent error), got $exit_code"$'\n'"Output:"$'\n'"$output"
  fi

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  assert_file_exists "$run_dir/report.md" "opencode error event should write report.md"
  assert_contains "$(cat "$run_dir/report.md")" "Model not found" "opencode error report should include error message"
}

test_timeout_kills_hung_harness() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-timeout"
  mkdir -p "$workdir"

  # Overwrite fake codex to sleep longer than the timeout.
  cat > "$test_tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 2
EOF
  chmod +x "$test_tmp/bin/codex"

  local output exit_code
  output="$(
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model gpt-5.3-codex --prompt "hello" --timeout 0.02 -C "$workdir" 2>&1
  )" || exit_code=$?
  exit_code="${exit_code:-0}"

  if [[ "$exit_code" -ne 3 ]]; then
    fail "timeout should return exit 3, got $exit_code"$'\n'"Output:"$'\n'"$output"
  fi

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  assert_file_exists "$run_dir/report.md" "timeout should write report.md"
  assert_contains "$(cat "$run_dir/report.md")" "Timed out" "timeout report should explain failure"
}

test_orchestrate_config_template_is_auto_created() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-config-template"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-config-template.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-config-template.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local config_file="$workdir/.orchestrate/config.toml"
  assert_file_exists "$config_file" "run should auto-create .orchestrate/config.toml"

  local config_text
  config_text="$(cat "$config_file")"
  assert_contains "$config_text" "# [skills]" "config template should include commented skills table"
  assert_contains "$config_text" "# pinned = [\"orchestrate\", \"run-agent\", \"mermaid\"]" "config template should include commented pinned skills example"
}

test_pinned_skills_load_from_config() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-config-pinned-skills"
  mkdir -p "$workdir/.orchestrate"

  cat > "$workdir/.orchestrate/config.toml" <<'EOF'
[skills]
pinned = ["orchestrate", "run-agent", "mermaid"]
EOF

  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model gpt-5.3-codex --dry-run --prompt "hello" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "Skills: orchestrate run-agent mermaid" "dry run should include pinned skills from .orchestrate/config.toml"
}

test_pinned_skills_multiline_array_loads() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-config-pinned-multiline"
  mkdir -p "$workdir/.orchestrate"

  cat > "$workdir/.orchestrate/config.toml" <<'EOF'
[skills]
pinned = [
  "orchestrate",
  "run-agent",
  "mermaid",
]
EOF

  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model gpt-5.3-codex --dry-run --prompt "hello" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "Skills: orchestrate run-agent mermaid" "multiline pinned skills should load from TOML"
}

test_pinned_skills_hash_in_quotes_is_not_treated_as_comment() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-config-pinned-hash"
  mkdir -p "$workdir/.orchestrate"

  cat > "$workdir/.orchestrate/config.toml" <<'EOF'
[skills]
pinned = ["orchestrate", "team#1"]
EOF

  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model gpt-5.3-codex --dry-run --prompt "hello" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "Skills: orchestrate team#1" "quoted # should be preserved in pinned skill values"
}

test_strict_skills_errors_on_unknown_skills() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-strict-skills"
  mkdir -p "$workdir"

  local output
  output="$(
    PATH="$test_tmp/bin:$PATH" \
    "$RUNNER" --model gpt-5.3-codex --strict-skills --skills definitely-missing --prompt "hello" -C "$workdir" 2>&1 || true
  )"
  assert_contains "$output" "ERROR: Unknown skill(s): definitely-missing" "--strict-skills should fail on unknown skills"
}

test_invalid_args_do_not_create_runtime_dirs() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-invalid-args-no-side-effects"
  mkdir -p "$workdir"

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --timeout not-a-number --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null || true

  assert_file_not_exists "$workdir/.orchestrate/config.toml" "invalid args should not create runtime config"
}

test_help_flags_exit_zero() {
  local test_tmp="$1"
  local output

  output="$("$RUNNER" --help 2>&1)"
  assert_contains "$output" "Usage: run-agent.sh [OPTIONS]" "run-agent --help should print usage"

  output="$("$INDEX" --help 2>&1)"
  assert_contains "$output" "Usage: run-index.sh <command> [options]" "run-index --help should print usage"
}

# ─── Agent Profile Tests ────────────────────────────────────────────────────

test_agent_dry_run_shows_correct_metadata() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-dry"
  mkdir -p "$workdir"

  local output
  output="$(
    cd "$REPO_ROOT"
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --agent reviewer --dry-run -p "Review auth" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "Agent: reviewer" "dry run should show agent name"
  assert_contains "$output" "Model: gpt-5.3-codex" "dry run should show agent's default model"
  assert_contains "$output" "Variant: high" "dry run should show agent's default variant"
  assert_contains "$output" "Skills: reviewing" "dry run should show agent's default skills"
  assert_contains "$output" "Tools: Read,Glob,Grep,Bash,WebSearch,WebFetch" "dry run should show agent's tools"
  assert_contains "$output" "Sandbox: danger-full-access" "dry run should show agent's sandbox"
  # Codex should enforce sandbox and avoid dangerous fallback flags.
  assert_contains "$output" "--sandbox danger-full-access" "codex harness should receive sandbox from reviewer profile"
  assert_not_contains "$output" "--dangerously-bypass-approvals-and-sandbox" "agent run should not use dangerous bypass when sandbox is explicit"
}

test_agent_cli_model_overrides_profile() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-override"
  mkdir -p "$workdir"

  local output
  output="$(
    cd "$REPO_ROOT"
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --agent reviewer --model claude-opus-4-6 --dry-run -p "Deep review" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "Model: claude-opus-4-6" "CLI --model should override agent profile model"
  assert_contains "$output" "--agent reviewer" "agent flag should still be passed"
}

test_agent_coder_unrestricted() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-coder"
  mkdir -p "$workdir"

  local output
  output="$(
    cd "$REPO_ROOT"
    FAKE_ARGS_LOG="$test_tmp/args-coder.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-coder.log" \
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --agent coder --dry-run -p "Implement feature" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "Agent: coder" "dry run should show coder agent"
  assert_contains "$output" "Model: gpt-5.3-codex" "coder should default to codex model"
  # Codex with unrestricted sandbox should use bypass flag
  assert_contains "$output" "--dangerously-bypass-approvals-and-sandbox" "unrestricted coder should use bypass flag for codex"
}

test_no_agent_backward_compat() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-no-agent"
  mkdir -p "$workdir"

  local output
  output="$(
    cd "$REPO_ROOT"
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --model claude-sonnet-4-6 --dry-run -p "hello" -C "$workdir" 2>&1
  )"

  assert_contains "$output" "--dangerously-skip-permissions" "no --agent should use dangerous flag for backward compat"
  assert_not_contains "$output" "Agent:" "no --agent should not show agent line"
}

test_agent_nonexistent_errors() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-missing"
  mkdir -p "$workdir"

  local output
  output="$(
    cd "$REPO_ROOT"
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --agent nonexistent --dry-run -p "hello" -C "$workdir" 2>&1 || true
  )"

  assert_contains "$output" "Agent profile not found: nonexistent" "missing agent should produce clear error"
}

test_agent_codex_sandbox_inference() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-sandbox"
  mkdir -p "$workdir"

  local output
  output="$(
    cd "$REPO_ROOT"
    FAKE_ARGS_LOG="$test_tmp/args-sandbox.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-sandbox.log" \
    PATH="$test_tmp/bin:$PATH" "$RUNNER" --agent reviewer --model gpt-5.3-codex --dry-run -p "Review" -C "$workdir" 2>&1
  )"

  # Reviewer has explicit sandbox: danger-full-access, so codex should use that
  assert_contains "$output" "--sandbox danger-full-access" "codex should translate agent sandbox to CLI flag"
  assert_not_contains "$output" "--dangerously-bypass-approvals-and-sandbox" "agent with sandbox should not use bypass flag"
}

test_run_id_is_compact() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-runid"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-agent-runid.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-agent-runid.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --agent reviewer --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  local run_id
  run_id="$(basename "$run_dir")"

  if [[ ! "$run_id" =~ ^[0-9]{8}T[0-9]{6}Z__[0-9]+[0-9a-f]{4}$ ]]; then
    fail "  run ID should use compact timestamp+suffix format"$'\n'"  Got: $run_id"
  fi
  assert_not_contains "$run_id" "reviewer" "compact run ID should not embed agent name"
  assert_not_contains "$run_id" "gpt-5.3-codex" "compact run ID should not embed model name"
}

test_agent_recorded_in_params_and_index() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-agent-params"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-agent-params.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-agent-params.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --agent reviewer --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"

  # Check params.json
  local agent_in_params
  agent_in_params="$(jq -r '.agent' "$run_dir/params.json")"
  assert_eq "$agent_in_params" "reviewer" "params.json should record agent name"

  local tools_in_params
  tools_in_params="$(jq -r '.tools' "$run_dir/params.json")"
  assert_contains "$tools_in_params" "Read" "params.json should record agent tools"

  local sandbox_in_params
  sandbox_in_params="$(jq -r '.sandbox' "$run_dir/params.json")"
  assert_eq "$sandbox_in_params" "danger-full-access" "params.json should record agent sandbox"

  # Check index start row (use raw JSONL, not pretty-printed jq)
  local index_raw
  index_raw="$(head -1 "$workdir/.orchestrate/index/runs.jsonl")"
  assert_contains "$index_raw" "\"agent\":\"reviewer\"" "index start row should contain agent field"
}

test_run_index_files_regenerates_from_output_log() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-files-fallback"
  mkdir -p "$workdir"

  cat > "$test_tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null || true
echo '{"thread_id":"thread-files-fallback"}'
echo '{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"text","text":"Touched src/app.ts and README.md"}]}}'
echo '{"file_path":"src/app.ts"}'
echo '{"path":"README.md"}'
EOF
  chmod +x "$test_tmp/bin/codex"

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"

  # Force cmd_files() to derive from output.jsonl.
  rm -f "$run_dir/files-touched.txt" "$run_dir/files-touched.nul"

  local output
  output="$(
    cd "$workdir"
    "$INDEX" files @latest
  )"

  assert_contains "$output" "src/app.ts" "run-index files should extract paths from output log when artifacts are missing"
  assert_contains "$output" "README.md" "run-index files should include README.md from output log extraction"
  assert_file_exists "$run_dir/files-touched.txt" "run-index files should regenerate files-touched.txt"
  assert_file_exists "$run_dir/files-touched.nul" "run-index files should regenerate files-touched.nul"
}

test_run_index_logs_default_shows_last_message_and_flags() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-logs-default"
  mkdir -p "$workdir"
  setup_fake_cli_bin "$test_tmp/bin"

  FAKE_ARGS_LOG="$test_tmp/args-logs-default.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-logs-default.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local output
  output="$(
    cd "$workdir"
    "$INDEX" logs @latest
  )"

  assert_contains "$output" "base" "run-index logs default should print the last assistant message"
  assert_contains "$output" "Other logs flags:" "run-index logs default should show available flags"
  assert_contains "$output" "--limit N          Messages per page (default: 1)" "run-index logs default should state --limit default"
  assert_contains "$output" "--cursor N         Offset from newest message (default: 0)" "run-index logs default should state --cursor default"
}

test_run_index_logs_cursor_and_limit_page_messages() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-logs-pagination"
  mkdir -p "$workdir"

  cat > "$test_tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null || true
echo '{"thread_id":"thread-logs-pagination"}'
echo '{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"text","text":"first assistant message"}]}}'
echo '{"type":"item.completed","item":{"type":"message","role":"assistant","content":[{"type":"text","text":"second assistant message"}]}}'
EOF
  chmod +x "$test_tmp/bin/codex"

  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "hello" -C "$workdir" >/dev/null 2>/dev/null

  local latest_output older_output
  latest_output="$(
    cd "$workdir"
    "$INDEX" logs @latest --limit 1
  )"
  older_output="$(
    cd "$workdir"
    "$INDEX" logs @latest --limit 1 --cursor 1
  )"

  assert_contains "$latest_output" "second assistant message" "cursor=0 should return the newest assistant message"
  assert_not_contains "$latest_output" "first assistant message" "cursor=0 should not include older message when limit=1"
  assert_contains "$older_output" "first assistant message" "cursor=1 should return the next older assistant message"
  assert_not_contains "$older_output" "second assistant message" "cursor=1 should not include newest message when limit=1"
}

main() {
  local test_tmp
  test_tmp="$(mktemp -d)"
  trap "rm -rf '$test_tmp'" EXIT

  setup_fake_cli_bin "$test_tmp/bin"

  run_test test_missing_option_value_is_friendly "$test_tmp"
  run_test test_run_writes_output_log_under_run_dir "$test_tmp"
  run_test test_continuation_uses_codex_resume_and_sets_metadata "$test_tmp"
  run_test test_retry_uses_original_prompt_and_records_retries "$test_tmp"
  run_test test_codex_explicit_fork_fails_fast "$test_tmp"
  run_test test_claude_empty_output_fails_fast "$test_tmp"
  run_test test_opencode_error_event_fails_fast "$test_tmp"
  run_test test_timeout_kills_hung_harness "$test_tmp"
  run_test test_orchestrate_config_template_is_auto_created "$test_tmp"
  run_test test_pinned_skills_load_from_config "$test_tmp"
  run_test test_pinned_skills_multiline_array_loads "$test_tmp"
  run_test test_pinned_skills_hash_in_quotes_is_not_treated_as_comment "$test_tmp"
  run_test test_strict_skills_errors_on_unknown_skills "$test_tmp"
  run_test test_invalid_args_do_not_create_runtime_dirs "$test_tmp"
  run_test test_help_flags_exit_zero "$test_tmp"

  # Agent profile tests
  run_test test_agent_dry_run_shows_correct_metadata "$test_tmp"
  run_test test_agent_cli_model_overrides_profile "$test_tmp"
  run_test test_agent_coder_unrestricted "$test_tmp"
  run_test test_no_agent_backward_compat "$test_tmp"
  run_test test_agent_nonexistent_errors "$test_tmp"
  run_test test_agent_codex_sandbox_inference "$test_tmp"
  run_test test_run_id_is_compact "$test_tmp"
  run_test test_agent_recorded_in_params_and_index "$test_tmp"
  run_test test_run_index_files_regenerates_from_output_log "$test_tmp"
  run_test test_run_index_logs_default_shows_last_message_and_flags "$test_tmp"
  run_test test_run_index_logs_cursor_and_limit_page_messages "$test_tmp"

  finish_tests "run-agent unit tests"
}

main "$@"
