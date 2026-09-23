#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/run"

cat > "$test_dir/bin/nvidia-smi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --query-gpu=uuid,pstate,power.draw,utilization.gpu)
        if [[ -n "${MOCK_GPU_RECHECK_DATA:-}" && -f "$NIPW_RUN_DIR/queried" ]]; then
            printf '%s\n' "$MOCK_GPU_RECHECK_DATA"
        else
            printf '%s\n' "${MOCK_GPU_DATA-GPU-1, P8, 32, 0}"
        fi
        touch "$NIPW_RUN_DIR/queried"
        ;;
    --query-compute-apps=pid)
        [[ "${MOCK_PROCESS_QUERY_FAIL:-0}" != 1 ]] || exit 1
        printf '%s' "${MOCK_PROCESSES:-}"
        ;;
    *) exit 1 ;;
esac
STUB
cat > "$test_dir/bin/flock" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$test_dir/bin/logger" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$test_dir/bin/sleep" <<'STUB'
#!/usr/bin/env bash
[[ "${MOCK_SLEEP_FAIL:-0}" != 1 ]]
STUB
cat > "$test_dir/fix-ok" <<'STUB'
#!/usr/bin/env bash
printf 'fixed\n' >> "$MOCK_FIX_LOG"
STUB
cat > "$test_dir/fix-fail" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$test_dir/bin/"* "$test_dir/fix-ok" "$test_dir/fix-fail"

export PATH="$test_dir/bin:$PATH"
export NIPW_CONFIG_FILE="$test_dir/config"
export NIPW_RUN_DIR="$test_dir/run"
export NIPW_FIX_SCRIPT="$test_dir/fix-ok"
export MOCK_FIX_LOG="$test_dir/fixes"

reset_case() {
    printf 'MODE=%s\nPOWER_THRESHOLD_W=25\nREQUIRED_PROBES=2\n' "$1" > "$NIPW_CONFIG_FILE"
    rm -f "$test_dir/run/nvidia-idle-power-bad-count" "$MOCK_FIX_LOG" "$test_dir/run/queried"
    unset MOCK_GPU_DATA MOCK_GPU_RECHECK_DATA MOCK_PROCESSES MOCK_SLEEP_FAIL MOCK_PROCESS_QUERY_FAIL
    NIPW_FIX_SCRIPT="$test_dir/fix-ok"
    export NIPW_FIX_SCRIPT
}
probe() { bash "$repo_dir/scripts/nvidia-idle-watchdog.sh"; }
assert_fixes() {
    local expected="$1" actual=0
    if [[ -f "$MOCK_FIX_LOG" ]]; then
        actual="$(wc -l < "$MOCK_FIX_LOG" | tr -d ' ')"
    fi
    [[ "$actual" == "$expected" ]] || { echo "Expected $expected fixes, got $actual" >&2; exit 1; }
}

reset_case strict
MOCK_GPU_DATA='GPU-1, P8, 15, 0'; export MOCK_GPU_DATA
probe; probe; assert_fixes 0

reset_case strict
MOCK_GPU_DATA='GPU-1, P8, 32, 10'; export MOCK_GPU_DATA
probe; probe; assert_fixes 0

reset_case strict
MOCK_PROCESSES=1234; export MOCK_PROCESSES
probe; probe; assert_fixes 0

reset_case strict
MOCK_PROCESS_QUERY_FAIL=1; export MOCK_PROCESS_QUERY_FAIL
if probe; then echo 'Failed process query unexpectedly succeeded' >&2; exit 1; fi
assert_fixes 0

reset_case strict
probe; probe; assert_fixes 1

reset_case loaded-idle
MOCK_PROCESSES=1234; export MOCK_PROCESSES
probe; probe; assert_fixes 1

reset_case loaded-idle
MOCK_GPU_DATA='garbage'; export MOCK_GPU_DATA
if probe; then echo 'Malformed reading unexpectedly succeeded' >&2; exit 1; fi
assert_fixes 0

reset_case strict
MOCK_GPU_DATA=$'GPU-1, P8, 32, 0\nGPU-2, P0, 300, 100'; export MOCK_GPU_DATA
if probe; then echo 'Multi-GPU reading unexpectedly succeeded' >&2; exit 1; fi
assert_fixes 0

for bad_reading in '' 'GPU-1, P8, 32' 'GPU-1, P8, 32, 0,' ', P8, 32, 0'; do
    reset_case loaded-idle
    MOCK_GPU_DATA="$bad_reading"; export MOCK_GPU_DATA
    if probe; then echo 'Invalid reading unexpectedly succeeded' >&2; exit 1; fi
    assert_fixes 0
done

# The initial reading is eligible, but a second GPU appears on the final check.
reset_case strict
printf '1\n' > "$test_dir/run/nvidia-idle-power-bad-count"
MOCK_GPU_RECHECK_DATA=$'GPU-1, P8, 32, 0\nGPU-2, P0, 300, 100'; export MOCK_GPU_RECHECK_DATA
if probe; then echo 'Invalid recheck unexpectedly succeeded' >&2; exit 1; fi
assert_fixes 0
[[ "$(< "$test_dir/run/nvidia-idle-power-bad-count")" == 0 ]]

for bad_count in 08 09 000 -1 garbage 2 2147483648 999999999999999999999999999999 $'1\ngarbage'; do
    reset_case strict
    printf '%s\n' "$bad_count" > "$test_dir/run/nvidia-idle-power-bad-count"
    probe
    assert_fixes 0
    [[ "$(< "$test_dir/run/nvidia-idle-power-bad-count")" == 1 ]]
    probe
    assert_fixes 1
done

for bad_limit in 08 2147483648 999999999999999999999999999999; do
    reset_case strict
    printf 'REQUIRED_PROBES=%s\n' "$bad_limit" >> "$NIPW_CONFIG_FILE"
    if probe; then echo 'Invalid probe limit unexpectedly succeeded' >&2; exit 1; fi
    assert_fixes 0
done

reset_case strict
NIPW_FIX_SCRIPT="$test_dir/fix-fail"; export NIPW_FIX_SCRIPT
probe
if probe; then echo 'Failed recovery unexpectedly succeeded' >&2; exit 1; fi
[[ "$(< "$test_dir/run/nvidia-idle-power-bad-count")" == 0 ]]

reset_case strict
NIPW_SUSPEND_PATH="$test_dir/suspend"; export NIPW_SUSPEND_PATH
touch "$NIPW_SUSPEND_PATH"
MOCK_SLEEP_FAIL=1; export MOCK_SLEEP_FAIL
if bash "$repo_dir/scripts/nvidia-idle-fix.sh"; then
    echo 'Failed recovery sleep unexpectedly succeeded' >&2; exit 1
fi
[[ "$(< "$NIPW_SUSPEND_PATH")" == resume ]]

echo 'All stubbed watchdog tests passed.'
bash "$repo_dir/tests/uninstall.sh"
