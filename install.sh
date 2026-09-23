#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run as root: sudo ./install.sh" >&2
    exit 1
fi
for command in nvidia-smi flock awk logger systemctl; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

source_dir="$(cd "$(dirname "$0")" && pwd)"
program_dir=/usr/local/libexec/nvidia-idle-power-watchdog
config_path=/etc/default/nvidia-idle-power-watchdog

install -d -m 0755 "$program_dir"
install -m 0755 "$source_dir/scripts/nvidia-idle-watchdog.sh" "$program_dir/nvidia-idle-watchdog.sh"
install -m 0755 "$source_dir/scripts/nvidia-idle-fix.sh" "$program_dir/nvidia-idle-fix.sh"
install -m 0644 "$source_dir/systemd/nvidia-idle-power-watchdog.service" /etc/systemd/system/nvidia-idle-power-watchdog.service
install -m 0644 "$source_dir/systemd/nvidia-idle-power-watchdog.timer" /etc/systemd/system/nvidia-idle-power-watchdog.timer
systemctl daemon-reload

echo "Installed. Measure normal idle power, then create and edit $config_path:"
echo "  sudo install -m 0644 config.example $config_path"
echo "  sudoedit $config_path"
echo "Then run:"
echo "  sudo systemctl enable --now nvidia-idle-power-watchdog.timer"
