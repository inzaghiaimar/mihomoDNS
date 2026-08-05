#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

completion="$(bash "$PROJECT_DIR/scripts/core/clashctl.sh" completion zsh)"

if printf '%s\n' "$completion" | grep -Eq '(^|[[:space:]])compinit([[:space:]]|$)'; then
  echo "not ok - zsh completion should not run compinit from project startup" >&2
  exit 1
fi

if ! printf '%s\n' "$completion" | grep -Fq 'bashcompinit'; then
  echo "not ok - zsh completion should still bridge bash completions when available" >&2
  exit 1
fi

if ! printf '%s\n' "$completion" | grep -Fq 'command -v compdef'; then
  echo "not ok - zsh completion should guard compdef availability" >&2
  exit 1
fi

echo "ok - zsh completion is non-invasive"
