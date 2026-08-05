# mihomoDNS

> clash-for-linux（代理） + mosdns（DNS 分流） 一键安装项目，按「机场」个性化配置
>
> 一个仓库即可在 Linux 上一键装好代理 + DNS 分流联动；内置 6 套机场预设，开箱即用。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-amd64%20%7C%20arm64%20%7C%20armv7-lightgrey.svg)]()
[![Shell](https://img.shields.io/badge/shell-bash-4%2B-green.svg)]()

---

## 目录

- [项目简介](#项目简介)
- [架构与端口联动](#架构与端口联动)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [安装参数详解](#安装参数详解)
- [机场个性化配置](#机场个性化配置)
  - [内置预设](#内置预设)
  - [字段说明](#字段说明)
  - [新增自定义机场](#新增自定义机场)
  - [完整配置示例](#完整配置示例)
- [安装后使用](#安装后使用)
- [卸载](#卸载)
- [目录结构](#目录结构)
- [常见问题](#常见问题)
- [故障排查与日志](#故障排查与日志)
- [上游项目致谢](#上游项目致谢)
- [声明](#声明)

---

## 项目简介

把两个互补的开源项目打包为一键安装：

| 组件 | 来源 | 职责 |
| --- | --- | --- |
| **clash-for-linux** | [wnlen/clash-for-linux](https://github.com/wnlen/clash-for-linux) | 代理与节点分流，内置 fakeip DNS |
| **mosdns** | [jasonxtt/mosdns](https://github.com/jasonxtt/mosdns) | DNS 智能分流（国内外分流） |

- **clash-for-linux** 有完善的代理与节点分流，但没有面向多机场的 DNS 分流策略。
- **mosdns** 有 DNS 智能分流能力，但需要外部代理（mihomo）提供 SOCKS 与 fakeip 上游。
- 二者天然互补：**mosdns 做国内外 DNS 分流 → clash 做流量代理分流**，组合后既有干净的 DNS，又有稳定的代理。

本项目把两个子项目源码 **vendored 打包进本仓库**（克隆本仓库即含完整源码，无需再拉取子项目），并按机场特征（协议、IPv6、流媒体、DNS 模式）自动生成各自的配置，让它们开箱联动。

---

## 架构与端口联动

```
┌──────────────────────────────────────────────────────────┐
│                       宿主机                              │
│                                                          │
│   系统/应用 ──DNS查询──► mosdns(:5335)                    │
│                           │                              │
│         ┌─────────────────┼─────────────────┐            │
│         ▼                                   ▼            │
│   国内 DNS 直连                    国外 DNS ──SOCKS──► clash(:7890)
│   (223.5.5.5 等)                  (1.1.1.1/8.8.8.8)  │    │
│                                                      │    │
│   fakeip 域名 ──► clash 内部 DNS(:1053) ◄────────────┘    │
│                          │                              │
│   clash(mihomo) 代理分流 ◄┘                              │
│   WebUI: http://<IP>:9090/ui   mosdns WebUI: :9099      │
└──────────────────────────────────────────────────────────┘
```

| 端口 | 服务 | 说明 |
| --- | --- | --- |
| `7890` | clash mixed-port | HTTP/SOCKS 混合代理，mosdns 国外 DNS 经此转发 |
| `9090` | clash external-controller | clash API 与 WebUI |
| `1053` | clash DNS | mihomo 内部 DNS（fakeip/redir-host） |
| `5335` | mosdns | mosdns 监听，供系统/应用查询 |
| `9099` | mosdns WebUI | 浏览器管理界面 |

> 所有端口均可在 `.env` 或 `airports/<name>.conf` 中调整。

---

## 系统要求

| 项 | 要求 |
| --- | --- |
| 操作系统 | **Linux**（amd64 / arm64 / armv7）。macOS 仅支持 `--config-only` 生成配置 |
| 权限 | root 走 systemd 自启；普通用户走脚本（nohup）模式 |
| 依赖命令 | `bash` ≥ 4、`tar`、`curl` 或 `wget`（二选一） |
| 网络 | 能访问 GitHub（直连或经 `CLASH_GH_PROXY` 加速） |
| 订阅 | 一个 clash/mihomo 格式的订阅链接 |

---

## 快速开始

### 1. 克隆仓库

本仓库已 vendored 子项目源码，**克隆即完整**，无需再拉取子项目：

```bash
git clone https://github.com/inzaghiaimar/mihomoDNS.git
cd mihomoDNS
```

### 2. 一键安装

最简单：交互式选机场 + 填订阅

```bash
bash install.sh
```

指定机场 + 订阅链接（推荐）

```bash
bash install.sh --airport generic \
  --subscription-url "https://your-airport.example.com/api/v1/client/subscribe?token=xxx"
```

Hysteria2 机场

```bash
bash install.sh --airport hysteria2 \
  --subscription-url "https://your-airport.example.com/sub"
```

装完不自动启动（仅安装二进制与配置）

```bash
bash install.sh --airport generic --subscription-url "https://..." --skip-start
```

### 3. 演练（推荐先跑一次）

`--dry-run` 只打印将要执行的步骤，不实际安装，适合先确认配置是否符合预期：

```bash
bash install.sh --dry-run --airport streaming --subscription-url "https://..."
```

---

## 安装参数详解

```text
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
  -h, --help                   显示帮助
```

### 常用组合

```bash
# 列出可选机场
bash install.sh --list-airports

# 只装 mosdns（clash 已装好）
bash install.sh --only mosdns --airport generic --subscription-url "https://..."

# 详细日志 + 指定日志文件（排查问题用）
bash install.sh -v --log-file /tmp/mihomo-install.log --airport generic --subscription-url "https://..."

# 仅生成配置，不下载二进制（macOS 或只想看配置）
bash install.sh --config-only --airport streaming
```

### 安装流程

`install.sh` 会依次执行（每步有计时与错误捕获）：

1. **前置检查** — 依赖命令、系统架构、GitHub 连通性
2. **子项目就位检查** — vendored 已含则跳过；缺失则自动从上游克隆
3. **选择机场** — `--airport` > `.env` > 交互式
4. **生成配置** — `.env` / `clash-for-linux/config/mixin.yaml` / `runtime/mosdns/config_custom.yaml`
5. **安装 clash** — 调用 clash-for-linux 的 `install.sh`
6. **安装 mosdns** — 下载 release 二进制 + 写入 systemd unit
7. **启动 & 联动检查** — clash / mosdns 启动，端口健康检查

---

## 机场个性化配置

「机场」指订阅服务提供方。不同机场在协议、IPv6 支持、DNS 需求、流媒体规则等方面存在差异。`airports/` 目录为每类机场提供一套预设配置，安装时 `--airport <name>` 选择即可。

### 内置预设

| 机场 | 文件 | 适用场景 | 关键差异 |
| --- | --- | --- | --- |
| `default` | [default.conf](airports/default.conf) | 模板 | 占位，填订阅即用 |
| `generic` | [generic.conf](airports/generic.conf) | 标准协议机场 | vmess/vless/trojan，fakeip，IPv6 auto |
| `hysteria2` | [hysteria2.conf](airports/hysteria2.conf) | Hy2 机场 | mihomo 内核，需 UDP 放行 |
| `ipv6-only` | [ipv6-only.conf](airports/ipv6-only.conf) | IPv6-only 节点 | 内核 IPv6 + DNS AAAA 开 |
| `streaming` | [streaming.conf](airports/streaming.conf) | 流媒体机场 | 内置 Netflix/Disney+/YouTube 规则 |
| `china-optimized` | [china-optimized.conf](airports/china-optimized.conf) | 国内优化 | redir-host 模式，IPv6 off |

### 字段说明

每个 `airports/<name>.conf` 以 shell 变量定义以下字段：

| 字段 | 说明 | 示例 |
| --- | --- | --- |
| `AIRPORT_NAME` | 机场显示名 | `"流媒体优化机场"` |
| `AIRPORT_SUBSCRIPTION_URL` | 订阅链接（clash/mihomo YAML、base64 或分享链接均可） | `"https://..."` |
| `AIRPORT_SUBSCRIPTION_UA` | 拉取订阅时的 User-Agent（默认 `clash-verge/v2.4.0`，兼容 hy2/anytls） | `"clash-verge/v2.4.0"` |
| `AIRPORT_IPV6` | 是否启用内核 IPv6 与 DNS AAAA | `auto` / `on` / `off` |
| `AIRPORT_DNS_MODE` | clash DNS 增强模式 | `fakeip` / `redir-host` |
| `AIRPORT_KERNEL` | 代理内核 | `mihomo` / `clash` |
| `AIRPORT_DOMESTIC_DNS` | 国内 DNS，分号分隔 | `"223.5.5.5;119.29.29.29"` |
| `AIRPORT_PROXY_DNS` | 国外 DNS（走代理），分号分隔 | `"https://1.1.1.1/dns-query;tls://8.8.8.8:853"` |
| `AIRPORT_RULES_EXTRA` | 额外规则（YAML 数组文本，追加到 rules 前） | 见 streaming 示例 |
| `AIRPORT_PROXY_GROUPS_EXTRA` | 额外策略组（YAML 文本） | — |
| `AIRPORT_TUN` | 是否启用 Tun 透明代理（需 root） | `true` / `false` |
| `AIRPORT_NOTES` | 备注 | — |

### 新增自定义机场

复制任一预设并修改：

```bash
cp airports/generic.conf airports/myairport.conf
# 编辑 myairport.conf，填入订阅链接与个性化设置
bash install.sh --airport myairport
```

### 完整配置示例

#### 示例 1：流媒体优化机场（streaming.conf）

```bash
AIRPORT_NAME="流媒体优化机场"
AIRPORT_SUBSCRIPTION_URL=""
AIRPORT_SUBSCRIPTION_UA="clash-verge/v2.4.0"
AIRPORT_IPV6="auto"
AIRPORT_DNS_MODE="fakeip"
AIRPORT_KERNEL="mihomo"
AIRPORT_DOMESTIC_DNS="223.5.5.5;119.29.29.29"
AIRPORT_PROXY_DNS="https://1.1.1.1/dns-query;tls://8.8.8.8:853"
AIRPORT_RULES_EXTRA='    - DOMAIN-SUFFIX,netflix.com,节点选择
    - DOMAIN-SUFFIX,nflxvideo.net,节点选择
    - DOMAIN-SUFFIX,disneyplus.com,节点选择
    - DOMAIN-SUFFIX,hbomax.com,节点选择
    - DOMAIN-SUFFIX,primevideo.com,节点选择
    - DOMAIN-SUFFIX,youtube.com,节点选择
    - DOMAIN-SUFFIX,googlevideo.com,节点选择
    - DOMAIN-KEYWORD,spotify,节点选择
    - DOMAIN-SUFFIX,hulu.com,节点选择'
AIRPORT_PROXY_GROUPS_EXTRA=""
AIRPORT_TUN="false"
AIRPORT_NOTES="流媒体：内置 Netflix/Disney+/HBO/YouTube 等走代理规则。"
```

#### 示例 2：IPv6-only 机场（ipv6-only.conf）

```bash
AIRPORT_NAME="IPv6-only 机场"
AIRPORT_SUBSCRIPTION_URL=""
AIRPORT_SUBSCRIPTION_UA="clash-verge/v2.4.0"
AIRPORT_IPV6="on"                    # 开启内核 IPv6 与 DNS AAAA
AIRPORT_DNS_MODE="fakeip"
AIRPORT_KERNEL="mihomo"
AIRPORT_DOMESTIC_DNS="2402:4e00::;2001:4860:4860::8888"   # IPv6 DNS
AIRPORT_PROXY_DNS="https://1.1.1.1/dns-query;tls://8.8.8.8:853"
AIRPORT_RULES_EXTRA=""
AIRPORT_PROXY_GROUPS_EXTRA=""
AIRPORT_TUN="false"
AIRPORT_NOTES="IPv6-only：内核 IPv6 与 DNS AAAA 已开启；请确认宿主机 IPv6 默认路由可用。"
```

#### 示例 3：国内优化机场（china-optimized.conf）

```bash
AIRPORT_NAME="国内优化机场"
AIRPORT_SUBSCRIPTION_URL=""
AIRPORT_SUBSCRIPTION_UA="clash-verge/v2.4.0"
AIRPORT_IPV6="off"                   # 关闭 IPv6
AIRPORT_DNS_MODE="redir-host"        # 保留真实 IP（非 fakeip）
AIRPORT_KERNEL="mihomo"
AIRPORT_DOMESTIC_DNS="223.5.5.5;119.29.29.29;114.114.114.114"
AIRPORT_PROXY_DNS="https://1.1.1.1/dns-query;tls://8.8.8.8:853"
AIRPORT_RULES_EXTRA=""
AIRPORT_PROXY_GROUPS_EXTRA=""
AIRPORT_TUN="false"
AIRPORT_NOTES="国内优化：redir-host 模式保留真实 IP，IPv6 关闭，国内 DNS 含 114。"
```

### 配置如何生效

安装时，[scripts/airport.sh](scripts/airport.sh) 会：

1. 加载 `airports/<name>.conf`
2. 把订阅、UA、IPv6、端口等写入 `.env`（供 clash-for-linux 读取）
3. 按机场特征生成 `clash-for-linux/config/mixin.yaml`（DNS、IPv6、规则覆盖）
4. 按国内/国外 DNS 与 SOCKS 端口生成 `runtime/mosdns/config_custom.yaml`

---

## 安装后使用

### clash 管理

```bash
clashon              # 开启代理（设置系统代理环境变量）
clashoff             # 关闭代理
clash                # 进入 clash 管理面板
clash ls             # 订阅列表
clash select         # 选择节点
clash mode           # 切换规则/全局/直连模式
clash mixin edit     # 编辑 mixin 重新生成运行配置
clash doctor         # 诊断
```

### mosdns 管理（systemd 安装时）

```bash
systemctl status mosdns       # 状态
systemctl restart mosdns      # 重启
systemctl stop mosdns         # 停止
journalctl -u mosdns -f       # 实时日志
```

### WebUI

- clash：<http://<本机IP>:9090/ui>
- mosdns：<http://<本机IP>:9099>

### 让系统 DNS 走 mosdns

```bash
# 方式 1：改 /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

# 方式 2：systemd-resolved
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/mosdns.conf > /dev/null <<'EOF'
[Resolve]
DNS=127.0.0.1:5335
DNSStubListener=no
EOF
sudo systemctl restart systemd-resolved
```

### 联动健康检查

```bash
bash scripts/integrate.sh check
```

---

## 卸载

```bash
# 保留运行目录
bash uninstall.sh

# 连运行目录一起删
bash uninstall.sh --purge-runtime -y

# 跳过确认
bash uninstall.sh -y
```

---

## 目录结构

```
mihomoDNS/
├── install.sh                 # 一键安装入口
├── uninstall.sh               # 卸载
├── .env.example               # 环境变量示例
├── airports/                  # 机场个性化配置
│   ├── README.md
│   ├── default.conf
│   ├── generic.conf
│   ├── hysteria2.conf
│   ├── ipv6-only.conf
│   ├── streaming.conf
│   └── china-optimized.conf
├── config/                    # 配置参考模板
│   ├── clash-template.yaml
│   └── mosdns-config.yaml
├── scripts/                   # 安装与联动逻辑
│   ├── common.sh              # 通用函数（日志、架构、下载、错误处理）
│   ├── airport.sh             # 机场加载与配置生成
│   ├── install-clash.sh       # 安装 clash-for-linux
│   ├── install-mosdns.sh      # 下载安装 mosdns
│   └── integrate.sh           # 联动启动与健康检查
├── clash-for-linux/           # vendored 子项目：clash/mihomo 管理
└── mosdns/                    # vendored 子项目：DNS 分流
```

> `runtime/` 目录在安装时自动生成，含 mosdns 配置/日志，已在 `.gitignore` 中忽略。

---

## 常见问题

**Q：mosdns 国外 DNS 为什么要走 clash 的 SOCKS？**
A：避免 DNS 泄露与污染。mosdns 把国外域名查询经 `127.0.0.1:7890`（clash mixed-port）转发到国外 DoH/DoT，结果由 clash 代理通道获取，不会被中间设备污染或看到明文 DNS。

**Q：fakeip 与 redir-host 怎么选？**
A：`fakeip`（默认）更快、对代理友好，mosdns 把代理域名指向 clash 的 fakeip 段；`redir-host` 保留真实 IP，适合需要真实 IP 的国内服务（如部分 CDN、登录态），见 `china-optimized` 机场。

**Q：Hysteria2 节点连不上？**
A：确认 `AIRPORT_KERNEL=mihomo`、宿主机有 IPv6 默认路由（IPv6-only 时）、防火墙放行 UDP/QUIC。

**Q：mosdns 监听 5335 而不是 53？**
A：非 root 无法绑 53。如需让系统 DNS 走 mosdns，见[安装后使用](#安装后使用)的「让系统 DNS 走 mosdns」。

**Q：GitHub 下载慢/失败？**
A：脚本默认用 `CLASH_GH_PROXY=https://ghfast.top` 加速。可在 `.env` 改为其他镜像（`https://gh-proxy.org`、`https://ghproxy.net`、`https://kkgithub.com`），或 `--skip-network-check` 跳过预检。

**Q：能只装其中一个吗？**
A：能。`bash install.sh --only clash` 或 `--only mosdns`。

---

## 故障排查与日志

安装日志默认写入 `runtime/install-<时间>.log`，包含每步的开始/完成/耗时与错误。

```bash
# 查看最近一次安装日志
ls -t runtime/install-*.log | head -1 | xargs tail -50

# 详细模式重装（打印每条命令）
bash install.sh -v --log-file /tmp/debug.log --airport generic --subscription-url "https://..."

# dry-run 演练
bash install.sh --dry-run --airport streaming

# clash 诊断
clash doctor

# mosdns 日志（systemd）
journalctl -u mosdns -n 100
```

### 错误处理机制

`install.sh` 已内置完善的错误处理：

- **`set -euo pipefail`** — 任意命令失败即终止，未定义变量报错
- **`trap ERR`** — 全局错误捕获，输出失败行号与所在步骤
- **`run_step`** — 每个步骤有名称、计时、错误包裹
- **前置检查** — 依赖命令、系统架构、网络连通性预检
- **`--dry-run`** — 演练模式，先确认再执行
- **`-v / --verbose`** — 详细日志，打印执行的每条命令

---

## 上游项目致谢

- [wnlen/clash-for-linux](https://github.com/wnlen/clash-for-linux) — Linux Clash/Mihomo 运行平台
- [jasonxtt/mosdns](https://github.com/jasonxtt/mosdns) — DNS 分流增强版（基于 yyysuo/mosdns）

本仓库已将上述两个项目的源码 vendored 打包，安装时无需再从外部拉取。

---

## 声明

本项目用于学习与研究，不得用于违反所在地法律法规的用途。使用前请确认订阅来源合规。
