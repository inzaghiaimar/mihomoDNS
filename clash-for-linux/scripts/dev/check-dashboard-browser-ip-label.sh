#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE="$PROJECT_DIR/resources/dashboard/dist.zip"

[ -f "$ARCHIVE" ] || {
  echo "not ok - dashboard archive is missing: $ARCHIVE" >&2
  exit 1
}

bundle_text="$(unzip -p "$ARCHIVE" 'dist/assets/*.js')"

assert_bundle_contains() {
  local name="$1"
  local expected="$2"

  if ! grep -Fq "$expected" <<<"$bundle_text"; then
    echo "not ok - $name" >&2
    return 1
  fi
  echo "ok - $name"
}

assert_bundle_contains "dashboard identifies the browser egress IP" "浏览器出口 IP"
assert_bundle_contains \
  "dashboard explains that browser and backend proxy exits may differ" \
  "此处显示的是当前浏览器的出口 IP，可能与后端代理出口不同。"
assert_bundle_contains "dashboard includes the English browser-egress label" "Browser egress IP"
