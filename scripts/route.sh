#!/usr/bin/env bash
# route.sh — 静态路由表写入/删除（RouterOS/ROS、爱快 iKuai、Linux 三种目标）
#
# 用途：把发往 mosdns(:5335) 与 clash(:7890/:1053) 的流量从旁路由/客户端
#       正确引导到本机。典型场景：本机作为旁路由/DNS 服务器，ROS/爱快作为主路由，
#       需要在主路由上写静态路由把客户端的 DNS/代理流量指向本机，或反过来
#       把本机出网流量经主路由出去。
#
# 三种目标：
#   ros    — MikroTik RouterOS / ROS 软路由（通过 SSH+ROS CLI 或 REST API）
#   ikuai  — 爱快 iKuai 软路由（通过 Web 后台 API 或手动步骤指引）
#   linux  — 本机 Linux（通过 ip route 命令直接写入）
#
# 路由项（默认按需写入，可在 .env / 命令行覆盖）：
#   1) DNS 劫持：把客户端 53 端口流量引到本机 mosdns（通常用 DNAT，见下）
#   2) 旁路由回程：若本机作旁路由，主路由需把回程流量指向本机
#   3) 默认网关经主路由：本机默认路由指向主路由 LAN IP
#
# 说明：本脚本对 ROS/爱快只生成「可在其后台执行的命令清单」或经 SSH 自动执行，
#       不直接登录除非提供了 SSH 凭据。删除时生成对应的 remove 命令。

# ============ 路由参数（可被 .env / 命令行覆盖） ============
ROUTE_TARGET="${ROUTE_TARGET:-linux}"          # ros / ikuai / linux
ROUTE_GATEWAY="${ROUTE_GATEWAY:-}"             # 主路由 LAN IP（如 192.168.1.1）
ROUTE_LAN_IF="${ROUTE_LAN_IF:-}"               # 本机 LAN 网卡（如 eth0 / ens18）
ROUTE_LAN_IP="${ROUTE_LAN_IP:-}"               # 本机 LAN IP（如 192.168.1.2）
ROUTE_LAN_CIDR="${ROUTE_LAN_CIDR:-}"           # 本机所在网段（如 192.168.1.0/24）
ROUTE_DNS_HIJACK="${ROUTE_DNS_HIJACK:-true}"   # 是否劫持客户端 53 到本机 mosdns
ROUTE_SSH_HOST="${ROUTE_SSH_HOST:-}"           # ROS/爱快 SSH 主机
ROUTE_SSH_PORT="${ROUTE_SSH_PORT:-22}"
ROUTE_SSH_USER="${ROUTE_SSH_USER:-admin}"
ROUTE_IKUAI_HOST="${ROUTE_IKUAI_HOST:-}"        # 爱快 Web 后台地址
ROUTE_IKUAI_USER="${ROUTE_IKUAI_USER:-admin}"
ROUTE_IKUAI_PASS="${ROUTE_IKUAI_PASS:-}"

# ============ 解析本机 LAN 信息（linux 目标自动探测） ============
detect_lan_info() {
  # 无 ip 命令时跳过自动探测（非 Linux 环境）
  if ! command -v ip >/dev/null 2>&1; then
    info "LAN 探测: 无 ip 命令，跳过自动探测（当前值: IP=${ROUTE_LAN_IP:-?} 网关=${ROUTE_GATEWAY:-?}）"
    return 0
  fi
  if [[ -z "$ROUTE_LAN_IP" ]]; then
    # 取默认路由出口网卡的 IPv4
    local default_if
    default_if="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
    if [[ -n "$default_if" ]]; then
      ROUTE_LAN_IF="${ROUTE_LAN_IF:-$default_if}"
      ROUTE_LAN_IP="$(ip -4 addr show "$default_if" 2>/dev/null \
        | grep -oP 'inet \K[0-9.]+' | head -1)"
    fi
  fi
  if [[ -z "$ROUTE_GATEWAY" ]]; then
    ROUTE_GATEWAY="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
  fi
  if [[ -z "$ROUTE_LAN_CIDR" && -n "$ROUTE_LAN_IF" ]]; then
    local net
    net="$(ip -4 addr show "$ROUTE_LAN_IF" 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1)"
    if [[ -n "$net" ]]; then
      # 简单推导 /24 网段
      ROUTE_LAN_CIDR="${net%.*}.0/24"
    fi
  fi
  info "LAN 探测: 网卡=${ROUTE_LAN_IF:-?} 本机IP=${ROUTE_LAN_IP:-?} 网关=${ROUTE_GATEWAY:-?} 网段=${ROUTE_LAN_CIDR:-?}"
}

# ============ 校验必要参数 ============
validate_route_params() {
  local missing=()
  case "$ROUTE_TARGET" in
    linux)
      [[ -z "$ROUTE_LAN_IF" ]] && missing+=("ROUTE_LAN_IF")
      [[ -z "$ROUTE_GATEWAY" ]] && missing+=("ROUTE_GATEWAY")
      ;;
    ros)
      [[ -z "$ROUTE_SSH_HOST" ]] && missing+=("ROUTE_SSH_HOST")
      [[ -z "$ROUTE_LAN_IP" ]] && missing+=("ROUTE_LAN_IP")
      ;;
    ikuai)
      [[ -z "$ROUTE_IKUAI_HOST" ]] && missing+=("ROUTE_IKUAI_HOST")
      [[ -z "$ROUTE_LAN_IP" ]] && missing+=("ROUTE_LAN_IP")
      ;;
    *)
      die "未知 ROUTE_TARGET：$ROUTE_TARGET（支持 ros / ikuai / linux）"
      ;;
  esac
  if (( ${#missing[@]} > 0 )); then
    error "路由配置缺少参数：${missing[*]}"
    info "请在 .env 或命令行设置，例如："
    echo "  --route-gateway 192.168.1.1 --route-lan-ip 192.168.1.2"
    die "已终止"
  fi
}

# ============ Linux：本机静态路由写入 ============
route_linux_apply() {
  step "Linux 静态路由写入（本机）"
  validate_route_params
  if ! is_root; then
    warn "非 root，以下命令需 sudo 执行（已用 sudo 前缀）"
    local SUDO=sudo
  else
    local SUDO=""
  fi

  # 1) 默认网关经主路由（若当前默认路由不是主路由则添加）
  local cur_gw
  cur_gw="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
  if [[ "$cur_gw" != "$ROUTE_GATEWAY" ]]; then
    info "设置默认网关 → $ROUTE_GATEWAY"
    $SUDO ip route replace default via "$ROUTE_GATEWAY" dev "$ROUTE_LAN_IF"
    success "默认网关已设置"
  else
    success "默认网关已正确（$ROUTE_GATEWAY）"
  fi

  # 2) 关闭 rp_filter（旁路由场景防反向过滤丢包）
  if [[ "${ROUTE_DISABLE_RPFILTER:-true}" == "true" ]]; then
    info "关闭 rp_filter（all/default/$ROUTE_LAN_IF）"
    $SUDO sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1 || true
    $SUDO sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1 || true
    [[ -n "$ROUTE_LAN_IF" ]] && $SUDO sysctl -w "net.ipv4.conf.$ROUTE_LAN_IF.rp_filter=0" >/dev/null 2>&1 || true
    # 持久化
    if is_root; then
      cat > /etc/sysctl.d/99-mihomoDNS.conf <<EOF
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.ip_forward=1
EOF
      sysctl -p /etc/sysctl.d/99-mihomoDNS.conf >/dev/null 2>&1 || true
    fi
    success "rp_filter 已关闭，ip_forward 已开启"
  fi

  # 3) 开启 IP 转发（旁路由必须）
  $SUDO sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  success "Linux 静态路由写入完成"
}

route_linux_clean() {
  step "Linux 静态路由删除（本机）"
  if ! is_root; then local SUDO=sudo; else local SUDO=""; fi
  # 仅删除本项目写入的 sysctl 持久化文件
  $SUDO rm -f /etc/sysctl.d/99-mihomoDNS.conf
  info "已删除 /etc/sysctl.d/99-mihomoDNS.conf"
  warn "默认网关与 rp_filter 请按需手动恢复（脚本不擅自改回，避免断网）"
  warn "恢复 rp_filter: sysctl -w net.ipv4.conf.all.rp_filter=1"
  warn "恢复默认网关: ip route replace default via <原网关> dev $ROUTE_LAN_IF"
}

# ============ ROS / RouterOS：生成可在 ROS 执行的命令 ============
# ROS 静态路由：
#   /ip route add dst-address=0.0.0.0/0 gateway=<本机IP>           # 回程经本机
#   /ip firewall nat add chain=dstnat protocol=udp dst-port=53 action=dst-nat to-addresses=<本机IP> to-ports=5335
#   /ip firewall nat add chain=dstnat protocol=tcp dst-port=53 action=dst-nat to-addresses=<本机IP> to-ports=5335
route_ros_print() {
  step "ROS / RouterOS 静态路由命令（$1）"
  local action="$1"
  local gw="${ROUTE_LAN_IP:?ROUTE_LAN_IP 未设置}"
  echo
  if [[ "$action" == "add" ]]; then
    cat <<EOF
# ===== 在 ROS 主路由（${ROUTE_SSH_HOST:-<ROS后台>}）执行 =====
# 目的：让客户端 DNS(53) 流量自动指向本机 mosdns(:5335)，并把本机出网回程经 ROS
# 1) DNS 劫持：UDP/TCP 53 → 本机 5335
/ip firewall nat add chain=dstnat protocol=udp dst-port=53 action=dst-nat to-addresses=${gw} to-ports=${MOSDNS_DNS_PORT} comment="mihomoDNS-udp"
/ip firewall nat add chain=dstnat protocol=tcp dst-port=53 action=dst-nat to-addresses=${gw} to-ports=${MOSDNS_DNS_PORT} comment="mihomoDNS-tcp"
# 2) 若本机作旁路由，把需要走代理的网段回程指向本机（按需）
# /ip route add dst-address=${ROUTE_LAN_CIDR:-192.168.1.0/24} gateway=${gw} comment="mihomoDNS-route"
# 3) 若需把特定客户端全部流量经本机代理：
# /ip route add dst-address=<客户端IP>/32 gateway=${gw}
EOF
  else
    cat <<EOF
# ===== 在 ROS 主路由执行：删除 mihomoDNS 相关路由 =====
# 1) 删除 DNS 劫持 NAT 规则
/ip firewall nat remove [find comment~"mihomoDNS"]
# 2) 删除回程静态路由
/ip route remove [find comment="mihomoDNS-route"]
# 验证
/ip firewall nat print
/ip route print
EOF
  fi
  echo
  # 若提供 SSH 凭据则自动执行（dry-run 下跳过）
  if [[ -n "$ROUTE_SSH_HOST" ]]; then
    if $ARG_DRY_RUN; then
      info "DRY-RUN：跳过 SSH 自动执行（实际安装会询问）"
    elif confirm "是否通过 SSH 在 ROS(${ROUTE_SSH_HOST}) 自动执行以上命令？" "n"; then
      route_ros_ssh_exec "$action"
    else
      info "已跳过自动执行，请手动复制上方命令到 ROS 后台"
    fi
  else
    info "未提供 ROUTE_SSH_HOST，请手动复制上方命令到 ROS 后台执行"
  fi
}

# 经 SSH 在 ROS 执行（需要 sshpass 或密钥）
route_ros_ssh_exec() {
  local action="$1"
  require_cmds ssh || die "缺少 ssh 命令"
  local ssh_args=(-p "$ROUTE_SSH_PORT" "$ROUTE_SSH_USER@$ROUTE_SSH_HOST")
  local cmds
  if [[ "$action" == "add" ]]; then
    cmds="/ip firewall nat add chain=dstnat protocol=udp dst-port=53 action=dst-nat to-addresses=$ROUTE_LAN_IP to-ports=$MOSDNS_DNS_PORT comment=mihomoDNS-udp"
    cmds="$cmds; /ip firewall nat add chain=dstnat protocol=tcp dst-port=53 action=dst-nat to-addresses=$ROUTE_LAN_IP to-ports=$MOSDNS_DNS_PORT comment=mihomoDNS-tcp"
  else
    cmds="/ip firewall nat remove [find comment~\"mihomoDNS\"]"
  fi
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -e ssh -o StrictHostKeyChecking=no "${ssh_args[@]}" "$cmds"
  else
    warn "未安装 sshpass，将使用交互式 SSH（需手动输入密码）"
    ssh -o StrictHostKeyChecking=no "${ssh_args[@]}" "$cmds"
  fi
}

# ============ 爱快 iKuai：生成后台操作步骤与 API 调用 ============
route_ikuai_print() {
  step "爱快 iKuai 静态路由设置（$1）"
  local action="$1"
  local gw="${ROUTE_LAN_IP:?ROUTE_LAN_IP 未设置}"
  echo
  if [[ "$action" == "add" ]]; then
    cat <<EOF
# ===== 在爱快后台（${ROUTE_IKUAI_HOST:-<爱快后台地址>}）操作 =====
# 方式 A：Web 界面手动添加
#   1) DNS 劫持（端口转发）：流控分流 → 端口映射 → 添加
#      协议: UDP/TCP   外部端口: 53   内部IP: ${gw}   内部端口: ${MOSDNS_DNS_PORT}
#   2) 静态路由（可选，旁路由回程）：网络设置 → 路由设置 → 静态路由 → 添加
#      目标网段: ${ROUTE_LAN_CIDR:-192.168.1.0/24}   网关: ${gw}
#   3) 若需特定客户端全流量经本机：目标网段填客户端IP/32，网关填 ${gw}

# 方式 B：经 SSH 执行（爱快基于 OpenWrt，支持 ip 命令）
#   ssh ${ROUTE_IKUAI_USER:-root}@${ROUTE_IKUAI_HOST:-<爱快IP>}
#   iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination ${gw}:${MOSDNS_DNS_PORT}
#   iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to-destination ${gw}:${MOSDNS_DNS_PORT}
#   # 静态路由（旁路由回程）
#   ip route add ${ROUTE_LAN_CIDR:-192.168.1.0/24} via ${gw}
EOF
  else
    cat <<EOF
# ===== 在爱快后台删除 mihomoDNS 相关路由 =====
# 方式 A：Web 界面
#   流控分流 → 端口映射 → 删除 53 → ${gw}:${MOSDNS_DNS_PORT} 的规则
#   网络设置 → 路由设置 → 静态路由 → 删除网关为 ${gw} 的条目
#
# 方式 B：经 SSH 执行
#   ssh ${ROUTE_IKUAI_USER:-root}@${ROUTE_IKUAI_HOST:-<爱快IP>}
#   iptables -t nat -D PREROUTING -p udp --dport 53 -j DNAT --to-destination ${gw}:${MOSDNS_DNS_PORT}
#   iptables -t nat -D PREROUTING -p tcp --dport 53 -j DNAT --to-destination ${gw}:${MOSDNS_DNS_PORT}
#   ip route del ${ROUTE_LAN_CIDR:-192.168.1.0/24} via ${gw}
EOF
  fi
  echo
  info "请按上方步骤在爱快后台执行"
}

# ============ 统一入口 ============
route_apply() {
  detect_lan_info
  validate_route_params
  case "$ROUTE_TARGET" in
    linux)  route_linux_apply ;;
    ros)    route_ros_print add ;;
    ikuai)  route_ikuai_print add ;;
  esac
}

route_clean() {
  detect_lan_info
  validate_route_params
  case "$ROUTE_TARGET" in
    linux)  route_linux_clean ;;
    ros)    route_ros_print del ;;
    ikuai)  route_ikuai_print del ;;
  esac
}

# ============ 独立执行入口（scripts/route.sh apply|clean） ============
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=common.sh
  source "$PROJECT_DIR/scripts/common.sh"
  load_env
  sub="${1:-apply}"; shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) ROUTE_TARGET="$2"; shift 2 ;;
      --gateway) ROUTE_GATEWAY="$2"; shift 2 ;;
      --lan-if) ROUTE_LAN_IF="$2"; shift 2 ;;
      --lan-ip) ROUTE_LAN_IP="$2"; shift 2 ;;
      --lan-cidr) ROUTE_LAN_CIDR="$2"; shift 2 ;;
      --ssh-host) ROUTE_SSH_HOST="$2"; shift 2 ;;
      --ssh-port) ROUTE_SSH_PORT="$2"; shift 2 ;;
      --ssh-user) ROUTE_SSH_USER="$2"; shift 2 ;;
      --ikuai-host) ROUTE_IKUAI_HOST="$2"; shift 2 ;;
      --ikuai-user) ROUTE_IKUAI_USER="$2"; shift 2 ;;
      -h|--help)
        cat <<EOF
用法: bash scripts/route.sh <apply|clean> [选项]
  --target ros|ikuai|linux   路由目标（默认 linux）
  --gateway <ip>             主路由 LAN IP
  --lan-if <if>              本机网卡（如 eth0）
  --lan-ip <ip>              本机 LAN IP
  --lan-cidr <cidr>          本机网段（如 192.168.1.0/24）
  --ssh-host <ip>            ROS SSH 主机
  --ssh-port <port>          SSH 端口（默认 22）
  --ssh-user <user>          SSH 用户（默认 admin）
  --ikuai-host <ip>          爱快后台地址
  --ikuai-user <user>        爱快 SSH 用户（默认 admin）
EOF
        exit 0 ;;
      *) error "未知参数：$1"; exit 1 ;;
    esac
  done
  case "$sub" in
    apply) route_apply ;;
    clean) route_clean ;;
    *) die "子命令必须是 apply 或 clean" ;;
  esac
fi
