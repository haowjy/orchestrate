#!/usr/bin/env bash
# lib.sh — Shared helpers for orchestrate hooks.
#
# Sourced by hook scripts. Provides project-root detection, hook-root
# resolution, and tracked-skills loading.

# find_project_root — walk up from CWD (or $1) looking for .git
find_project_root() {
  local dir="${1:-$PWD}"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# get_hook_root — resolve the hooks/ dir via BASH_SOURCE of the calling script
get_hook_root() {
  local caller="${BASH_SOURCE[1]}"
  local scripts_dir
  scripts_dir="$(cd "$(dirname "$caller")" && pwd)"
  # scripts/ is one level below hooks/
  dirname "$scripts_dir"
}

# load_tracked_skills — read .orchestrate/tracked-skills (one skill per line).
# Falls back to default list if the file doesn't exist.
# Usage: mapfile -t skills < <(load_tracked_skills "$project_root")
load_tracked_skills() {
  local project_root="$1"
  local tracked_file="$project_root/.orchestrate/tracked-skills"

  if [[ -f "$tracked_file" ]]; then
    while IFS= read -r line; do
      # Strip comments and whitespace
      line="${line%%#*}"
      line="$(echo "$line" | xargs)"
      [[ -z "$line" ]] && continue
      echo "$line"
    done < "$tracked_file"
  else
    # Default tracked skills
    echo "orchestrate"
    echo "run-agent"
  fi
}
