#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

source "$SCRIPT_DIR/lib/assert.sh"
parse_test_flags "$@"

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
- plan-task
EOF

  # Default only.
  local out
  out="$("$root/scripts/load-skill-policy.sh")"
  assert_contains "$out" "run-agent" "default policy should be loaded when no custom files exist"
  assert_contains "$out" "plan-task" "default policy should include plan-task"

  # Add custom policy -> default ignored.
  cat > "$root/references/custom.md" <<'EOF'
# custom policy
- reviewing
researching
EOF
  out="$("$root/scripts/load-skill-policy.sh")"
  assert_contains "$out" "reviewing" "custom policy should be loaded when present"
  assert_not_contains "$out" "run-agent" "default policy should be ignored when custom exists"

  # Parsed skills should normalize comments and bullets and dedupe.
  cat > "$root/references/custom-2.md" <<'EOF'
reviewing
reviewing  # duplicate
- scratchpad
EOF

  # skills mode filters to installed sibling skills (../<name>/SKILL.md)
  mkdir -p "$tmp/reviewing" "$tmp/researching" "$tmp/scratchpad"
  : > "$tmp/reviewing/SKILL.md"
  : > "$tmp/researching/SKILL.md"
  : > "$tmp/scratchpad/SKILL.md"

  out="$("$root/scripts/load-skill-policy.sh" --mode skills)"
  assert_contains "$out" "reviewing" "skills mode should include normalized skill names"
  assert_contains "$out" "researching" "skills mode should include plain-line skills"
  assert_contains "$out" "scratchpad" "skills mode should include bullet-line skills"
}

main() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT

  run_test test_model_guidance_loader_precedence "$tmp"
  run_test test_skill_policy_loader_precedence_and_parse "$tmp"

  finish_tests "resource loader unit tests"
}

main "$@"
