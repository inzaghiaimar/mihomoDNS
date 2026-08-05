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
# 输出到 clash-for-linux 的 mixin 文件，由 clash-for-linux 编译时合并
generate_clash_mixin_for_airport() {
  local mixin_file="$CLASH_DIR/config/mixin.yaml"
  mkdir -p "$(dirname "$mixin_file")"

  local extra_rules_block=""
  if [[ -n "$AIRPORT_RULES_EXTRA" ]]; then
    extra_rules_block="$AIRPORT_RULES_EXTRA"
  fi

  cat > "$mixin_file" <<EOF
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
    enhanced-mode: $AIRPORT_DNS_MODE
    fake-ip-range: 198.18.0.1/16
    fake-ip-filter:
      - '*.lan'
      - '*.local'
      - '+.msftconnecttest.com'
      - '+.msftncsi.com'
EOF

  # IPv6 处理
  case "$AIRPORT_IPV6" in
    on) cat >> "$mixin_file" <<'EOF'
    ipv6: true
EOF
        ;;
    off) cat >> "$mixin_file" <<'EOF'
    ipv6: false
EOF
        ;;
    *) ;; # auto 不覆盖
  esac

  cat >> "$mixin_file" <<EOF
prepend:
  rules:
$extra_rules_block
EOF

  if [[ -n "$AIRPORT_PROXY_GROUPS_EXTRA" ]]; then
    cat >> "$mixin_file" <<EOF
  proxy-groups:
$AIRPORT_PROXY_GROUPS_EXTRA
EOF
  fi

  cat >> "$mixin_file" <<'EOF'
append:
  rules:
    - MATCH,节点选择
EOF
  success "已生成 clash mixin：$mixin_file"
}

# ============ 生成 mosdns 配置（按机场 DNS 需求） ============
generate_mosdns_config_for_airport() {
  local out="$MOSDNS_RUNTIME_DIR/config_custom.yaml"
  mkdir -p "$MOSDNS_RUNTIME_DIR"

  # 拆分 DNS 列表（分号分隔）
  local domestic_dns proxy_dns
  domestic_dns="$(printf '%s' "$AIRPORT_DOMESTIC_DNS" | tr ';' '\n' | grep -v '^$' || true)"
  proxy_dns="$(printf '%s' "$AIRPORT_PROXY_DNS" | tr ';' '\n' | grep -v '^$' || true)"
  [[ -z "$proxy_dns" ]] && proxy_dns="https://1.1.1.1/dns-query"

  # 构造国内上游 yaml 片段（每项 8 空格缩进，置于 upstreams: 之下）
  local domestic_block="" i=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    domestic_block+=$'        - tag: domestic_'"${i}"$'\n'
    domestic_block+=$'          upstream:\n'
    domestic_block+="          - \"${line}\""$'\n'
    i=$((i+1))
  done <<< "$domestic_dns"

  # 构造国外上游 yaml 片段：走 clash 的 SOCKS（mixed-port 兼容 socks5）
  local proxy_block="" j=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    proxy_block+=$'        - tag: proxy_'"${j}"$'\n'
    proxy_block+=$'          upstream:\n'
    proxy_block+="          - \"${line}\""$'\n'
    proxy_block+="          socks5: \"127.0.0.1:${CLASH_MIXED_PORT}\""$'\n'
    j=$((j+1))
  done <<< "$proxy_dns"

  cat > "$out" <<EOF
# mosdns 配置 — 由 clash-mosdns 一键安装项目按机场（${AIRPORT_ID}）生成
# 运行目录: ${MOSDNS_RUNTIME_DIR}
# 与 clash-for-linux 联动：
#   - 国内域名 → 国内 DNS 直连
#   - 国外域名 → 国外 DNS（经 clash SOCKS ${CLASH_MIXED_PORT}）
#   - FakeIP 域名 → clash 内部 DNS 127.0.0.1:${CLASH_DNS_PORT}（经 SOCKS）
#
# 说明：本配置为最小可用版本（默认全部走国内 DNS，国外上游已就绪但未启用）。
# 完整国内外域名分流需导入 mosdns 官方配置包 config_all.zip：
#   https://raw.githubusercontent.com/jasonxtt/file/main/mosdns/config/config_all.zip
# 解压后覆盖本目录，再重启 mosdns 即可启用 geosite/geoip 分流。

log:
  level: info
  file: "${MOSDNS_RUNTIME_DIR}/mosdns.log"

plugins:
  - tag: main_server
    type: server
    args:
      entry:
        - main_sequence
      listen: 127.0.0.1:${MOSDNS_DNS_PORT}
      # WebUI 由 mosdns 内核监听 ${MOSDNS_WEBUI_PORT}（见启动参数）

  - tag: main_sequence
    type: sequence
    args:
      - exec: \$cache
      - exec: \$forward_domestic
      # 如需把国外域名走代理上游，导入 config_all.zip 后，
      # 在此追加 matches+forward_proxy 规则（见 mosdns 文档）。

  - tag: forward_domestic
    type: forward
    args:
      upstreams:
${domestic_block}
  - tag: forward_proxy
    type: forward
    args:
      upstreams:
${proxy_block}
  - tag: cache
    type: cache
    args:
      size: 4096
      lazy_cache_ttl: 86400
EOF
  success "已生成 mosdns 配置：$out"
}
