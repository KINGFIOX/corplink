# docker 飞连部署说明(本机)

基于 [sleepymole/docker-corplink](https://github.com/sleepymole/docker-corplink):
官方飞连 Linux 客户端(镜像内置 v3.0.24,deb 来自 cdn.isealsuite.com)跑在
Kasm 网页桌面容器里,VPN 隧道建立后由 privoxy/socks5 转成宿主机代理。

## 日常使用

```bash
cd /root/corplink
docker compose up -d      # 启动(已配置 restart,开机自启)
docker compose down       # 停止
docker logs -f corplink   # 看日志
```

- **网页桌面(登录飞连)**:https://127.0.0.1:6901 用户 `kasm_user`,密码 `password`(VNC_PW)
- **HTTP 代理**:127.0.0.1:8888(容器内 privoxy:8118)
- **SOCKS5 代理**:127.0.0.1:1088(容器内 go-socks5-proxy:1080,无认证)
- 登录状态持久化在 named volume `corplink-home`(显式命名,不随项目名/目录名变;
  挂载 /home/kasm-user),重建容器不丢,但重建后飞连一般需在桌面里手动重连一次。

## 核心设计:TEST-NET 网段绕过飞连的私网阻断

飞连 VPN 启用后,客户端会在容器内核层(eBPF,iptables/nft/tc 均不可见)阻断
**路径上含 RFC1918 地址的新建连接**——入站(docker-proxy 转发)和出站(访问
网关/私网)都拦,已建立连接的回包和公网出站不受影响。普通 docker 网段
(172.x)下,-p 端口映射在 VPN 开启时全部超时,这就是最初"VPN 一开 6901 就断"
的原因。

解法:容器网络固定为 **`192.0.2.0/30`**(TEST-NET-1 文档保留段,/30 正好一个
容器:网关 .1 + 容器 .2)。docker-proxy 转发路径(源 192.0.2.1 → 目的
192.0.2.2)上没有任何 RFC1918 地址,飞连过滤器全放行——2026-10 实测 VPN
开启状态下端口映射稳定可用。

选段禁忌:
- **100.64.0.0/10(CGNAT)**:宿主机 Tailscale 的 ts-input 防伪造规则会丢弃
  源地址在该段、但非 tailscale0 接口进来的包,容器将完全到不了宿主机
  (且 CGNAT 疑似也在飞连黑名单内,入站实测被拦)
- 任何 RFC1918 段(10/8、172.16/12、192.168/16):就是被拦的对象

Mac 访问:`ssh -N -L 6901:127.0.0.1:6901 -L 8888:127.0.0.1:8888 -L 1088:127.0.0.1:1088 archlinux`;
桌面必须用 **https://** 访问(KasmVNC 对明文 http 直接断开,报 ERR_EMPTY_RESPONSE)。

## 与上游的差异(本机定制)

1. **端口只绑 127.0.0.1**:两个代理都无认证,绝不能绑 0.0.0.0。
2. **compose 指定 dns: 223.5.5.5/119.29.29.29**:宿主机 resolv.conf 指向
   Tailscale 100.100.100.100,容器内嵌 DNS 转发不可达。
3. **custom_startup.sh 覆盖(去掉 iptables 操作)**:上游脚本在容器内执行
   `iptables -t nat -F` 等 SNAT 模式规则,会误清新版 Docker 内嵌 DNS 依赖的
   容器内 DNAT 规则(127.0.0.11:53→随机端口),导致容器内 DNS 全挂
   (privoxy 报 "No such domain")。端口映射模式用不到 SNAT,直接去掉。
4. **网络固定 192.0.2.0/30**:见上节,绕过飞连私网阻断的关键。
5. tun/NET_ADMIN 仅作用于容器自身 netns(飞连建 WireGuard 隧道必需),
   不影响宿主机网络。

## 排障

- 容器内 DNS 失灵 → `docker exec corplink getent hosts baidu.com`,
  先看 `ss -lnup` 里 127.0.0.11:53 的 DNAT 是否又被清掉。
- 代理返回 502 No such domain → 同上,DNS 问题。
- VPN 开着但宿主机端口不通 → 先确认容器网段仍是 192.0.2.0/30 且
  docker-proxy 在监听(`ss -tlnp | grep 6901`)。
- 飞连连不上 VPN → `docker exec -u root corplink supervisorctl status`,
  看 corplink 服务日志 /var/log/corplink/。
- mihomo 分流:把 `127.0.0.1:1088` 加为 SOCKS5 节点,内网域名/网段规则指向它。

镜像经 docker.1panel.live 拉取后 retag 为 sleepymole/corplink:latest
(宿主机 docker daemon 无代理配置,直连 Docker Hub 不通)。
旧 volume `docker-corplink_corplink-home`(数据已迁移到 corplink-home)确认
无异常后可 `docker volume rm docker-corplink_corplink-home` 清理。
