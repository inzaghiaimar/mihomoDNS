#!/usr/bin/env bash
# integrate.sh — clash 与 mosdns 联动配置、启动、健康检查

# 生成 mosdns 启动参数（WebUI 端口等）
mosdns_start_args() {
  printf -- '-d %s --webui-port %s' "$MOSDNS_RUNTIME_DIR" "$MOSDNS_WEBUI_PORT"
}

# 启动 mosdns（systemd 或 nohup 后台）
start_mosdns() {
  step "启动 mosdns"
  if have_systemd && [[ -f /etc/systemd/system/mosdns.service ]]; then
    systemctl enable --now mosdns 2>/dev/null
    sleep 1
    if systemctl is-active --quiet mosdns; then
      success "mosdns 已通过 systemd 启动"
    else
      warn "mosdns systemd 启动失败，查看：journalctl -u mosdns -n 50"
    fi
    return 0
  fi

  # 退路：nohup 后台
  local bin; bin="$(command -v mosdns 2>/dev/null || true)"
  [[ -z "$bin" ]] && die "mosdns 未安装"
  local log="$MOSDNS_RUNTIME_DIR/mosdns-launch.log"
  mkdir -p "$MOSDNS_RUNTIME_DIR"
  nohup "$bin" $(mosdns_start_args) >"$log" 2>&1 &
  echo $! > "$MOSDNS_RUNTIME_DIR/mosdns.pid"
  success "mosdns 已后台启动（pid $(cat "$MOSDNS_RUNTIME_DIR/mosdns.pid" 2>/dev/null || echo ?)，日志 $log）"
}

# 停止 mosdns
stop_mosdns() {
  if have_systemd && [[ -f /etc/systemd/system/mosdns.service ]]; then
    systemctl stop mosdns 2>/dev/null || true
    return 0
  fi
  local pidfile="$MOSDNS_RUNTIME_DIR/mosdns.pid"
  if [[ -f "$pidfile" ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
}

# 启动 clash（复用其 clashon 入口）
start_clash() {
  step "启动 clash"
  if command -v clashon >/dev/null 2>&1; then
    clashon 2>/dev/null || true
    success "clash 已启动（clashon）"
  else
    warn "未找到 clashon 命令，请手动执行 clashon"
  fi
}

# 停止 clash
stop_clash() {
  if command -v clashoff >/dev/null 2>&1; then
    clashoff 2>/dev/null || true
  fi
}

# 把系统 DNS 指向 mosdns（仅提示，不强制改 /etc/resolv.conf）
hint_system_dns() {
  echo
  info "如需让系统使用 mosdns 作为主 DNS："
  echo "  将 /etc/resolv.conf 首行改为：nameserver 127.0.0.1"
  echo "  或（systemd-resolved）："
  echo "    mkdir -p /etc/systemd/resolved.conf.d"
  echo "    printf '[Resolve]\\nDNS=127.0.0.1:%s\\nDNSStubListener=no\\n' '$MOSDNS_DNS_PORT' > /etc/systemd/resolved.conf.d/mosdns.conf"
  echo "    systemctl restart systemd-resolved"
  echo
  info "clash WebUI:   http://<本机IP>:9090/ui"
  info "mosdns WebUI:  http://<本机IP>:$MOSDNS_WEBUI_PORT"
}

# 联动健康检查
integration_check() {
  step "联动健康检查"
  local ok=true

  # clash mixed-port
  if port_in_use "$CLASH_MIXED_PORT"; then
    success "clash mixed-port $CLASH_MIXED_PORT 监听中"
  else
    warn "clash mixed-port $CLASH_MIXED_PORT 未监听（可能 clash 尚未启动）"
    ok=false
  fi

  # clash DNS
  if port_in_use "$CLASH_DNS_PORT"; then
    success "clash DNS $CLASH_DNS_PORT 监听中"
  else
    warn "clash DNS $CLASH_DNS_PORT 未监听"
    ok=false
  fi

  # mosdns
  if port_in_use "$MOSDNS_DNS_PORT"; then
    success "mosdns $MOSDNS_DNS_PORT 监听中"
  else
    warn "mosdns $MOSDNS_DNS_PORT 未监听"
    ok=false
  fi

  if $ok; then
    success "联动检查通过：clash(mixed:$CLASH_MIXED_PORT, dns:$CLASH_DNS_PORT) ↔ mosdns(:$MOSDNS_DNS_PORT)"
  else
    warn "部分端口未就绪，可稍后重试：bash $PROJECT_DIR/scripts/integrate.sh check"
  fi
}
