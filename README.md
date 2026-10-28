# docker-corplink

docker-corplink builds a docker image to run corplink in a container: the
official Corplink (飞连) Linux client on a plain **TigerVNC + openbox** desktop
(no KasmVNC / web desktop stack), exposing its VPN tunnel as HTTP and SOCKS5
proxies.

Forked from [sleepymole/docker-corplink](https://github.com/sleepymole/docker-corplink),
which was based on [kasmtech/workspaces-images](https://github.com/kasmtech/workspaces-images).

## Usage

1. Run the container as a daemon.

```bash
docker run -d \
  --name=corplink \
  --hostname=ubuntu \
  --device=/dev/net/tun \
  --cap-add=NET_ADMIN \
  --shm-size=512m \
  -p 127.0.0.1:5901:5901 \
  -p 8888:8118 \
  -p 1088:1080 \
  -e VNC_PW=password \
  sleepymole/corplink:latest
```

Both arm64 and amd64 architectures are supported.

Optional environment variables:

* `VNC_PW`: VNC password (VNC protocol limits it to 8 characters)
* `VNC_GEOMETRY`: desktop resolution, default `1440x900`

2. Configure corplink with any VNC client: `vnc://localhost:5901`
   (e.g. macOS Screen Sharing), password is `VNC_PW`.

3. Access corplink network via http proxy: localhost:8888 or socks5 proxy:
   localhost:1088. You can also route traffic to the container (SNAT mode is
   not included in this fork).
