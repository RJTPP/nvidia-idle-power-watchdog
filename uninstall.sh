#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run as root: sudo ./uninstall.sh" >&2
    exit 1
fi

systemctl disable --now nvidia-idle-power-watchdog.timer 2>/dev/null || true
rm -f /etc/systemd/system/nvidia-idle-power-watchdog.service
rm -f /etc/systemd/system/nvidia-idle-power-watchdog.timer
rm -f /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-watchdog.sh
rm -f /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-fix.sh
rmdir /usr/local/libexec/nvidia-idle-power-watchdog 2>/dev/null || true
systemctl daemon-reload

echo "Removed program and systemd units. Configuration remains at:"
echo "  /etc/default/nvidia-idle-power-watchdog"
