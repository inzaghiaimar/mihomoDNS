#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

assert_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"

  if ! grep -Fq "$pattern" "$file"; then
    echo "not ok - $name: missing '$pattern' in $file" >&2
    return 1
  fi

  echo "ok - $name"
}

assert_not_contains() {
  local name="$1"
  local file="$2"
  local pattern="$3"

  if grep -Fq "$pattern" "$file"; then
    echo "not ok - $name: unexpected '$pattern' in $file" >&2
    return 1
  fi

  echo "ok - $name"
}

assert_contains "system service uses simple foreground process" "$PROJECT_DIR/scripts/init/systemd.sh" "Type=simple"
assert_contains "system service starts run-direct" "$PROJECT_DIR/scripts/init/systemd.sh" "ExecStart=/usr/local/bin/clashctl run-direct"
assert_not_contains "system service no longer uses forking" "$PROJECT_DIR/scripts/init/systemd.sh" "Type=forking"
assert_not_contains "system service no longer relies on PIDFile" "$PROJECT_DIR/scripts/init/systemd.sh" "PIDFile="

assert_contains "user service uses simple foreground process" "$PROJECT_DIR/scripts/init/systemd-user.sh" "Type=simple"
assert_contains "user service starts run-direct" "$PROJECT_DIR/scripts/init/systemd-user.sh" "clashctl run-direct"
assert_not_contains "user service no longer uses forking" "$PROJECT_DIR/scripts/init/systemd-user.sh" "Type=forking"
assert_not_contains "user service no longer relies on PIDFile" "$PROJECT_DIR/scripts/init/systemd-user.sh" "PIDFile="
