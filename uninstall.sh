#!/usr/bin/env bash
# uninstall.sh — 卸载 clash-mosdns
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR

# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh"
# shellcheck source=scripts/install-clash.sh
source "$PROJECT_DIR/scripts/install-clash.sh"
# shellcheck source=scripts/install-mosdns.sh
source "$PROJECT_DIR/scripts/install-mosdns.sh"
# shellcheck source=scripts/integrate.sh
source "$PROJECT_DIR/scripts/integrate.sh"

ARG_PURGE_RUNTIME=false
ARG_YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-runtime) ARG_PURGE_RUNTIME=true; shift ;;
    -y|--yes) ARG_YES=true; shift ;;
    -h|--help)
      cat <<EOF
卸载 clash-mosdns
用法: bash uninstall.sh [选项]
  --purge-runtime  连 runtime/ 运行目录一起删除
  -y, --yes       跳过确认
EOF
      exit 0 ;;
    *) error "未知参数：$1"; exit 1 ;;
  esac
done

if ! $ARG_YES; then
  warn "将卸载 clash-for-linux 与 mosdns"
  $ARG_PURGE_RUNTIME && warn "并删除运行目录 $RUNTIME_DIR"
  confirm "确认卸载？" "n" || die "已取消"
fi

stop_mosdns || true
stop_clash || true

uninstall_clash || true
uninstall_mosdns || true

if $ARG_PURGE_RUNTIME; then
  rm -rf "$RUNTIME_DIR" || true
  success "已删除运行目录 $RUNTIME_DIR"
fi

success "clash-mosdns 卸载完成"
