#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# Source the removal function and replace every host-changing command. These
# tests never use root, real systemd units, or the installed program files.
run_uninstall() (
    source "$repo_dir/uninstall.sh"
    systemctl() {
        printf '%s\n' "$*" >> "$test_dir/events"
        case "$1" in
            disable) [[ "$scenario" != disable-failure ]] ;;
            show)
                [[ "$scenario" != query-failure ]] || return 1
                local checks=0
                if [[ -f "$test_dir/checks" ]]; then checks="$(< "$test_dir/checks")"; fi
                checks=$((checks + 1))
                printf '%s\n' "$checks" > "$test_dir/checks"
                if [[ "$scenario" == timeout || "$checks" == 1 ]]; then
                    printf 'activating\n'
                else
                    touch "$test_dir/finished"
                    printf 'inactive\n'
                fi
                ;;
            daemon-reload) return 0 ;;
            *) return 1 ;;
        esac
    }
    sleep() { printf 'wait\n' >> "$test_dir/events"; }
    rm() {
        [[ -f "$test_dir/finished" ]] || return 1
        printf 'remove %s\n' "$*" >> "$test_dir/events"
    }
    rmdir() { printf 'remove-dir %s\n' "$*" >> "$test_dir/events"; }
    uninstall_watchdog
)

scenario=finishes
run_uninstall
[[ "$(< "$test_dir/checks")" == 2 ]]
[[ "$(awk '/^remove -f / {n++} END {print n+0}' "$test_dir/events")" == 4 ]]
[[ "$(tail -n 1 "$test_dir/events")" == daemon-reload ]]

for scenario in timeout disable-failure query-failure; do
    rm -f "$test_dir/events" "$test_dir/checks" "$test_dir/finished"
    if run_uninstall; then
        echo "Uninstall unexpectedly succeeded: $scenario" >&2
        exit 1
    fi
    if awk '/^remove|^daemon-reload/ {found=1} END {exit !found}' "$test_dir/events"; then
        echo "Uninstall removed files after $scenario" >&2
        exit 1
    fi
    if [[ "$scenario" == timeout ]]; then
        [[ "$(awk '/^wait$/ {n++} END {print n+0}' "$test_dir/events")" == 30 ]]
    fi
done

echo 'All stubbed uninstall tests passed.'
