# mihomo-anytls-brutal

为 Mihomo AnyTLS 服务端自动适配 TCP Brutal v2 的小工具。

TCP Brutal v2 可以在 Linux TCP 层按目标 IP 应用 Brutal，不要求 AnyTLS 或 Mihomo 原生支持 `smux.brutal-opts`。本项目通过监听 Mihomo 的 systemd 日志，自动识别正在使用服务端的客户端公网 IPv4；当发现新 IP 时，自动添加 `/32` Brutal 规则并断开该 IP 已建立的 AnyTLS TCP 连接，使客户端自动重连后从建连阶段直接使用 TCP Brutal。

## 默认配置

- AnyTLS 监听端口：`443`
- TCP Brutal 速率：`500 Mbps`
- 最近客户端 IP 保留数量：`20`
- Mihomo systemd 服务名：`mihomo.service`
- 状态文件：`/var/lib/brutal-anytls/clients`

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jh4ygsg-dot/mihomo-anytls-brutal/main/install.sh)
```

脚本需要以 root 身份运行。如果系统中没有 `brutalctl`，安装脚本会调用 TCP Brutal 官方安装脚本：

```bash
bash <(curl -fsSL https://tcp.hy2.sh/)
```

安装后无需修改 Mihomo 的 AnyTLS 节点配置。

## 自定义参数

可以在执行安装脚本时覆盖默认值。例如 AnyTLS 使用 8443、Brutal 速率 300 Mbps、保留 10 个 IP：

```bash
RATE_MBPS=300 MAX_IPS=10 ANYTLS_PORT=8443 bash <(curl -fsSL https://raw.githubusercontent.com/jh4ygsg-dot/mihomo-anytls-brutal/main/install.sh)
```

如果你的 Mihomo systemd 服务名不同：

```bash
MIHOMO_UNIT=clash-meta.service bash <(curl -fsSL https://raw.githubusercontent.com/jh4ygsg-dot/mihomo-anytls-brutal/main/install.sh)
```

## 工作原理

Mihomo 在 `info` 日志中会出现类似：

```text
[TCP] 110.53.44.6:4383 --> example.com:443 ...
```

监控服务提取其中的源 IPv4。如果当前没有对应 Brutal 规则，就执行等价于：

```bash
brutalctl add 110.53.44.6/32 500
```

然后关闭该客户端当前连向 AnyTLS 端口的旧 TCP 连接。客户端自动重连时，对应 `/32` 路由已经带有 `congctl lock brutal`，因此新 TCP socket 会直接进入 Brutal。

脚本维护最近 20 个客户端 IP。再次切回近期使用过的网络且公网 IP 未变化时，Brutal 规则已经存在，可以从第一次连接开始生效。超过上限时会删除最久未使用的 IP 规则。

## 使用要求

- Linux + systemd
- Mihomo 通过 systemd 运行
- Mihomo 日志级别至少为 `info`
- TCP Brutal v2 / `brutalctl`
- `journalctl`、`ss`、`sed`、`grep`
- 当前脚本只处理 IPv4

> [!IMPORTANT]
> 当前识别方式依赖 Mihomo 的 `[TCP] <source-ip>:<port> --> ...` 日志。如果同一个 Mihomo 实例还对外提供其他 TCP 入站协议，这些入站客户端的源 IP 也可能被识别并加入 Brutal。最适合 443/指定端口主要用于个人 AnyTLS 服务端的场景。

## 查看状态

查看自动监控服务：

```bash
systemctl status brutal-anytls-watch
```

实时查看脚本日志：

```bash
journalctl -u brutal-anytls-watch -f
```

查看 Brutal v2 规则：

```bash
brutalctl list
```

查看最近识别的客户端 IP（从上到下由旧到新）：

```bash
cat /var/lib/brutal-anytls/clients
```

检查 AnyTLS 当前 TCP 连接：

```bash
ss -tin 'sport = :443'
```

当 `brutalctl list` 中对应规则的 `MEMBERS` 大于 0，并且产生流量时 `SENT(MB)` 持续增长，即可确认 Brutal 正在工作。

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jh4ygsg-dot/mihomo-anytls-brutal/main/uninstall.sh)
```

卸载脚本会移除本项目的 systemd 服务、监控脚本和状态目录，并尝试删除由状态文件记录的 Brutal `/32` 规则；不会卸载 TCP Brutal 内核模块本身，也不会修改 Mihomo 配置。

## 致谢

本项目的脚本设计、实现与文档编写由项目作者与 OpenAI ChatGPT（GPT-5.6 Sol）协作完成。

感谢 Mihomo / MetaCubeX 与 TCP Brutal / HyNetworks 项目的开发者。

## 说明

TCP Brutal 是独立项目。本仓库只是围绕 Mihomo AnyTLS + TCP Brutal v2 的自动规则管理脚本，与 Mihomo / MetaCubeX、TCP Brutal / HyNetworks 无官方关联。

## License

MIT
