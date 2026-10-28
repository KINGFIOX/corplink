#!/bin/bash
# 容器入口(root,PID 1):生成 VNC 密码与 xstartup,再交给 supervisor
set -eu

: "${VNC_PW:=password}"
: "${VNC_GEOMETRY:=1440x900}"

mkdir -p "$HOME/.vnc"

# vncpasswd -f:从 stdin 读明文,输出加密密码文件(VNC 协议密码最多 8 位)
printf '%s\n' "$VNC_PW" | vncpasswd -f >"$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

cat >"$HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
# tigervncconfig/vncconfig 负责剪贴板同步(宿主机复制 -> VNC 内粘贴)
(tigervncconfig -nowin || vncconfig -nowin) &
stalonetray &
exec dbus-launch --exit-with-session openbox-session
EOF
chmod 755 "$HOME/.vnc/xstartup"

chown -R corplink:corplink "$HOME/.vnc"

exec /usr/bin/supervisord -n
