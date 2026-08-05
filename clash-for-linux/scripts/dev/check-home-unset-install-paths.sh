#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

output="$(
  env -u HOME bash -c '
    set -euo pipefail
    PROJECT_DIR="'"$PROJECT_DIR"'"
    source "$PROJECT_DIR/scripts/core/common.sh"
    init_project_context "$PROJECT_DIR"
    detect_install_scope user
    completion_dir
    profile_entry_file
    command_install_dir
  '
)"

if printf '%s\n' "$output" | grep -Eq '/\.config/clash-for-linux|/\.local/bin'; then
  echo "ok - user install paths resolve when HOME is unset"
else
  echo "not ok - missing user install path output" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
