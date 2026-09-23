#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${NIPW_CONFIG_FILE:-/etc/default/nvidia-idle-power-watchdog}"
RUN_DIR="${NIPW_RUN_DIR:-/run}"
FIX_SCRIPT="${NIPW_FIX_SCRIPT:-$(dirname "$0")/nvidia-idle-fix.sh}"
STATE_FILE="$RUN_DIR/nvidia-idle-power-bad-count"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Missing configuration: $CONFIG_FILE" >&2
    exit 1
fi
# The installed configuration must be root-owned and not writable by others.
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${MODE:=strict}"
if [[ "$MODE" != strict && "$MODE" != loaded-idle ]]; then
    echo "MODE must be strict or loaded-idle" >&2
    exit 1
fi
if [[ ! "${POWER_THRESHOLD_W:-}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
   ! awk -v p="$POWER_THRESHOLD_W" 'BEGIN { exit !(p > 0) }'; then
    echo "POWER_THRESHOLD_W must be a positive number" >&2
    exit 1
fi
if [[ ! "${REQUIRED_PROBES:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "REQUIRED_PROBES must be a positive integer" >&2
    exit 1
fi

exec 9>"$RUN_DIR/nvidia-idle-power-watchdog.lock"
flock -n 9 || exit 0

log() { logger -t nvidia-idle-power-watchdog -- "$*"; }

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

eligible() {
    local gpu_list gpu_data pstate power utilization extra processes
    if ! gpu_list="$(nvidia-smi --query-gpu=uuid --format=csv,noheader,nounits)"; then
        echo "Could not list NVIDIA GPUs" >&2
        return 2
    fi
    if [[ -z "$gpu_list" || "$(printf '%s\n' "$gpu_list" | awk 'END { print NR }')" != 1 ]]; then
        echo "Exactly one NVIDIA GPU is required" >&2
        return 2
    fi

    if ! gpu_data="$(nvidia-smi --query-gpu=pstate,power.draw,utilization.gpu --format=csv,noheader,nounits)"; then
        echo "Could not read NVIDIA GPU state" >&2
        return 2
    fi
    IFS=',' read -r pstate power utilization extra <<< "$gpu_data"
    pstate="$(trim "${pstate:-}")"
    power="$(trim "${power:-}")"
    utilization="$(trim "${utilization:-}")"
    if [[ -n "${extra:-}" || "$pstate" != P[0-9]* ||
          ! "$power" =~ ^[0-9]+([.][0-9]+)?$ ||
          ! "$utilization" =~ ^[0-9]+$ ]]; then
        echo "Malformed NVIDIA GPU reading" >&2
        return 2
    fi

    if [[ "$MODE" == strict ]]; then
        if ! processes="$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits)"; then
            echo "Could not inspect NVIDIA compute processes" >&2
            return 2
        fi
        if [[ -n "$(trim "$processes")" ]]; then
            return 1
        fi
    fi

    [[ "$pstate" == P8 && "$utilization" == 0 ]] &&
        awk -v p="$power" -v t="$POWER_THRESHOLD_W" 'BEGIN { exit !(p > t) }'
}

count=0
if [[ -f "$STATE_FILE" ]]; then
    read -r count < "$STATE_FILE" || true
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
fi

if eligible; then
    count=$((count + 1))
else
    result=$?
    if (( result > 1 )); then
        printf '0\n' > "$STATE_FILE"
        exit 1
    fi
    count=0
fi
printf '%s\n' "$count" > "$STATE_FILE"

if (( count >= REQUIRED_PROBES )); then
    # A new workload may start at any time. Recheck immediately before recovery.
    if eligible; then
        printf '0\n' > "$STATE_FILE"
        log "High-power P8 persisted for $count probes; attempting recovery ($MODE)"
        "$FIX_SCRIPT"
        log "Recovery completed"
    else
        result=$?
        printf '0\n' > "$STATE_FILE"
        (( result == 1 )) || exit 1
    fi
fi
