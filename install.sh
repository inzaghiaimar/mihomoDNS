#!/usr/bin/env bash
# install.sh — mihomoDNS 一键安装主入口
# 合并 clash-for-linux（代理）与 mosdns（DNS 分流），并按机场个性化配置。
#
# 用法:
#   bash install.sh                          # 交互式选择机场
#   bash install.sh --airport generic        # 指定机场
#   bash install.sh --airport hysteria2 --subscription-url https://...
#   bash install.sh --list-airports          # 列出可选机场
#   bash install.sh --only clash|mosdns      # 只装其中一个
#   bash install.sh --skip-start             # 装完不自动启动
#   bash install.sh --config-only             # 仅生成配置，不下载二进制
#   bash install.sh --dry-run                # 演练，只打印不执行
#   bash install.sh -v / --verbose           # 详细日志（打印每条命令）
#   bash install.sh --log-file /path/to.log  # 指定日志文件
#   bash install.sh --no-color               # 关闭颜色输出
#   bash install.sh --skip-network-check     # 跳过 GitHub 连通性预检
set -euo pipefail
# 兼容 CRLF（Windows 编辑后传到 Linux）
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
# shellcheck source=scripts/route.sh
source "$PROJECT_DIR/scripts/route.sh"

# ============ 参数解析 ============
ARG_AIRPORT=""
ARG_SUBSCRIPTION_URL=""
ARG_ONLY=""
ARG_SKIP_START=false
ARG_LIST_AIRPORTS=false
ARG_HELP=false
ARG_CONFIG_ONLY=false
ARG_DRY_RUN=false
ARG_VERBOSE=false
ARG_LOG_FILE=""
ARG_NO_COLOR=false
ARG_SKIP_NETWORK=false
ARG_ROUTE_TARGET=""
ARG_ROUTE_CLEAN=false
ARG_ROUTE_GATEWAY=""
ARG_ROUTE_LAN_IP=""
ARG_ROUTE_LAN_IF=""
ARG_ROUTE_LAN_CIDR=""
ARG_ROUTE_SSH_HOST=""
ARG_ROUTE_IKUAI_HOST=""

print_usage() {
  cat <<EOF
mihomoDNS 一键安装（clash-for-linux + mosdns）

用法:
  bash install.sh [选项]

选项:
  --airport <name>             指定机场预设（见 airports/），默认交互选择或 default
  --subscription-url <url>     订阅链接（覆盖机场预设里的订阅）
  --only <clash|mosdns>        只安装其中一个组件
  --skip-start                 仅安装，不自动启动服务
  --config-only                仅生成配置（机场/.env/mixin/mosdns），不下载二进制
  --dry-run                    演练模式，只打印将要执行的步骤，不实际改动
  -v, --verbose                详细日志（打印执行的每条命令）
  --log-file <path>            指定日志文件路径（默认 runtime/install-<时间>.log）
  --no-color                   关闭彩色输出
  --skip-network-check         跳过 GitHub 连通性预检
  --list-airports              列出可选机场预设后退出
  --route-target <linux|ros|ikuai>  安装后写入静态路由（Linux本机/ROS/爱快）
  --route-clean                删除已写入的静态路由（配合 --route-target）
  --route-gateway <ip>         主路由 LAN IP（如 192.168.1.1）
  --route-lan-ip <ip>          本机 LAN IP（如 192.168.1.2）
  --route-lan-if <if>          本机网卡（如 eth0，linux 目标可自动探测）
  --route-lan-cidr <cidr>      本机网段（如 192.168.1.0/24）
  --route-ssh-host <ip>        ROS SSH 主机（ros 目标用）
  --route-ikuai-host <ip>      爱快后台地址（ikuai 目标用）
  -h, --help                   显示帮助

示例:
  bash install.sh --airport generic --subscription-url https://example.com/sub
  bash install.sh --airport hysteria2
  bash install.sh --dry-run --airport streaming
  bash install.sh -v --log-file /tmp/mihomo.log
  bash install.sh --route-target linux --route-gateway 192.168.1.1
  bash install.sh --route-target ros --route-lan-ip 192.168.1.2 --route-ssh-host 192.168.1.1
  bash install.sh --route-target ikuai --route-clean
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --airport) ARG_AIRPORT="$2"; shift 2 ;;
    --subscription-url) ARG_SUBSCRIPTION_URL="$2"; shift 2 ;;
    --only) ARG_ONLY="$2"; shift 2 ;;
    --skip-start) ARG_SKIP_START=true; shift ;;
    --config-only) ARG_CONFIG_ONLY=true; shift ;;
    --dry-run) ARG_DRY_RUN=true; shift ;;
    -v|--verbose) ARG_VERBOSE=true; shift ;;
    --log-file) ARG_LOG_FILE="$2"; shift 2 ;;
    --no-color) ARG_NO_COLOR=true; shift ;;
    --skip-network-check) ARG_SKIP_NETWORK=true; shift ;;
    --list-airports) ARG_LIST_AIRPORTS=true; shift ;;
    --route-target) ARG_ROUTE_TARGET="$2"; shift 2 ;;
    --route-clean) ARG_ROUTE_CLEAN=true; shift ;;
    --route-gateway) ARG_ROUTE_GATEWAY="$2"; shift 2 ;;
    --route-lan-ip) ARG_ROUTE_LAN_IP="$2"; shift 2 ;;
    --route-lan-if) ARG_ROUTE_LAN_IF="$2"; shift 2 ;;
    --route-lan-cidr) ARG_ROUTE_LAN_CIDR="$2"; shift 2 ;;
    --route-ssh-host) ARG_ROUTE_SSH_HOST="$2"; shift 2 ;;
    --route-ssh-port) ROUTE_SSH_PORT="$2"; shift 2 ;;
    --route-ssh-user) ROUTE_SSH_USER="$2"; shift 2 ;;
    --route-ikuai-host) ARG_ROUTE_IKUAI_HOST="$2"; shift 2 ;;
    --route-ikuai-user) ROUTE_IKUAI_USER="$2"; shift 2 ;;
    -h|--help) ARG_HELP=true; shift ;;
    *) error "未知参数：$1"; print_usage >&2; exit 1 ;;
  esac
done

# 关闭颜色
if $ARG_NO_COLOR; then
  C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''; C_RESET=''
fi

# verbose
if $ARG_VERBOSE; then verbose_on; fi

# ============ 早期分支：help / list-airports ============
if $ARG_HELP; then print_usage; exit 0; fi

if $ARG_LIST_AIRPORTS; then
  echo "可用机场预设（airports/*.conf）："
  list_airports || echo "  （无）"
  exit 0
fi

# ============ 主流程 ============
main() {
  # 1) 日志文件初始化
  local ts; ts="$(date '+%Y%m%d-%H%M%S')"
  local default_log="$PROJECT_DIR/runtime/install-${ts}.log"
  init_log_file "${ARG_LOG_FILE:-$default_log}"

  # 2) 全局错误捕获（注册 trap）
  trap trap_errors ERR

  # 3) 加载 .env（提前配置时用）
  load_env

  echo
  log "${C_CYAN}╔══════════════════════════════════════════════════╗${C_RESET}"
  log "${C_CYAN}║   mihomoDNS 一键安装（clash + mosdns 联动）       ║${C_RESET}"
  log "${C_CYAN}╚══════════════════════════════════════════════════╝${C_RESET}"
  info "项目目录: $PROJECT_DIR"
  info "日志文件: $LOG_FILE"
  $ARG_DRY_RUN && warn "DRY-RUN 模式：仅打印，不执行实际安装"
  echo

  # 4) 前置环境检查
  run_step "前置依赖检查" preflight_checks

  # 5) 确保子项目就位
  #    本仓库已 vendored 子项目源码（clash-for-linux/ mosdns/）。
  #    若目录缺失（如只 clone 了主仓库未带子目录），自动从上游克隆补齐。
  run_step "子项目就位检查" ensure_subprojects

  # 6) 选机场
  step "选择机场配置"
  select_airport

  # 命令行订阅链接覆盖
  if [[ -n "$ARG_SUBSCRIPTION_URL" ]]; then
    AIRPORT_SUBSCRIPTION_URL="$ARG_SUBSCRIPTION_URL"
    info "使用命令行传入的订阅链接"
  fi

  # 订阅缺失时给提示
  if [[ -z "$AIRPORT_SUBSCRIPTION_URL" ]]; then
    warn "尚未配置订阅链接 AIRPORT_SUBSCRIPTION_URL"
    info "可继续安装，clash-for-linux 会在安装时交互询问订阅"
    $ARG_DRY_RUN || {
      if ! confirm "是否继续？" "n"; then die "已取消"; fi
    }
  fi

  # 7) 生成配置（.env / mixin / mosdns）
  run_step "写回 .env 与生成 clash mixin" apply_airport_to_env
  run_step "生成 clash mixin（机场覆盖）" generate_clash_mixin_for_airport
  run_step "生成 mosdns 配置" generate_mosdns_config_for_airport

  # 8) 安装（--config-only / --dry-run 跳过二进制安装）
  if $ARG_CONFIG_ONLY; then
    echo
    info "已使用 --config-only：仅完成配置生成，未下载安装二进制/启动服务"
    info "Linux 目标机上可去掉 --config-only 重新执行："
    echo "  bash install.sh --airport ${AIRPORT_ID}"
  elif $ARG_DRY_RUN; then
    echo
    info "DRY-RUN：以下步骤将被跳过（实际安装会执行）："
    echo "  - install_clash（调用 clash-for-linux install.sh）"
    echo "  - install_mosdns（下载 mosdns 二进制 + systemd unit）"
    echo "  - start_clash / start_mosdns / integration_check"
  else
    if [[ "$ARG_ONLY" == "" || "$ARG_ONLY" == "clash" ]]; then
      run_step "安装 clash-for-linux" install_clash
    fi
    if [[ "$ARG_ONLY" == "" || "$ARG_ONLY" == "mosdns" ]]; then
      run_step "安装 mosdns 二进制" install_mosdns
      run_step "安装 mosdns systemd 服务" install_mosdns_service
    fi

    # 9) 启动 & 联动检查
    if ! $ARG_SKIP_START; then
      run_step "启动 clash" start_clash
      run_step "启动 mosdns" start_mosdns
      sleep 2
      run_step "联动健康检查" integration_check
      hint_system_dns
    fi
  fi

  # 10) 静态路由（与 ROS / 爱快 / Linux 主路由配合）
  if [[ -n "$ARG_ROUTE_TARGET" ]]; then
    apply_route_args_to_env
    if $ARG_ROUTE_CLEAN; then
      run_step "删除静态路由（${ROUTE_TARGET}）" route_clean
    else
      run_step "写入静态路由（${ROUTE_TARGET}）" route_apply
    fi
  fi

  echo
  success "mihomoDNS 安装完成"
  echo
  log "常用命令："
  echo "  clash              # clash 管理（select / mode / mixin / doctor …）"
  echo "  clashon / clashoff # 开关代理"
  echo "  systemctl status mosdns   # mosdns 服务状态（systemd 安装时）"
  echo "  bash $PROJECT_DIR/scripts/integrate.sh check   # 重新检查联动"
  echo "  bash $PROJECT_DIR/scripts/route.sh apply --target linux   # 写入静态路由"
  echo "  bash $PROJECT_DIR/scripts/route.sh clean --target linux   # 删除静态路由"
  echo "  tail -f $LOG_FILE    # 查看本次安装日志"
  echo
}

# 把命令行路由参数映射到 route.sh 使用的全局变量
apply_route_args_to_env() {
  [[ -n "$ARG_ROUTE_TARGET" ]] && ROUTE_TARGET="$ARG_ROUTE_TARGET"
  [[ -n "$ARG_ROUTE_GATEWAY" ]] && ROUTE_GATEWAY="$ARG_ROUTE_GATEWAY"
  [[ -n "$ARG_ROUTE_LAN_IP" ]] && ROUTE_LAN_IP="$ARG_ROUTE_LAN_IP"
  [[ -n "$ARG_ROUTE_LAN_IF" ]] && ROUTE_LAN_IF="$ARG_ROUTE_LAN_IF"
  [[ -n "$ARG_ROUTE_LAN_CIDR" ]] && ROUTE_LAN_CIDR="$ARG_ROUTE_LAN_CIDR"
  [[ -n "$ARG_ROUTE_SSH_HOST" ]] && ROUTE_SSH_HOST="$ARG_ROUTE_SSH_HOST"
  [[ -n "$ARG_ROUTE_IKUAI_HOST" ]] && ROUTE_IKUAI_HOST="$ARG_ROUTE_IKUAI_HOST"
  return 0
}

# ============ 前置检查 ============
preflight_checks() {
  # 依赖命令：bash/tar 必需；curl/wget 至少一个（二选一）
  require_cmds bash tar || return 1
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    error "需要 curl 或 wget 至少一个"
    info "请安装：apt-get install -y curl   或   apt-get install -y wget"
    return 1
  fi
  success "依赖命令检查通过"

  # 系统信息
  local os arch
  os="$(detect_os 2>/dev/null || echo unknown)"
  arch="$(detect_arch 2>/dev/null || echo unknown)"
  info "系统: ${os} / 架构: ${arch} / root: $([[ ${EUID:-$(id -u)} -eq 0 ]] && echo yes || echo no)"

  # 非 Linux 直接终止（本项目面向 Linux）；--dry-run 放行以便预览
  if [[ "$os" != "linux" ]] && ! $ARG_DRY_RUN; then
    die "本项目仅支持 Linux（当前：${os}）。请在 Linux 目标机上执行。"
  fi
  if [[ "$os" != "linux" ]] && $ARG_DRY_RUN; then
    warn "当前为 ${os}（DRY-RUN 模式下放行，仅预览；实际安装请在 Linux 上执行）"
  fi

  # 网络连通性预检
  if ! $ARG_SKIP_NETWORK && ! $ARG_DRY_RUN; then
    step "检查 GitHub 连通性"
    if check_network "https://github.com"; then
      success "GitHub 可达"
    else
      warn "GitHub 直连不可达，将使用 CLASH_GH_PROXY=$CLASH_GH_PROXY 加速"
      info "如加速也不可用，可通过 --skip-network-check 跳过本预检"
    fi
  fi

  return 0
}

# ============ 机场选择 ============
select_airport() {
  if [[ -n "$ARG_AIRPORT" ]]; then
    load_airport "$ARG_AIRPORT"
    return
  fi
  if [[ -n "${CLASH_SUBSCRIPTION_URL:-}" || -n "${AIRPORT_ID:-}" ]]; then
    if [[ -n "${AIRPORT_ID:-}" ]]; then
      load_airport "$AIRPORT_ID"
      return
    fi
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
    return
  fi
  # 交互
  if $ARG_DRY_RUN; then
    info "DRY-RUN：跳过交互式选择，使用 default"
    load_airport default
    return
  fi
  pick_airport_interactive
}

main "$@"
