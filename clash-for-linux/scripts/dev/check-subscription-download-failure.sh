#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

RUNTIME_DIR="$tmp_dir/runtime"
mkdir -p "$RUNTIME_DIR"

export CLASH_AUTO_UPDATE_SUBSCRIPTIONS="true"

download_subscription_file() {
  return 28
}

subscription_cache_store() {
  echo "not ok - cache store called after failed subscription download" >&2
  return 0
}

if download_subscription_yaml "https://example.invalid/sub" "$tmp_dir/sub.yaml" "manual-refresh"; then
  echo "not ok - failed subscription download returned success" >&2
  exit 1
fi

if [ -e "$tmp_dir/sub.yaml" ]; then
  echo "not ok - failed subscription download left an output file" >&2
  exit 1
fi

echo "ok - failed subscription download returns failure"
