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

log()     { printf '%s\n' "$*"; log_file "$*"; }
info()    { printf '%sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"; log_file "INFO  $*"; }
step()    { printf '%s➜%s %s\n' "$C_CYAN" "$C_RESET" "$*"; log_file "STEP  $*"; }
success() { printf '%s✔ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; log_file "OK    $*"; }
warn()    { printf '%s⚠ %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; log_file "WARN  $*"; }
error()   { printf '%s✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; log_file "ERROR $*"; }
die()     { error "$*"; exit 1; }

# verbose 模式：打印执行的每条命令
VERBOSE="${VERBOSE:-false}"
verbose_on()  { VERBOSE=true; set -x; }
verbose_off() { VERBOSE=false; set +x; }

# 日志文件：所有 log/info/step/... 同时写入此文件
LOG_FILE="${LOG_FILE:-}"
log_file() {
  [[ -z "$LOG_FILE" ]] && return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}
init_log_file() {
  LOG_FILE="${1:-}"
  [[ -z "$LOG_FILE" ]] && return 0
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  log_file "===== 日志开始 ====="
}

# 步骤计时：run_step "名称" cmd...
STEP_START_TS=0
STEP_NAME=""
run_step() {
  local name="$1"; shift
  STEP_NAME="$name"
  STEP_START_TS=$(date +%s)
  log_file ">>> 开始: $name"
  if ! "$@"; then
    local rc=$?
    error "步骤失败: $name（退出码 $rc）"
    [[ -n "$LOG_FILE" ]] && error "详见日志: $LOG_FILE"
    die "已终止"
  fi
  local elapsed=$(( $(date +%s) - STEP_START_TS ))
  log_file "<<< 完成: $name (耗时 ${elapsed}s)"
  STEP_NAME=""
}

# 全局错误捕获（set -e 触发时输出最后一条命令与行号）
trap_errors() {
  local rc=$?
  local line="?"
  [[ ${#BASH_LINENO[@]} -gt 0 ]] && line="${BASH_LINENO[0]}"
  error "脚本异常退出（行 ${line}，退出码 ${rc}）"
  [[ -n "${STEP_NAME:-}" ]] && error "失败步骤: $STEP_NAME"
  [[ -n "${LOG_FILE:-}" ]] && error "详见日志: $LOG_FILE"
  exit $rc
}

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
# 容错加载：旧版 .env 可能存在未加引号、含分号的值（如 DNS 列表），
# 直接 source 会被当作多条命令执行而触发 set -e 退出。这里临时关闭
# errexit 并抑制错误输出，坏行被跳过；随后 apply_airport_to_env 会用
# set_env_value 以正确的带引号格式重写整个 .env，从而自愈。
load_env() {
  local env_file="$PROJECT_DIR/.env"
  [[ -f "$env_file" ]] || return 0
  local errexit_was_on=0
  [[ $- == *e* ]] && errexit_was_on=1
  set +e
  set -a
  # shellcheck disable=SC1090
  source "$env_file" 2>/dev/null || true
  set +a
  [[ $errexit_was_on -eq 1 ]] && set -e
}

# 写入/更新 .env 中某个键
# 值始终用双引号包裹，确保含 ; / : 等特殊字符的值（如 DNS 列表
# "223.5.5.5;119.29.29.29"）在被 source 加载时不会被当作多条命令解析。
set_env_value() {
  local key="$1" val="$2" env_file="$PROJECT_DIR/.env"
  # 转义值中的反斜杠与双引号，避免破坏 .env 的双引号语法
  local escaped="${val//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  touch "$env_file"
  # 删除已有同名键（兼容旧的无引号写法），再追加带引号的新行；
  # 用 grep -v + 追加代替 sed 替换，避免值中的 / & 等字符破坏 sed 替换串。
  if [[ -s "$env_file" ]]; then
    local tmp; tmp="$(mktemp)"
    grep -vE "^${key}=" "$env_file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$env_file"
  fi
  printf '%s="%s"\n' "$key" "$escaped" >> "$env_file"
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

# 批量前置依赖检查：require_cmds curl wget tar bash
# 任一缺失则汇总报错（不自动安装，保持前置检查的纯净）
# 用法: require_cmds curl wget tar
#       require_cmds -o curl wget tar   # -o: 可选，缺失只 warn 不 fail
require_cmds() {
  local optional=false
  [[ "${1:-}" == "-o" ]] && { optional=true; shift; }
  local missing=()
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing+=("$c")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    if $optional; then
      warn "可选命令缺失: ${missing[*]}（不影响核心安装）"
    else
      error "缺少依赖命令: ${missing[*]}"
      info "请先安装，例如: apt-get install -y ${missing[*]}"
      return 1
    fi
  fi
  return 0
}

# 网络连通性检查（可选）：检测 GitHub / DNS 是否可达
check_network() {
  local target="${1:-https://github.com}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSI --connect-timeout 10 "$target" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=10 --spider "$target" 2>/dev/null
  else
    return 0  # 无工具则跳过
  fi
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
