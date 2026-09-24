---
name: n300-profiling
description: >-
  Run JVM/Hardwood benchmarks and profiling on the personal N300 bare-metal box
  (perfasm, perfnorm, async-profiler, JIT codegen inspection), or maintain it
  (dnf/kernel updates, JDK upgrades, reboots). Use whenever the user wants to
  profile, benchmark or update "the n300" / "the profiling box" / "the bare-metal
  box", mentions perfasm/perfnorm/hsdis/async-profiler on real hardware, or asks
  to SSH in to run something. Covers access, the on-box layout, pushing local
  branches to the box's throwaway repo checkouts, and the rules for touching
  machine-wide state (clock pin, reboots) on a box other sessions share.
---

# N300 profiling box

A personal, silent, always-on Intel N300 box: 8 Gracemont E-cores (no SMT), AVX2
only, single memory channel, PL1 7 W, Fedora, Temurin 25 via SDKMan. Use it for
JIT codegen, inlining, scalar/AVX2 `perfasm`/`perfnorm` and single-core-pinned
numbers — **not** for memory-bandwidth scaling or AVX-512 (single channel makes
almost anything parallel look bandwidth-bound).

Read the matching file before acting; don't work from memory:

| Before you… | Read |
| --- | --- |
| run a profiler (`--prof perfnorm/perfasm/async/…`), inspect JIT output, or decide what bounds a benchmark | [`references/profiling.md`](references/profiling.md) |
| pick a benchmark or its flags | `~/projects/hardwood-benchmarks/README.md` and `./run-<bench>.sh --help` on the box |
| pin the clock or run `profiling-setup` | [`../benchmark.md`](../benchmark.md) |
| update packages, reboot, or change the JDK | [`../maintain.md`](../maintain.md) |
| reinstall or re-provision | [`../install.md`](../install.md), [`../provision.md`](../provision.md) |

Relative paths resolve inside the `cloud-boxes` repo this skill lives in
(`n300/claude-skill/`); the box docs are its siblings under `n300/`.

## Box state: `profiling-setup`

Installed on the box as `/usr/local/sbin/profiling-setup` (source:
`cloud-boxes/ansible/roles/bench_host/files/profiling-setup`, deployed by
`n300.yml`). Every session runs that one copy against one saved state, so run it
by name — never a copy from a repo checkout.

- `profiling-setup status` — current clock, pin, saved calibration, profiling mode.
- `sudo profiling-setup pin` — apply the box's saved calibration (1.50 GHz); no
  90 s calibration needed. Add `sudo sysctl -w kernel.perf_event_paranoid=1` for
  perfasm.
- `sudo profiling-setup guard -- <cmd>` — was the run throttled?
- `sudo profiling-setup restore` — revert what `pin`/`apply`/`calibrate --pin` set.

Changing the script means editing it in `cloud-boxes` and deploying with Ansible
from the user's Mac; this container has no Ansible. Don't hot-patch
`/usr/local/sbin` on the box.

## Access

- **Key:** `/workspace/_tmp/n300-claude` (use the absolute path — the working dir
  drifts). `chmod 600` it first. If it isn't there, ask the user; don't guess.
- **Host:** `n300_host` in `/workspace/_tmp/cloud-boxes/ansible/n300.local.yml`
  (gitignored). User `build`, port 22, passwordless sudo.
- **Host key:** a fresh container has no `known_hosts`, so the first SSH fails with
  "Host key verification failed". Pass `-o StrictHostKeyChecking=accept-new` once
  and state the ED25519 fingerprint it accepted.
- **No interactive shells.** One command per SSH call. For anything long,
  `nohup … > ~/scratch/<log> 2>&1 < /dev/null &` on the box and poll the log.
- **Poll on a log marker** (`grep -q DONE`), never `pgrep -f "<pattern>"` over SSH:
  the pattern is in the polling shell's own argv, so it always matches.

## The box is shared — gate, don't just look

Other Claude sessions use this box too, often starting a run minutes after the
last check. Any action with machine-wide effect — `profiling-setup
pin/apply/calibrate/restore`, a clock pin, `dnf upgrade`, a reboot, switching the
default JDK — must be **gated** in the same SSH command on an idle check, so it
aborts instead of printing a warning you read afterwards:

```sh
ssh … 'pgrep -x java >/dev/null && { echo BUSY; ps -eo pid,etime,args | grep [j]ava | cut -c1-200; exit 1; }; <action>'
```

Also look at `who` and recent mtimes in `~/scratch` before a reboot. An idle check
from earlier in the conversation is stale.

- **Say in chat what you are about to set and why** before changing clock/governor
  state; the user must never reverse-engineer a clock change from a number.
- **Leave the box as you found it:** record `scaling_max_freq`, governor and
  `no_turbo` first, `restore` when done, and say what state you left.
- **Found a pin you didn't set?** Report it and ask — it may be a run in progress.
- **Busy when you want to restore?** Leave the pin and tell the user; a stale pin
  is a smaller harm than a corrupted run.
- `sudo sysctl -w kernel.perf_event_paranoid=1` (plus `kernel.kptr_restrict=0`)
  needs no ceremony: it touches no clock state and resets at boot.

## On-box layout (`~` = `/home/build`)

- `~/projects/hardwood`, `~/projects/hardwood-benchmarks` — **throwaway copies**
  of local work. Push over them freely; no backups or stashes.
- `~/bench-data/` — downloaded data cache (taxi, Overture).
- `~/scratch/` — all your scratch: scripts, logs, TSVs, profiler output dirs.
  **Never create files loose in `~`.** Clean up what you created when done and
  **only ever delete your own files** — `~` and `~/scratch` hold the user's and
  other sessions' outputs.

## Getting local code onto the box

Push straight into the box checkouts (once per box:
`git -C ~/projects/<repo> config receive.denyCurrentBranch updateInstead`):

```sh
git remote add box "build@<n300_host>:projects/hardwood"      # or …/hardwood-benchmarks
GIT_SSH_COMMAND="ssh -i /workspace/_tmp/n300-claude" git push -f box <local-branch>:<box-branch>
```

Non-fast-forward is normal (the box may sit on a divergent line). `updateInstead`
refuses on a dirty tree — `git -C … reset --hard` there first. Only committed
work transfers. The benchmark harness resolves `hardwood-core` from the box
`~/.m2`, so after pushing `hardwood` run `./mvnw -q -pl core -am install
-DskipTests` there.

## Gotchas

- A new SDKMan JDK has no hsdis until it's copied in (`maintain.md`); `profiling-setup
  check` reports it.
- A reboot resets `perf_event_paranoid` to 2 and clears any pin.
- Don't run updates or builds during someone's measurement.
