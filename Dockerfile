# 原镜像基于 kasmweb/core-ubuntu-noble(KasmVNC 网页桌面),不稳定且自带
# iptables/SNAT 启动逻辑会破坏容器内嵌 DNS。后改为 ubuntu:noble + TigerVNC +
# openbox,纯原生 VNC(5901),supervisor 托管全部进程;现在基础镜像再换成
# debian:trixie —— Ubuntu 24.04 源里 firefox/chromium 都是 snap 过渡包,容器内
# 装不了,而 Debian main 源有原生 chromium deb(t64 库名也与 noble 相同)。
# 国内网络直连 Docker Hub 不通时,可用 --build-arg BASE_IMAGE 指定镜像源,如:
#   docker build --build-arg BASE_IMAGE=docker.1panel.live/library/debian:trixie .
ARG BASE_IMAGE="debian:trixie"
FROM ${BASE_IMAGE}

USER root

ENV HOME=/home/corplink \
    TZ=Asia/Shanghai \
    VNC_GEOMETRY=1440x900

# Install socks5
COPY --from=serjs/go-socks5-proxy /socks5 /usr/local/bin/socks5

# Install Corplink client + VNC desktop + proxy services
COPY ./src/ubuntu/install/corplink /corplink-build
RUN bash /corplink-build/install_corplink.sh && rm -rf /corplink-build

# 飞连 service 靠 shell 调 `ip link/route` 配置 utun 网卡与路由;飞连 deb 的
# 依赖链在 Ubuntu 上会带 iproute2,在 Debian 上不会 —— 缺了它 VPN 就
# "显示已连接但 utun 无地址无路由、流量全不走隧道"。单独一层,便于缓存。
RUN apt-get update -o Acquire::Retries=3 \
  && apt-get install -y --no-install-recommends iproute2 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# 容器入口单独一层,改 entrypoint 不必重跑上面的安装层
COPY ./src/ubuntu/install/corplink/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# 中文 locale 放在安装层之后声明:locale-gen 在安装层里生成 zh_CN.UTF-8,
# 若在此之前 export,构建期每个 RUN 都会报 setlocale warning
ENV LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8

EXPOSE 5901 8118 1080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
