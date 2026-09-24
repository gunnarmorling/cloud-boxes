# N300 — Maintenance

Keeping the provisioned box up to date: packages and kernel, JDKs, async-profiler,
firmware, Fedora release upgrades.

Updates change the measurement environment: a new kernel, `perf` or JDK can move
benchmark numbers. Update between measurement series, never during one, and
re-run the baseline side of any A/B afterwards instead of reusing old logs.

**Check the box is idle first.** Another session may be mid-run, and a reboot or
a JDK switch under it corrupts the measurement. Gate on it rather than reading
it:

```bash
who                                   # foreign SSH sessions?
pgrep -a java && echo BUSY            # any JVM = someone is measuring or building
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq   # below cpuinfo_max_freq = a pin is in place
```

## Fedora packages and kernel

```bash
sudo dnf upgrade --refresh
sudo dnf needs-restarting -r          # exit 1 = reboot required
sudo systemctl reboot
```

After the reboot, confirm the new kernel and that `perf` matches it (`perf` is
versioned with the kernel and misbehaves against an older running one):

```bash
uname -r; perf --version
systemctl is-system-running; systemctl --failed
```

A reboot resets all per-session state: `perf_event_paranoid` returns to 2, any
clock pin and turbo setting return to the defaults (3.8 GHz ceiling, governor
`powersave`), and stopped timers restart. That also clears a stale pin left by an
unrestored session.

If a new kernel fails to boot, the previous ones stay installed; pick one in the
GRUB menu (needs a monitor, as in [install.md](install.md) §3).

## JDK (SDKMan)

Fedora's dnf does not touch the SDKMan JDKs.

```bash
sdk selfupdate
sdk list java | grep tem              # latest Temurin build of the current LTS
sdk install java <version>-tem        # answer Y to make it the default
cp ~/.sdkman/candidates/java/<old>-tem/lib/hsdis-amd64.so \
   ~/.sdkman/candidates/java/<version>-tem/lib/
sdk uninstall java <old>-tem          # optional; keep it to re-measure old baselines
```

Verify hsdis in the new JDK produces real disassembly:

```bash
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly -Xcomp \
     -XX:CompileOnly=java.lang.String::hashCode -version 2>&1 | grep -cE '^\s+0x[0-9a-f]+:'
```

A non-zero count means it works. Temurin LTS updates ship quarterly (January,
April, July, October).

## async-profiler

Bump `async_profiler_version` in `ansible/roles/base/defaults/main.yml` and re-run
`ansible-playbook -i hosts.n300 n300.yml` ([provision.md](provision.md)). The new version installs next to
the old one under `/opt`; update the `libPath` in profiler invocations.

## Firmware

```bash
sudo fwupdmgr refresh && sudo fwupdmgr get-updates
sudo fwupdmgr update
```

A BIOS update can change the power limit (PL1), which invalidates the calibrated
clock pin; re-run the calibration afterwards ([benchmark.md](benchmark.md)).

## Fedora release upgrades

Each Fedora release is supported until about a month after the release two
versions later ships, so one release can be skipped but not two. Upgrade from a
fully updated system:

```bash
sudo dnf upgrade --refresh
sudo dnf system-upgrade download --releasever=<next>
sudo dnf offline reboot
```

Re-run `ansible-playbook -i hosts.n300 n300.yml` afterwards, and re-calibrate.

## Automatic updates (optional)

```bash
sudo dnf install dnf5-plugin-automatic
sudo systemctl enable --now dnf5-automatic.timer
```

Configure `/etc/dnf/automatic.conf` to download only (`apply_updates = no`) and
never reboot, so an unattended kernel update cannot reboot the box mid-series.
`profiling-setup apply` ([benchmark.md](benchmark.md)) stops this timer for the duration of a session.
