#!/usr/bin/env bash
# common.sh — 通用函数库（日志、环境、架构识别、下载）

set -euo pipefail

# ============ 颜色与日志 ============
if [[ -t 1 ]]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_RESET=$'\033[0m'
else
  C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''; C_RESET=''
fi

log()     { printf '%s\n' "$*"; }
info()    { printf '%sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
step()    { printf '%s➜%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
success() { printf '%s✔ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()    { printf '%s⚠ %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
error()   { printf '%s✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()     { error "$*"; exit 1; }

confirm() {
  local prompt="$1" default="${2:-y}"
  local reply
  if [[ "$default" =~ ^[Yy] ]]; then
    read -r -p "${prompt} [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]] && return 0
    return 1
  else
    read -r -p "${prompt} [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]] && return 0
    return 1
  fi
}

# ============ 路径常量 ============
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CLASH_DIR="$PROJECT_DIR/clash-for-linux"
MOSDNS_DIR="$PROJECT_DIR/mosdns"
AIRPORTS_DIR="$PROJECT_DIR/airports"
CONFIG_DIR="$PROJECT_DIR/config"
RUNTIME_DIR="$PROJECT_DIR/runtime"
MOSDNS_RUNTIME_DIR="${MOSDNS_RUNTIME_DIR:-$RUNTIME_DIR/mosdns}"

# ============ 运行时变量（可被 .env 覆盖） ============
CLASH_MIXED_PORT="${CLASH_MIXED_PORT:-7890}"
CLASH_CONTROLLER="${CLASH_CONTROLLER:-0.0.0.0:9090}"
CLASH_DNS_PORT="${CLASH_DNS_PORT:-1053}"           # mihomo 内部 DNS（fakeip）
MOSDNS_DNS_PORT="${MOSDNS_DNS_PORT:-5335}"          # mosdns 监听
MOSDNS_WEBUI_PORT="${MOSDNS_WEBUI_PORT:-9099}"
CLASH_IPV6="${CLASH_IPV6:-auto}"
KERNEL_TYPE="${KERNEL_TYPE:-mihomo}"
CLASH_GH_PROXY="${CLASH_GH_PROXY:-https://ghfast.top}"

# ============ 架构识别 ============
detect_arch() {
  local m
  m="$(uname -m 2>/dev/null || echo x86_64)"
  case "$m" in
    x86_64|amd64)   printf 'amd64' ;;
    aarch64|arm64)  printf 'arm64' ;;
    armv7l|armv6l)  printf 'armv7' ;;
    *) die "不支持的架构：$m（当前仅支持 amd64 / arm64 / armv7）" ;;
  esac
}

detect_os() {
  local s
  s="$(uname -s 2>/dev/null || echo Linux)"
  case "$s" in
    Linux) printf 'linux' ;;
    Darwin) printf 'darwin' ;;
    *) die "不支持的系统：$s（本项目面向 Linux）" ;;
  esac
}

# ============ root 判定 ============
is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

# ============ .env 加载 ============
load_env() {
  local env_file="$PROJECT_DIR/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

# 写入/更新 .env 中某个键
set_env_value() {
  local key="$1" val="$2" env_file="$PROJECT_DIR/.env"
  touch "$env_file"
  if grep -qE "^${key}=" "$env_file"; then
    # macOS sed 与 GNU sed 兼容写法：用临时文件
    local tmp
    tmp="$(mktemp)"
    sed -E "s|^${key}=.*|${key}=${val}|" "$env_file" > "$tmp" && mv "$tmp" "$env_file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$env_file"
  fi
  export "$key=$val"
}

# ============ 下载工具（带 GitHub 加速前缀） ============
# 将 github.com 下载地址套上加速前缀
with_gh_proxy() {
  local url="$1"
  if [[ "$url" =~ ^https://github\.com(/.*) ]]; then
    printf '%s%s\n' "$CLASH_GH_PROXY" "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$url"
  fi
}

# 下载文件（自动套加速前缀；第二个参数为目标路径）
download() {
  local url="$1" dest="$2" real_url
  real_url="$(with_gh_proxy "$url")"
  info "下载: $real_url"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 20 --retry 3 -o "$dest" "$real_url" \
      || curl -fsSL --connect-timeout 20 --retry 3 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=20 --tries=3 -O "$dest" "$real_url" \
      || wget -q --timeout=20 --tries=3 -O "$dest" "$url"
  else
    die "未找到 curl 或 wget，无法下载"
  fi
}

# ============ 包管理器检查与安装 ============
ensure_cmd() {
  local cmd="$1" pkg="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    [[ -z "$pkg" ]] && pkg="$cmd"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y "$pkg"
    elif command -v yum >/dev/null 2>&1; then
      yum install -y "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y "$pkg"
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache "$pkg"
    elif command -v opkg >/dev/null 2>&1; then
      opkg update && opkg install "$pkg"
    else
      die "缺少命令 $cmd，且无法自动安装"
    fi
  fi
}

# ============ systemd / 服务管理 ============
have_systemd() {
  [[ -d /etc/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

# ============ 端口占用检测 ============
port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntu 2>/dev/null | awk '{print $5}' | grep -q ":${port}\$"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntu 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"
  else
    return 1
  fi
}

ensure_port_free() {
  local port="$1" name="$2"
  if port_in_use "$port"; then
    warn "端口 $port（$name）已被占用，可能影响运行。可在 .env 中调整端口。"
    return 1
  fi
  return 0
}

# ============ 子项目自动获取 ============
# mihomoDNS 仓库本身只含合并/安装逻辑，两个子项目在安装时按需克隆到本目录。
# 克隆用 --depth 1 减小体积；已存在则跳过。
SUBPROJECTS=(
  "clash-for-linux|https://github.com/wnlen/clash-for-linux.git"
  "mosdns|https://github.com/jasonxtt/mosdns.git"
)

ensure_subprojects() {
  local entry name url
  for entry in "${SUBPROJECTS[@]}"; do
    name="${entry%%|*}"
    url="${entry##*|}"
    if [[ -d "$PROJECT_DIR/$name" && -f "$PROJECT_DIR/$name/install.sh" ]] \
       || [[ -d "$PROJECT_DIR/$name" && -f "$PROJECT_DIR/$name/main.go" ]]; then
      continue
    fi
    if [[ -d "$PROJECT_DIR/$name" ]]; then
      warn "目录 $name/ 已存在但不完整，尝试重新克隆"
      rm -rf "$PROJECT_DIR/$name"
    fi
    step "克隆子项目：$name"
    download_git_clone "$url" "$PROJECT_DIR/$name" \
      || die "克隆 $name 失败：$url（请检查网络或 CLASH_GH_PROXY）"
    success "已克隆 $name"
  done
}

# git clone 包装（自动套 GitHub 加速前缀；无 git 时回退到 codeload zip）
download_git_clone() {
  local url="$1" dest="$2"
  if command -v git >/dev/null 2>&1; then
    local real_url; real_url="$(with_gh_proxy "$url")"
    git clone --depth 1 "$real_url" "$dest" 2>&1 || git clone --depth 1 "$url" "$dest"
    return $?
  fi
  # 无 git：下载 codeload tarball 并解压
  warn "未找到 git，尝试下载 zip 包代替"
  local owner_repo="${url#https://github.com/}"
  owner_repo="${owner_repo%.git}"
  local default_branch="main"
  local zip_url="https://codeload.github.com/${owner_repo}/zip/refs/heads/${default_branch}"
  local tmp; tmp="$(mktemp -d)"
  download "$zip_url" "$tmp/repo.zip" || return 1
  # 解压（unzip 或 python）
  if command -v unzip >/dev/null 2>&1; then
    (cd "$tmp" && unzip -q repo.zip)
  else
    (cd "$tmp" && python3 -c "import zipfile; zipfile.ZipFile('repo.zip').extractall('.')")
  fi
  local extracted; extracted="$(ls -d "$tmp"/*/ | head -1)"
  mv "$extracted" "$dest"
  rm -rf "$tmp"
}
