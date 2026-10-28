#!/usr/bin/env bash
set -ex
export DEBIAN_FRONTEND=noninteractive

apt update
# tigervnc-standalone-server: Xvnc + tigervncserver 包装脚本
# openbox/stalonetray: 轻量窗口管理器 + 托盘(飞连最小化到托盘用)
# dbus-x11: Electron 需要 session dbus;fonts-noto-cjk: 中文渲染
# libgtk/libnss/libasound 等: Electron 运行时依赖
apt install -y --no-install-recommends \
  supervisor privoxy jq wget ca-certificates locales tzdata \
  tigervnc-standalone-server tigervnc-common tigervnc-tools \
  openbox stalonetray dbus-x11 x11-utils xterm xauth \
  fonts-noto-cjk fonts-liberation fonts-dejavu-core \
  libgtk-3-0t64 libnss3 libxss1 libasound2t64 libgbm1 libnotify4 libxtst6 \
  libatk-bridge2.0-0t64 libxkbcommon-x11-0 libxkbfile1 libglib2.0-bin

sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

# 运行桌面的普通用户(uid 1000,兼容旧 volume corplink-home 里的文件属主)。
# ubuntu:noble 自带 uid 1000 的默认用户 ubuntu,先删掉腾出 uid
userdel -r ubuntu 2>/dev/null || true
groupdel ubuntu 2>/dev/null || true
useradd -m -u 1000 -s /bin/bash corplink

# Privoxy:容器内 HTTP 代理
sed -i '/^listen-address/d' /etc/privoxy/config
echo 'listen-address 0.0.0.0:8118' >>/etc/privoxy/config

mkdir -p /var/log/corplink /var/log/privoxy /var/log/socks5 /var/log/fixdns /var/log/xvnc

# 飞连后台服务(建 WireGuard 隧道,root 运行)
cat <<EOF >/etc/supervisor/conf.d/corplink-service.conf
[program:corplink-service]
command=/opt/apps/com.volcengine.feilian/files/corplink-service
priority=20
autostart=true
autorestart=true
stderr_logfile=/var/log/corplink/stderr.log
stdout_logfile=/var/log/corplink/stdout.log
EOF

# VNC 桌面(Xvnc,display :1 即 5901 端口;密码文件由 entrypoint 生成)
cat <<'EOF' >/etc/supervisor/conf.d/xvnc.conf
[program:xvnc]
command=/usr/bin/tigervncserver :1 -fg -geometry %(ENV_VNC_GEOMETRY)s -depth 24 -localhost no
priority=10
user=corplink
environment=HOME="/home/corplink",USER="corplink",DISPLAY=":1"
autostart=true
autorestart=true
startsecs=3
stderr_logfile=/var/log/xvnc/stderr.log
stdout_logfile=/var/log/xvnc/stdout.log
EOF

# 飞连 GUI(Electron,跑在 VNC 桌面里,崩溃自动拉起)
cat <<'EOF' >/usr/local/bin/corplink-gui.sh
#!/bin/bash
export HOME=/home/corplink
export USER=corplink
export DISPLAY=:1
export XDG_RUNTIME_DIR=/tmp/xdg-corplink
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
# 等待 Xvnc 就绪
while ! xdpyinfo >/dev/null 2>&1; do sleep 1; done
while true; do
  /opt/apps/com.volcengine.feilian/files/corplink --no-sandbox --disable-gpu || true
  sleep 2
done
EOF
chmod +x /usr/local/bin/corplink-gui.sh
cat <<EOF >/etc/supervisor/conf.d/corplink-gui.conf
[program:corplink-gui]
command=/usr/local/bin/corplink-gui.sh
priority=30
user=corplink
autostart=true
autorestart=true
stderr_logfile=/var/log/corplink/gui-stderr.log
stdout_logfile=/var/log/corplink/gui-stdout.log
EOF

# Privoxy 服务
cat <<EOF >/etc/supervisor/conf.d/privoxy.conf
[program:privoxy]
command=/usr/sbin/privoxy --no-daemon /etc/privoxy/config
priority=40
autostart=true
autorestart=true
stderr_logfile=/var/log/privoxy/stderr.log
stdout_logfile=/var/log/privoxy/stdout.log
EOF

# Socks5 服务
cat <<EOF >/etc/supervisor/conf.d/socks5.conf
[program:socks5]
command=/usr/local/bin/socks5
environment=REQUIRE_AUTH=false
priority=40
autostart=true
autorestart=true
stderr_logfile=/var/log/socks5/stderr.log
stdout_logfile=/var/log/socks5/stdout.log
EOF

# 飞连 VPN 起来后把它的 DNS 写进 /etc/resolv.conf
cat <<'EOF' >/usr/local/bin/fixdns.sh
#!/bin/bash
set -x
while true; do
  sleep 5
  dns=$(jq -r '.DNS[0]' /opt/apps/com.volcengine.feilian/files/vpn.conf 2>/dev/null)
  [ -z "$dns" ] && continue
  grep -q "$dns" /etc/resolv.conf && continue
  echo "nameserver ${dns}" >/etc/resolv.conf
done
EOF
chmod +x /usr/local/bin/fixdns.sh
cat <<EOF >/etc/supervisor/conf.d/fixdns.conf
[program:fixdns]
command=/usr/local/bin/fixdns.sh
priority=50
autostart=true
autorestart=true
stderr_logfile=/var/log/fixdns/stderr.log
stdout_logfile=/var/log/fixdns/stdout.log
EOF

# 飞连客户端本体
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
  wget -q -O /tmp/corplink.deb https://cdn.isealsuite.com/linux/FeiLian_Linux_arm64_v3.0.24_r5980_d44583.deb
else
  wget -q -O /tmp/corplink.deb https://cdn.isealsuite.com/linux/FeiLian_Linux_amd64_v3.0.24_r5980_6ebb49.deb
fi
apt install -y /tmp/corplink.deb
rm /tmp/corplink.deb

# 容器入口:每次启动生成 VNC 密码文件与 xstartup,然后 exec supervisor
install -m 755 /corplink-build/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

apt clean
rm -rf /var/lib/apt/lists/*
