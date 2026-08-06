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
- [与 ROS / 爱快配合：静态路由表设置](#与-ros--爱快配合静态路由表设置)
  - [场景说明](#场景说明)
  - [Linux 本机静态路由](#linux-本机静态路由)
  - [ROS / RouterOS 静态路由](#ros--routeros-静态路由)
  - [爱快 iKuai 静态路由](#爱快-ikuai-静态路由)
  - [路由参数一览](#路由参数一览)
  - [删除静态路由](#删除静态路由)
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
│                       Linux 宿主机                         │
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
          ▲                                    ▲
          │ 客户端 DNS(53) 经主路由 DNAT 指向本机  │ 本机默认网关经主路由
          │                                    │
┌─────────┴────────────────────────────────────┴──────────┐
│              ROS / 爱快 主路由（192.168.1.1）              │
│  - NAT: 53 → 本机:5335（DNS 劫持）                        │
│  - 静态路由: 代理网段 → 本机（旁路由回程）                 │
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

## 与 ROS / 爱快配合：静态路由表设置

本项目的 Linux 宿主机通常作为**旁路由 / DNS 服务器**部署，主路由是 ROS（RouterOS）或爱快 iKuai。为了让客户端的 DNS 查询自动到达本机 mosdns，以及让本机的出网流量正确经主路由，需要在主路由上写入静态路由 / NAT 规则。

`scripts/route.sh` 脚本封装了这一过程，支持三种目标：`linux`（本机）、`ros`（RouterOS）、`ikuai`（爱快）。

### 场景说明

```
                        ┌─────────────────────────┐
                        │   ROS / 爱快 主路由       │
                        │   LAN: 192.168.1.1       │
                        └────────┬────────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
     ┌────────┴───────┐  ┌───────┴───────┐  ┌───────┴───────┐
     │  客户端 A       │  │  客户端 B      │  │ mihomoDNS 宿主机│
     │  192.168.1.10  │  │  192.168.1.11 │  │ 192.168.1.2    │
     │  DNS → 主路由   │  │  DNS → 主路由  │  │ mosdns:5335    │
     └────────────────┘  └───────────────┘  │ clash:7890     │
                                            └────────────────┘
```

- **DNS 劫持**：主路由把客户端发往 53 端口的流量 DNAT 到 `192.168.1.2:5335`（mosdns）
- **旁路由回程**（可选）：主路由把需要走代理的网段路由到 `192.168.1.2`
- **本机默认网关**：mihomoDNS 宿主机的默认网关指向主路由 `192.168.1.1`

### Linux 本机静态路由

适用于 mihomoDNS 宿主机本身需要设置默认网关、关闭 rp_filter、开启 IP 转发的场景。

#### 一键写入

```bash
# 自动探测网卡与本机 IP
bash install.sh --airport generic --subscription-url "https://..." \
  --route-target linux --route-gateway 192.168.1.1

# 或手动指定全部参数
bash scripts/route.sh apply \
  --target linux \
  --gateway 192.168.1.1 \
  --lan-if eth0 \
  --lan-ip 192.168.1.2 \
  --lan-cidr 192.168.1.0/24
```

#### 实际执行的命令

脚本会在本机执行：

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

### ROS / RouterOS 静态路由

适用于主路由为 MikroTik RouterOS / ROS 软路由的场景。脚本生成 ROS CLI 命令，可选经 SSH 自动执行。

#### 一键生成并执行

```bash
# 经 install.sh（安装后自动生成 ROS 命令）
bash install.sh --airport generic --subscription-url "https://..." \
  --route-target ros \
  --route-lan-ip 192.168.1.2 \
  --route-ssh-host 192.168.1.1

# 或单独调用 route.sh
bash scripts/route.sh apply \
  --target ros \
  --lan-ip 192.168.1.2 \
  --ssh-host 192.168.1.1
```

#### 生成的 ROS CLI 命令（写入）

在 ROS 主路由执行以下命令，作用是把客户端 DNS(53) 流量自动指向本机 mosdns(:5335)：

```routeros
# 1) DNS 劫持：UDP 53 → 本机 5335
/ip firewall nat add chain=dstnat protocol=udp dst-port=53 \
    action=dst-nat to-addresses=192.168.1.2 to-ports=5335 \
    comment="mihomoDNS-udp"

# 2) DNS 劫持：TCP 53 → 本机 5335
/ip firewall nat add chain=dstnat protocol=tcp dst-port=53 \
    action=dst-nat to-addresses=192.168.1.2 to-ports=5335 \
    comment="mihomoDNS-tcp"

# 3) 旁路由回程（按需）：把需要走代理的网段指向本机
/ip route add dst-address=192.168.1.0/24 gateway=192.168.1.2 \
    comment="mihomoDNS-route"

# 4) 若需把特定客户端全部流量经本机代理
/ip route add dst-address=192.168.1.10/32 gateway=192.168.1.2
```

#### 生成的 ROS CLI 命令（删除）

```routeros
# 1) 删除 DNS 劫持 NAT 规则（按 comment 匹配）
/ip firewall nat remove [find comment~"mihomoDNS"]

# 2) 删除回程静态路由
/ip route remove [find comment="mihomoDNS-route"]

# 验证
/ip firewall nat print
/ip route print
```

#### SSH 自动执行

若提供了 `--route-ssh-host`，脚本会询问是否经 SSH 自动执行。需要 `sshpass`（否则交互输入密码）：

```bash
# 安装 sshpass（Ubuntu/Debian）
apt-get install -y sshpass

# 自动执行（SSH 密码通过环境变量 SSHPASS 传入）
SSHPASS=your_password bash scripts/route.sh apply \
  --target ros \
  --lan-ip 192.168.1.2 \
  --ssh-host 192.168.1.1 \
  --ssh-user admin
```

#### ROS WebFig / WinBox 手动操作

若不便用 SSH，也可在 ROS 管理界面手动添加：

1. **DNS 劫持（NAT）**：`IP` → `Firewall` → `NAT` → `+`
   - `Chain`: dstnat
   - `Protocol`: 6 (tcp) 或 17 (udp)
   - `Dst. Port`: 53
   - `Action`: dst-nat
   - `To Addresses`: 192.168.1.2
   - `To Ports`: 5335

2. **静态路由**：`IP` → `Routes` → `+`
   - `Dst. Address`: 192.168.1.0/24（或客户端 IP/32）
   - `Gateway`: 192.168.1.2

---

### 爱快 iKuai 静态路由

适用于主路由为爱快 iKuai 软路由的场景。脚本生成 Web 后台操作步骤与 SSH 命令。

#### 一键生成

```bash
# 经 install.sh
bash install.sh --airport generic --subscription-url "https://..." \
  --route-target ikuai \
  --route-lan-ip 192.168.1.2 \
  --route-ikuai-host 192.168.1.1

# 或单独调用 route.sh
bash scripts/route.sh apply \
  --target ikuai \
  --lan-ip 192.168.1.2 \
  --ikuai-host 192.168.1.1
```

#### 方式 A：爱快 Web 后台手动操作

1. **DNS 劫持（端口映射）**：
   - `流控分流` → `端口映射` → `添加`
   - 协议: `UDP`，外部端口: `53`，内部 IP: `192.168.1.2`，内部端口: `5335`
   - 再添加一条 `TCP` / `53` → `192.168.1.2:5335`

2. **静态路由（旁路由回程，可选）**：
   - `网络设置` → `路由设置` → `静态路由` → `添加`
   - 目标网段: `192.168.1.0/24`，网关: `192.168.1.2`

3. **特定客户端全流量经本机（可选）**：
   - 目标网段填客户端 IP/32，网关填 `192.168.1.2`

#### 方式 B：经 SSH 执行（爱快基于 OpenWrt，支持 iptables）

```bash
ssh root@192.168.1.1

# DNS 劫持
iptables -t nat -A PREROUTING -p udp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
iptables -t nat -A PREROUTING -p tcp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335

# 静态路由（旁路由回程）
ip route add 192.168.1.0/24 via 192.168.1.2
```

#### 删除

```bash
# Web 后台
# 流控分流 → 端口映射 → 删除 53 → 192.168.1.2:5335 的规则
# 网络设置 → 路由设置 → 静态路由 → 删除网关为 192.168.1.2 的条目

# SSH
iptables -t nat -D PREROUTING -p udp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
iptables -t nat -D PREROUTING -p tcp --dport 53 \
    -j DNAT --to-destination 192.168.1.2:5335
ip route del 192.168.1.0/24 via 192.168.1.2
```

或用脚本：

```bash
bash scripts/route.sh clean --target ikuai --lan-ip 192.168.1.2 --ikuai-host 192.168.1.1
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

### 删除静态路由

所有目标都支持 `clean` 子命令或 `--route-clean` 参数：

```bash
# 删除 Linux 本机路由
bash scripts/route.sh clean --target linux

# 删除 ROS 路由（生成删除命令）
bash scripts/route.sh clean --target ros --lan-ip 192.168.1.2 --ssh-host 192.168.1.1

# 删除爱快路由（生成删除命令）
bash scripts/route.sh clean --target ikuai --lan-ip 192.168.1.2 --ikuai-host 192.168.1.1

# 经 install.sh 删除
bash install.sh --route-target ros --route-clean --route-lan-ip 192.168.1.2 --route-ssh-host 192.168.1.1
```

> **注意**：Linux 目标删除时只清理本项目写入的 `/etc/sysctl.d/99-mihomoDNS.conf`，不擅自改回默认网关与 rp_filter，避免断网。请按提示手动恢复。

---

## PVE 部署操作手册

Proxmox VE（PVE）是部署旁路由/DNS 服务的常见平台。mihomoDNS 可运行在 **KVM 虚拟机** 或 **LXC 容器** 中。本手册给出从零开始的完整部署步骤。

> 本手册以 `192.168.1.0/24` 网段为例：主路由 `192.168.1.1`，mihomoDNS 宿主 `192.168.1.2`。请按实际网段替换。

### PVE 选型对比

| 维度 | LXC 容器 | KVM 虚拟机 |
| --- | --- | --- |
| 资源占用 | 极低（共享宿主内核，~64M 即可） | 较高（独立内核，建议 ≥512M） |
| 启动速度 | 秒级 | 较慢（需引导内核） |
| 内核模块 | 依赖宿主加载（TUN/TAP 需宿主开启） | 自带内核，自主加载 |
| Tun 透明代理 | 需宿主 `/dev/net/tun` 透传 | 原生支持 |
| 网络性能 | 接近宿主（veth 直连） | 略有损耗（virtio） |
| 推荐场景 | 纯代理 + DNS 分流（非 Tun 模式） | 需要 Tun 模式 / 完整内核功能 |

> **结论**：若只用 `fakeip` + SOCKS 代理 + mosdns DNS 分流（本项目的默认模式），**LXC 容器**更轻量；若需要 `AIRPORT_TUN=true`（Tun 透明代理，劫持全局流量），用 **KVM 虚拟机**更省心。

### PVE 网络拓扑

```
┌──────────────────────────────────────────────────────────┐
│                    PVE 宿主机                              │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │ ROS/爱快 主路由│    │  vmbr0 桥接   │                   │
│  │ (或虚拟机/CT)  │◄──►│  192.168.1.x │                   │
│  └──────┬───────┘    └──────┬───────┘                   │
│         │                   │                            │
│         │      ┌────────────┼────────────┐              │
│         │      │            │            │              │
│  ┌──────┴──┐ ┌─┴──────┐ ┌──┴─────┐ ┌────┴────┐        │
│  │ 客户端A  │ │客户端B │ │ LXC/VM │ │ 其他VM  │        │
│  │ .10     │ │ .11    │ │ .2     │ │         │        │
│  └─────────┘ └────────┘ │mihomoDNS│ └─────────┘        │
│                          │mosdns   │                   │
│                          │clash    │                   │
│                          └─────────┘                   │
└──────────────────────────────────────────────────────────┘
```

- 主路由（ROS/爱快）可以是 PVE 上的虚拟机/LXC，也可以是物理机
- mihomoDNS 作为旁路由/DNS 服务器，IP 固定为 `192.168.1.2`
- 客户端 DNS 流量经主路由 DNAT 指向 `192.168.1.2:5335`

### PVE LXC 容器完整部署

#### 步骤 1：宿主前置准备

在 PVE 宿主（SSH 或 Web Shell）执行：

```bash
# 1) 加载 TUN 模块（clash Tun 模式 / mosdns 需要）
modprobe tun
echo "tun" >> /etc/modules-load.d/tun.conf

# 2) 确认 bridge-utils 与 lxcfs 正常（PVE 默认已装）
apt update && apt install -y bridge-utils

# 3) 确认 vmbr0 桥接已存在（PVE 安装时默认创建）
ip addr show vmbr0
```

#### 步骤 2：下载 LXC 模板

PVE 后台 → 节点 → CT 模板 → 模板 → 下载：

- 选择 `debian-12-standard` 或 `ubuntu-22.04-standard`

或命令行下载：

```bash
pveam update
pveam download local debian-12-standard_12.2-1_amd64.tar.zst
```

#### 步骤 3：创建 LXC 容器

**方式 A：PVE 后台图形界面**

1. 节点 → 右键 → 创建 CT
2. **常规**：CTID `100`，主机名 `mihomoDNS`，密码自设
3. **模板**：选 `debian-12-standard`
4. **磁盘**：4GB
5. **CPU**：1 核
6. **内存**：256MB（mosdns+clash 共跑建议 ≥256M，Tun 模式建议 ≥512M）
7. **网络**：
   - 名称：`eth0`
   - 桥接：`vmbr0`
   - IPv4：`192.168.1.2/24`
   - 网关：`192.168.1.1`
   - 取消勾选 DHCP
8. **DNS**：`192.168.1.1`（先用主路由，安装后改自身）
9. **确认** → 创建

**方式 B：命令行创建（非特权容器，推荐）**

```bash
pct create 100 debian-12-standard_12.2-1_amd64.tar.zst \
  --rootfs local-lvm:4 \
  --ostype debian \
  --hostname mihomoDNS \
  --password your_password \
  --memory 256 --swap 0 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.2/24,gw=192.168.1.1 \
  --unprivileged 1
```

**方式 C：命令行创建（特权容器，简化但安全性低）**

```bash
pct create 100 debian-12-standard_12.2-1_amd64.tar.zst \
  --rootfs local-lvm:4 \
  --ostype debian \
  --hostname mihomoDNS \
  --password your_password \
  --memory 256 --swap 0 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.2/24,gw=192.168.1.1 \
  --unprivileged 0
```

#### 步骤 4：开启关键特性（非特权容器必做）

编辑容器配置（CTID=100）：

```bash
nano /etc/pve/lxc/100.conf
```

在文件末尾添加：

```ini
# 开启 TUN 设备（clash Tun 模式 / mosdns 需要）
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file

# 开启 net_admin / net_raw / bind_service（iptables/路由/低端口需要）
lxc.capabilities: cap_net_admin cap_net_raw cap_net_bind_service
```

> - `cap_net_admin` — 允许容器内执行 `ip route`、`iptables`、改网卡
> - `cap_net_raw` — 允许 raw socket（部分 DNS 探测需要）
> - `cap_net_bind_service` — 允许绑定 1024 以下端口（若想让 mosdns 监听 53）

#### 步骤 5：启动容器并进入

```bash
pct start 100
pct enter 100
```

#### 步骤 6：容器内网络配置（可选，创建时已指定则跳过）

若创建时未指定 IP，或需要修改：

```bash
# 容器内编辑 /etc/network/interfaces
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.2/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1
EOF

# 应用配置
ifdown eth0 && ifup eth0
# 或重启容器：pct reboot 100
```

#### 步骤 7：容器内安装依赖与 mihomoDNS

```bash
# 更新系统
apt update && apt install -y curl tar git iproute2 procps

# 克隆项目
cd /root
git clone https://github.com/inzaghiaimar/mihomoDNS.git
cd mihomoDNS

# 先演练
bash install.sh --dry-run --airport generic --subscription-url "https://你的订阅"

# 正式安装
bash install.sh --airport generic --subscription-url "https://你的订阅"

# 若需同时写入本机静态路由
bash install.sh --airport generic --subscription-url "https://你的订阅" \
  --route-target linux --route-gateway 192.168.1.1
```

#### 步骤 8：路由配合（主路由侧）

LXC 容器网络与虚拟机等价，在主路由做 DNS 劫持指向容器 IP：

```bash
# ROS 主路由
bash install.sh --route-target ros \
  --route-lan-ip 192.168.1.2 --route-ssh-host 192.168.1.1

# 或爱快主路由
bash install.sh --route-target ikuai \
  --route-lan-ip 192.168.1.2 --route-ikuai-host 192.168.1.1
```

#### 步骤 9：设为开机自启

```bash
# PVE 宿主执行
pct set 100 --onboot 1
```

### PVE KVM 虚拟机完整部署

#### 步骤 1：上传系统镜像

1. 下载 Debian 12 或 Ubuntu 22.04 Server ISO
2. PVE 后台 → 节点 → local → ISO 映像 → 上传

#### 步骤 2：创建虚拟机

PVE 后台 → 右上角创建虚拟机：

- **常规**：节点自选，VMID `101`，名称 `mihomoDNS`
- **系统**：机型 q35，BIOS 默认，SCSI 控制器 VirtIO SCSI single
- **硬盘**：8GB，VirtIO Block，discard 勾选（SSD 建议）
- **CPU**：1 核，类型 host（性能最佳）
- **内存**：512MB（Tun 模式建议 ≥512M）
- **网络**：VirtIO (paravirtualized)，桥接 `vmbr0`，取消防火墙勾选（避免拦截代理流量）
- **确认** → 创建（先不启动）

#### 步骤 3：启动并安装系统

1. 选中虚拟机 → 启动
2. 打开 Console，按提示安装 Debian/Ubuntu
3. 安装时网络选择 DHCP 或手动指定 `192.168.1.2/24`，网关 `192.168.1.1`
4. 只装基本系统 + SSH server，不装桌面环境
5. 安装完重启

#### 步骤 4：虚拟机内网络配置（若安装时未指定）

```bash
# 查看网卡名（现代 Linux 多为 ens18 / enp6s18 等）
ip link

# 编辑网络配置（Debian/Ubuntu）
nano /etc/network/interfaces
```

```bash
auto ens18
iface ens18 inet static
    address 192.168.1.2/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1
```

```bash
# 应用
systemctl restart networking
# 验证
ip addr show ens18
ip route show
```

#### 步骤 5：安装 mihomoDNS

```bash
apt update && apt install -y curl tar git

cd /root
git clone https://github.com/inzaghiaimar/mihomoDNS.git
cd mihomoDNS

# 演练
bash install.sh --dry-run --airport generic --subscription-url "https://你的订阅"

# 正式安装
bash install.sh --airport generic --subscription-url "https://你的订阅"
```

#### 步骤 6：开启 Tun 模式（KVM 推荐）

KVM 虚拟机有独立内核，可完整支持 Tun 透明代理：

```bash
# 编辑机场配置开启 Tun
sed -i 's/AIRPORT_TUN="false"/AIRPORT_TUN="true"/' airports/generic.conf

# 重新安装（生成含 Tun 的 clash 配置）
bash install.sh --airport generic --subscription-url "https://你的订阅"
```

Tun 模式下 clash 会创建虚拟网卡接管全局流量，无需主路由配合做 DNAT，但需关闭虚拟机自身防火墙对 Tun 网卡的拦截：

```bash
# 若装了 firewalld
systemctl stop firewalld && systemctl disable firewalld

# 或 ufw
ufw disable
```

#### 步骤 7：路由配合（主路由侧）

与 LXC 相同，在主路由做 DNS 劫持指向虚拟机 IP：

```bash
bash install.sh --route-target ros \
  --route-lan-ip 192.168.1.2 --route-ssh-host 192.168.1.1
```

#### 步骤 8：设为开机自启

PVE 后台 → 虚拟机 → 选项 → 自启动时启动 → 是。

或命令行：

```bash
qm set 101 --onboot 1
```

### PVE 部署后验证

```bash
# 1) 容器/虚拟机内验证 mihomoDNS 服务
systemctl status mosdns
clash doctor

# 2) 验证 DNS 分流
nslookup www.baidu.com 127.0.0.1 -port=5335   # 国内直连
nslookup www.google.com 127.0.0.1 -port=5335  # 国外经代理

# 3) 验证代理
curl --socks5 127.0.0.1:7890 https://www.google.com -I

# 4) 验证主路由 DNAT 是否生效（在客户端执行）
nslookup www.google.com 192.168.1.1   # 主路由应转发到 192.168.1.2:5335

# 5) PVE 层面验证
pct status 100          # LXC 状态
qm status 101           # KVM 状态
pct config 100          # 查看 LXC 配置
```

### PVE 常见问题

**Q：LXC 容器内 `ip route` 报权限不足？**
A：容器缺少 `cap_net_admin`。编辑 `/etc/pve/lxc/<CTID>.conf` 添加 `lxc.capabilities: cap_net_admin cap_net_raw`，重启容器。

**Q：LXC 内 clash Tun 模式启动失败（`/dev/net/tun` 不存在）？**
A：宿主执行 `modprobe tun`，并在容器配置添加 `lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file`。若仍不行，改用 KVM 虚拟机或关闭 Tun（`AIRPORT_TUN=false`，用 fakeip + SOCKS 模式即可）。

**Q：LXC 容器内 mosdns 无法绑定 53 端口？**
A：非特权容器默认无法绑 1024 以下端口。方案：① 用主路由 DNAT 53→5335（推荐）；② 添加 `cap_net_bind_service`；③ 用特权容器。

**Q：PVE 宿主与容器/虚拟机网络不通？**
A：确认 `vmbr0` 桥接正常、容器/虚拟机的 IP 与宿主在同一网段、防火墙未拦截。用 `ping` 与 `tcpdump -i vmbr0` 排查。

**Q：KVM 虚拟机网卡名不是 eth0？**
A：现代 Linux 用预测网卡名（如 `ens18`）。用 `--route-lan-if ens18` 指定，或恢复传统命名：`ln -s /dev/null /etc/systemd/network/99-default.link` 后重启。

**Q：PVE 防火墙拦截了代理流量？**
A：虚拟机选项里取消「防火墙」勾选，或在 PVE 后台 → 防火墙 → 规则中放行 7890/9090/5335/9099 端口。

**Q：容器/虚拟机重启后服务没自启？**
A：mosdns 走 systemd（`systemctl enable mosdns`）；clash 走 `clash-for-linux` 的启动脚本（安装时已注册 rc.local 或 systemd）。

---

## ESXi 部署操作手册

VMware ESXi 是企业级 Type-1 Hypervisor，部署 mihomoDNS 需使用 **ESXi 虚拟机**（ESXi 不支持 LXC 容器）。

### ESXi 环境准备

#### 1) 网络规划

| 角色 | IP | 说明 |
| --- | --- | --- |
| ESXi 宿主 | `192.168.1.10` | 管理网段 |
| 主路由（ROS/爱快） | `192.168.1.1` | DNS 劫持与网关 |
| mihomoDNS 虚拟机 | `192.168.1.2` | 旁路由/DNS 服务器 |
| 客户端 | `192.168.1.x` | 经主路由指向 mihomoDNS |

#### 2) ESXi 网络拓扑

```
┌──────────────────────────────────────────────────────────┐
│                    ESXi 宿主机                             │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │ 物理交换机/   │    │ vSwitch0     │                   │
│  │ 主路由        │◄──►│ 虚拟交换机    │                   │
│  │ 192.168.1.1  │    │ VM Network   │                   │
│  └──────┬───────┘    └──────┬───────┘                   │
│         │                   │                            │
│         │      ┌────────────┼────────────┐              │
│         │      │            │            │              │
│  ┌──────┴──┐ ┌─┴──────┐ ┌──┴───────┐ ┌───┴────┐        │
│  │ 客户端A  │ │客户端B │ │mihomoDNS │ │ 其他VM │        │
│  │ .10     │ │ .11    │ │ VM .2    │ │        │        │
│  └─────────┘ └────────┘ │mosdns    │ └────────┘        │
│                          │clash     │                   │
│                          └──────────┘                   │
└──────────────────────────────────────────────────────────┘
```

#### 3) ESXi 前置检查

```bash
# 通过 SSH 登录 ESXi Shell（需在 DCUI 中启用 SSH）
# 确认网络与虚拟交换机
esxcfg-vswitch -l          # 列出虚拟交换机
esxcfg-vmknic -l           # 列出管理网卡
esxcli network ip interface list
```

### ESXi 虚拟机创建完整步骤

#### 步骤 1：上传系统镜像 ISO

1. 下载 Debian 12 或 Ubuntu 22.04 Server ISO
2. vSphere Client → 主机 → 数据存储 → 数据存储浏览器 → 上传 ISO
3. 建议路径：`[datastore1] ISO/debian-12.x.x-amd64-netinst.iso`

#### 步骤 2：创建虚拟机

vSphere Client → 主机 → 右键 → 新建虚拟机：

**常规**：
- 名称：`mihomoDNS`
- 兼容性：ESXi 7.0 U2 及更高（按宿主版本）
- 客户机操作系统系列：Linux
- 客户机操作系统版本：Debian GNU/Linux 12 (64 位) / Ubuntu Linux (64 位)

**硬件**（选择「自定义」）：
- **CPU**：1 核（Tun 模式建议 2 核）
- **内存**：512MB（Tun 模式建议 1GB）
- **硬盘**：8GB，磁盘置备「精简置备」（Thin Provision）
- **SCSI 控制器**：VMware Paravirtual（PVSCSI，性能最佳）
- **网络适配器**：VMXNET3（最佳性能），端口组 `VM Network`
- **CD/DVD**：指向步骤 1 上传的 ISO
- **视频卡**：默认即可

**就绪完成** → 创建后先不启动。

#### 步骤 3：调整虚拟机选项（可选优化）

选中虚拟机 → 编辑设置 → 虚拟机选项：
- **引导选项**：固件 BIOS（Debian 默认），启动延迟 0
- **高级参数** → 配置参数 → 添加：
  - `disk.EnableUUID` = `TRUE`（快照一致性）

#### 步骤 4：启动并安装系统

1. 选中虚拟机 → 启动 → 打开 Web Console
2. 选择 `Install`（非 Graphical Install，省资源）
3. 语言/区域按需，主机名 `mihomoDNS`，域名留空
4. **网络配置**：
   - 取消 DHCP，手动配置
   - IP：`192.168.1.2`
   - 子网掩码：`255.255.255.0`
   - 网关：`192.168.1.1`
   - DNS：`192.168.1.1`（先用主路由，安装 mihomoDNS 后改 `127.0.0.1`）
5. **分区**：使用整个磁盘，LVM（推荐，便于扩容）
6. **软件选择**：只勾选 `SSH server` + `standard system utilities`，取消桌面环境
7. 安装 GRUB 到主引导记录 → 完成重启

#### 步骤 5：安装 VMware Tools（强烈推荐）

```bash
# 虚拟机内
apt update && apt install -y open-vm-tools
systemctl enable open-vm-tools
systemctl start open-vm-tools
```

### ESXi 网络配置

#### 步骤 6：虚拟机内静态 IP 配置（若安装时用 DHCP）

```bash
# 查看网卡名（VMXNET3 通常为 ens192 / eth0）
ip link

# Debian/Ubuntu 配置静态 IP
nano /etc/network/interfaces
```

```bash
auto ens192
iface ens192 inet static
    address 192.168.1.2/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1
```

```bash
# 应用配置
systemctl restart networking

# 验证
ip addr show ens192
ip route show
ping -c 3 192.168.1.1
```

#### 步骤 7：关闭虚拟机防火墙（避免拦截代理流量）

```bash
# Debian 默认无防火墙，若有则关闭
systemctl stop firewalld 2>/dev/null && systemctl disable firewalld
ufw disable 2>/dev/null

# 确认 nftables 未拦截
nft list ruleset 2>/dev/null | head
```

#### 步骤 8：ESXi 端口组放行（若启用了 VLAN/安全策略）

vSphere Client → 主机 → 网络 → 虚拟交换机 → `vSwitch0` → 安全策略：
- 混杂模式：**接受**（旁路由监听/转发需要）
- MAC 地址变更：接受
- 伪传输：接受

> 旁路由场景下，混杂模式开启可避免某些异常流量被丢弃。

### ESXi 安装 mihomoDNS

#### 步骤 9：安装依赖并克隆项目

```bash
apt update && apt install -y curl tar git iproute2 procps

cd /root
git clone https://github.com/inzaghiaimar/mihomoDNS.git
cd mihomoDNS
```

#### 步骤 10：演练与安装

```bash
# 演练
bash install.sh --dry-run --airport generic --subscription-url "https://你的订阅"

# 正式安装
bash install.sh --airport generic --subscription-url "https://你的订阅"

# 同时写入本机静态路由（默认网关 + rp_filter + ip_forward）
bash install.sh --airport generic --subscription-url "https://你的订阅" \
  --route-target linux --route-gateway 192.168.1.1
```

#### 步骤 11：开启 Tun 模式（ESXi 推荐）

ESXi 虚拟机有完整内核，支持 Tun 透明代理：

```bash
# 开启 Tun
sed -i 's/AIRPORT_TUN="false"/AIRPORT_TUN="true"/' airports/generic.conf

# 重新安装
bash install.sh --airport generic --subscription-url "https://你的订阅"
```

#### 步骤 12：主路由侧 DNS 劫持

在 ROS/爱快主路由上把客户端 53 端口流量指向 ESXi 虚拟机：

```bash
# ROS
bash install.sh --route-target ros \
  --route-lan-ip 192.168.1.2 --route-ssh-host 192.168.1.1

# 或爱快
bash install.sh --route-target ikuai \
  --route-lan-ip 192.168.1.2 --route-ikuai-host 192.168.1.1
```

#### 步骤 13：设为开机自启

```bash
# mosdns（systemd 已自动注册）
systemctl enable mosdns

# clash（clash-for-linux 已注册启动脚本）
# 验证
systemctl status mosdns
crontab -l | grep clash    # 或 rc.local
```

ESXi 侧设为开机自启：vSphere Client → 虚拟机 → 管理 → 自动启动 → 启用 → 设为「与主机一起自动启动」。

### ESXi 部署后验证

```bash
# 1) 服务状态
systemctl status mosdns
clash doctor

# 2) DNS 分流测试
nslookup www.baidu.com 127.0.0.1 -port=5335
nslookup www.google.com 127.0.0.1 -port=5335

# 3) 代理测试
curl --socks5 127.0.0.1:7890 https://www.google.com -I

# 4) 路由验证
ip route show
sysctl net.ipv4.ip_forward
sysctl net.ipv4.conf.all.rp_filter

# 5) ESXi 侧验证
# vSphere Client → 虚拟机 → 状态为「已打开电源」
# 性能图表查看 CPU/内存占用
```

### ESXi 常见问题

**Q：VMXNET3 网卡在系统中不可见？**
A：安装 `open-vm-tools`，或临时改用 E1000E 网卡（兼容性好但性能差）。

**Q：虚拟机网络不通（ping 不通主路由）？**
A：① 检查端口组 `VM Network` 桥接到正确的物理网卡；② 确认虚拟机 IP 与宿主同网段；③ 检查 vSwitch 安全策略是否过严。

**Q：ESXi 防火墙拦截了端口？**
A：ESXi 默认防火墙只拦截宿主管理端口，虚拟机流量不受影响。若虚拟机内装了 firewalld/ufw，需在虚拟机内关闭。

**Q：Tun 模式下虚拟机流量异常？**
A：① 关闭虚拟机内防火墙；② ESXi vSwitch 安全策略开启混杂模式；③ 确认 `ip_forward` 已开启（`sysctl net.ipv4.ip_forward=1`）。

**Q：精简置备磁盘满了？**
A：vSphere Client → 数据存储 → 查看使用率。若超 80% 需扩容或清理。精简置备按实际使用计算，8GB 虚拟盘实际占用通常 < 2GB。

**Q：虚拟机重启后服务未自启？**
A：① 确认 `systemctl enable mosdns`；② ESXi 设为「与主机一起自动启动」；③ 检查 clash-for-linux 的启动脚本是否在 rc.local 或 systemd。

**Q：网卡名是 ens192 而非 eth0？**
A：VMXNET3 网卡预测命名通常为 `ens192`。用 `--route-lan-if ens192` 指定，或恢复传统命名。

---

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
A：避免 DNS 泄露与污染。mosdns 把国外域名查询经 `127.0.0.1:7890` 转发到国外 DoH/DoT，结果由 clash 代理通道获取，不会被中间设备污染。

**Q：ROS/爱快上为什么要把 53 端口 DNAT 到 5335？**
A：mosdns 默认监听 5335（非 root 无法绑 53）。在主路由上做 DNAT，客户端无需任何设置，DNS 查询自动到达 mosdns。

**Q：旁路由模式下本机需要什么配置？**
A：① 默认网关指向主路由；② 关闭 rp_filter；③ 开启 ip_forward。`--route-target linux` 一键完成。

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
