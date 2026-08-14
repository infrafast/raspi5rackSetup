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
