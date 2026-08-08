#!/usr/bin/env bash
# airport.sh — 机场个性化配置加载与生成
#
# 机场（airport）= 订阅服务提供方。不同机场在协议、IPv6 支持、DNS 需求、
# 流媒体规则、UA 要求等方面存在差异。本模块负责按机场名加载对应预设，
# 并把这些设置写回 .env 与 clash/mosdns 配置模板。

# 机场配置字段（在 airports/<name>.conf 中以 shell 变量定义）：
#   AIRPORT_NAME            机场显示名
#   AIRPORT_SUBSCRIPTION_URL订阅链接（clash/mihomo 格式或 base64/分享链接）
#   AIRPORT_SUBSCRIPTION_UA  订阅 UA（默认 clash-verge/v2.4.0，兼容 hy2/anytls）
#   AIRPORT_IPV6            auto/on/off
#   AIRPORT_DNS_MODE        fakeip / redir-host
#   AIRPORT_KERNEL          mihomo / clash
#   AIRPORT_DOMESTIC_DNS    国内 DNS，分号分隔，如 223.5.5.5;119.29.29.29
#   AIRPORT_PROXY_DNS       国外 DNS（走代理），如 https://1.1.1.1/dns-query;tls://8.8.8.8
#   AIRPORT_RULES_EXTRA     额外规则（YAML 数组文本，追加到 rules）
#   AIRPORT_PROXY_GROUPS_EXTRA 额外策略组（YAML 文本）
#   AIRPORT_TUN             true/false 是否启用 Tun
#   AIRPORT_NOTES           备注

# ============ 列举可用机场 ============
list_airports() {
  local found=0
  if [[ -d "$AIRPORTS_DIR" ]]; then
    for f in "$AIRPORTS_DIR"/*.conf; do
      [[ -f "$f" ]] || continue
      local name; name="$(basename "$f" .conf)"
      local desc=""
      # 读取 AIRPORT_NAME 字段作为描述
      desc="$(grep -E '^AIRPORT_NAME=' "$f" 2>/dev/null | head -1 | sed -E "s/^AIRPORT_NAME=['\"]?([^'\"]*)['\"]?$/\1/" || true)"
      printf '  %-18s %s\n' "$name" "${desc:-(无描述)}"
      found=1
    done
  fi
  [[ $found -eq 1 ]]
}

# 加载指定机场配置；无参数则用 default
# 用法: load_airport [name]
load_airport() {
  local name="${1:-default}"
  local file="$AIRPORTS_DIR/${name}.conf"
  if [[ ! -f "$file" ]]; then
    warn "未找到机场配置：$name"
    if [[ -d "$AIRPORTS_DIR" ]]; then
      info "可用机场："
      list_airports >&2 || true
    fi
    die "请通过 --airport <name> 指定，或在 airports/ 下新建 ${name}.conf"
  fi
  # shellcheck disable=SC1090
  source "$file"

  # 默认值兜底
  : "${AIRPORT_NAME:=$name}"
  : "${AIRPORT_SUBSCRIPTION_URL:=}"
  : "${AIRPORT_SUBSCRIPTION_UA:=clash-verge/v2.4.0}"
  : "${AIRPORT_IPV6:=auto}"
  : "${AIRPORT_DNS_MODE:=fakeip}"
  : "${AIRPORT_KERNEL:=mihomo}"
  : "${AIRPORT_DOMESTIC_DNS:=223.5.5.5;119.29.29.29}"
  : "${AIRPORT_PROXY_DNS:=https://1.1.1.1/dns-query;tls://8.8.8.8:853}"
  : "${AIRPORT_RULES_EXTRA:=}"
  : "${AIRPORT_PROXY_GROUPS_EXTRA:=}"
  : "${AIRPORT_TUN:=false}"
  : "${AIRPORT_NOTES:=}"

  AIRPORT_ID="$name"
  success "已加载机场配置：$AIRPORT_NAME ($name)"
  [[ -n "$AIRPORT_NOTES" ]] && info "$AIRPORT_NOTES"
}

# ============ 交互式选择机场 ============
pick_airport_interactive() {
  if [[ ! -d "$AIRPORTS_DIR" ]] || ! ls "$AIRPORTS_DIR"/*.conf >/dev/null 2>&1; then
    warn "airports/ 下无预设，将使用内置默认值"
    load_airport default 2>/dev/null || {
      # 没有 default.conf 也能继续：直接置空，后续由 install 流程提示填订阅
      AIRPORT_ID="default"; AIRPORT_NAME="默认"; AIRPORT_SUBSCRIPTION_URL=""
      AIRPORT_SUBSCRIPTION_UA="clash-verge/v2.4.0"; AIRPORT_IPV6="auto"
      AIRPORT_DNS_MODE="fakeip"; AIRPORT_KERNEL="mihomo"
      AIRPORT_DOMESTIC_DNS="223.5.5.5;119.29.29.29"
      AIRPORT_PROXY_DNS="https://1.1.1.1/dns-query;tls://8.8.8.8:853"
      AIRPORT_RULES_EXTRA=""; AIRPORT_PROXY_GROUPS_EXTRA=""; AIRPORT_TUN="false"
    }
    return 0
  fi
  echo
  info "可选机场预设："
  list_airports
  echo
  local choice
  read -r -p "请输入机场名（回车默认 default）: " choice
  [[ -z "$choice" ]] && choice="default"
  load_airport "$choice"
}

# ============ 把机场设置写回 .env（供 clash-for-linux 读取） ============
apply_airport_to_env() {
  [[ -z "${AIRPORT_ID:-}" ]] && die "尚未加载机场配置"
  set_env_value "KERNEL_TYPE" "$AIRPORT_KERNEL"
  set_env_value "CLASH_SUBSCRIPTION_URL" "$AIRPORT_SUBSCRIPTION_URL"
  set_env_value "CLASH_SUBSCRIPTION_UA" "$AIRPORT_SUBSCRIPTION_UA"
  set_env_value "CLASH_IPV6" "$AIRPORT_IPV6"
  set_env_value "MIXED_PORT" "$CLASH_MIXED_PORT"
  set_env_value "EXTERNAL_CONTROLLER" "$CLASH_CONTROLLER"
  # 本项目自定义端口（mosdns 侧读取）
  set_env_value "CLASH_DNS_PORT" "$CLASH_DNS_PORT"
  set_env_value "MOSDNS_DNS_PORT" "$MOSDNS_DNS_PORT"
  set_env_value "MOSDNS_LISTEN_ADDR" "$MOSDNS_LISTEN_ADDR"
  set_env_value "MOSDNS_WEBUI_PORT" "$MOSDNS_WEBUI_PORT"
  set_env_value "AIRPORT_ID" "$AIRPORT_ID"
  set_env_value "AIRPORT_DNS_MODE" "$AIRPORT_DNS_MODE"
  set_env_value "AIRPORT_DOMESTIC_DNS" "$AIRPORT_DOMESTIC_DNS"
  set_env_value "AIRPORT_PROXY_DNS" "$AIRPORT_PROXY_DNS"
  if [[ "$AIRPORT_TUN" == "true" ]]; then
    set_env_value "CLASH_TUN_ENABLE" "true"
  fi
}

# ============ 生成 clash mixin（机场特定覆盖） ============
# 输出到 clash-for-linux 的 mixin 文件，由 clash-for-linux 编译时合并。
# clash-for-linux 新版把 mixin 从 config/mixin.yaml 迁移到 runtime/mixin.yaml，
# mixin_read_file() 优先读 runtime 版；若 runtime 版存在而 config 版不一致会告警。
# 因此这里同时写两个路径，保持一致，避免告警与旧文件干扰。
generate_clash_mixin_for_airport() {
  local mixin_file="$CLASH_DIR/config/mixin.yaml"
  local mixin_runtime_file="$CLASH_DIR/runtime/mixin.yaml"
  mkdir -p "$(dirname "$mixin_file")" "$(dirname "$mixin_runtime_file")"

  local extra_rules_block=""
  if [[ -n "$AIRPORT_RULES_EXTRA" ]]; then
    extra_rules_block="$AIRPORT_RULES_EXTRA"
  fi

  # mihomo 内核 enhanced-mode 合法值映射：
  #   fakeip / fake-ip  → fake-ip（mihomo 新版要求带连字符）
  #   redir-host / redir → fake-ip（mihomo v1.19+ 已废弃 redir-host，兜底为 fake-ip）
  #   其它未知值         → fake-ip（兜底）
  local enhanced_mode="fake-ip"
  case "$AIRPORT_DNS_MODE" in
    fakeip|fake-ip)     enhanced_mode="fake-ip" ;;
    redir-host|redir)   enhanced_mode="fake-ip" ;;  # redir-host 已废弃，兜底
    *)                  enhanced_mode="fake-ip" ;;
  esac

  # 用函数生成内容，避免重复写两遍
  _write_mixin_content() {
    cat > "$1" <<EOF
# 由 clash-mosdns 一键安装项目按机场（${AIRPORT_ID}）自动生成
# 手动修改后请执行 clash mixin edit 重新生成运行配置
override:
  mixed-port: ${CLASH_MIXED_PORT}
  external-controller: ${CLASH_CONTROLLER}
  allow-lan: true
  mode: rule
  log-level: info
  dns:
    enable: true
    listen: 0.0.0.0:$CLASH_DNS_PORT
    enhanced-mode: $enhanced_mode
    fake-ip-range: 198.18.0.1/16
    fake-ip-filter:
      - '*.lan'
      - '*.local'
      - '+.msftconnecttest.com'
      - '+.msftncsi.com'
EOF
    # IPv6 处理
    case "$AIRPORT_IPV6" in
      on) cat >> "$1" <<'EOF'
    ipv6: true
EOF
          ;;
      off) cat >> "$1" <<'EOF'
    ipv6: false
EOF
          ;;
      *) ;; # auto 不覆盖
    esac

    cat >> "$1" <<EOF
prepend:
  rules:
$extra_rules_block
EOF

    if [[ -n "$AIRPORT_PROXY_GROUPS_EXTRA" ]]; then
      cat >> "$1" <<EOF
  proxy-groups:
$AIRPORT_PROXY_GROUPS_EXTRA
EOF
    fi

    # 兜底规则用 DIRECT 而非「节点选择」：很多机场订阅不带 proxy-groups，
    # 引用不存在的策略组会导致 mihomo 校验失败（proxy [节点选择] not found）。
    # 需要走代理的流量由订阅自带 rules 决定；无 rules 时全部直连最安全。
    cat >> "$1" <<'EOF'
append:
  rules:
    - MATCH,DIRECT
EOF
  }

  _write_mixin_content "$mixin_file"
  _write_mixin_content "$mixin_runtime_file"
  success "已生成 clash mixin：$mixin_file（同步 runtime 版）"
}

# ============ DNS 地址格式转换辅助函数 ============
# 把各种 DNS 地址格式统一转成 TCP DNS 格式 tcp://host:53
# 原因：socks5 代理只稳定支持 TCP CONNECT，UDP ASSOCIATE 常被阻断；
#       DoH/DoT 有 TLS 握手超时风险（默认 3-6 秒）；TCP DNS 最稳最快。
# 支持：https://1.1.1.1/dns-query, tls://8.8.8.8:853, udp://1.1.1.1:53,
#       tcp://8.8.8.8:53, 1.1.1.1, 1.1.1.1:53, [2001:4860::8888]:53
_dns_to_tcp() {
  local s="$1" host
  # 去掉协议前缀
  s="${s#https://}"
  s="${s#tls://}"
  s="${s#h3://}"
  s="${s#quic://}"
  s="${s#udp://}"
  s="${s#tcp://}"
  # 去掉路径部分（DoH 的 /dns-query 等）
  s="${s%%/*}"
  # 提取 host（去掉端口）——IPv6 地址形如 [2001:4860::8888] 需特殊处理
  if [[ "$s" == \[* ]]; then
    host="${s%%]*}"
    host="${host#\[}"
  elif [[ "$s" == *:* ]]; then
    host="${s%:*}"
  else
    host="$s"
  fi
  [[ -z "$host" ]] && return 1
  printf 'tcp://%s:53\n' "$host"
}

# ============ 生成 mosdns 配置（按机场 DNS 需求） ============
# 配置文件名沿用 mosdns 官方约定的 config_custom.yaml；
# mosdns start -d <dir> 默认找 config.yaml，因此 systemd unit 的 ExecStart
# 需用 -c 显式指定 config_custom.yaml（见 install-mosdns.sh）。
#
# mosdns v0.7.x 配置要点（与旧版差异）：
#   - 没有 type: server，拆成 udp_server + tcp_server 两个插件
#   - forward 的 upstreams 项用 addr 字段（不是 upstream）
#   - socks5 是 forward 的全局参数（Args 级，非每个 upstream 项）
#   - sequence 的 exec 引用其他插件 tag 要用 $ 前缀（$cache, $forward）
#     不带 $ 会被当作插件类型名，新建匿名插件而非引用
#
# 分流策略（已验证可用）：
#   1. geosite_cn 域名匹配分流（优先）：国内域名走国内 DNS，非国内走代理
#      —— 避免 DNS 污染（国内 DNS 对被墙域名返回污染 IP，响应回退方案无效）
#   2. 响应回退分流（fallback）：无 geosite 数据时，国内 DNS 无 IP 则走代理
#      —— 受 DNS 污染影响，仅作降级方案
#
# 上游协议选择（已验证）：
#   - 国外上游用 TCP DNS（tcp://host:53），不用 DoH/DoT/UDP
#   - socks5 只稳定支持 TCP CONNECT；DoH/DoT 有 TLS 握手超时；UDP 常被阻断
#   - concurrent: 2 并发查多上游，任一成功即返回
generate_mosdns_config_for_airport() {
  local out="$MOSDNS_RUNTIME_DIR/config_custom.yaml"
  local rule_dir="$MOSDNS_RUNTIME_DIR/rule"
  mkdir -p "$MOSDNS_RUNTIME_DIR" "$rule_dir"

  # 拆分 DNS 列表（分号分隔）
  local domestic_dns proxy_dns
  domestic_dns="$(printf '%s' "$AIRPORT_DOMESTIC_DNS" | tr ';' '\n' | grep -v '^$' || true)"
  proxy_dns="$(printf '%s' "$AIRPORT_PROXY_DNS" | tr ';' '\n' | grep -v '^$' || true)"
  [[ -z "$proxy_dns" ]] && proxy_dns="1.1.1.1;8.8.8.8"

  # 构造国内上游 yaml 片段：直连 UDP（国内 DNS 无污染，UDP 最快）
  local domestic_block="" i=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    domestic_block+=$'        - tag: domestic_'"${i}"$'\n'
    domestic_block+=$'          addr: '"\"${line}\""$'\n'
    i=$((i+1))
  done <<< "$domestic_dns"

  # 构造国外上游 yaml 片段：统一转成 TCP DNS 格式（经 clash SOCKS5 代理）
  local proxy_block="" j=0 tcp_addr
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    tcp_addr="$(_dns_to_tcp "$line")" || { warn "无法解析 DNS 地址: $line, 跳过"; continue; }
    proxy_block+=$'        - tag: proxy_'"${j}"$'\n'
    proxy_block+=$'          addr: '"\"${tcp_addr}\""$'\n'
    j=$((j+1))
  done <<< "$proxy_dns"
  # 兜底：全部转换失败时用默认上游
  [[ -z "$proxy_block" ]] && proxy_block=$'        - tag: proxy_0\n          addr: "tcp://1.1.1.1:53"\n        - tag: proxy_1\n          addr: "tcp://8.8.8.8:53"\n'

  # 检查 geosite_cn.txt 是否存在，决定分流策略
  local has_geosite=false
  [[ -f "$rule_dir/geosite_cn.txt" ]] && has_geosite=true

  # geosite_cn domain_set 插件段（仅当数据文件存在时生成）
  local geosite_plugin=""
  if $has_geosite; then
    geosite_plugin='  - tag: geosite_cn
    type: domain_set
    args:
      files:
        - "rule/geosite_cn.txt"

'
  else
    warn "rule/geosite_cn.txt 不存在，将使用响应回退分流（国外域名可能受 DNS 污染）"
    warn "运行 install-mosdns.sh 的 download_geosite_data 可下载分流数据"
  fi

  # main_sequence 分流逻辑（单引号字符串，$ 为字面量，供 mosdns 读取）
  local sequence_args
  if $has_geosite; then
    # 域名匹配分流：国内域名走国内DNS，非国内走代理
    sequence_args='      - exec: $cache
      - matches: "qname $geosite_cn"
        exec: $forward_domestic
      - exec: $forward_proxy'
  else
    # 响应回退分流：国内 DNS 无 IP 则走代理（受 DNS 污染影响，降级方案）
    sequence_args='      - exec: $cache
      - exec: $forward_domestic
      - matches: "!resp_ip 0.0.0.0/0"
        exec: $forward_proxy'
  fi

  cat > "$out" <<EOF
# mosdns 配置 — 由 clash-mosdns 一键安装项目按机场（${AIRPORT_ID}）生成
# 运行目录: ${MOSDNS_RUNTIME_DIR}
# 与 clash-for-linux 联动：
#   - 国内域名（geosite_cn）→ 国内 DNS 直连
#   - 国外域名 → 国外 DNS（经 clash SOCKS ${CLASH_MIXED_PORT}，TCP DNS）
#   - 使用 domain_set 域名匹配分流，避免 DNS 污染
#
# 上游协议选择：TCP DNS（非 DoH/DoT/UDP）
#   - socks5 代理只稳定支持 TCP CONNECT，UDP ASSOCIATE 常被阻断
#   - DoH/DoT 有 TLS 握手超时风险（默认 3-6 秒）
#   - TCP DNS 无 TLS 握手，经 socks5 走 CONNECT，最稳最快
#
# 分流数据：rule/geosite_cn.txt（国内域名集）
#   - 由 install-mosdns.sh 的 download_geosite_data 下载
#   - 来源：mosdns 官方配置包 config_all.zip

log:
  level: info
  file: "${MOSDNS_RUNTIME_DIR}/mosdns.log"

plugins:
${geosite_plugin}  # 国内 DNS 直连
  - tag: forward_domestic
    type: forward
    args:
      upstreams:
${domestic_block}
  # 国外 DNS 经 clash SOCKS5 代理（TCP DNS，concurrent 并发查多上游）
  - tag: forward_proxy
    type: forward
    args:
      socks5: "127.0.0.1:${CLASH_MIXED_PORT}"
      concurrent: 2
      upstreams:
${proxy_block}
  - tag: cache
    type: cache
    args:
      size: 4096
      lazy_cache_ttl: 86400

  # ${has_geosite:+域名匹配分流}${has_geosite:-响应回退分流}
  - tag: main_sequence
    type: sequence
    args:
${sequence_args}

  - tag: main_udp_server
    type: udp_server
    args:
      entry: main_sequence
      listen: ${MOSDNS_LISTEN_ADDR}:${MOSDNS_DNS_PORT}

  - tag: main_tcp_server
    type: tcp_server
    args:
      entry: main_sequence
      listen: ${MOSDNS_LISTEN_ADDR}:${MOSDNS_DNS_PORT}
EOF
  success "已生成 mosdns 配置：$out"
}
