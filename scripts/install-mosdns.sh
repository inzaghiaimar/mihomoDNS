#!/usr/bin/env bash
# install-mosdns.sh — 下载并安装 mosdns 二进制，配置运行目录

MOSDNS_VERSION="${MOSDNS_VERSION:-v0.7.1}"
MOSDNS_REPO="${MOSDNS_REPO:-https://github.com/jasonxtt/mosdns}"
MOSDNS_INSTALL_BIN_DIR="${MOSDNS_INSTALL_BIN_DIR:-/usr/local/bin}"
MOSDNS_SERVICE_USER="${MOSDNS_SERVICE_USER:-root}"

# 判断 mosdns 是否已安装
mosdns_installed() {
  command -v mosdns >/dev/null 2>&1
}

# 解析最新 release tag（若 MOSDNS_VERSION 为 latest）
resolve_mosdns_version() {
  if [[ "$MOSDNS_VERSION" != "latest" ]]; then
    printf '%s\n' "$MOSDNS_VERSION"
    return
  fi
  local tag=""
  if command -v curl >/dev/null 2>&1; then
    tag="$(curl -fsSL --connect-timeout 15 "https://api.github.com/repos/jasonxtt/mosdns/tags" 2>/dev/null \
      | grep '"name"' | head -1 | sed -E 's/.*"name": *"?([^"]+)"?.*/\1/' || true)"
  fi
  [[ -z "$tag" ]] && tag="v0.7.1"
  printf '%s\n' "$tag"
}

# 下载并安装二进制
install_mosdns() {
  step "安装 mosdns"
  local arch os version
  arch="$(detect_arch)"
  os="$(detect_os)"
  [[ "$os" != "linux" ]] && die "本项目仅支持 Linux（当前：$os）"

  version="$(resolve_mosdns_version)"
  info "目标版本：$version（架构 $arch）"

  if mosdns_installed && [[ "${MOSDNS_FORCE_REINSTALL:-false}" != "true" ]]; then
    success "mosdns 已安装：$(mosdns version 2>/dev/null | head -1)"
    return 0
  fi

  # 下载地址：release 产物命名 mosdns-<ver>-linux-<arch>.tar.gz，内含 mosdns 二进制
  local ver_no_v="${version#v}"
  local archive_name="mosdns-${ver_no_v}-linux-${arch}.tar.gz"
  local download_url="$MOSDNS_REPO/releases/download/${version}/${archive_name}"

  local tmp_dir; tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  download "$download_url" "$tmp_dir/$archive_name" \
    || die "下载 mosdns 失败：$download_url"

  info "解压: $archive_name"
  tar -xzf "$tmp_dir/$archive_name" -C "$tmp_dir" || die "解压失败"
  [[ -f "$tmp_dir/mosdns" ]] || die "解压后未找到 mosdns 二进制"

  # 安装二进制
  local target_dir="$MOSDNS_INSTALL_BIN_DIR"
  if ! is_root && [[ ! -w "$target_dir" ]]; then
    target_dir="$HOME/.local/bin"
    mkdir -p "$target_dir"
    warn "非 root，安装到用户目录：$target_dir"
    case ":$PATH:" in
      *":$target_dir:"*) ;;
      *) warn "$target_dir 不在 PATH 中，请手动加入 ~/.bashrc：export PATH=$target_dir:\$PATH" ;;
    esac
  fi

  install -m 0755 "$tmp_dir/mosdns" "$target_dir/mosdns"
  success "mosdns 二进制已安装：$target_dir/mosdns（$(mosdns version 2>/dev/null | head -1 || echo unknown)）"

  # 运行目录
  mkdir -p "$MOSDNS_RUNTIME_DIR"
}

# 写入 systemd unit（root 安装时）
install_mosdns_service() {
  if ! have_systemd; then
    warn "未检测到 systemd，mosdns 需手动启动：mosdns -d $MOSDNS_RUNTIME_DIR"
    return 0
  fi
  local unit_file="/etc/systemd/system/mosdns.service"
  if ! is_root; then
    warn "非 root 用户，跳过 systemd unit 安装；请手动启动或使用 systemd-user"
    return 0
  fi

  cat > "$unit_file" <<EOF
[Unit]
Description=MosDNS-T DNS Splitter (clash-mosdns)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$MOSDNS_SERVICE_USER
WorkingDirectory=$MOSDNS_RUNTIME_DIR
ExecStart=$(command -v mosdns) -d $MOSDNS_RUNTIME_DIR
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  success "已写入 systemd unit：$unit_file"
}

# 卸载 mosdns
uninstall_mosdns() {
  info "卸载 mosdns"
  if have_systemd && [[ -f /etc/systemd/system/mosdns.service ]]; then
    systemctl stop mosdns 2>/dev/null || true
    systemctl disable mosdns 2>/dev/null || true
    rm -f /etc/systemd/system/mosdns.service
    systemctl daemon-reload
  fi
  if mosdns_installed; then
    local bin; bin="$(command -v mosdns)"
    rm -f "$bin"
  fi
  warn "mosdns 运行目录保留：$MOSDNS_RUNTIME_DIR（如需删除请手动 rm -rf）"
}
