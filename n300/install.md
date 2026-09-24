# N300 — Installation

One-time manual install of Fedora Server on the box, from ISO download to key-only
SSH. Needs a monitor and keyboard attached for §3–§5; everything after runs
headless. Host machine for the prep steps: macOS (Linux variants noted where they
differ). Next: [provisioning](provision.md).

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
    User admin                     # your installer admin user; `build` after provisioning
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
straight to [provisioning](provision.md).
