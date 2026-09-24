# N300 — Provisioning

Brings a freshly installed box ([install.md](install.md)) to its working state with
the repo's Ansible setup, and adds hsdis. Idempotent: re-run it after a Fedora
release upgrade ([maintain.md](maintain.md)) or to deploy a changed role.

---

## 1. Ansible

Run from the repo (on the Mac). The box was installed by hand rather than from
cloud-init, so it differs from a Hetzner/AWS box in a few ways and gets its own
inventory and playbooks (the Hetzner flow is untouched):

- it has a **personal admin user** from the installer ([install.md](install.md) §5), not `build`;
- it stays on **port 22** (LAN-only behind your router), not a custom port;
- [install.md](install.md) §5 only disabled password auth, so the full Hetzner SSH-hardening assertion
  does not apply;
- **no Docker** — its daemon would work against the quiet, low-noise
  measurement environment the box exists for ([benchmark.md](benchmark.md)).

`ansible/hosts.n300` and `ansible/group_vars/n300.yml` are committed (port 22
and local key paths hold no secrets); the box's LAN IP and admin user live in
the gitignored `ansible/n300.local.yml`.

1. **Set the box details.** Create the local vars file:

   ```bash
   cp ansible/n300.local.yml.example ansible/n300.local.yml
   ```

   and set `n300_host` to the box's LAN IP and `n300_admin_user` to your admin
   user from [install.md](install.md) §5. The key paths in `ansible/group_vars/n300.yml` default to the
   dedicated `~/.ssh/n300` pair from [install.md](install.md) §5.

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
   `capstone-devel` (for hsdis, §2), and `/usr/local/sbin/profiling-setup`
   (role `bench_host`, [benchmark.md](benchmark.md)). Install JDKs with SDKMan — there's no Fedora JDK on
   the box.

4. **Switch the `ssh n300` alias to `build`** — set `User build` in the
   `Host n300` block from [install.md](install.md) §5. All following steps run as `build`.

---

## 2. hsdis (so PrintAssembly works)

Build against your installed JDK version (Capstone backend = least painful).

```bash
git clone https://github.com/openjdk/jdk.git && cd jdk
git checkout jdk-<your-version>          # match `java -version`
bash configure --with-hsdis=capstone --enable-hsdis-bundling
make build-hsdis
cp build/*/jdk/lib/hsdis-amd64.so "$(dirname $(readlink -f $(which java)))/../lib/"
```

Verify — prints disassembly, not a load warning:

```bash
java -XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly -version 2>&1 | head -40
```

hsdis goes into that JDK's `lib/`, so every SDKMan JDK needs its own copy ([maintain.md](maintain.md)).
The binary is not tied to a JDK update release: the one built for 25 GA loads in
25.0.4.

async-profiler is installed by the `base` role (§1) under
`/opt/async-profiler-<version>-linux-x64` (version: `async_profiler_version` in
`ansible/roles/base/defaults/main.yml`).
