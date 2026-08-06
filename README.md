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
| `china-optimized` | [airports/china-optimized.conf](airports/china-optimized.conf) | 国内优化 | redir-host 模式，IPv6 off |

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
| `AIRPORT_DNS_MODE` | clash DNS 增强模式 | `fakeip` / `redir-host` |
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
A：`fakeip`（默认）更快、对代理友好；`redir-host` 保留真实 IP，适合需要真实 IP 的国内服务，见 `china-optimized` 机场。

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
