# Manual installation and removal

Use these steps if you want to inspect and install each file yourself. They do
not run `install.sh` or `uninstall.sh`. The [README](../README.md) explains the
headless, single-GPU scope, the manual pulse test, and how to choose the three
configuration values. Run the commands on the Linux host that controls the
NVIDIA GPU.

## Install

1. Get the repository and confirm that `nvidia-smi` lists one NVIDIA GPU.
   Check that the NVIDIA GPU is not driving a display before continuing.

   ```bash
   git clone https://github.com/RJTPP/nvidia-idle-power-watchdog.git
   cd nvidia-idle-power-watchdog
   nvidia-smi -L
   ```

2. Check the required commands and driver interface. Resolve any missing
   command or unwritable interface before continuing.

   ```bash
   for required_command in nvidia-smi flock awk logger systemctl; do
     command -v "$required_command" || printf 'Missing: %s\n' "$required_command"
   done
   if sudo test -w /proc/driver/nvidia/suspend; then
     printf 'NVIDIA suspend interface is writable\n'
   else
     printf 'NVIDIA suspend interface is not writable\n' >&2
   fi
   ```

3. Copy the scripts and systemd units to the paths used by the service, then
   reload systemd. This does not enable the timer.

   ```bash
   sudo install -d -m 0755 /usr/local/libexec/nvidia-idle-power-watchdog
   sudo install -m 0755 scripts/nvidia-idle-watchdog.sh /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-watchdog.sh
   sudo install -m 0755 scripts/nvidia-idle-fix.sh /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-fix.sh
   sudo install -m 0644 systemd/nvidia-idle-power-watchdog.service /etc/systemd/system/nvidia-idle-power-watchdog.service
   sudo install -m 0644 systemd/nvidia-idle-power-watchdog.timer /etc/systemd/system/nvidia-idle-power-watchdog.timer
   sudo systemctl daemon-reload
   ```

4. Keep any existing config. Otherwise copy the example, then edit it. Set
   `MODE`, `POWER_THRESHOLD_W`, and `REQUIRED_PROBES` from your own readings as
   described in [Install and configure](../README.md#install-and-configure).

   ```bash
   if [ ! -e /etc/default/nvidia-idle-power-watchdog ]; then
     sudo install -m 0644 config.example /etc/default/nvidia-idle-power-watchdog
   fi
   sudoedit /etc/default/nvidia-idle-power-watchdog
   ```

5. Enable the timer only after reviewing the config. Then inspect its status
   and the service journal.

   ```bash
   sudo systemctl enable --now nvidia-idle-power-watchdog.timer
   systemctl status nvidia-idle-power-watchdog.timer
   journalctl -u nvidia-idle-power-watchdog.service -b
   ```

## Remove

1. Disable the timer and let any running service check finish before removing
   its files. An inactive service is expected; if it is active, wait before
   continuing.

   ```bash
   sudo systemctl disable --now nvidia-idle-power-watchdog.timer
   systemctl status nvidia-idle-power-watchdog.service
   ```

2. Remove only the files installed above and reload systemd. `rmdir` removes
   the program directory only if it is empty.

   ```bash
   sudo rm -f /etc/systemd/system/nvidia-idle-power-watchdog.service
   sudo rm -f /etc/systemd/system/nvidia-idle-power-watchdog.timer
   sudo rm -f /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-watchdog.sh
   sudo rm -f /usr/local/libexec/nvidia-idle-power-watchdog/nvidia-idle-fix.sh
   sudo rmdir /usr/local/libexec/nvidia-idle-power-watchdog 2>/dev/null || true
   sudo systemctl daemon-reload
   ```

The config at `/etc/default/nvidia-idle-power-watchdog` remains in place so a
later reinstall keeps your settings.
