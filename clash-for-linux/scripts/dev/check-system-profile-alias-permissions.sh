#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"

tmp_dir="$(mktemp -d)"
trap 'chmod 700 "$tmp_dir/private-project" 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT

test_project="$tmp_dir/private-project"
FIXTURE_PROFILE_FILE="$tmp_dir/clash-for-linux.sh"
FIXTURE_ALIAS_FILE="$test_project/scripts/core/alias.sh"

mkdir -p "$(dirname "$FIXTURE_ALIAS_FILE")"
cat > "$FIXTURE_ALIAS_FILE" <<'EOF'
export CLASH_ALIAS_FIXTURE_LOADED="true"
EOF

INSTALL_SCOPE="system"
cleanup_legacy_shell_entries() { :; }
profile_entry_file() { echo "$FIXTURE_PROFILE_FILE"; }
alias_source_file() { echo "$FIXTURE_ALIAS_FILE"; }
bash_completion_entry_file() { echo "$tmp_dir/completion.bash"; }
zsh_completion_entry_file() { echo "$tmp_dir/completion.zsh"; }
command_install_dir() { echo "$tmp_dir/bin"; }
user_home_dir() { echo "$tmp_dir/home"; }
install_rc_source_block() { :; }
install_alias_command_wrappers() { :; }

install_shell_alias_entry

readable_output="$(
  env -i PATH="$PATH" bash --noprofile --norc -c \
    'source "$1"; printf "%s" "${CLASH_ALIAS_FIXTURE_LOADED:-false}"' \
    bash "$FIXTURE_PROFILE_FILE"
)"

if [ "$readable_output" != "true" ]; then
  echo "not ok - readable system alias should still load" >&2
  exit 1
fi

chmod 000 "$test_project"

if ! restricted_output="$(
  env -i PATH="$PATH" bash --noprofile --norc -c 'source "$1"' bash "$FIXTURE_PROFILE_FILE" 2>&1
)"; then
  echo "not ok - unreadable system alias should not fail shell startup" >&2
  printf '%s\n' "$restricted_output" >&2
  exit 1
fi

if [ -n "$restricted_output" ]; then
  echo "not ok - unreadable system alias should not print a shell startup error" >&2
  printf '%s\n' "$restricted_output" >&2
  exit 1
fi

echo "ok - system profile skips an unreadable project alias"
