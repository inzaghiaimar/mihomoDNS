#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

test_unit_file="$tmp_dir/clash-for-linux.service"

service_unit_name() { printf 'clash-for-linux.service\n'; }

run_case() {
  local name="$1"
  local expected="$2"
  local content="$3"

  printf '%s\n' "$content" > "$test_unit_file"

  case "$expected" in
    stale)
      if ! systemd_unit_has_stale_runtime_template "$test_unit_file"; then
        echo "not ok - $name: stale unit was not detected" >&2
        return 1
      fi
      ;;
    fresh)
      if systemd_unit_has_stale_runtime_template "$test_unit_file"; then
        echo "not ok - $name: fresh unit was marked stale" >&2
        return 1
      fi
      ;;
    *)
      echo "not ok - bad expected value: $expected" >&2
      return 1
      ;;
  esac

  echo "ok - $name"
}

run_case "detects forking type" stale '[Service]
Type=forking
ExecStart=/usr/local/bin/clashctl run-direct'

run_case "detects pid file" stale '[Service]
Type=simple
PIDFile=/tmp/mihomo.pid
ExecStart=/usr/local/bin/clashctl run-direct'

run_case "detects old start direct command" stale '[Service]
Type=simple
ExecStart=/usr/local/bin/clashctl start-direct'

run_case "accepts current run direct template" fresh '[Service]
Type=simple
ExecStart=/usr/local/bin/clashctl run-direct
ExecStopPost=/bin/rm -f /tmp/mihomo.pid'

systemd_unit_file_path() { printf '%s\n' "$test_unit_file"; }
systemd_user_unit_file_path() { printf '%s\n' "$test_unit_file"; }

printf '%s\n' '[Service]
Type=forking
PIDFile=/tmp/mihomo.pid
ExecStart=/usr/local/bin/clashctl start-direct' > "$test_unit_file"

output="$(systemd_unit_stale_runtime_template_warning systemd)"
if ! printf '%s\n' "$output" | grep -Fq "systemd 服务文件仍是旧模板"; then
  echo "not ok - systemd warning missing" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

output="$(systemd_unit_stale_runtime_template_warning systemd-user)"
if ! printf '%s\n' "$output" | grep -Fq "用户级 systemd 服务文件仍是旧模板"; then
  echo "not ok - systemd-user warning missing" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "ok - stale unit warning text"
