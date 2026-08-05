#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ZSH_BIN="${ZSH_BIN:-$(command -v zsh 2>/dev/null || true)}"

if [ -z "$ZSH_BIN" ] || [ ! -x "$ZSH_BIN" ]; then
  echo "skip - zsh is not available"
  exit 0
fi

# shellcheck source=../core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

test_project="$tmp_dir/project"
FIXTURE_PROFILE_FILE="$tmp_dir/clash-for-linux.sh"
FIXTURE_ALIAS_FILE="$test_project/scripts/core/alias.sh"
FIXTURE_BIN_DIR="$tmp_dir/bin"
FIXTURE_ZSH_RC="$tmp_dir/etc/zsh/zshrc"

mkdir -p "$(dirname "$FIXTURE_ALIAS_FILE")" "$test_project/runtime" "$FIXTURE_BIN_DIR"
cp "$PROJECT_DIR/scripts/core/alias.sh" "$FIXTURE_ALIAS_FILE"

cat > "$test_project/runtime/config.yaml" <<'YAML'
mixed-port: 7890
YAML

cat > "$FIXTURE_BIN_DIR/clashctl-bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FIXTURE_BIN_DIR/clashctl-bin"

PROJECT_DIR="$test_project"
INSTALL_SCOPE="system"
cleanup_legacy_shell_entries() { :; }
profile_entry_file() { echo "$FIXTURE_PROFILE_FILE"; }
alias_source_file() { echo "$FIXTURE_ALIAS_FILE"; }
bash_completion_entry_file() { echo "$tmp_dir/completion.bash"; }
zsh_completion_entry_file() { echo "$tmp_dir/completion.zsh"; }
command_install_dir() { echo "$FIXTURE_BIN_DIR"; }
user_home_dir() { echo "$tmp_dir/home"; }
system_zsh_rc_file() { echo "$FIXTURE_ZSH_RC"; }
install_alias_command_wrappers() { :; }

install_shell_alias_entry

if ! output="$(
  env -i \
    HOME="$tmp_dir/home" \
    PATH="$FIXTURE_BIN_DIR:/usr/bin:/bin" \
    ZDOTDIR="$tmp_dir/home" \
    "$ZSH_BIN" -dfc '
      source "$1"
      [ "$(whence -w clashon 2>/dev/null || true)" = "clashon: function" ] || {
        echo "clashon is not a zsh function" >&2
        exit 1
      }

      clashon >/dev/null
      printf "%s\n" "$http_proxy"
      printf "%s\n" "$all_proxy"
    ' zsh "$FIXTURE_ZSH_RC" 2>&1
)"; then
  echo "not ok - zsh should load current-shell proxy functions" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

expected="$(printf '%s\n' \
  'http://127.0.0.1:7890' \
  'socks5://127.0.0.1:7890')"

if [ "$output" != "$expected" ]; then
  echo "not ok - zsh proxy variables did not update in the current shell" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$output" >&2
  exit 1
fi

if ! restore_output="$(
  env -i \
    HOME="$tmp_dir/home" \
    PATH="$FIXTURE_BIN_DIR:/usr/bin:/bin" \
    ZDOTDIR="$tmp_dir/home" \
    "$ZSH_BIN" -dfc '
      source "$1"
      printf "%s\n" "$http_proxy"

      clashoff >/dev/null
      if [ -n "${http_proxy+x}" ]; then
        echo "set"
      else
        echo "unset"
      fi
    ' zsh "$FIXTURE_ZSH_RC" 2>&1
)"; then
  echo "not ok - zsh should restore and clear current-shell proxy variables" >&2
  printf '%s\n' "$restore_output" >&2
  exit 1
fi

restore_expected="$(printf '%s\n' \
  'http://127.0.0.1:7890' \
  'unset')"

if [ "$restore_output" != "$restore_expected" ]; then
  echo "not ok - a new zsh session did not restore or clear proxy variables" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$restore_expected" "$restore_output" >&2
  exit 1
fi

remove_shell_alias_entry

if grep -Fq '# >>> clash-for-linux >>>' "$FIXTURE_ZSH_RC"; then
  echo "not ok - uninstall should remove the system zsh source block" >&2
  exit 1
fi

echo "ok - zsh updates, restores, and clears current-shell proxy variables"
