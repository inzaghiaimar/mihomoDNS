#!/usr/bin/env bash
# install.sh — clash-mosdns 一键安装主入口
# 合并 clash-for-linux（代理）与 mosdns（DNS 分流），并按机场个性化配置。
#
# 用法:
#   bash install.sh                          # 交互式选择机场
#   bash install.sh --airport generic        # 指定机场
#   bash install.sh --airport hysteria2 --subscription-url https://...
#   bash install.sh --list-airports          # 列出可选机场
#   bash install.sh --only clash|mosdns      # 只装其中一个
#   bash install.sh --skip-start             # 装完不自动启动
set -euo pipefail
sed -i 's/\r$//' "$0" 2>/dev/null || true

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR

# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh"
# shellcheck source=scripts/airport.sh
source "$PROJECT_DIR/scripts/airport.sh"
# shellcheck source=scripts/install-clash.sh
source "$PROJECT_DIR/scripts/install-clash.sh"
# shellcheck source=scripts/install-mosdns.sh
source "$PROJECT_DIR/scripts/install-mosdns.sh"
# shellcheck source=scripts/integrate.sh
source "$PROJECT_DIR/scripts/integrate.sh"

# ============ 参数解析 ============
ARG_AIRPORT=""
ARG_SUBSCRIPTION_URL=""
ARG_ONLY=""
ARG_SKIP_START=false
ARG_LIST_AIRPORTS=false
ARG_HELP=false
ARG_CONFIG_ONLY=false

print_usage() {
  cat <<EOF
clash-mosdns 一键安装（clash-for-linux + mosdns）

用法:
  bash install.sh [选项]

选项:
  --airport <name>             指定机场预设（见 airports/），默认交互选择或 default
  --subscription-url <url>     订阅链接（覆盖机场预设里的订阅）
  --only <clash|mosdns>        只安装其中一个组件
  --skip-start                 仅安装，不自动启动服务
  --config-only                仅生成配置（机场/.env/mixin/mosdns），不下载二进制
  --list-airports              列出可选机场预设后退出
  -h, --help                   显示帮助

示例:
  bash install.sh --airport generic --subscription-url https://example.com/sub
  bash install.sh --airport hysteria2
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --airport) ARG_AIRPORT="$2"; shift 2 ;;
    --subscription-url) ARG_SUBSCRIPTION_URL="$2"; shift 2 ;;
    --only) ARG_ONLY="$2"; shift 2 ;;
    --skip-start) ARG_SKIP_START=true; shift ;;
    --config-only) ARG_CONFIG_ONLY=true; shift ;;
    --list-airports) ARG_LIST_AIRPORTS=true; shift ;;
    -h|--help) ARG_HELP=true; shift ;;
    *) error "未知参数：$1"; print_usage >&2; exit 1 ;;
  esac
done

if $ARG_HELP; then print_usage; exit 0; fi

if $ARG_LIST_AIRPORTS; then
  echo "可用机场预设（airports/*.conf）："
  list_airports || echo "  （无）"
  exit 0
fi

# ============ 主流程 ============
main() {
  load_env

  echo
  log "${C_CYAN}╔══════════════════════════════════════════════════╗${C_RESET}"
  log "${C_CYAN}║   clash-mosdns 一键安装（clash + mosdns 联动）    ║${C_RESET}"
  log "${C_CYAN}╚══════════════════════════════════════════════════╝${C_RESET}"
  echo

  # 0) 确保子项目就位（本仓库不含子项目源码，运行时自动克隆）
  ensure_subprojects

  # 1) 选机场
  if [[ -n "$ARG_AIRPORT" ]]; then
    load_airport "$ARG_AIRPORT"
  elif [[ -n "${CLASH_SUBSCRIPTION_URL:-}" || -n "${AIRPORT_ID:-}" ]]; then
    # 已通过 .env 提前配置
    if [[ -n "${AIRPORT_ID:-}" ]]; then
      load_airport "$AIRPORT_ID"
    else
      AIRPORT_ID="default"; AIRPORT_NAME="环境变量配置"
      : "${AIRPORT_SUBSCRIPTION_URL:=$CLASH_SUBSCRIPTION_URL}"
      : "${AIRPORT_SUBSCRIPTION_UA:=${CLASH_SUBSCRIPTION_UA:-clash-verge/v2.4.0}}"
      : "${AIRPORT_IPV6:=${CLASH_IPV6:-auto}}"
      : "${AIRPORT_DNS_MODE:=fakeip}"
      : "${AIRPORT_KERNEL:=${KERNEL_TYPE:-mihomo}}"
      : "${AIRPORT_DOMESTIC_DNS:=223.5.5.5;119.29.29.29}"
      : "${AIRPORT_PROXY_DNS:=https://1.1.1.1/dns-query;tls://8.8.8.8:853}"
      : "${AIRPORT_RULES_EXTRA:=}"; : "${AIRPORT_PROXY_GROUPS_EXTRA:=}"
      : "${AIRPORT_TUN:=false}"; : "${AIRPORT_NOTES:=}"
      success "使用 .env 中的配置：$AIRPORT_NAME"
    fi
  else
    pick_airport_interactive
  fi

  # 命令行订阅链接覆盖
  if [[ -n "$ARG_SUBSCRIPTION_URL" ]]; then
    AIRPORT_SUBSCRIPTION_URL="$ARG_SUBSCRIPTION_URL"
    info "使用命令行传入的订阅链接"
  fi

  # 订阅缺失时给提示（clash 侧会在安装时再交互询问）
  if [[ -z "$AIRPORT_SUBSCRIPTION_URL" ]]; then
    warn "尚未配置订阅链接 AIRPORT_SUBSCRIPTION_URL"
    info "可继续安装，clash-for-linux 会在安装时交互询问订阅"
  fi

  # 2) 写回 .env 与生成配置
  apply_airport_to_env
  generate_clash_mixin_for_airport
  generate_mosdns_config_for_airport

  # 3) 安装（--config-only 时跳过二进制安装）
  if ! $ARG_CONFIG_ONLY; then
    if [[ "$ARG_ONLY" == "" || "$ARG_ONLY" == "clash" ]]; then
      install_clash
    fi
    if [[ "$ARG_ONLY" == "" || "$ARG_ONLY" == "mosdns" ]]; then
      install_mosdns
      install_mosdns_service
    fi

    # 4) 启动 & 联动检查
    if ! $ARG_SKIP_START; then
      start_clash
      start_mosdns
      sleep 2
      integration_check
      hint_system_dns
    fi
  else
    echo
    info "已使用 --config-only：仅完成配置生成，未下载安装二进制/启动服务"
    info "Linux 目标机上可去掉 --config-only 重新执行："
    echo "  bash install.sh --airport ${AIRPORT_ID}"
  fi

  echo
  success "clash-mosdns 安装完成"
  echo
  log "常用命令："
  echo "  clash              # clash 管理（select / mode / mixin / doctor …）"
  echo "  clashon / clashoff # 开关代理"
  echo "  systemctl status mosdns   # mosdns 服务状态（systemd 安装时）"
  echo "  bash $PROJECT_DIR/scripts/integrate.sh check   # 重新检查联动"
  echo
}

main "$@"
