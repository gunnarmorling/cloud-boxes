# N300 — Benchmark sessions

Clock pinning, PMU access and quiet background timers are applied per session and
reverted afterwards, not configured permanently on the box. The `bench_host` role
([provision.md](provision.md)) installs the tool for this as `/usr/local/sbin/profiling-setup`; its source is
`ansible/roles/bench_host/files/profiling-setup`. Every session on the box runs
that one copy, which keeps its saved state in `/run/profiling-setup.state`
(cleared at boot).

| Command | Effect |
| --- | --- |
| `profiling-setup status` | Current values, the saved calibration, whether profiling mode is active. No root needed. |
| `profiling-setup check` | Readiness self-test: PMU counts cycles, hsdis in the active JDK, clock, temperature, cumulative thermal throttles. |
| `sudo profiling-setup pin` | Governor `performance`, `scaling_max_freq` capped at the saved calibration. |
| `sudo profiling-setup apply` | `perf_event_paranoid=1`, `kptr_restrict=0`, `nmi_watchdog=0`, governor `performance`, turbo off, THP `madvise`; stops the `dnf-makecache`, `fstrim` and `dnf5-automatic` timers that were running. `PARANOID=0` also allows unprivileged `perf -a`; `ASLR_OFF=1` disables ASLR. |
| `sudo profiling-setup calibrate [secs] [--pin] [--save]` | All-core load; measures the clock the package settles at after the PL2→PL1 boost transient and suggests a pin at 97 % of it. `--pin` applies it, `--save` writes it to `/etc/profiling-setup.conf` for `pin`. |
| `sudo profiling-setup guard -- <cmd…>` | Runs the command, then reports thermal throttles and the busy clock against the sustainable base (`SUSPECT` = power-limited). |
| `sudo profiling-setup restore` | Reverts everything `apply`, `pin` and `calibrate --pin` changed. |

For comparable throughput numbers, combine `pin` with the `perf_event_paranoid`
sysctl rather than using `apply`: `apply` turns turbo off, and the pin sits above
the base clock. Run `calibrate` only on an idle box, and restore only when no one
else is measuring ([maintain.md](maintain.md) has the idle checks).

Profiler recipes and the bottleneck-classification method are in the Claude skill's
[`references/profiling.md`](claude-skill/references/profiling.md); the benchmarks
themselves are documented in the
[hardwood-benchmarks README](https://github.com/hardwood-hq/hardwood-benchmarks#readme).

## Calibrated clock

The N300 is power-limited at a fixed PL1, so its sustainable all-core clock is a
property of the box and can be pinned directly instead of re-measured:

| | |
| --- | --- |
| Settled all-core clock | 1.57 GHz (8 cores, 10 s tail) |
| Package power | 7.2 W (PL1 7.0 W) |
| Package temperature | 51 °C, 0 thermal throttles |
| **Pin** | **1.50 GHz** (`scaling_max_freq=1500000` on every core), governor `performance` |
| Measured | 2026-09-10, idle box, `calibrate 90` |

The box keeps its own copy in `/etc/profiling-setup.conf`, which `pin` reads.
Re-calibrate with `sudo profiling-setup calibrate 90 --save` after a BIOS update
that may change PL1 ([maintain.md](maintain.md)), when the ambient temperature changes noticeably, or
before publishing an absolute figure, and update this table.

Turbo off pins the 0.80 GHz base clock — about half the sustainable clock — so
prefer `pin` over `apply`'s turbo-off for throughput
numbers. A turbo-off `apply` that was never restored leaves the box at 0.80 GHz
and every JMH number about 2× slow, with nothing in the result announcing it:
compare `scaling_max_freq` against `cpuinfo_max_freq` (3.8 GHz) before trusting an
absolute figure.
