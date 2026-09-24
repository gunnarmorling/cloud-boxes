# N300 Benchmark Box — End-to-End Runbook

A local, silent, always-on x86 box (MINIX NEO Z300-0dB, Intel N300, 8C/8T
Gracemont, no SMT, single memory channel, ~7 W fanless) for **JIT codegen
inspection** and **scalar/AVX2 perfasm**. AVX-512 codegen and bandwidth-bound
scaling live on the rented AX162 EPYC, not here.

Host machine for prep steps below: macOS. Commands note Linux variants where they differ.

§1–§5 are a one-time manual install. From §6 on, the box is provisioned with the
repo's Ansible setup (`ansible/`), reusing the `base` role of the cloud boxes;
§7–§9 are still manual until they get their own Ansible role.

---

## 0. Version note

Fedora 44 is current (released 2026-04-28). The download page may serve it
tagged BETA for a while — prefer the GA build, and if the filenames below 404,
copy the current ones from <https://fedoraproject.org/server/download/>.
Replace `44-1.7` with the current point release throughout.

---

## 1. Download the Server DVD ISO + verify

Fedora Server has **no Live image** — the DVD boots straight into the Anaconda
installer (no desktop). The DVD is self-contained; prefer it over the netinstall
unless you want the leaner base and have wired ethernet during install.

```bash
BASE=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/x86_64/iso
curl -LO $BASE/Fedora-Server-dvd-x86_64-44-1.7.iso
# leaner alternative (pulls packages over the network during install):
# curl -LO $BASE/Fedora-Server-netinst-x86_64-44-1.7.iso
curl -LO https://fedoraproject.org/fedora.gpg
curl -LO $BASE/Fedora-Server-44-1.7-x86_64-CHECKSUM

gpg --import fedora.gpg
gpg --verify-files Fedora-Server-44-1.7-x86_64-CHECKSUM   # checksum file is authentic

# verify ONLY the image you downloaded — the CHECKSUM file lists every Server
# image, so a plain `shasum -c` tries (and fails) to open the ones you don't have
grep 'Fedora-Server-dvd-x86_64-44-1.7.iso' Fedora-Server-44-1.7-x86_64-CHECKSUM \
  | shasum -a 256 -c                                      # Linux: sha256sum -c
```

Expect a single `Fedora-Server-dvd-x86_64-44-1.7.iso: OK`. (Feeding the whole
CHECKSUM to `shasum -c` instead also works, but prints harmless "No such file"
errors for the other images and PGP-armor "improperly formatted" warnings —
the `grep` form avoids both.)

The `--verify-files` step is the one to not skip — it proves the checksum itself
wasn't tampered with, not just that the ISO matches some number.

---

## 2. Write to USB stick (macOS)

Raw write to the whole device. **Destroys the stick. Triple-check the node.**

```bash
diskutil list                          # find the stick, e.g. /dev/disk4
diskutil unmountDisk /dev/disk4
sudo dd if=Fedora-Server-dvd-x86_64-44-1.7.iso of=/dev/rdisk4 bs=4m   # rdisk = raw = fast
diskutil eject /dev/disk4
```

`dd` on macOS is silent; press **Ctrl-T** for a progress line.

Linux variant:
```bash
lsblk
sudo dd if=Fedora-Server-dvd-x86_64-44-1.7.iso of=/dev/sdX bs=4M \
        status=progress oflag=direct conv=fsync ; sync
```

---

## 3. Boot the stick (BIOS + first boot; monitor + keyboard attached)

No BMC/IPMI on this box, so this one session needs a screen. Two goals: make the
firmware boot the USB instead of Windows, and set the persistent settings while
you're in there.

### Get into the firmware

Power on and **tap the key repeatedly the instant the logo appears**, before
Windows' bootloader grabs control:

- One-time boot menu: usually **F7**, **F11**, or **Esc** (sometimes F12).
- BIOS setup: **Del** — more reliable; start here if the boot-menu key is a guess.

The window is short; miss it and you fall through into Windows.

### Settings to set in setup

- **Boot order:** move the **USB device above "Windows Boot Manager"** (or
  temporarily disable Windows Boot Manager). Boots the stick with no timing game.
  Restore it after install.
- **Fast Boot → Disabled** — otherwise it can skip USB enumeration and jump
  straight into Windows.
- **Secure Boot:** Fedora is signed and normally boots with it on; turn it off
  only if the stick is ignored or errors.
- Pick the **UEFI** USB entry, not a legacy/CSM one, so the install matches the
  firmware mode.
- **Restore on AC Power Loss → Power On** — set it now while you're here, so the
  basement box self-recovers after an outage.
- (Optional) **UEFI PXE / network boot** if you ever want unattended re-imaging.

WoL and RTC wake are supported, so you can wake it remotely once headless.

### First boot from the stick

Save & exit. At Fedora's GRUB menu take the default — **"Install Fedora
Server"** — which drops you straight into the **Anaconda installer** (no desktop,
no "Try Fedora" step). Let it reach the Anaconda welcome screen, then do the
pre-flight checks below from the installer console *before* committing the
install.

---

## 4. Pre-flight from the installer console (no install yet)

Fedora Server has no live desktop, but Anaconda runs a full Linux underneath. At
the Anaconda welcome screen, switch to a text console with **Ctrl+Alt+F2** (the
SSD is still untouched at this point). Switch back to the installer GUI later
with **Ctrl+Alt+F6** (try F1 if F6 doesn't land).

### Back up the embedded Windows license

The OEM key is in the firmware MSDM table, not on the SSD — wiping the disk does
not lose it, but grab it anyway. Presence of the file also confirms a genuine
embedded OEM license.

```bash
ls -l /sys/firmware/acpi/tables/MSDM                        # exists? -> there is an embedded key
strings /sys/firmware/acpi/tables/MSDM | tail -1            # the 29-char key (you're root here)
# exact-offset alternative:
dd if=/sys/firmware/acpi/tables/MSDM bs=1 skip=56 count=29 2>/dev/null; echo
```

Note the key down or photograph the screen. (If you ever reinstall Windows it
auto-activates from this table; key entry not required.)

### Hardware sanity

```bash
lscpu                  # confirm N300, 8 cores, AVX2 (no AVX-512 — expected)
ip link                # confirm the 2.5GbE NIC (RTL8125) is seen
lsblk                  # confirm the NVMe target
```

Then **Ctrl+Alt+F6** back to Anaconda.

---

## 5. Install Fedora Server

Back in Anaconda (Ctrl+Alt+F6), work through the spokes:

- **Installation Destination** → select the NVMe, reclaim/delete the Windows
  partitions. Default automatic Btrfs partitioning is fine for this box.
- **Network & Hostname** → toggle the wired NIC **On**, enable "Connect
  automatically," set a hostname. Doing this here means the box is on the network
  the instant it reboots — essential for a headless install.
- **Root Account / User Creation** → create your admin user ("Make this user
  administrator"); optionally lock root.
- **Software Selection** → the "Fedora Server" default is already lean; choose
  Minimal or deselect extras if offered, for an even quieter base.
- **Begin Installation** → reboot → pull the stick. Restore the BIOS boot order
  (NVMe first) if you changed it in §3.

Fedora Server boots to `multi-user.target` with **sshd enabled out of the box**
(and Cockpit on `:9090` if you want a web UI), so there's no desktop to strip.
Drop in a dedicated SSH key from your Mac and lock down login.

### Create a dedicated key (on the Mac)

A key just for this box keeps it isolated from your other hosts and easy to
revoke.

```bash
# ed25519, dedicated file, passphrase-protected and stored in the macOS keychain
ssh-keygen -t ed25519 -f ~/.ssh/n300 -C "n300"
ssh-add --apple-use-keychain ~/.ssh/n300
```

Add a host alias so `ssh n300` just works and *only* this key is offered:

```bash
cat >> ~/.ssh/config <<'EOF'

Host n300
    HostName 192.168.1.50          # the box's IP or hostname
    User admin                     # your installer admin user; `build` after §6
    IdentityFile ~/.ssh/n300
    IdentitiesOnly yes
    UseKeychain yes
    AddKeysToAgent yes
EOF
```

### Install the key and harden (order matters)

```bash
# 1. copy the PUBLIC key to the box — this still uses your password, once
ssh-copy-id -i ~/.ssh/n300.pub admin@192.168.1.50

# 2. confirm key login works BEFORE disabling passwords
ssh n300 true && echo "key login OK"

# 3. only then, on the box, turn off password auth
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

Do step 2 before step 3 — if the key login fails and you've already disabled
passwords, you're locked out and back to a monitor. Run headless from here on,
straight to §6.

---

## 6. Provision with Ansible

Run from the repo (on the Mac). The box was installed by hand rather than from
cloud-init, so it differs from a Hetzner/AWS box in a few ways and gets its own
inventory and playbooks (the Hetzner flow is untouched):

- it has a **personal admin user** from the installer (§5), not `build`;
- it stays on **port 22** (LAN-only behind your router), not a custom port;
- §5 only disabled password auth, so the full Hetzner SSH-hardening assertion
  does not apply;
- **no Docker** — its daemon would work against the quiet, low-noise
  measurement environment the box exists for (§9).

`ansible/hosts.n300` and `ansible/group_vars/n300.yml` are committed (port 22
and local key paths hold no secrets); the box's LAN IP and admin user live in
the gitignored `ansible/n300.local.yml`.

1. **Set the box details.** Create the local vars file:

   ```bash
   cp ansible/n300.local.yml.example ansible/n300.local.yml
   ```

   and set `n300_host` to the box's LAN IP and `n300_admin_user` to your admin
   user from §5. The key paths in `ansible/group_vars/n300.yml` default to the
   dedicated `~/.ssh/n300` pair from §5.

2. **Bootstrap the `build` user** (the cloud-init equivalent — run once). This
   connects as your admin user and creates the uniform `build` user with the
   n300 key and passwordless sudo:

   ```bash
   cd ansible
   ansible-playbook -i hosts.n300 n300-bootstrap.yml -K
   ```

   The `-K` prompts for your admin user's sudo password (Fedora's default
   `wheel` rule requires one). After this, `build` has NOPASSWD sudo.

3. **Provision** as `build` — no `-K` needed, and safe to re-run:

   ```bash
   ansible-playbook -i hosts.n300 n300.yml
   ```

   This installs the same base tooling as the cloud boxes (Git, SDKMan,
   async-profiler, …) plus the bench tools (role `n300_bench`): `perf` (JMH
   perf* profilers), `kernel-tools` (cpupower + turbostat), `stress-ng`, and
   `capstone-devel` (for hsdis, §10). Install JDKs with SDKMan — there's no
   Fedora JDK on the box.

4. **Switch the `ssh n300` alias to `build`** — set `User build` in the
   `Host n300` block from §5. All following steps run as `build`.

---

## 7. Kernel / sysctl (unlock PMU, cut noise)

```bash
sudo tee /etc/sysctl.d/99-bench.conf >/dev/null <<'EOF'
kernel.perf_event_paranoid = -1   # perf reads HW events + kernel symbols
kernel.kptr_restrict       = 0
kernel.nmi_watchdog        = 0    # frees a PMU counter, less noise
kernel.numa_balancing      = 0
kernel.randomize_va_space  = 0    # stable perfasm addresses across runs (optional)
EOF
sudo sysctl --system
```

Boot params (Fedora-preferred `grubby`, then reboot):

```bash
sudo grubby --update-kernel=ALL --args="intel_pstate=passive mitigations=off"
```

- `intel_pstate=passive` → enables hard frequency pinning (§8).
- `mitigations=off` → cleaner microarch numbers on an isolated box (security
  tradeoff; drop it if you'd rather not).
- Optional core isolation for undisturbed single-thread perfasm:
  `isolcpus=6,7 nohz_full=6,7 rcu_nocbs=6,7`, then `taskset -c 6 …`.

---

## 8. Lock the clock (the critical step)

No SMT, so no sibling pinning. Goal: **same per-core freq at 1 and 8 threads**.

```bash
# turbo off
echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null \
  || echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost
sudo cpupower frequency-set -g performance
cpupower frequency-info
```

Find the sustainable all-core clock, then pin below it:

```bash
# terminal A:
stress-ng --cpu 8 --timeout 120s
# terminal B:
sudo turbostat --interval 1        # read Bzy_MHz (achieved), PkgWatt, PkgTmp
```

```bash
FREQ=2000MHz                        # example: a bit below observed all-core Bzy_MHz
sudo cpupower frequency-set -d $FREQ -u $FREQ
```

Re-run the stress+turbostat pair: confirm `Bzy_MHz` flat at the pin, `PkgTmp`
stable, no throttle. Persist:

```bash
sudo tee /etc/systemd/system/benchclock.service >/dev/null <<'EOF'
[Unit]
Description=Pin CPU for benchmarking
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo; \
  cpupower frequency-set -g performance -d 2000MHz -u 2000MHz'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable benchclock.service
```

---

## 9. Quiesce

```bash
sudo systemctl mask packagekit dnf-makecache.timer fstrim.timer \
                    plocate-updatedb.timer irqbalance
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

Don't run updates/builds during a measurement.

---

## 10. hsdis (so PrintAssembly works)

Build against your installed JDK version (Capstone backend = least painful).

```bash
git clone https://github.com/openjdk/jdk.git && cd jdk
git checkout jdk-<your-version>          # match `java -version`
bash configure --with-hsdis=capstone --enable-hsdis-bundling
make build-hsdis
sudo cp build/*/jdk/lib/hsdis-amd64.so "$(dirname $(readlink -f $(which java)))/../lib/"
```

Verify (should print disassembly, not a load warning):
```bash
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly -version 2>&1 | head -40
```

hsdis goes into that JDK's `lib/`, so repeat the copy for each SDKMan JDK you
want PrintAssembly in.

async-profiler is installed by the `base` role (§6) under
`/opt/async-profiler-<version>-linux-x64` (version: `async_profiler_version` in
`ansible/roles/base/defaults/main.yml`); point JMH at
`-prof async:libPath=/opt/async-profiler-<version>-linux-x64/lib/libasyncProfiler.so`.

---

## 11. Invocation recipes

```bash
# codegen for one method (Intel syntax)
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly \
     -XX:PrintAssemblyOptions=intel \
     -XX:CompileCommand=print,com.hardwood.SomeClass::hotMethod ...

# inlining decisions
-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining

# JMH profilers
java -jar benchmarks.jar Bench -prof perfasm:intelSyntax=true   # annotated asm
java -jar benchmarks.jar Bench -prof perfnorm                   # IPC, misses/op
java -jar benchmarks.jar Bench -prof perfc2c                    # false sharing

# reproducibility knobs
-Xms=-Xmx (equal) -XX:+AlwaysPreTouch -XX:-BackgroundCompilation   # + multiple JMH forks
```

JITWatch workflow (generate headless, analyse on the Mac):
```bash
-XX:+UnlockDiagnosticVMOptions -XX:+LogCompilation -XX:+PrintAssembly
# scp hotspot_pid*.log to the Mac, open in JITWatch
```

---

## 12. Validate it's a good instrument

```bash
# 1. PMU readable (must NOT print <not supported>)
perf stat -e cycles,instructions,cache-misses true

# 2. full chain: a JMH bench with perfasm yields annotated assembly
java -jar benchmarks.jar AnyBench -prof perfasm | head -60

# 3. clock flat under load
sudo turbostat --interval 1 &  stress-ng --cpu 8 --timeout 30s
```

All three pass → ready.

---

## Appendix A — Is a workload memory-bandwidth-bound?

Combine; the key trap is bandwidth-bound vs latency-bound (opposite fixes).

1. **Frequency test (no PMU needed).** Run at two pinned clocks (e.g. 2.0 vs
   3.0 GHz, temporarily lifting the §8 pin). Throughput scales with clock →
   compute-bound. Throughput flat → memory-bound.
2. **Measure GB/s vs ceiling.** Establish the ceiling with **STREAM Triad**
   (build from source). Then measure the workload:
   `likwid-perfctr -g MEM java …` (reports GB/s, works Intel + AMD). Intel:
   `pcm-memory`. AMD EPYC: uProf data-fabric counters. ≳80% of STREAM Triad =
   saturated.
3. **Top-down (authoritative).** `perf stat --topdown`, or `toplev.py -l3`
   (pmu-tools) → Backend ▸ Memory_Bound ▸ DRAM_Bound splits **Memory_Bandwidth**
   vs **Memory_Latency**. Answers the question directly. Cleanest on Intel; on
   EPYC use uProf/likwid groups.
4. **Scaling signature.** Sweep threads while measuring aggregate GB/s.
   Bandwidth-bound = throughput plateaus *while* GB/s flatlines at the STREAM
   ceiling. Plateau with GB/s well below peak → not bandwidth (locks / alloc /
   latency).
5. **Bandwidth vs latency tells.** Bandwidth-bound: clock-insensitive, near
   STREAM peak, TMA says Memory_Bandwidth → fix by moving fewer bytes. Latency-
   bound (pointer-chasing / random page access): far below peak, TMA says
   Memory_Latency, below the MLC loaded-latency knee → fix access patterns /
   prefetch / MLP.

> On the N300, single channel makes almost anything parallel *look*
> bandwidth-bound — good for rehearsing the method, but do the real
> characterization on the 12-channel EPYC, calibrated against a STREAM run on
> that same box.

---

## Appendix B — Division of labor

- **N300 (this box):** codegen inspection, inlining, scalar/AVX2 perfasm. Silent,
  always-on, fixed clock. Single-channel + AVX2 by design. Don't read scaling
  efficiency off it.
- **AX162 EPYC (rented, monthly):** AVX-512 codegen, memory-bandwidth-bound
  scaling, `perf c2c` at server fidelity, the real scale-out curves.
- **GCP `-metal` (hourly):** zero-commitment one-offs; Intel Sapphire Rapids
  comparison vs the AMD side.
