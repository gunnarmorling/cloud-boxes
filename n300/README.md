# N300 bench box

A local, silent, always-on x86 box (MINIX NEO Z300-0dB, Intel N300, 8C/8T
Gracemont, no SMT, single memory channel, ~7 W fanless) for **JIT codegen
inspection** and **scalar/AVX2 perfasm**. AVX-512 codegen and bandwidth-bound
scaling live on the rented AX162 EPYC, not here.

| File | Covers | When |
| --- | --- | --- |
| [install.md](install.md) | ISO, BIOS, Fedora install, SSH key — manual, at the console | Once, or to rebuild the box |
| [provision.md](provision.md) | Ansible (`build` user, tooling, `profiling-setup`), hsdis | After install; after each Fedora release upgrade |
| [maintain.md](maintain.md) | dnf/kernel/reboot, JDK + hsdis, async-profiler, firmware, release upgrades | Routinely, between measurement series |
| [benchmark.md](benchmark.md) | `profiling-setup` commands, the calibrated clock pin | Every benchmark session |

[`claude-skill/`](claude-skill/SKILL.md) is a Claude Code skill for working on the
box (see the repo [README](../README.md#using-the-local-n300-bench-box)).

## Division of labor

- **N300 (this box):** codegen inspection, inlining, scalar/AVX2 perfasm. Silent,
  always-on, fixed clock. Single-channel + AVX2 by design. Don't read scaling
  efficiency off it.
- **AX162 EPYC (rented, monthly):** AVX-512 codegen, memory-bandwidth-bound
  scaling, `perf c2c` at server fidelity, the real scale-out curves.
- **GCP `-metal` (hourly):** zero-commitment one-offs; Intel Sapphire Rapids
  comparison vs the AMD side.
