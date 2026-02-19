#!/usr/bin/env bash
# install.sh — Install orchestrate skills for your CLI harness
#
# Usage:
#   ./scripts/install.sh [claude|codex|opencode]
#
# Claude Code: Registers as a plugin (recommended: use marketplace instead)
# Codex:       Symlinks skills/ into .agents/skills/ at repo root
# OpenCode:    Symlinks skills/ into .agents/skills/ at repo root (OpenCode reads .agents/)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

case "${1:-}" in
  claude)
    echo "Claude Code: Use the plugin marketplace:"
    echo "  /plugin marketplace add jimmyyao/orchestrate"
    echo ""
    echo "Or load directly:"
    echo "  claude --plugin-dir $PLUGIN_ROOT"
    ;;
  codex|opencode)
    TARGET="$REPO_ROOT/.agents"
    if [[ -d "$TARGET" ]] && [[ ! -L "$TARGET/skills" ]]; then
      # .agents/ exists but skills/ isn't a symlink — check if skills already there
      if [[ -d "$TARGET/skills/orchestrate" ]]; then
        echo "Already installed at $TARGET/skills/"
        exit 0
      fi
      # Symlink individual skill dirs into existing .agents/skills/
      mkdir -p "$TARGET/skills"
      for skill in "$PLUGIN_ROOT"/skills/*/; do
        name="$(basename "$skill")"
        ln -sfn "$skill" "$TARGET/skills/$name"
        echo "Linked: $TARGET/skills/$name -> $skill"
      done
    else
      # No .agents/ yet — symlink the whole skills/ dir
      mkdir -p "$TARGET"
      ln -sfn "$PLUGIN_ROOT/skills" "$TARGET/skills"
      echo "Linked: $TARGET/skills -> $PLUGIN_ROOT/skills"
    fi
    echo ""
    echo "Done. Skills available for $1 CLI."
    ;;
  *)
    echo "Usage: ./scripts/install.sh [claude|codex|opencode]"
    echo ""
    echo "  claude   — Show Claude Code plugin install instructions"
    echo "  codex    — Symlink skills into .agents/skills/ for Codex"
    echo "  opencode — Symlink skills into .agents/skills/ for OpenCode"
    exit 1
    ;;
esac
