#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

test_project="$tmp_dir/project"
test_home="$tmp_dir/home"
output_file="$tmp_dir/uninstall-output"

mkdir -p "$test_project" "$test_home" "$test_project/runtime"
cp "$PROJECT_DIR/uninstall.sh" "$test_project/uninstall.sh"
cp -R "$PROJECT_DIR/scripts" "$test_project/scripts"
cp -R "$PROJECT_DIR/config" "$test_project/config"
cp "$PROJECT_DIR/.env" "$test_project/.env"

# Override external effects in the isolated fixture while preserving the real
# uninstall control flow and forcing the exact /etc/environment cleanup failure.
cat >> "$test_project/scripts/init/script.sh" <<'EOF'
boot_proxy_keep_disable() { return 2; }
system_proxy_env_file() { printf '%s\n' /etc/environment; }
clear_shell_proxy_persist_state() { :; }
stop_subconverter() { :; }
service_stop() { :; }
stop_runtime() { :; }
remove_runtime_entry() { :; }
remove_clashctl_entry() { :; }
remove_clashctl_completion() { :; }
remove_shell_alias_entry() { :; }
clear_controller_secret() { :; }
EOF

if env -i \
  HOME="$test_home" \
  PATH="/usr/bin:/bin" \
  bash "$test_project/uninstall.sh" > "$output_file" 2>&1; then
  echo "not ok - uninstall should fail when /etc/environment cleanup fails" >&2
  sed 's/^/  /' "$output_file" >&2
  exit 1
fi

if ! grep -Fq '[error]' "$output_file" || ! grep -Fq '/etc/environment' "$output_file"; then
  echo "not ok - uninstall should clearly report the system proxy cleanup error" >&2
  sed 's/^/  /' "$output_file" >&2
  exit 1
fi

if grep -Fq '[ok] 卸载完成' "$output_file"; then
  echo "not ok - uninstall must not claim success after system proxy cleanup fails" >&2
  sed 's/^/  /' "$output_file" >&2
  exit 1
fi

echo "ok - uninstall fails clearly when /etc/environment cleanup fails"
