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
    LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    TZ=Asia/Shanghai \
    VNC_GEOMETRY=1440x900

# Install socks5
COPY --from=serjs/go-socks5-proxy /socks5 /usr/local/bin/socks5

# Install Corplink client + VNC desktop + proxy services
COPY ./src/ubuntu/install/corplink /corplink-build
RUN bash /corplink-build/install_corplink.sh && rm -rf /corplink-build

# 容器入口单独一层,改 entrypoint 不必重跑上面的安装层
COPY ./src/ubuntu/install/corplink/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 5901 8118 1080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
