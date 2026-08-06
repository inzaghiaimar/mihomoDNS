# 机场个性化配置

「机场」指订阅服务提供方。不同机场在协议（vmess/vless/trojan/hysteria2/anytls）、
IPv6 支持、DNS 策略、流媒体规则等方面存在差异。本目录用 `.conf` 文件为每类机场
预设一套配置，安装时按 `--airport <name>` 选择即可。

## 字段说明

每个 `*.conf` 以 shell 变量定义以下字段：

| 字段 | 说明 |
| --- | --- |
| `AIRPORT_NAME` | 机场显示名 |
| `AIRPORT_SUBSCRIPTION_URL` | 订阅链接（clash/mihomo YAML、base64 或分享链接均可） |
| `AIRPORT_SUBSCRIPTION_UA` | 拉取订阅时的 User-Agent（默认 `clash-verge/v2.4.0`，兼容 hy2/anytls） |
| `AIRPORT_IPV6` | `auto` / `on` / `off`，是否启用内核 IPv6 与 DNS AAAA |
| `AIRPORT_DNS_MODE` | DNS 增强模式。可填 `fakeip`/`fake-ip`/`redir-host`/`redir`；mihomo v1.19+ 已废弃 redir-host，脚本会自动兜底为 `fake-ip` |
| `AIRPORT_KERNEL` | `mihomo` / `clash`，代理内核 |
| `AIRPORT_DOMESTIC_DNS` | 国内 DNS，分号分隔，如 `223.5.5.5;119.29.29.29` |
| `AIRPORT_PROXY_DNS` | 国外 DNS（走代理），如 `https://1.1.1.1/dns-query;tls://8.8.8.8:853` |
| `AIRPORT_RULES_EXTRA` | 额外规则（YAML 数组文本，追加到 rules 前） |
| `AIRPORT_PROXY_GROUPS_EXTRA` | 额外策略组（YAML 文本） |
| `AIRPORT_TUN` | `true` / `false`，是否启用 Tun 透明代理（需 root 安装） |
| `AIRPORT_NOTES` | 备注 |

## 内置预设

| 文件 | 适用场景 |
| --- | --- |
| `default.conf` | 默认模板，安装前需填入订阅链接 |
| `generic.conf` | 通用标准协议机场 |
| `hysteria2.conf` | Hysteria2 / Hy2 机场 |
| `ipv6-only.conf` | IPv6-only 节点机场 |
| `streaming.conf` | 流媒体解锁机场 |
| `china-optimized.conf` | 国内优化、IPv6 off |

## 使用方式

```bash
# 安装时指定机场
bash install.sh --airport generic

# 或通过环境变量
CLASH_SUBSCRIPTION_URL=https://example.com/sub bash install.sh --airport hysteria2

# 列出可选机场
bash install.sh --list-airports
```

## 新增自定义机场

复制任一预设并修改：

```bash
cp airports/generic.conf airports/myairport.conf
# 编辑 airports/myairport.conf，填入订阅链接与个性化设置
bash install.sh --airport myairport
```

## 配置如何生效

安装时，[scripts/airport.sh](../scripts/airport.sh) 会：

1. 加载 `airports/<name>.conf`
2. 把订阅、UA、IPv6、端口等写入 `.env`（供 clash-for-linux 读取）
3. 按 `AIRPORT_*` 生成 `clash-for-linux/config/mixin.yaml`（DNS、规则覆盖）
4. 按国内/国外 DNS 与 SOCKS 端口生成 `runtime/mosdns/config_custom.yaml`

之后可分别用 `clash` 与 `mosdns-ctl` 命令维护各自运行状态。
