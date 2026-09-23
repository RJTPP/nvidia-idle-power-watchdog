# NVIDIA Idle Power Watchdog

A Linux/systemd workaround for a headless, single NVIDIA GPU that returns to
P8 and zero reported utilization but keeps drawing more power than its normal
idle level. A timer checks every two minutes. After a configurable number of
consecutive high readings, the watchdog briefly writes `suspend` and `resume`
to the NVIDIA driver interface.

This pulse is a community workaround, not an NVIDIA-supported fix for high
idle power or its underlying cause. NVIDIA documents
`/proc/driver/nvidia/suspend` for coordinated system power management. The
watchdog requires root, refuses recovery if `nvidia-smi` reports more than one
GPU, and could interrupt a workload.

## When this may help

On a headless Proxmox host, elevated P8 idle power has appeared after Ollama,
llama.cpp, and vLLM workloads. A [similar RTX 3090 report on the NVIDIA
Developer Forums](https://forums.developer.nvidia.com/t/high-idle-power-consumption-in-headless-server-without-monitor-connected/311064/7)
describes higher idle power after Ollama or llama.cpp use. A suspend/resume
pulse lowered it even while a model remained loaded. Related symptoms were
[reported after headless boot](https://forums.developer.nvidia.com/t/high-idle-power-consumption-in-headless-server-without-monitor-connected/311064)
and [after a driver change on an RTX 3080 Ti](https://forums.developer.nvidia.com/t/increased-idle-consumption-with-driver-570/321460).
The reports do not establish one cause or show that this watchdog helps in
every case. The strongest matching experience is with a headless RTX 3090;
other GPUs, drivers, and setups remain unverified for this project.

Measure normal P8 idle power on your own GPU and setup, then compare readings
after the workload settles. One high reading, P8, or zero reported utilization
alone is not enough. In another [headless GPU report](https://forums.developer.nvidia.com/t/575-3090-idling-at-over-100-watts/339427),
`nvidia-smi` monitoring itself changed the observed power behavior.

### Other approaches to check

- If power is high from boot, check display detection. Users reported a drop
  after connecting a monitor or HDMI emulator; one described a [fake EDID
  setup](https://forums.developer.nvidia.com/t/high-idle-power-consumption-in-headless-server-without-monitor-connected/311064).
- If it began after a driver upgrade, compare driver versions. In a [driver
  570 discussion](https://forums.developer.nvidia.com/t/increased-idle-consumption-with-driver-570/321460),
  one user reported lower idle power after reverting to 565.
- A manual [GPU reset](https://docs.nvidia.com/deploy/nvidia-smi/) is an option
  when you can stop workloads. NVIDIA requires that no applications, including
  monitoring tools, be using the GPU being reset.

These options address different situations; none is required to install the
watchdog.

## Requirements

- Linux, systemd, one NVIDIA GPU, a working NVIDIA driver and `nvidia-smi`
- Bash, `flock` (util-linux), `awk`, and `logger`
- A writable `/proc/driver/nvidia/suspend` interface
- A GPU that reaches P8 during normal idle periods

## Install

```bash
sudo ./install.sh
sudo install -m 0644 config.example /etc/default/nvidia-idle-power-watchdog
sudoedit /etc/default/nvidia-idle-power-watchdog
sudo systemctl enable --now nvidia-idle-power-watchdog.timer
```

The installer leaves the timer disabled and does not set a threshold. Keep an
existing configuration instead of replacing it with the example. Its `25` W
threshold and five probes were chosen for one RTX 3090, not as universal
settings. Measure your normal P8 idle power and set the threshold above it
before enabling the timer.

```bash
nvidia-smi --query-gpu=pstate,power.draw,utilization.gpu --format=csv,noheader,nounits
```

The watchdog uses one of two modes:

| Mode | Recovery requires | Use case |
| --- | --- | --- |
| `strict` (default) | P8, zero reported utilization, power above threshold, and no reported compute processes | Conservative automatic operation |
| `loaded-idle` | P8, zero reported utilization, and power above threshold | A loaded model may remain resident |

Both modes require consecutive matching probes and recheck immediately before
recovery. In `loaded-idle`, a request could start between the check and the
driver operation. The strict mode checks compute processes reported by
`nvidia-smi`; the watchdog is intended for headless compute hosts.

Use only a root-controlled installed configuration: the watchdog sources it as
a shell file. It needs no network access or external service.

## Observe and roll back

```bash
systemctl status nvidia-idle-power-watchdog.timer
journalctl -t nvidia-idle-power-watchdog -b
journalctl -u nvidia-idle-power-watchdog.service -b
sudo systemctl disable --now nvidia-idle-power-watchdog.timer
```

`sudo ./uninstall.sh` removes the program and units but retains the
configuration for a later reinstall.

## Limits and recovery

- The NVIDIA suspend interface affects the driver, not an individual GPU.
  This version supports exactly one GPU.
- A normal or busy reading, or a recovery attempt, resets the high-power
  counter. A transient reading cannot trigger recovery.
- If `nvidia-smi` fails or returns invalid data, recovery does not run.
- The recovery script attempts `resume` on exit if an error follows `suspend`.
  If the driver does not recover, check the service log and GPU state before
  trying again.
- The two-minute interval can be changed with a systemd timer override.

NVIDIA's [power-management documentation](https://download.nvidia.com/XFree86/Linux-x86_64/535.216.01/README/powermanagement.html)
describes the intended suspend interface and its requirements.

## Test

`bash tests/test.sh` uses stubbed GPU readings and a temporary fake suspend
interface. It never accesses a real GPU. The workaround has been used on a
Proxmox host, but this standalone port has not been tested against a live GPU
or validated for installation and recovery there.
