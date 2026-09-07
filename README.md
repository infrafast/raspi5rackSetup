# Raspberry Pi 5 — X11 / VNC / QLC+ systemd setup

## Architecture

The installed startup chain is:

```text
LightDM + Openbox / X11 :0
        ↓
x11-display-setup.service
        ↓
x11vnc.service
        ↓
qlcplus.service
        ├─ ExecStartPre: check-qlc-workspace.sh
        └─ ExecStart: qlcplus-qml
```

Openbox owns only desktop-session applications (`pcmanfm`, `tint2`, `xterm`, `btop`). systemd owns X11 resolution setup, VNC and QLC+.

## Validated target

- Raspberry Pi 5 / Raspberry Pi OS Debian 13 ARM64
- LightDM autologin to Openbox
- X11 display `:0`
- X authority `/home/pi/.Xauthority`
- x11vnc shares the real X11 desktop on TCP 5900
- QLC+ binary `/usr/bin/qlcplus-qml`
- QLC+ project `/home/pi/interval/QLCfiles/intervalPI5.qxw`
- default resolution `1368x768`
- alternate resolution `1024x768`

## Prerequisites

The installer expects:

- LightDM/Openbox/X11 already usable on `:0`
- headless X11/HDMI forcing already configured if required by the device
- `/usr/bin/qlcplus-qml` already installed
- `/home/pi/interval/QLCfiles/intervalPI5.qxw` present
- `/home/pi/interval/QLCfiles/backup/intervalPI5.qxw` present for recovery
- `/home/pi/.vnc/passwd` already created

The pack does not define Raspberry Pi firmware HDMI-forcing settings because those settings were outside the validated migration procedure.

## Installation

From the extracted directory:

```bash
sudo ./install.sh
```

The installer is non-interactive. It backs up the existing Openbox autostart, installs all files, enables the three services and leaves the machine ready for reboot.

Then reboot:

```bash
sudo reboot
```

## Public MCP access with Tailscale Funnel

Tailscale Funnel exposes the rack services over public HTTPS without router port forwarding or a separately purchased domain. The services remain bound locally on the Raspberry Pi; Funnel publishes them through the Raspberry Pi's stable `*.ts.net` hostname.

The validated rack setup uses **one public HTTPS endpoint on port 443** and mounts each service below its own path:

```text
https://raspberrypi-1.tail70348.ts.net
        ├─ /xm  → 127.0.0.1:8787 → XMSeries-MCP
        ├─ /qlc → 127.0.0.1:8788 → QLCPlus-MCP
        └─ /lsa → 127.0.0.1:8765 → LiveStageAssistant
```

This avoids exposing QLCPlus-MCP on an explicit `:8443` URL, which was rejected by Claude during testing.

Install and connect Tailscale once:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

After authentication, check the device and Funnel state with:

```bash
tailscale status
sudo tailscale funnel status
```

### XMSeries-MCP

XMSeries-MCP listens locally on port `8787`:

```text
http://127.0.0.1:8787/mcp
```

Publish it under `/xm` on the default Funnel HTTPS port `443`:

```bash
sudo tailscale funnel --https=443 --set-path=/xm --bg 8787
```

Validated public endpoints:

```text
MCP    : https://raspberrypi-1.tail70348.ts.net/xm/mcp
Health : https://raspberrypi-1.tail70348.ts.net/xm/health
GUI    : https://raspberrypi-1.tail70348.ts.net/xm/mcp
```

The MCP administration GUI uses paths relative to the current MCP URL. It therefore works both locally at `/mcp` and through Funnel at `/xm/mcp`.

```
cd /home/pi/XMSeries-MCP && OSC_HOST=192.168.0.16 OSC_PORT=10024 OSC_PROTOCOL=OSCXR OSC_CHANNEL_COUNT=16 OSC_BUS_COUNT=4 HTTP_HOST=0.0.0.0 HTTP_PORT=8787 npm run start:http
```

### QLCPlus-MCP

QLCPlus-MCP listens locally on port `8788`:

```text
http://127.0.0.1:8788/mcp
```

Publish it under `/qlc` on the same public HTTPS port `443`:

```bash
sudo tailscale funnel --https=443 --set-path=/qlc --bg 8788
```

Validated public endpoints:

```text
MCP    : https://raspberrypi-1.tail70348.ts.net/qlc/mcp
Health : https://raspberrypi-1.tail70348.ts.net/qlc/health
GUI    : https://raspberrypi-1.tail70348.ts.net/qlc/mcp
```

The QLCPlus-MCP administration GUI also uses paths relative to the current MCP URL, so status and runtime-log requests continue to work behind the `/qlc` Funnel prefix.

```
cd /home/pi/QLCPlus-MCP && MCP_TRANSPORT=http HTTP_HOST=0.0.0.0 HTTP_PORT=8788 QLC_NATIVE_HOST=127.0.0.1 QLC_NATIVE_PORT=9998 npm run start:http
```

### LiveStageAssistant

LiveStageAssistant listens locally on port `8765`:

```text
http://127.0.0.1:8765
```

Publish it under `/lsa` on the same public HTTPS port `443`:

```bash
sudo tailscale funnel --https=443 --set-path=/lsa --bg 8765
```

The public base URL is then:

```text
https://raspberrypi-1.tail70348.ts.net/lsa
```

### Expected Funnel state

The current validated layout is:

```text
Internet / Claude / MCP client
        │
        └─ HTTPS 443
              ↓
        Tailscale Funnel
              ├─ /xm  → http://127.0.0.1:8787
              ├─ /qlc → http://127.0.0.1:8788
              └─ /lsa → http://127.0.0.1:8765
```

`sudo tailscale funnel status` should show a layout equivalent to:

```text
https://raspberrypi-1.tail70348.ts.net (Funnel on)
|-- /xm  proxy http://127.0.0.1:8787
|-- /qlc proxy http://127.0.0.1:8788
|-- /lsa proxy http://127.0.0.1:8765
```

Both MCP servers use **stateless Streamable HTTP**. Clients therefore keep the same `/mcp` URL across Raspberry Pi or MCP service restarts and do not depend on a server-side `Mcp-Session-Id` surviving a reboot.

### Claude or another MCP-compatible agent

For Claude, add each public URL as a separate custom/remote MCP connector:

```text
XMSeries-MCP  : https://raspberrypi-1.tail70348.ts.net/xm/mcp
QLCPlus-MCP   : https://raspberrypi-1.tail70348.ts.net/qlc/mcp
```

For agents that use JSON MCP configuration, the equivalent configuration is:

```json
{
  "mcpServers": {
    "mixer": {
      "type": "streamable-http",
      "url": "https://raspberrypi-1.tail70348.ts.net/xm/mcp"
    },
    "qlcplus": {
      "type": "streamable-http",
      "url": "https://raspberrypi-1.tail70348.ts.net/qlc/mcp"
    }
  }
}
```

The same Streamable HTTP endpoints remain usable by LiveStageAssistant and other MCP clients that use the 2025-era MCP protocol.

### MCP protocol compatibility

The current XMSeries-MCP and QLCPlus-MCP servers intentionally remain on the stable v1 TypeScript MCP SDK so existing clients such as LiveStageAssistant keep their current behavior.

Claude may initially send:

```text
MCP-Protocol-Version: 2026-07-28
```

The servers detect that version and present the request to the current SDK using the supported legacy version:

```text
2025-11-25
```

A log entry such as the following is therefore expected when Claude connects:

```text
MCP 2026-07-28 request detected; using legacy 2025 compatibility for client fallback
```

This compatibility layer does not modify requests from existing 2025-era clients, including LiveStageAssistant. A future native migration to the MCP SDK v2 can add first-class `2026-07-28` support separately without changing the public Funnel URLs.

### Authentication

During temporary testing the MCP servers may run without HTTP authentication. For production or unattended public exposure, enable authentication because these MCP servers can perform real mixer and lighting actions.

XMSeries-MCP supports `MCP_AUTH_TOKEN`. QLCPlus-MCP supports bearer authentication through its MCP auth configuration. When authentication is enabled, configure the client with the corresponding header:

```text
Authorization: Bearer <token>
```

Do not expose a stage-control MCP publicly without authentication unless it is a deliberate temporary test.

### Removing Funnel rules

Remove only the individual mount without resetting the rest of the Funnel configuration:

```bash
sudo tailscale funnel --https=443 --set-path=/xm off
```

```bash
sudo tailscale funnel --https=443 --set-path=/qlc off
```

```bash
sudo tailscale funnel --https=443 --set-path=/lsa off
```

Avoid `tailscale funnel reset` unless the intention is to erase the complete Funnel configuration.

## Main configuration files

- `/etc/default/x11-display`

Change resolution by editing `SCREEN_RESOLUTION` in `/etc/default/x11-display`, then restart:

```bash
sudo systemctl restart x11-display-setup.service
```

QLC+ is launched directly by `/etc/systemd/system/qlcplus.service`. To change its flags or project, edit its `ExecStart` line, then run:

```bash
sudo systemctl daemon-reload
qlcplus-service restart
```

## QLC+ wrapper

```text
qlcplus-service start
qlcplus-service stop
qlcplus-service restart
qlcplus-service status
qlcplus-service logs
qlcplus-service auto
qlcplus-service noauto
qlcplus-service last-state
qlcplus-service health
```

`noauto` disables boot autostart without stopping the current QLC+ process.

## Quick verification after reboot

```bash
systemctl is-active x11-display-setup.service x11vnc.service qlcplus.service
pgrep -af 'openbox|x11vnc|qlcplus-qml'
DISPLAY=:0 XAUTHORITY=/home/pi/.Xauthority xrandr | head -12
systemd-analyze critical-chain qlcplus.service
```

Expected dependency chain:

```text
qlcplus.service
└─ x11vnc.service
   └─ x11-display-setup.service
      └─ lightdm.service
```

## Remaining physical validation

When physical access is available, connect an HDMI display and confirm it shows the same Openbox/X11 desktop as the VNC client.
