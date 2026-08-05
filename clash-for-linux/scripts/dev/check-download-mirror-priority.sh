#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

RUNTIME_DIR="$tmp_dir/runtime"
mkdir -p "$RUNTIME_DIR"

unset CLASH_GH_PROXY
unset URL_GH_PROXY
unset CLASH_GH_PROXY_POOL

url="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
ordered_entries="$(
  github_mirror_candidate_entries_ordered "$url" \
    | sort -t'|' -k1,1nr \
    | cut -d'|' -f2-
)"

first_label="$(printf '%s\n' "$ordered_entries" | head -n 1 | cut -d'|' -f1)"
last_label="$(printf '%s\n' "$ordered_entries" | tail -n 1 | cut -d'|' -f1)"

if [ "$first_label" != "gh-proxy" ]; then
  echo "not ok - default mirror priority: first label is $first_label, expected gh-proxy" >&2
  printf '%s\n' "$ordered_entries" >&2
  exit 1
fi

if [ "$last_label" != "origin" ]; then
  echo "not ok - default mirror priority: last label is $last_label, expected origin" >&2
  printf '%s\n' "$ordered_entries" >&2
  exit 1
fi

echo "ok - default GitHub downloads prefer mirrors before origin"
