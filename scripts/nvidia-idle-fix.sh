#!/usr/bin/env bash
set -euo pipefail

SUSPEND_PATH="${NIPW_SUSPEND_PATH:-/proc/driver/nvidia/suspend}"
RUN_DIR="${NIPW_RUN_DIR:-/run}"

if (( EUID != 0 )) && [[ "$SUSPEND_PATH" == /proc/driver/nvidia/suspend ]]; then
    echo "Run as root to access $SUSPEND_PATH" >&2
    exit 1
fi
if [[ ! -w "$SUSPEND_PATH" ]]; then
    echo "NVIDIA suspend interface is not writable: $SUSPEND_PATH" >&2
    exit 1
fi

exec 8>"$RUN_DIR/nvidia-idle-power-fix.lock"
if ! flock -n 8; then
    echo "Another recovery is in progress" >&2
    exit 1
fi

suspended=0
resume_on_exit() {
    if (( suspended )); then
        printf 'resume\n' > "$SUSPEND_PATH" ||
            echo "WARNING: automatic NVIDIA resume failed" >&2
    fi
}
trap resume_on_exit EXIT

# Mark first so a failed write also causes a best-effort resume.
suspended=1
printf 'suspend\n' > "$SUSPEND_PATH"
sleep 1
printf 'resume\n' > "$SUSPEND_PATH"
suspended=0
