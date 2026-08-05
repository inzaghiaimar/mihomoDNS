# clash-mosdns 一键安装项目

将 [clash-for-linux](https://github.com/wnlen/clash-for-linux)（代理）与 [mosdns](https://github.com/jasonxtt/mosdns)（DNS 分流）合并为一键安装项目，并针对不同「机场」（订阅服务提供方）做个性化配置。

## 为什么合并

- **clash-for-linux** 负责代理与节点分流，内置 fakeip DNS，但没有面向多机场的 DNS 分流策略。
- **mosdns** 负责 DNS 智能分流，但需要外部代理（mihomo/sing-box）提供 SOCKS 与 fakeip 上游。
- 二者天然互补：mosdns 做国内外 DNS 分流 → clash 做流量代理分流，组合后既有干净的 DNS，又有稳定的代理。

本项目把两者打包为一键安装，并按机场特征（协议、IPv6、流媒体、DNS 模式）自动生成各自的配置，让它们开箱联动。

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

端口均可在 `.env` 中调整。

## 一键安装

### 1. 准备

克隆本仓库（含两个子项目）：

```bash
git clone https://github.com/<you>/clash-mosdns.git
cd clash-mosdns
```

若子项目未随仓库分发，需先拉取：

```bash
git clone --depth 1 https://github.com/wnlen/clash-for-linux.git
git clone --depth 1 https://github.com/jasonxtt/mosdns.git
```

> 目标主机需为 Linux（amd64/arm64/armv7），已安装 `curl` 或 `wget`、`tar`、`bash`。
> root 安装走 systemd 自启；普通用户走脚本模式。

### 2. 安装

最简单：交互式选机场 + 填订阅

```bash
bash install.sh
```

指定机场 + 订阅链接（推荐）

```bash
bash install.sh --airport generic --subscription-url https://your-airport.example.com/sub
```

列出可选机场预设

```bash
bash install.sh --list-airports
```

只装其中一个组件

```bash
bash install.sh --only clash
bash install.sh --only mosdns
```

装完不自动启动

```bash
bash install.sh --airport hysteria2 --skip-start
```

### 3. 安装后

- clash 代理：`clashon` 开启，`clashoff` 关闭，`clash` 进入管理面板
- mosdns：`systemctl status mosdns`（root）或查看 `runtime/mosdns/mosdns-launch.log`
- WebUI：
  - clash：<http://<IP>:9090/ui>
  - mosdns：<http://<IP>:9099>

## 机场个性化

`airports/` 目录为每类机场提供一套预设配置。安装时 `--airport <name>` 选择，[scripts/airport.sh](scripts/airport.sh) 会：

1. 加载 `airports/<name>.conf`（订阅、UA、IPv6、DNS 模式、内核、流媒体规则等）
2. 把订阅与端口写入 `.env`（供 clash-for-linux 读取）
3. 按机场特征生成 `clash-for-linux/config/mixin.yaml`（DNS、IPv6、规则覆盖）
4. 按国内/国外 DNS 与 SOCKS 端口生成 `runtime/mosdns/config_custom.yaml`

内置预设：

| 机场 | 适用 | 关键差异 |
| --- | --- | --- |
| `default` | 模板 | 占位，填订阅即用 |
| `generic` | 标准协议机场 | vmess/vless/trojan，fakeip，IPv6 auto |
| `hysteria2` | Hy2 机场 | mihomo 内核，需 UDP 放行 |
| `ipv6-only` | IPv6-only 节点 | 内核 IPv6 + DNS AAAA 开 |
| `streaming` | 流媒体机场 | 内置 Netflix/Disney+/YouTube 规则 |
| `china-optimized` | 国内优化 | redir-host 模式，IPv6 off |

新增自定义机场：

```bash
cp airports/generic.conf airports/myairport.conf
# 编辑 myairport.conf 填入订阅与个性化设置
bash install.sh --airport myairport
```

字段说明见 [airports/README.md](airports/README.md)。

## 目录结构

```
clash-mosdns/
├── install.sh                 # 一键安装入口
├── uninstall.sh               # 卸载
├── .env.example               # 环境变量示例
├── airports/                  # 机场个性化配置
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
│   ├── common.sh              # 通用函数（日志、架构、下载）
│   ├── airport.sh             # 机场加载与配置生成
│   ├── install-clash.sh        # 安装 clash-for-linux
│   ├── install-mosdns.sh       # 下载安装 mosdns
│   └── integrate.sh            # 联动启动与健康检查
├── clash-for-linux/           # 子项目：clash/mihomo 管理
├── mosdns/                    # 子项目：DNS 分流
└── runtime/                   # 运行时目录（自动生成，含 mosdns 配置/日志）
```

## 常用命令

```bash
# clash 管理
clashon / clashoff              # 开关代理
clash                           # 管理面板（select / mode / mixin / doctor …）
clash ls                        # 订阅列表
clash select                    # 选节点
clash doctor                    # 诊断

# mosdns 管理（systemd 安装时）
systemctl status mosdns
systemctl restart mosdns
journalctl -u mosdns -f

# 联动检查
bash scripts/integrate.sh check

# 卸载
bash uninstall.sh               # 保留运行目录
bash uninstall.sh --purge-runtime -y   # 连运行目录一起删
```

## 常见问题

**Q：mosdns 国外 DNS 为什么要走 clash 的 SOCKS？**
A：避免 DNS 泄露与污染。mosdns 把国外域名查询经 `127.0.0.1:7890`（clash mixed-port）转发到国外 DoH/DoT，结果由 clash 代理通道获取，不会被中间设备污染或看到明文 DNS。

**Q：fakeip 与 redir-host 怎么选？**
A：`fakeip`（默认）更快、对代理友好，mosdns 把代理域名指向 clash 的 fakeip 段；`redir-host` 保留真实 IP，适合需要真实 IP 的国内服务（如部分 CDN、登录态），见 `china-optimized` 机场。

**Q：Hysteria2 节点连不上？**
A：确认 mihomo 内核（`AIRPORT_KERNEL=mihomo`）、宿主机有 IPv6 默认路由（IPv6-only 时）、防火墙放行 UDP/QUIC。

**Q：mosdns 监听 5335 而不是 53？**
A：非 root 无法绑 53。如需让系统 DNS 走 mosdns，见安装后提示，把 `/etc/resolv.conf` 指向 `127.0.0.1` 或用 `iptables` 把 53 重定向到 5335。

## 上游项目致谢

- [wnlen/clash-for-linux](https://github.com/wnlen/clash-for-linux) — Linux Clash/Mihomo 运行平台
- [jasonxtt/mosdns](https://github.com/jasonxtt/mosdns) — DNS 分流增强版（基于 yyysuo/mosdns）

## 声明

本项目用于学习与研究，不得用于违反所在地法律法规的用途。使用前请确认订阅来源合规。
