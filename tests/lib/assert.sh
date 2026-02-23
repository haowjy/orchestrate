#!/usr/bin/env bash
# tests/lib/assert.sh — Shared test runner and assertion helpers.
# Source this from test scripts. Provides:
#   - Assertion functions (assert_contains, assert_not_contains, assert_file_exists)
#   - Test runner with verbosity control (run_test, finish_tests)
#   - Default: quiet (only show failures). -v/--verbose: show all output.
#
# Usage:
#   source "$(dirname "$0")/lib/assert.sh"
#   parse_test_flags "$@"          # handles -v/--verbose
#
#   my_test() { assert_contains "abc" "b" "should find b"; }
#   run_test my_test "$test_tmp"
#   finish_tests

# ─── Verbosity ──────────────────────────────────────────────────────────────

_VERBOSE=false
_TEST_PASSED=0
_TEST_FAILED=0
_TEST_FAILURES=()

parse_test_flags() {
  for arg in "$@"; do
    case "$arg" in
      -v|--verbose) _VERBOSE=true ;;
    esac
  done
}

# ─── Assertions ─────────────────────────────────────────────────────────────

fail() {
  echo "$1" >&2
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "  $msg"$'\n'"  Expected to find: $needle"$'\n'"  In output (first 500 chars):"$'\n'"  ${haystack:0:500}"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "  $msg"$'\n'"  Unexpectedly found: $needle"$'\n'"  In output (first 500 chars):"$'\n'"  ${haystack:0:500}"
  fi
}

assert_file_exists() {
  local file="$1" msg="$2"
  [[ -f "$file" ]] || fail "  $msg: $file"
}

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "  $msg"$'\n'"  Expected: $expected"$'\n'"  Got:      $actual"
  fi
}

# ─── Test Runner ────────────────────────────────────────────────────────────
# Runs a test function, captures output, reports pass/fail.

run_test() {
  local test_fn="$1"
  shift

  # Capture to temp file instead of $() to avoid fd-inheritance hangs
  # from process substitutions (e.g. 2> >(tee ...)) in called scripts.
  if [[ "$_VERBOSE" == true ]]; then
    echo "  RUN   $test_fn"
  fi

  local _capture_file
  _capture_file="$(mktemp)"

  local exit_code=0
  ( $test_fn "$@" ) > "$_capture_file" 2>&1 || exit_code=$?

  local output=""
  if [[ -s "$_capture_file" ]]; then
    output="$(cat "$_capture_file")"
  fi
  rm -f "$_capture_file"

  if [[ $exit_code -eq 0 ]]; then
    (( _TEST_PASSED += 1 )) || true
    if [[ "$_VERBOSE" == true ]]; then
      echo "  PASS  $test_fn"
      if [[ -n "$output" ]]; then echo "$output" | sed 's/^/        /'; fi
    fi
  else
    (( _TEST_FAILED += 1 )) || true
    _TEST_FAILURES+=("$test_fn")
    echo "  FAIL  $test_fn"
    if [[ -n "$output" ]]; then echo "$output" | sed 's/^/        /'; fi
  fi
}

# Print summary and exit with appropriate code.
finish_tests() {
  local suite_name="${1:-tests}"
  local total=$(( _TEST_PASSED + _TEST_FAILED ))
  echo ""
  if [[ $_TEST_FAILED -eq 0 ]]; then
    echo "PASS: $suite_name ($total tests)"
  else
    echo "FAIL: $suite_name ($_TEST_FAILED/$total failed)"
    for f in "${_TEST_FAILURES[@]}"; do
      echo "  - $f"
    done
    exit 1
  fi
}
