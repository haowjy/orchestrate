#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$msg"$'\n'"Expected: $needle"$'\n'"Got:"$'\n'"$haystack"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$msg"$'\n'"Unexpected: $needle"$'\n'"Got:"$'\n'"$haystack"
  fi
}

test_model_guidance_loader_precedence() {
  local tmp="$1"
  local root="$tmp/model-guidance"
  mkdir -p "$root/scripts" "$root/references/model-guidance"
  cp "$REPO_ROOT/skills/run-agent/scripts/load-model-guidance.sh" "$root/scripts/load-model-guidance.sh"
  chmod +x "$root/scripts/load-model-guidance.sh"

  cat > "$root/references/default-model-guidance.md" <<'EOF'
DEFAULT_GUIDANCE
EOF

  # Default only -> default is used.
  local out
  out="$("$root/scripts/load-model-guidance.sh")"
  assert_contains "$out" "DEFAULT_GUIDANCE" "default guidance should be used when no custom files exist"

  # Add custom file -> custom wins and default is ignored.
  cat > "$root/references/model-guidance/custom.md" <<'EOF'
CUSTOM_GUIDANCE
EOF
  out="$("$root/scripts/load-model-guidance.sh")"
  assert_contains "$out" "CUSTOM_GUIDANCE" "custom guidance should be loaded when present"
  assert_not_contains "$out" "DEFAULT_GUIDANCE" "default guidance should be ignored when custom files exist"
}

test_skill_policy_loader_precedence_and_parse() {
  local tmp="$1"
  local root="$tmp/skill-policy"
  mkdir -p "$root/scripts" "$root/references"
  cp "$REPO_ROOT/skills/orchestrate/scripts/load-skill-policy.sh" "$root/scripts/load-skill-policy.sh"
  chmod +x "$root/scripts/load-skill-policy.sh"

  cat > "$root/references/default.md" <<'EOF'
# defaults
run-agent
- model-guidance
EOF

  # Default only.
  local out
  out="$("$root/scripts/load-skill-policy.sh")"
  assert_contains "$out" "run-agent" "default policy should be loaded when no custom files exist"
  assert_contains "$out" "model-guidance" "default policy should include model-guidance"

  # Add custom policy -> default ignored.
  cat > "$root/references/custom.md" <<'EOF'
# custom policy
- review
research
EOF
  out="$("$root/scripts/load-skill-policy.sh")"
  assert_contains "$out" "review" "custom policy should be loaded when present"
  assert_not_contains "$out" "run-agent" "default policy should be ignored when custom exists"

  # Parsed skills should normalize comments and bullets and dedupe.
  cat > "$root/references/custom-2.md" <<'EOF'
review
review  # duplicate
- smoke-test
EOF
  out="$("$root/scripts/load-skill-policy.sh" --mode skills)"
  assert_contains "$out" "review" "skills mode should include normalized skill names"
  assert_contains "$out" "research" "skills mode should include plain-line skills"
  assert_contains "$out" "smoke-test" "skills mode should include bullet-line skills"
}

main() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT

  test_model_guidance_loader_precedence "$tmp"
  test_skill_policy_loader_precedence_and_parse "$tmp"

  echo "PASS: resource loader unit tests"
}

main "$@"

