#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RUNNER="$REPO_ROOT/skills/run-agent/scripts/run-agent.sh"
INDEX="$REPO_ROOT/skills/run-agent/scripts/run-index.sh"

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$msg"$'\n'"Unexpectedly found: $needle"$'\n'"In output:"$'\n'"$haystack"
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
cat >/dev/null || true
echo '{"type":"result","session_id":"claude-session","result":{"text":"ok"}}'
EOF

  cat > "$bin_dir/opencode" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null || true
echo '{"type":"assistant","sessionID":"opencode-session","content":"ok"}'
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
  "$RUNNER" --model gpt-5.3-codex --prompt "hello" -C "$workdir" >/dev/null 2>"$test_tmp/run.log"

  local run_dir
  run_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  assert_file_exists "$run_dir/output.jsonl" "run should write output.jsonl inside the run directory"
  assert_not_contains "$(cat "$test_tmp/run.log")" "/output.jsonl: Permission denied" "run should not attempt writing output.jsonl at filesystem root"
}

test_continuation_uses_codex_resume_and_sets_metadata() {
  local test_tmp="$1"
  local workdir="$test_tmp/work-continue"
  mkdir -p "$workdir"

  FAKE_ARGS_LOG="$test_tmp/args-continue.log" \
  FAKE_STDIN_LOG="$test_tmp/stdin-continue.log" \
  PATH="$test_tmp/bin:$PATH" \
  "$RUNNER" --model gpt-5.3-codex --prompt "first prompt" -C "$workdir" >/dev/null

  sleep 1

  (
    cd "$workdir"
    FAKE_ARGS_LOG="$test_tmp/args-continue.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-continue.log" \
    PATH="$test_tmp/bin:$PATH" \
    "$INDEX" continue @latest -p "follow up"
  ) >/dev/null

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
  "$RUNNER" --model gpt-5.3-codex --prompt "original prompt" -C "$workdir" >/dev/null

  sleep 1

  (
    cd "$workdir"
    FAKE_ARGS_LOG="$test_tmp/args-retry.log" \
    FAKE_STDIN_LOG="$test_tmp/stdin-retry.log" \
    PATH="$test_tmp/bin:$PATH" \
    "$INDEX" retry @latest
  ) >/dev/null

  local latest_dir
  latest_dir="$(find "$workdir/.orchestrate/runs/agent-runs" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1)"
  local input_md
  input_md="$(cat "$latest_dir/input.md")"
  assert_contains "$input_md" "original prompt" "retry should preserve the original prompt content"
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
  "$RUNNER" --model gpt-5.3-codex --prompt "first prompt" -C "$workdir" >/dev/null

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

main() {
  local test_tmp
  test_tmp="$(mktemp -d)"
  trap "rm -rf '$test_tmp'" EXIT

  setup_fake_cli_bin "$test_tmp/bin"

  test_missing_option_value_is_friendly "$test_tmp"
  test_run_writes_output_log_under_run_dir "$test_tmp"
  test_continuation_uses_codex_resume_and_sets_metadata "$test_tmp"
  test_retry_uses_original_prompt_and_records_retries "$test_tmp"
  test_codex_explicit_fork_fails_fast "$test_tmp"

  echo "PASS: run-agent script unit tests"
}

main "$@"
