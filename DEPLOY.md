# docker 飞连部署说明(本机)

基于 [sleepymole/docker-corplink](https://github.com/sleepymole/docker-corplink)
改造:官方飞连 Linux 客户端(镜像内置 v3.0.24,deb 来自 cdn.isealsuite.com)跑在
**ubuntu:noble + TigerVNC + openbox** 容器里(2026-10 从 Kasm 网页桌面迁移,
Kasm 不稳定),VPN 隧道建立后由 privoxy/socks5 转成宿主机代理。
所有进程(supervisor)托管:Xvnc、飞连 GUI、飞连 service、privoxy、socks5、fixdns。

## 日常使用

```bash
cd /root/corplink
docker compose up -d      # 启动(已配置 restart,开机自启)
docker compose down       # 停止
docker logs -f corplink   # 看日志
docker exec corplink supervisorctl status   # 各进程状态
```

- **VNC 桌面(登录飞连)**:`vnc://127.0.0.1:5901`,密码 `VNC_PW`(默认 password;
  VNC 协议密码最多 8 位)。分辨率可用 `VNC_GEOMETRY` 调(默认 1440x900)。
- **HTTP 代理**:192.168.122.1:8118(容器内 privoxy)
- **SOCKS5 代理**:192.168.122.1:1080(容器内 go-socks5-proxy,无认证)
- 登录状态持久化在 named volume `corplink-home`(显式命名,不随项目名/目录名变;
  挂载 /home/corplink,uid 1000 与旧 kasm 镜像一致),重建容器不丢,但重建后
  飞连一般需在桌面里手动重连一次。
- 回滚:旧 kasm 镜像 ID `2067eb46c3ba`,`docker tag 2067eb46c3ba
  sleepymole/corplink:latest && docker compose up -d` 即可切回。

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

Mac 访问:`ssh -N -L 5901:127.0.0.1:5901 -L 8888:192.168.122.1:8118 -L 1088:192.168.122.1:1080 archlinux`,
然后访达 ⌘K 连 `vnc://127.0.0.1:5901`(或"屏幕共享"App)。VNC 是纯 TCP,
无 KasmVNC 那种"必须 https"的限制。

## 与上游的差异(本机定制)

1. **镜像从 kasmweb/core-ubuntu-noble 换成 ubuntu:noble + TigerVNC + openbox**:
   去掉 KasmVNC 网页桌面(6901)与 kasm 启动脚本;原镜像的 `custom_startup.sh`
   里 `iptables -t nat -F` 等 SNAT 规则会误清新版 Docker 内嵌 DNS 依赖的容器内
   DNAT 规则(127.0.0.11:53→随机端口)导致 DNS 全挂,新镜像完全不做 iptables
   操作,不再需要挂载脚本覆盖。
2. **代理端口只绑 192.168.122.1、VNC 只绑 127.0.0.1**:两个代理都无认证,绝不能
   绑 0.0.0.0。
3. **compose 指定 dns: 223.5.5.5/119.29.29.29**:宿主机 resolv.conf 指向
   Tailscale 100.100.100.100,容器内嵌 DNS 转发不可达。
4. **网络固定 192.0.2.0/30**:见上节,绕过飞连私网阻断的关键。
5. tun/NET_ADMIN 仅作用于容器自身 netns(飞连建 WireGuard 隧道必需),
   不影响宿主机网络。
6. 镜像本地构建(基础镜像 ubuntu:noble 经 docker.1panel.live 拉取后 retag,
   或 `--build-arg BASE_IMAGE=...` 直指镜像源;serjs/go-socks5-proxy 同理)。

## 排障

- 容器内 DNS 失灵 → `docker exec corplink getent hosts baidu.com`,
  先看 `ss -lnup` 里 127.0.0.11:53 的 DNAT 是否又被清掉(新镜像理论上不会再发生)。
- 代理返回 502 No such domain → 同上,DNS 问题。
- VPN 开着但宿主机端口不通 → 先确认容器网段仍是 192.0.2.0/30 且
  docker-proxy 在监听(`ss -tlnp | grep -E '5901|8118|1080'`)。
- VNC 连不上 → `docker exec corplink supervisorctl status` 看 xvnc 是否 RUNNING,
  日志在 /var/log/xvnc/;确认密码是 VNC_PW(≤8 位)。
- 飞连连不上 VPN → `docker exec corplink supervisorctl status`,
  看 corplink-service 日志 /var/log/corplink/。
- mihomo 分流:把 `192.168.122.1:1080` 加为 SOCKS5 节点,内网域名/网段规则指向它。

volume `corplink-home` 沿用旧 kasm 数据(uid 1000 属主一致,飞连登录态保留;
旧 kasm 残留的 .vnc/.kasmpasswd 等文件无害)。
旧 volume `docker-corplink_corplink-home`(数据已迁移到 corplink-home)确认
无异常后可 `docker volume rm docker-corplink_corplink-home` 清理。
