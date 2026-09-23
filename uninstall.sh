#!/usr/bin/env bash
set -euo pipefail

uninstall_watchdog() {
    systemctl disable --now nvidia-idle-power-watchdog.timer || return 1

    # Stopping a timer does not stop its running service. Let a recovery finish
    # naturally so we neither interrupt the pulse nor remove a script it needs.
    local attempt service_state
    for (( attempt=0; attempt<=30; attempt++ )); do
        service_state="$(systemctl show --property=ActiveState --value nvidia-idle-power-watchdog.service)" || return 1
        case "$service_state" in
            inactive|failed) break ;;
            active|activating|deactivating|reloading) ;;
            *) echo "Unexpected service state: $service_state; files retained" >&2; return 1 ;;
        esac
        if (( attempt == 30 )); then
            echo "Service is still running; timer disabled, files retained. Retry after it finishes." >&2
            return 1
        fi
        sleep 1 || return 1
    done

    rm -f /etc/systemd/system/nvidia-idle-power-watchdog.service || return 1
    rm -f /etc/systemd/system/nvidia-idle-power-watchdog.timer || return 1
    rm -f /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-watchdog.sh || return 1
    rm -f /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-fix.sh || return 1
    rmdir /usr/local/libexec/nvidia-idle-power-watchdog 2>/dev/null || true
    systemctl daemon-reload || return 1

    echo "Removed program and systemd units. Configuration remains at:"
    echo "  /etc/default/nvidia-idle-power-watchdog"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if (( EUID != 0 )); then
        echo "Run as root: sudo ./uninstall.sh" >&2
        exit 1
    fi
    uninstall_watchdog
fi
