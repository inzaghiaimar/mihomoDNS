#!/usr/bin/env bash
# install-clash.sh — 安装 clash-for-linux 子项目（复用其 install.sh）

# 检查子项目存在
ensure_clash_project() {
  if [[ ! -d "$CLASH_DIR" || ! -f "$CLASH_DIR/install.sh" ]]; then
    die "未找到 clash-for-linux 子项目：$CLASH_DIR
请确认已克隆：git clone https://github.com/wnlen/clash-for-linux.git $CLASH_DIR"
  fi
}

# 安装范围解析：root → system，普通用户 → user
resolve_clash_scope() {
  if is_root; then
    printf 'system'
  else
    printf 'user'
  fi
}

# 调用 clash-for-linux 的 install.sh
# 依赖：调用前应已通过 apply_airport_to_env() 写好 .env 与 mixin
install_clash() {
  step "安装 clash-for-linux"
  ensure_clash_project

  # 把本项目的 .env 同步给 clash-for-linux（clash-for-linux 读取其自身目录下 .env）
  # 我们把端口/订阅等写入 clash-for-linux/.env
  local clash_env="$CLASH_DIR/.env"
  local root_env="$PROJECT_DIR/.env"
  if [[ -f "$root_env" ]]; then
    # 只同步 clash 相关键，避免覆盖冲突
    {
      echo "# 由 clash-mosdns 一键安装项目同步"
      grep -E '^(KERNEL_TYPE|MIXED_PORT|EXTERNAL_CONTROLLER|CLASH_SUBSCRIPTION_URL|CLASH_SUBSCRIPTION_UA|CLASH_IPV6|MIHOMO_VERSION|CLASH_VERSION|YQ_VERSION|SUBCONVERTER_VERSION|CLASH_GH_PROXY|CLASH_BUNDLED_ASSET_ENABLED|CLASH_OFFLINE|CLASH_PREDOWNLOAD_GEO|CLASH_TUN_ENABLE)=' "$root_env" 2>/dev/null || true
    } > "$clash_env"
  fi

  local scope; scope="$(resolve_clash_scope)"
  info "安装范围：$scope"

  # 端口冲突预检
  ensure_port_free "${CLASH_MIXED_PORT}" "clash mixed-port" || true
  ensure_port_free "${CLASH_CONTROLLER##*:}" "clash controller" || true
  ensure_port_free "$CLASH_DNS_PORT" "clash dns" || true

  # 进入子目录执行其 install.sh
  # shellcheck disable=SC2164
  pushd "$CLASH_DIR" >/dev/null
  if ! bash install.sh "$scope"; then
    popd >/dev/null
    die "clash-for-linux 安装失败，请查看上方日志"
  fi
  popd >/dev/null

  success "clash-for-linux 安装完成"
}

# 卸载 clash
uninstall_clash() {
  ensure_clash_project
  # shellcheck disable=SC2164
  pushd "$CLASH_DIR" >/dev/null
  bash uninstall.sh --keep-runtime 2>/dev/null || bash uninstall.sh 2>/dev/null || warn "clash 卸载未完全成功"
  popd >/dev/null
}
