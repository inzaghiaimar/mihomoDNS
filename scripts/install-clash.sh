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

  # 部署 clash WebUI 面板（上游 install.sh 可能未部署）
  deploy_clash_webui

  success "clash-for-linux 安装完成"
}

# 部署 clash WebUI 面板
# 从 GitHub 下载 zashboard 面板到 runtime/dashboard/
# 解决 WebUI 打开空白的问题
deploy_clash_webui() {
  local dashboard_dir="$CLASH_DIR/runtime/dashboard"
  local index_file="$dashboard_dir/index.html"

  # 已部署则跳过
  if [[ -f "$index_file" ]]; then
    success "clash WebUI 面板已存在：$dashboard_dir"
    return 0
  fi

  step "部署 clash WebUI 面板"
  mkdir -p "$dashboard_dir"
  local tmp_zip; tmp_zip="$(mktemp)"
  local ui_url="https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"
  local proxy_url="${CLASH_GH_PROXY:+$CLASH_GH_PROXY/}$ui_url"

  # 先走代理下载，失败则直连
  if ! download "$proxy_url" "$tmp_zip" 2>/dev/null; then
    if ! download "$ui_url" "$tmp_zip" 2>/dev/null; then
      rm -f "$tmp_zip"
      warn "下载 clash WebUI 面板失败，请手动执行：clash ui"
      return 1
    fi
  fi

  # 解压到 dashboard 目录
  if ! unzip -o "$tmp_zip" -d "$tmp_zip.extract" 2>/dev/null; then
    rm -rf "$tmp_zip" "$tmp_zip.extract"
    warn "解压 clash WebUI 面板失败"
    return 1
  fi

  # dist.zip 解压后含 dist/ 子目录，需把内容移到 dashboard 根目录
  if [[ -d "$tmp_zip.extract/dist" ]]; then
    cp -a "$tmp_zip.extract/dist/." "$dashboard_dir/"
  else
    cp -a "$tmp_zip.extract/." "$dashboard_dir/"
  fi
  rm -rf "$tmp_zip" "$tmp_zip.extract"

  if [[ -f "$index_file" ]]; then
    success "已部署 clash WebUI 面板：$dashboard_dir"
  else
    warn "clash WebUI 面板部署异常，index.html 未找到"
  fi
}

# 卸载 clash
uninstall_clash() {
  ensure_clash_project
  # shellcheck disable=SC2164
  pushd "$CLASH_DIR" >/dev/null
  bash uninstall.sh --keep-runtime 2>/dev/null || bash uninstall.sh 2>/dev/null || warn "clash 卸载未完全成功"
  popd >/dev/null
}
