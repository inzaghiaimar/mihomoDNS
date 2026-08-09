# mihomoDNS

> clash-for-linux（代理） + mosdns（DNS 分流） 一键安装项目，按「机场」个性化配置
>
> 面向 **Linux** 一键装好代理 + DNS 分流联动；内置 6 套机场预设；支持与 **ROS（RouterOS）/ 爱快 iKuai** 主路由配合写入/删除静态路由。

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
- [主路由配合指南：DNS 劫持与静态路由](#主路由配合指南dns-劫持与静态路由)
  - [前置条件：mosdns 局域网监听](#前置条件mosdns-局域网监听)
  - [配置方案选择](#配置方案选择)
  - [ROS / RouterOS 配置](#ros--routeros-配置)
  - [爱快 iKuai 配置](#爱快-ikuai-配置)
  - [Linux 本机静态路由](#linux-本机静态路由)
  - [路由参数一览](#路由参数一览)
  - [一键删除所有路由规则](#一键删除所有路由规则)
- [PVE 部署操作手册](#pve-部署操作手册)
  - [PVE 选型对比](#pve-选型对比)
  - [PVE 网络拓扑](#pve-网络拓扑)
  - [PVE LXC 容器完整部署](#pve-lxc-容器完整部署)
  - [PVE KVM 虚拟机完整部署](#pve-kvm-虚拟机完整部署)
  - [PVE 部署后验证](#pve-部署后验证)
  - [PVE 常见问题](#pve-常见问题)
- [ESXi 部署操作手册](#esxi-部署操作手册)
  - [ESXi 环境准备](#esxi-环境准备)
  - [ESXi 虚拟机创建完整步骤](#esxi-虚拟机创建完整步骤)
  - [ESXi 网络配置](#esxi-网络配置)
  - [ESXi 安装 mihomoDNS](#esxi-安装-mihomodns)
  - [ESXi 部署后验证](#esxi-部署后验证)
  - [ESXi 常见问题](#esxi-常见问题)
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

本仓库已将两个子项目源码 **vendored 打包**（克隆即完整），并按机场特征自动生成各自的配置，同时支持与 ROS / 爱快主路由配合写入/删除静态路由表。

---

## 架构与端口联动

```
┌──────────────────────────────────────────────────────────┐
│                    mihomoDNS 服务器                        │
│                                                          │
│   系统/应用 ──DNS查询──► mosdns(0.0.0.0:5335)             │
│                           │                              │
│         ┌─────────────────┼─────────────────┐            │
│         ▼                                   ▼            │
│   国内域名 → 国内 DNS 直连         国外域名 → TCP DNS      │
│   (geosite_cn 域名匹配)            ──SOCKS──► clash(:7890)│
│   223.5.5.5 / 119.29.29.29         1.1.1.1 / 8.8.8.8     │
│                                                      │    │
│   fakeip 域名 ──► clash 内部 DNS(:1053) ◄────────────┘    │
│                          │                              │
│   clash(mihomo) 代理分流 ◄┘                              │
│   WebUI: http://<IP>:9090/ui   mosdns WebUI: http://<IP>:9099
└──────────────────────────────────────────────────────────┘
          ▲                                    ▲
          │ 客户端 DNS(53) 经主路由 DNAT 指向本机  │ 本机默认网关经主路由
          │                                    │
┌─────────┴────────────────────────────────────┴──────────┐
│              ROS / 爱快 主路由（192.168.1.1）              │
│  - DHCP: DNS → 192.168.1.2（推荐）                        │
│  - NAT: 53 → 192.168.1.2:5335（DNS 劫持，兜底）           │
└──────────────────────────────────────────────────────────┘
```

| 端口 | 服务 | 说明 | 默认监听 |
| --- | --- | --- | --- |
| `7890` | clash mixed-port | HTTP/SOCKS 混合代理，mosdns 国外 DNS 经此转发 | `*` |
| `9090` | clash controller | clash API 与 WebUI | `0.0.0.0` |
| `1053` | clash DNS | mihomo 内部 DNS（fakeip） | `*` |
| `5335` | mosdns DNS | mosdns 监听，供系统/局域网查询 | `0.0.0.0` |
| `9099` | mosdns WebUI | 浏览器管理界面（需配置 `api.http`） | `0.0.0.0` |

> 所有端口与监听地址均可在 `.env` 中调整：
> - `MOSDNS_LISTEN_ADDR` — mosdns 监听地址（`0.0.0.0`=局域网可访问，`127.0.0.1`=仅本机）
> - `MOSDNS_DNS_PORT` / `MOSDNS_WEBUI_PORT` / `CLASH_MIXED_PORT` 等

---

## 系统要求

| 项 | 要求 |
| --- | --- |
| 操作系统 | **Linux**（amd64 / arm64 / armv7）。本项目仅面向 Linux |
| 权限 | root 走 systemd 自启；普通用户走脚本（nohup）模式 |
| 依赖命令 | `bash` ≥ 4、`tar`、`curl` 或 `wget`（二选一）、`ip`（路由功能用） |
| 网络 | 能访问 GitHub（直连或经 `CLASH_GH_PROXY` 加速） |
| 订阅 | 一个 clash/mihomo 格式的订阅链接 |

---

## 快速开始

### 1. 克隆仓库

本仓库已 vendored 子项目源码，**克隆即完整**：

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

安装并同时写入 Linux 本机静态路由（旁路由场景）

```bash
bash install.sh --airport generic --subscription-url "https://..." \
  --route-target linux --route-gateway 192.168.1.1
```

### 3. 演练（推荐先跑一次）

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
  --config-only                仅生成配置，不下载二进制
  --dry-run                    演练模式，只打印将要执行的步骤，不实际改动
  -v, --verbose                详细日志（打印执行的每条命令）
  --log-file <path>            指定日志文件路径（默认 runtime/install-<时间>.log）
  --no-color                   关闭彩色输出
  --skip-network-check         跳过 GitHub 连通性预检
  --list-airports              列出可选机场预设后退出

  --route-target <linux|ros|ikuai>  安装后写入静态路由（Linux本机/ROS/爱快）
  --route-clean                删除已写入的静态路由（配合 --route-target）
  --route-gateway <ip>         主路由 LAN IP（如 192.168.1.1）
  --route-lan-ip <ip>          本机 LAN IP（如 192.168.1.2）
  --route-lan-if <if>          本机网卡（如 eth0，linux 目标可自动探测）
  --route-lan-cidr <cidr>      本机网段（如 192.168.1.0/24）
  --route-ssh-host <ip>        ROS SSH 主机（ros 目标用）
  --route-ssh-port <port>      SSH 端口（默认 22）
  --route-ssh-user <user>      SSH 用户（默认 admin）
  --route-ikuai-host <ip>      爱快后台地址（ikuai 目标用）
  --route-ikuai-user <user>    爱快 SSH 用户（默认 admin）
  -h, --help                   显示帮助
```

---

## 机场个性化配置

「机场」指订阅服务提供方。不同机场在协议、IPv6 支持、DNS 需求、流媒体规则等方面存在差异。`airports/` 目录为每类机场提供一套预设配置。

### 内置预设

| 机场 | 文件 | 适用场景 | 关键差异 |
| --- | --- | --- | --- |
| `default` | [airports/default.conf](airports/default.conf) | 模板 | 占位，填订阅即用 |
| `generic` | [airports/generic.conf](airports/generic.conf) | 标准协议机场 | vmess/vless/trojan，fakeip，IPv6 auto |
| `hysteria2` | [airports/hysteria2.conf](airports/hysteria2.conf) | Hy2 机场 | mihomo 内核，需 UDP 放行 |
| `ipv6-only` | [airports/ipv6-only.conf](airports/ipv6-only.conf) | IPv6-only 节点 | 内核 IPv6 + DNS AAAA 开 |
| `streaming` | [airports/streaming.conf](airports/streaming.conf) | 流媒体机场 | 内置 Netflix/Disney+/YouTube 规则 |
| `china-optimized` | [airports/china-optimized.conf](airports/china-optimized.conf) | 国内优化 | IPv6 off，国内 DNS 含 114 |

### 新增自定义机场

```bash
cp airports/generic.conf airports/myairport.conf
# 编辑 myairport.conf，填入订阅链接与个性化设置
bash install.sh --airport myairport
```

### 字段说明

| 字段 | 说明 | 示例 |
| --- | --- | --- |
| `AIRPORT_NAME` | 机场显示名 | `"流媒体优化机场"` |
| `AIRPORT_SUBSCRIPTION_URL` | 订阅链接 | `"https://..."` |
| `AIRPORT_IPV6` | 是否启用内核 IPv6 与 DNS AAAA | `auto` / `on` / `off` |
| `AIRPORT_DNS_MODE` | clash DNS 增强模式 | `fakeip` / `fake-ip` / `redir-host`（脚本自动兜底为 mihomo 合法的 `fake-ip`） |
| `AIRPORT_KERNEL` | 代理内核 | `mihomo` / `clash` |
| `AIRPORT_DOMESTIC_DNS` | 国内 DNS，分号分隔 | `"223.5.5.5;119.29.29.29"` |
| `AIRPORT_PROXY_DNS` | 国外 DNS（走代理），分号分隔 | `"https://1.1.1.1/dns-query;tls://8.8.8.8:853"` |
| `AIRPORT_RULES_EXTRA` | 额外规则（追加到 rules 前） | 见 streaming 示例 |
| `AIRPORT_TUN` | 是否启用 Tun 透明代理（需 root） | `true` / `false` |

---

## 主路由配合指南：DNS 劫持与静态路由

mihomoDNS 服务器通常作为**旁路由 / DNS 服务器**部署，主路由是 ROS（RouterOS）或爱快 iKuai。需要在主路由上配置 DNS 指向，让局域网客户端的 DNS 查询到达 mosdns。

> 下文以 `192.168.1.0/24` 网段为例：主路由 `192.168.1.1`，mihomoDNS 服务器 `192.168.1.2`。请按实际网段替换。

### 前置条件：mosdns 局域网监听

mosdns 默认监听 `0.0.0.0:5335`（局域网可访问）。安装后请确认：

```bash
# 在 mihomoDNS 服务器上验证
ss -tulnp | grep 5335
# 应显示 *:5335（而非 127.0.0.1:5335）

# 放行防火墙
ufw allow 5335/udp && ufw allow 5335/tcp
ufw allow 9099/tcp  # mosdns WebUI
```

> 若监听地址为 `127.0.0.1`，在 `.env` 中设置 `MOSDNS_LISTEN_ADDR=0.0.0.0` 后重新执行 `bash install.sh --config-only`。

### 配置方案选择

| 方案 | 作用 | 适用场景 | 是否需要主路由操作 |
| --- | --- | --- | --- |
| **A. DHCP 分发 DNS** | 客户端自动获取 mosdns 作为 DNS | 新设备 / 配合 DHCP | 是（改 DHCP 设置） |
| **B. DNS 劫持** | 强制所有 53 端口流量指向 mosdns | 兜底 / 防硬编码 DNS 绕过 | 是（添加 NAT 规则） |
| C. 旁路由回程路由 | 全流量经 mihomoDNS 代理 | **仅 TUN 模式** | 是（添加静态路由） |

> **推荐**：方案 A + B 同时配置。方案 C 仅在开启 clash TUN 透明代理时使用，当前默认配置（SOCKS 模式）不需要。

---

### ROS / RouterOS 配置

#### 方案 A：DHCP 分发 DNS（推荐）

在 ROS 上把 DHCP 下发的 DNS 服务器改为 mihomoDNS 服务器地址：

```routeros
# 把所有 DHCP 网络的 DNS 服务器设为 mihomoDNS 服务器
/ip dhcp-server network set [find] dns-server=192.168.1.2
```

> ⚠️ **DHCP DNS 服务器填几个？**
>
> 客户端（尤其 Windows / 安卓）是**并发查询**所有配置的 DNS 服务器，谁先返回就用谁。如果填了备用公共 DNS（如 223.5.5.5、119.29.29.29），其响应通常快于经代理查询的 mosdns，会**绕过分流**导致污染。
>
> **推荐配置**：
>
> | 方案 | DNS 1 | DNS 2 | DNS 3 | 说明 |
> | --- | --- | --- | --- | --- |
> | ✅ **严格分流（推荐）** | `192.168.1.2`（mihomoDNS） | 留空 | 留空 | 所有查询必经 mosdns，分流最干净 |
> | ⚠️ 带兜底（有绕过风险） | `192.168.1.2` | `192.168.1.1`（主路由 LAN IP） | 留空 | mihomoDNS 挂掉时通过 ROS 主路由 DNS 兜底，但并发查询可能偶尔绕过 |
> | ❌ 不推荐 | `192.168.1.2` | `223.5.5.5` | `119.29.29.29` | 公共 DNS 响应快，大概率绕过 mosdns |
>
> **最佳实践**：DHCP 只填一个 mihomoDNS + 同时做**方案 B DNS 劫持**，即使客户端手动改 DNS 也会被强制拦截。

> ROS 自己的系统 DNS（`/ip dns set servers=`）与 DHCP 下发无关。如果希望 ROS 系统本身也走 mosdns 分流，可执行：
> ```routeros
> /ip dns set allow-remote-requests=yes servers=192.168.1.2
> ```

#### 方案 B：DNS 劫持（推荐配合 A 使用）

强制局域网所有 DNS 查询（含硬编码 8.8.8.8 的设备）指向 mosdns：

```routeros
# UDP 53 → 192.168.1.2:5335
/ip firewall nat add chain=dstnat protocol=udp dst-port=53 \
    action=dst-nat to-addresses=192.168.1.2 to-ports=5335 \
    comment="mihomoDNS-udp"

# TCP 53 → 192.168.1.2:5335
/ip firewall nat add chain=dstnat protocol=tcp dst-port=53 \
    action=dst-nat to-addresses=192.168.1.2 to-ports=5335 \
    comment="mihomoDNS-tcp"
```

> 因为大多数客户端 DNS 指向 53 端口，而 mosdns 监听 5335，所以需要 DNAT 做端口转换。

#### 方案 C：旁路由回程路由（仅 TUN 模式）

> **警告**：此方案仅适用于 clash 开启 TUN 透明代理（`AIRPORT_TUN=true`）的场景。默认 SOCKS 模式下执行会导致**路由回环**，切勿使用！

```routeros
# 仅 TUN 模式：把需要走代理的网段路由到 mihomoDNS
/ip route add dst-address=192.168.1.0/24 gateway=192.168.1.2 \
    comment="mihomoDNS-route"

# 仅 TUN 模式：把特定客户端全部流量经 mihomoDNS 代理
/ip route add dst-address=192.168.1.10/32 gateway=192.168.1.2
```

#### 删除 ROS 规则

```routeros
# 删除 DNS 劫持 NAT 规则（按 comment 匹配）
/ip firewall nat remove [find comment~"mihomoDNS"]

# 删除回程静态路由
/ip route remove [find comment="mihomoDNS-route"]

# 验证
/ip firewall nat print
/ip route print
```

#### ROS WebFig / WinBox 手动操作

1. **DNS 劫持（NAT）**：`IP` → `Firewall` → `NAT` → `+`
   - `Chain`: dstnat
   - `Protocol`: 6 (tcp) 或 17 (udp)
   - `Dst. Port`: 53
   - `Action`: dst-nat
   - `To Addresses`: 192.168.1.2
   - `To Ports`: 5335

2. **DHCP DNS**：`IP` → `DHCP Server` → `Networks` → 编辑 → `DNS Servers`: 192.168.1.2

#### SSH 自动执行

```bash
# 安装 sshpass
apt-get install -y sshpass

# 自动执行（SSH 密码通过环境变量 SSHPASS 传入）
SSHPASS=your_password bash scripts/route.sh apply \
  --target ros \
  --lan-ip 192.168.1.2 \
  --ssh-host 192.168.1.1 \
  --ssh-user admin
```

---

### 爱快 iKuai 配置

#### 方案 A：DHCP 分发 DNS

爱快 Web 后台 → `网络设置` → `DHCP 服务端` → 编辑 DHCP 地址池 → `DNS` 填 `192.168.1.2`

#### 方案 B：DNS 劫持（端口映射）

爱快 Web 后台 → `流控分流` → `端口映射` → `添加`：

| 协议 | 外部端口 | 内部 IP | 内部端口 |
| --- | --- | --- | --- |
| UDP | 53 | 192.168.1.2 | 5335 |
| TCP | 53 | 192.168.1.2 | 5335 |

或经 SSH 执行（爱快基于 OpenWrt，支持 iptables）：

```bash
ssh root@192.168.1.1

iptables -t nat -A PREROUTING -p udp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
iptables -t nat -A PREROUTING -p tcp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
```

#### 方案 C：旁路由回程路由（仅 TUN 模式）

> **警告**：同 ROS 方案 C，仅 TUN 模式可用。

爱快 Web 后台 → `网络设置` → `路由设置` → `静态路由` → `添加`：
- 目标网段: `192.168.1.0/24`，网关: `192.168.1.2`

#### 删除爱快规则

```bash
# Web 后台：流控分流 → 端口映射 → 删除 53 → 192.168.1.2:5335 的规则
# Web 后台：网络设置 → 路由设置 → 静态路由 → 删除相关条目

# SSH
iptables -t nat -D PREROUTING -p udp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
iptables -t nat -D PREROUTING -p tcp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
ip route del 192.168.1.0/24 via 192.168.1.2

# 或用脚本
bash scripts/route.sh clean --target ikuai --lan-ip 192.168.1.2 --ikuai-host 192.168.1.1
```

---

### Linux 本机静态路由

适用于 mihomoDNS 服务器本身需要设置默认网关、关闭 rp_filter、开启 IP 转发的场景。

#### 一键写入

```bash
# 自动探测网卡与本机 IP
bash install.sh --airport generic --subscription-url "https://..." \
  --route-target linux --route-gateway 192.168.1.1

# 或单独调用 route.sh
bash scripts/route.sh apply \
  --target linux \
  --gateway 192.168.1.1 \
  --lan-if eth0 \
  --lan-ip 192.168.1.2 \
  --lan-cidr 192.168.1.0/24
```

#### 实际执行的命令

```bash
# 1) 设置默认网关经主路由
ip route replace default via 192.168.1.1 dev eth0

# 2) 关闭 rp_filter（旁路由防丢包）
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.eth0.rp_filter=0

# 3) 开启 IP 转发
sysctl -w net.ipv4.ip_forward=1

# 4) 持久化到 /etc/sysctl.d/99-mihomoDNS.conf
cat > /etc/sysctl.d/99-mihomoDNS.conf <<EOF
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.ip_forward=1
EOF
sysctl -p /etc/sysctl.d/99-mihomoDNS.conf
```

#### 删除

```bash
bash scripts/route.sh clean --target linux
# 会删除 /etc/sysctl.d/99-mihomoDNS.conf
# 默认网关与 rp_filter 需手动恢复（脚本不擅自改回，避免断网）
```

---

### 路由参数一览

| 参数 | 环境变量 | 适用目标 | 说明 |
| --- | --- | --- | --- |
| `--route-target` | `ROUTE_TARGET` | 所有 | `linux` / `ros` / `ikuai` |
| `--route-gateway` | `ROUTE_GATEWAY` | linux | 主路由 LAN IP（默认网关） |
| `--route-lan-if` | `ROUTE_LAN_IF` | linux | 本机网卡（可自动探测） |
| `--route-lan-ip` | `ROUTE_LAN_IP` | ros/ikuai | 本机 LAN IP（DNAT 目标） |
| `--route-lan-cidr` | `ROUTE_LAN_CIDR` | ros/ikuai | 本机网段（旁路由回程路由） |
| `--route-ssh-host` | `ROUTE_SSH_HOST` | ros | ROS SSH 主机 |
| `--route-ssh-port` | `ROUTE_SSH_PORT` | ros | SSH 端口（默认 22） |
| `--route-ssh-user` | `ROUTE_SSH_USER` | ros | SSH 用户（默认 admin） |
| `--route-ikuai-host` | `ROUTE_IKUAI_HOST` | ikuai | 爱快后台地址 |
| `--route-ikuai-user` | `ROUTE_IKUAI_USER` | ikuai | 爱快 SSH 用户（默认 admin） |

> 这些参数也可写在 `.env` 文件中，见 `.env.example` 的「静态路由」部分。

### 一键删除所有路由规则

```bash
# Linux 本机
bash scripts/route.sh clean --target linux

# ROS
bash scripts/route.sh clean --target ros --lan-ip 192.168.1.2 --ssh-host 192.168.1.1

# 爱快
bash scripts/route.sh clean --target ikuai --lan-ip 192.168.1.2 --ikuai-host 192.168.1.1

# 经 install.sh 删除
bash install.sh --route-target ros --route-clean --route-lan-ip 192.168.1.2 --route-ssh-host 192.168.1.1
```

> **注意**：Linux 目标删除时只清理本项目写入的 `/etc/sysctl.d/99-mihomoDNS.conf`，不擅自改回默认网关与 rp_filter，避免断网。请按提示手动恢复。

---

## PVE / ESXi 部署（精简版）

> 以下保留核心步骤，以 `192.168.1.2` 为 mihomoDNS 服务器，`192.168.1.1` 为主路由。

### 选型：LXC vs KVM vs ESXi VM

| 平台 | 类型 | 推荐资源 | Tun 透明代理 | 适用 |
| --- | --- | --- | --- | --- |
| **PVE LXC** | 容器 | 1C / 256M / 4G | 需宿主透传 `/dev/net/tun` | 纯 DNS + SOCKS（默认模式），最省资源 |
| **PVE KVM** | 虚拟机 | 1C / 512M / 8G | 原生支持 | 需要 Tun 模式 |
| **ESXi** | 虚拟机 | 1C / 512M / 8G 精简盘 | 原生支持 | VMware 环境 |

### PVE LXC 容器（推荐，纯 DNS+SOCKS 模式）

```bash
# ===== PVE 宿主执行 =====

# 1. 加载 TUN 模块
modprobe tun && echo "tun" >> /etc/modules-load.d/tun.conf

# 2. 下载模板
pveam update
pveam download local debian-12-standard_12.2-1_amd64.tar.zst

# 3. 创建容器（CTID=100）
pct create 100 local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --rootfs local-lvm:4 --ostype debian --hostname mihomoDNS \
  --memory 256 --swap 0 --cores 1 --password your_password \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.2/24,gw=192.168.1.1 \
  --unprivileged 1

# 4. 关键特性（非特权容器必加）
cat >> /etc/pve/lxc/100.conf <<'EOF'
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
lxc.capabilities: cap_net_admin cap_net_raw cap_net_bind_service
EOF

# 5. 启动并自启
pct start 100
pct set 100 --onboot 1

# ===== 容器内执行 =====
pct enter 100
apt update && apt install -y curl tar git iproute2 procps
cd /root
git clone https://github.com/inzaghiaimar/mihomoDNS.git
cd mihomoDNS
bash install.sh --airport generic --subscription-url "https://你的订阅"
```

### PVE KVM 虚拟机

```bash
# PVE 宿主：创建 VM（VMID=101）
qm create 101 --name mihomoDNS --memory 512 --cores 1 --sockets 1 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single \
  --scsi0 local-lvm:8,discard=on --ide2 local:iso/debian-12-amd64-netinst.iso,media=cdrom \
  --boot order=scsi0,ide2 --ostype l26
qm set 101 --onboot 1
qm start 101
# 打开 Console 安装系统，IP/网关/DNS 指向 192.168.1.2 / 192.168.1.1 / 192.168.1.1

# 虚拟机内：安装 mihomoDNS
apt update && apt install -y curl tar git
cd /root && git clone https://github.com/inzaghiaimar/mihomoDNS.git && cd mihomoDNS
bash install.sh --airport generic --subscription-url "https://你的订阅"
```

### ESXi 虚拟机

```
vSphere Client → 创建虚拟机：
  OS: Debian 12 / Ubuntu 22.04
  CPU: 1核 | 内存: 512M | 硬盘: 8G 精简置备
  网卡: VMXNET3, 端口组 VM Network
  CD/DVD: 上传的 Debian ISO
```

```bash
# 虚拟机内
apt update && apt install -y curl tar git open-vm-tools iproute2 procps
systemctl enable --now open-vm-tools

# 静态 IP（若安装时用 DHCP）
cat > /etc/network/interfaces <<'EOF'
auto ens192
iface ens192 inet static
    address 192.168.1.2/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1
EOF
systemctl restart networking

# 安装 mihomoDNS
cd /root && git clone https://github.com/inzaghiaimar/mihomoDNS.git && cd mihomoDNS
bash install.sh --airport generic --subscription-url "https://你的订阅"

# ESXi 端口组（旁路由推荐）：vSwitch0 安全策略 → 混杂模式 = 接受
```

### 部署后验证（LXC/KVM/ESXi 通用）

```bash
# 服务
systemctl status mosdns
clash doctor

# DNS 分流
dig @127.0.0.1 -p 5335 www.baidu.com +short   # 国内直连
dig @127.0.0.1 -p 5335 google.com +short      # 国外走代理

# 代理连通
curl -s --socks5 127.0.0.1:7890 https://api.ipify.org
```

### 虚拟化常见坑

| 问题 | 解决 |
| --- | --- |
| LXC: `/dev/net/tun` 不存在 | 宿主 `modprobe tun` + 容器 conf 加 lxc.mount.entry 行 |
| LXC: `ip route` 权限不足 | 容器 conf 加 `lxc.capabilities: cap_net_admin cap_net_raw` |
| PVE 防火墙拦截端口 | 创建 CT/VM 时取消「防火墙」勾选，或 PVE 后台防火墙放行 7890/9090/5335/9099 |
| ESXi: VMXNET3 网卡不可见 | `apt install open-vm-tools` 或临时改用 E1000E |
| ESXi: 旁路由丢包 | vSwitch 安全策略 → 混杂模式 = 接受 |
| 网卡名不是 eth0 | `ip link` 查看实际名（LXC 多为 `eth0`，KVM `ens18`，ESXi `ens192`） |

## 安装后使用

### clash 管理

```bash
clashon              # 开启代理
clashoff             # 关闭代理
clash                # 进入 clash 管理面板
clash select         # 选择节点
clash mode           # 切换规则/全局/直连模式
clash doctor         # 诊断
```

### mosdns 管理（systemd 安装时）

```bash
systemctl status mosdns
systemctl restart mosdns
journalctl -u mosdns -f
```

### WebUI

- clash：<http://<本机IP>:9090/ui>
- mosdns：<http://<本机IP>:9099>（需配置 `api.http`，安装时已自动生成）

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
bash uninstall.sh                     # 保留运行目录
bash uninstall.sh --purge-runtime -y  # 连运行目录一起删
bash uninstall.sh -y                  # 跳过确认
```

---

## 目录结构

```
mihomoDNS/
├── install.sh                 # 一键安装入口
├── uninstall.sh               # 卸载
├── .env.example               # 环境变量示例（含路由参数）
├── airports/                  # 机场个性化配置（6 套预设）
├── config/                    # 配置参考模板
├── scripts/
│   ├── common.sh              # 通用函数（日志、下载、错误处理）
│   ├── airport.sh             # 机场加载与配置生成
│   ├── install-clash.sh       # 安装 clash-for-linux
│   ├── install-mosdns.sh      # 下载安装 mosdns
│   ├── integrate.sh           # 联动启动与健康检查
│   └── route.sh               # 静态路由写入/删除（ros/ikuai/linux）
├── clash-for-linux/           # vendored 子项目
└── mosdns/                    # vendored 子项目
```

---

## 常见问题

**Q：mosdns 国外 DNS 为什么要走 clash 的 SOCKS？**
A：避免 DNS 泄露与污染。mosdns 把国外域名查询经 `127.0.0.1:7890` 转发到国外 TCP DNS，结果由 clash 代理通道获取，不会被中间设备污染。

**Q：ROS/爱快上为什么要把 53 端口 DNAT 到 5335？**
A：mosdns 默认监听 5335（非特权容器无法绑 53）。在主路由上做 DNAT，客户端无需任何设置，DNS 查询自动到达 mosdns。也可通过 DHCP 分发 DNS 配合使用。

**Q：ROS 上的 4 条命令都要执行吗？**
A：不是。方案 A（DHCP 分发 DNS）和方案 B（DNS 劫持）推荐同时配置；方案 C（旁路由回程路由）仅 TUN 模式可用，默认 SOCKS 模式切勿执行，否则会导致路由回环。

**Q：旁路由模式下本机需要什么配置？**
A：① 默认网关指向主路由；② 关闭 rp_filter；③ 开启 ip_forward。`--route-target linux` 一键完成。

**Q：mosdns WebUI（9099）打不开？**
A：确认配置文件中包含 `api: http: "0.0.0.0:9099"` 段。重新执行 `bash install.sh --config-only` 生成配置后重启 mosdns。

**Q：ROS SSH 自动执行失败？**
A：安装 `sshpass`，或使用密钥认证。也选择不自动执行，手动复制命令到 ROS 后台。

**Q：爱快与 ROS 选哪个？**
A：两者功能等价。ROS 更强大灵活（支持 comment 匹配批量删除）；爱快界面更友好。按你的主路由选择即可。

**Q：fakeip 与 redir-host 怎么选？**
A：`fakeip`（默认）更快、对代理友好；`redir-host` 在 mihomo v1.19+ 已废弃，脚本会自动兜底为 `fake-ip`。如需保留真实 IP，建议直接在节点选择上走 DIRECT。

---

## 故障排查与日志

```bash
# 查看最近一次安装日志
ls -t runtime/install-*.log | head -1 | xargs tail -50

# 详细模式重装
bash install.sh -v --log-file /tmp/debug.log --airport generic --subscription-url "https://..."

# dry-run 演练
bash install.sh --dry-run --airport streaming

# 验证路由是否生效
ip route show
ip -4 addr show
sysctl net.ipv4.ip_forward
sysctl net.ipv4.conf.all.rp_filter

# clash 诊断
clash doctor

# mosdns 日志
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
- [jasonxtt/mosdns](https://github.com/jasonxtt/mosdns) — DNS 分流增强版

本仓库已将上述两个项目的源码 vendored 打包，安装时无需再从外部拉取。

---

## 声明

本项目用于学习与研究，不得用于违反所在地法律法规的用途。使用前请确认订阅来源合规。
