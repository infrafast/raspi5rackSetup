#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "ERROR: run this installer with sudo: sudo ./install.sh" >&2
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-pi}}"

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "ERROR: target user '$TARGET_USER' does not exist." >&2
    exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

if [[ -z "$TARGET_HOME" || "$TARGET_HOME" == "/root" ]]; then
    echo "ERROR: invalid target home for '$TARGET_USER': $TARGET_HOME" >&2
    exit 1
fi

require_file() {
    if [[ ! -e "$1" ]]; then
        echo "ERROR: required file missing: $1" >&2
        exit 1
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command missing: $1" >&2
        exit 1
    fi
}

for cmd in systemctl xrandr xdpyinfo x11vnc openbox; do
    require_cmd "$cmd"
done
require_file /usr/bin/qlcplus-qml
require_file "$TARGET_HOME/interval/QLCfiles/intervalPI5.qxw"
require_file "$TARGET_HOME/interval/QLCfiles/backup/intervalPI5.qxw"
require_file "$TARGET_HOME/.vnc/passwd"

install -o root -g root -m 0755 "$SCRIPT_DIR/bin/wait-for-x11" /usr/local/bin/wait-for-x11
install -o root -g root -m 0755 "$SCRIPT_DIR/bin/x11-display-setup" /usr/local/bin/x11-display-setup
install -o root -g root -m 0755 "$SCRIPT_DIR/bin/qlcplus-service" /usr/local/bin/qlcplus-service

install -o root -g root -m 0644 "$SCRIPT_DIR/defaults/x11-display" /etc/default/x11-display

# Remove files used by the previous QLC+ launcher architecture.
rm -f /usr/local/bin/qlcplus-run /etc/default/qlcplus

mkdir -p "$TARGET_HOME/interval/scripts"
sed "s#/home/pi#$TARGET_HOME#g" "$SCRIPT_DIR/scripts/check-qlc-workspace.sh" > "$TARGET_HOME/interval/scripts/check-qlc-workspace.sh"
chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/interval/scripts/check-qlc-workspace.sh"
chmod 0755 "$TARGET_HOME/interval/scripts/check-qlc-workspace.sh"

for unit in x11-display-setup.service x11vnc.service qlcplus.service; do
    sed -e "s/^User=pi$/User=$TARGET_USER/" -e "s/^Group=pi$/Group=$TARGET_GROUP/" -e "s#/home/pi#$TARGET_HOME#g" "$SCRIPT_DIR/systemd/$unit" > "/etc/systemd/system/$unit"
    chown root:root "/etc/systemd/system/$unit"
    chmod 0644 "/etc/systemd/system/$unit"
done

sed "s/^pi /$TARGET_USER /" "$SCRIPT_DIR/sudoers/qlcplus-service" > /etc/sudoers.d/qlcplus-service
chown root:root /etc/sudoers.d/qlcplus-service
chmod 0440 /etc/sudoers.d/qlcplus-service
if command -v visudo >/dev/null 2>&1; then
    visudo -cf /etc/sudoers.d/qlcplus-service >/dev/null
fi

OPENBOX_DIR="$TARGET_HOME/.config/openbox"
mkdir -p "$OPENBOX_DIR"
if [[ -f "$OPENBOX_DIR/autostart" ]]; then
    cp -a "$OPENBOX_DIR/autostart" "$OPENBOX_DIR/autostart.before-systemd-$(date +%Y%m%d-%H%M%S)"
fi
install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 0755 "$SCRIPT_DIR/openbox/autostart" "$OPENBOX_DIR/autostart"

/usr/bin/systemd-analyze verify /etc/systemd/system/x11-display-setup.service /etc/systemd/system/x11vnc.service /etc/systemd/system/qlcplus.service >/dev/null
/usr/bin/systemctl daemon-reload
/usr/bin/systemctl enable x11-display-setup.service x11vnc.service qlcplus.service >/dev/null

echo "Installation complete."
echo "Target user : $TARGET_USER"
echo "Target home : $TARGET_HOME"
echo "Services    : x11-display-setup, x11vnc, qlcplus enabled"
echo "Next step   : sudo reboot"
