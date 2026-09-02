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

Tailscale Funnel can expose the rack MCP servers over public HTTPS without router port forwarding or a separately purchased domain. The MCP services themselves remain local to the Raspberry Pi; Funnel publishes selected local HTTP ports through the Raspberry Pi's stable `*.ts.net` hostname.

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

XMSeries-MCP normally listens locally on port `8787`:

```text
http://127.0.0.1:8787/mcp
```

Publish it on the default public HTTPS port `443`:

```bash
sudo tailscale funnel --bg 8787
```

Current rack endpoint:

```text
https://raspberrypi-1.tail70348.ts.net/mcp
```

Health check:

```text
https://raspberrypi-1.tail70348.ts.net/health
```

### QLCPlus-MCP

QLCPlus-MCP normally listens locally on port `8788`:

```text
http://127.0.0.1:8788/mcp
```

Because port `443` is already used by XMSeries-MCP, publish QLCPlus-MCP on Funnel HTTPS port `8443`:

```bash
sudo tailscale funnel --https=8443 --bg http://127.0.0.1:8788
```

Current rack endpoint:

```text
https://raspberrypi-1.tail70348.ts.net:8443/mcp
```

Health check:

```text
https://raspberrypi-1.tail70348.ts.net:8443/health
```

The expected Funnel layout is therefore:

```text
Internet / Claude / MCP client
        │
        ├─ HTTPS 443  → Tailscale Funnel → 127.0.0.1:8787 → XMSeries-MCP
        │
        └─ HTTPS 8443 → Tailscale Funnel → 127.0.0.1:8788 → QLCPlus-MCP
```

Both servers use **stateless Streamable HTTP**, so clients keep the same `/mcp` URL across Raspberry Pi or MCP service restarts and do not depend on a server-side `Mcp-Session-Id` surviving the reboot.

### Claude or another MCP-compatible agent

For Claude, add each public URL as a separate custom/remote MCP connector:

```text
XMSeries-MCP  : https://raspberrypi-1.tail70348.ts.net/mcp
QLCPlus-MCP   : https://raspberrypi-1.tail70348.ts.net:8443/mcp
```

For agents that use JSON MCP configuration, the equivalent configuration is:

```json
{
  "mcpServers": {
    "mixer": {
      "type": "streamable-http",
      "url": "https://raspberrypi-1.tail70348.ts.net/mcp"
    },
    "qlcplus": {
      "type": "streamable-http",
      "url": "https://raspberrypi-1.tail70348.ts.net:8443/mcp"
    }
  }
}
```

The same Streamable HTTP endpoints can be used by OpenAI/ChatGPT-compatible MCP clients or other agents that support remote MCP servers.

If `MCP_AUTH_TOKEN` or bearer authentication is enabled on either MCP server, configure the client with the matching header:

```text
Authorization: Bearer <token>
```

Do not expose a stage-control MCP publicly without authentication unless it is a deliberate temporary test: these MCP servers can perform real mixer or lighting actions.

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
