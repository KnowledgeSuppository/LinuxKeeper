<div align="center">
  <img src="assets/lKBanner.svg" width="600"/>

  <p>
    <img src="https://img.shields.io/badge/build-passing-2ab32a?style=flat-square"/>
    <img src="https://img.shields.io/badge/version-v3.0.0-2ab32a?style=flat-square"/>
    <img src="https://img.shields.io/badge/license-MIT-2ab32a?style=flat-square"/>
    <img src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange?style=flat-square&logo=ubuntu&logoColor=white"/>
    <img src="https://img.shields.io/badge/Debian-12+-red?style=flat-square&logo=debian&logoColor=white"/>
  </p>

  <p><em>iTechniqs — "From code, to Core"</em></p>
</div>

---

> ⚠️ **Disclaimer — Use at your own risk.**
> LinuxKeeper modifies system configuration, installs packages, and makes hardware-level changes. While every effort has been made to ensure safety, iTechniqs takes no responsibility for data loss, system instability, or any damage resulting from the use of this script or `diag.sh`.
> **Always have a Timeshift or full system backup before running.**

---

**LinuxKeeper** is a toolkit for setting up and maintaining **Ubuntu** and **Debian** systems. Automate installs, optimize performance, and monitor your system in a simplified, secure environment.

It ships two tools:
- **`setup.sh`** — interactive setup & maintenance (16 modules)
- **`diag.sh`** — hardware diagnostics, drive stress testing & refurb reporting

---

## Quick Start

```bash
git clone https://github.com/KnowledgeSuppository/LinuxKeeper.git
cd LinuxKeeper
bash setup.sh
```

Or run setup directly:
```bash
curl -fsSL https://raw.githubusercontent.com/KnowledgeSuppository/LinuxKeeper/main/setup.sh | bash
```

Run diagnostics:
```bash
bash diag.sh
```

> **Note:** Run as your normal user — both scripts call `sudo` internally where needed. Do NOT run as root.

---

## setup.sh — What it does

An interactive TUI menu (powered by `whiptail`) with 16 modules you can run individually or all at once.

```
 ┌──────────────────────────────────────────────────────────────────┐
 │   iTechniqs Linux Setup v3.0.0 — Main Menu                      │
 │                                                                  │
 │    0  Boot Sequence      — health check + drivers + essentials   │
 │    1  System Essentials  — curl, git, sensors, Terminator        │
 │    2  System Tweaks      — swappiness, I/O scheduler…            │
 │    3  Package Infra      — Flatpak + Flathub + AppImage          │
 │    4  Dotfiles & Shell   — Starship, aliases, git config         │
 │    5  SSH & GitHub       — keygen, ssh-agent setup               │
 │    6  Developer Tools    — SDKMAN, JDK, Android, Docker…         │
 │    7  Creative & Eng     — GIMP, Inkscape, KiCad, Arduino        │
 │    8  Network & Pentest  — Wireshark, Aircrack, GParted          │
 │    9  Agent System       — ~/.qwen scaffold + git clone          │
 │   10  Drivers & Hardware — GPU, firmware, microcode              │
 │   11  Health Daemon      — weekly cron + health reports          │
 │   12  Media & System     — VLC, Kodi, Stremio, Timeshift         │
 │   13  Security Monitoring— fail2ban, rkhunter, UFW alerts        │
 │   14  Run All Modules    — full setup (fresh install)            │
 │   15  Run Health Check Now — manual health scan                  │
 └──────────────────────────────────────────────────────────────────┘
```

---

## Boot Sequence (v3.0)

On first run — or any run where errors are detected in the log — LinuxKeeper automatically runs the boot sequence before the menu appears:

1. **inxi** installed silently if missing
2. **Baseline health check** — logs all issues before anything is installed
3. **Drivers & Hardware** — gets hardware working correctly first
4. **System Essentials** — builds software on top of known-good hardware

Can always be forced manually via **menu option 0**.

---

## Modules

### 0 — Boot Sequence
Automated pre-menu sequence. Runs automatically on first launch or after logged errors. Always available via menu for a forced re-run.

### 1 — System Essentials
`curl` `wget` `git` `build-essential` `htop` `btop` `neofetch` `tree` `ncdu`
`lm-sensors` `smartmontools` `fio` `badblocks` `nvme-cli` `stress-ng` `hdparm`
`p7zip` `firacode fonts` `Terminator` `fwupd` `pciutils`

> Includes all tools required by `diag.sh` — install Module 1 before running diagnostics.

### 2 — System Tweaks
- `vm.swappiness=10` — reduces unnecessary swapping
- `fs.inotify.max_user_watches=524288` — required for Android Studio / IntelliJ
- I/O scheduler per device: SSD → `mq-deadline`, HDD → `bfq`, NVMe → `none`
- Systemd journal capped at 500MB
- Noisy crash reporter services disabled

### 3 — Package Infrastructure
- **Flatpak** + Flathub remote
- **GNOME Software** with Flatpak plugin
- **AppImageLauncher** — auto-integrates `.AppImage` files into app menu

### 4 — Dotfiles & Shell
- **Starship** prompt (official installer)
- **AdwaitaMono Nerd Font** v3.4.0
- **Terminator** config (dark Tokyo Night theme, AdwaitaMono 12)
- `.bashrc` with aliases for git, gradle, KMP, Docker, ADB, agent system
- `.gitconfig` with sensible defaults

### 5 — SSH & GitHub
- Ed25519 key generation
- `ssh-agent` auto-start on login
- Displays public key for GitHub, tests connection

### 6 — Developer Tools
Version-aware checklist — shows installed version for each tool. Already-installed tools default to OFF; tick to upgrade. Upgrade confirmation dialog runs before any upgrades execute.

| Tool | Method |
|---|---|
| SDKMAN | Official curl installer |
| OpenJDK 17 / 21 | via SDKMAN |
| Kotlin compiler | via SDKMAN |
| Gradle | via SDKMAN |
| Android SDK (command-line tools) | Official zip |
| JetBrains Toolbox | Official .tar.gz — **never snap** |
| Docker Engine + Compose | Official Docker repo |
| Python 3 + pip + venv + pipx | apt |
| Node.js LTS | NodeSource |
| Gemini CLI | npm |
| Qwen CLI | pip |
| DBeaver CE | Official .deb repo |
| Postman | Flatpak |
| PostgreSQL client | apt |
| Google Chrome | Official .deb + auto-update repo |

### 7 — Creative & Engineering Tools
Version-aware checklist — detects apt, snap, and Flatpak installs.

| Tool | Method |
|---|---|
| GIMP | apt |
| Inkscape | Official PPA |
| FFmpeg | apt |
| KiCad 9 | Official PPA |
| Arduino IDE | AppImage (avoids snap USB/serial bugs) |
| Frog OCR | Flatpak |
| Conky | apt + config (see `/conky`) — skipped on headless systems |
| gufw (firewall GUI) | apt |

### 8 — Network & Pentest Tools
- **Wireshark** — user added to `wireshark` group
- **Aircrack-ng** — skipped automatically in VMs (needs real Wi-Fi adapter)
- **GParted** — partition editor
- **nmap**
- **USBGuard** — USB device policy (optional)

### 9 — Agent System Scaffold
Scaffolds `~/.qwen/` directory structure and clones your config repo:
```
~/.qwen/
  execution/      startup_context.py, session_log.py
  templates/
    models/       SaCompany.kt, Product.kt, AppUser.kt, RestaurantProfile.kt
  docs/
  config/
```
Set `QWEN_REPO_URL` at the top of `setup.sh` before running on a new machine.

### 10 — Drivers & Hardware
- HWE kernel stack
- NVIDIA driver (auto-detect + version selection)
- AMD GPU firmware
- Intel media VA drivers
- CPU microcode (Intel/AMD auto-detect)
- fwupd firmware update check
- VM detection → installs guest tools instead (VMware / VirtualBox / KVM)

### 11 — Health Daemon
Installs `/usr/local/bin/itechniqs-health` + weekly cron (Monday 03:00).

**Checks:**
- SMART disk health + reallocated sector count
- I/O scheduler correctness per device type
- Memory usage + swappiness drift
- CPU temperature via `lm-sensors`
- `inxi -Fxxxz` full system snapshot
- Kernel errors + failed systemd services
- Auth failures (brute force detection)
- NVIDIA driver status + fwupd firmware updates
- Pending security updates
- Flatpak update status
- Inotify watch count (Android Studio requirement)
- Pending security alerts (from Module 13)

Reports saved to `/var/log/itechniqs-reports/` — keeps last 12.

```bash
# Run manually anytime
sudo itechniqs-health

# View latest report
cat $(ls -t /var/log/itechniqs-reports/health_*.txt | head -1) | less
```

### 12 — Media & System Tools
- **ubuntu-restricted-extras** — codecs, MS fonts (EULA auto-answered)
- **VLC** — apt
- **Kodi** — official PPA (skipped on headless systems)
- **Stremio** — AppImage (skipped on headless systems)
- **Timeshift** — RSYNC snapshots, interactive drive picker, auto-configured schedule
- **GNOME Tweaks** — only offered if GNOME desktop is detected
- **Nala** — prettier apt frontend
- **inxi** — system info tool (feeds health reports)

### 13 — Security Monitoring

| Tool | What it does |
|---|---|
| **fail2ban** | Bans IPs after 3 failed SSH attempts (1-day ban), or 2 in 24h (7-day ban) |
| **rkhunter** | Weekly rootkit scan — alerts on any system binary changes |
| **UFW logging** | Real-time watcher — alerts on blocks, port scan patterns, sustained attacks |

All tools funnel alerts to:
- `/var/log/itechniqs-alerts.log` — persistent log
- `notify-send` desktop popup — real-time (skipped on headless systems)
- Weekly health report — summary

```bash
# Watch alerts live
tail -f /var/log/itechniqs-alerts.log
```

---

## diag.sh — Hardware Diagnostics

A separate tool for drive stress testing, benchmarking, and generating refurb reports. Run it on any machine — no setup required beyond Module 1.

```bash
bash diag.sh
```

```
 ┌──────────────────────────────────────────────────────────────────┐
 │   iTechniqs LinuxKeeper — Hardware Diagnostics v1.0.0           │
 │                                                                  │
 │    1  💾 Drives   — SMART, bad sectors, benchmark, NVMe         │
 │    2  🖥 System   — hardware info, CPU/RAM stress test           │
 │    3  📋 Reports  — view, export, manage test reports            │
 └──────────────────────────────────────────────────────────────────┘
```

### Drive Tests

| Test | Tool | Safe Mounted? | Drive Types |
|---|---|---|---|
| SMART Health Check | smartctl | ✔ Yes | HDD, SSD, NVMe |
| Bad Sector Scan (read) | badblocks | ✔ Yes | HDD, SSD |
| Bad Sector Scan (write) | badblocks | ✖ No | HDD, SSD |
| fio Benchmark (read) | fio | ✔ Yes | All |
| fio Benchmark (write) | fio | ✖ No | All |
| NVMe Health & Self-Test | nvme-cli | ✔ Yes | NVMe only |

> ⚠️ **Destructive tests will never run on mounted drives.** The script checks mount state and hard-aborts with an explanation before any write operation.

### System Tests
- **System Information** — full hardware profile via inxi, lscpu, lsblk, lspci
- **CPU & Memory Stress** — stress-ng with selectable duration (1 min → 4 hours), pre/post temperature capture

### Reports
Every test produces a timestamped report in `/var/log/linuxkeeper-diag/` — formatted for refurb documentation. Reports can be viewed, exported to `~/Desktop`, or bulk-deleted from the Reports menu.

---

## Install Policy

Priority order — the script never deviates from this:

```
apt / PPA  →  AppImage  →  Flatpak  →  snap (last resort)
```

> ⚠️ **Firefox and JetBrains IDEs are NEVER installed via snap.**
> Firefox snap has sandbox issues. JetBrains IDEs via snap break SDK paths.
> JetBrains tools are always installed via **JetBrains Toolbox** (official .tar.gz).

---

## Compatibility

| | Supported |
|---|---|
| Ubuntu 22.04 LTS | ✔ |
| Ubuntu 24.04 LTS | ✔ |
| Debian 12 | ✔ |
| Headless / SSH-only | ✔ (display modules auto-skipped) |
| Arch / Fedora / other | ✖ (apt/Debian only) |

Hardware-aware — detects and adapts for:
- VM environments (skips GPU drivers, installs guest tools)
- Headless / SSH-only servers (skips Conky, GNOME Tweaks, desktop notifications)
- Laptops (battery support)
- NVIDIA / AMD / Intel GPU (correct driver per vendor)
- SSD / HDD / NVMe (correct I/O scheduler, preload only on HDD)

---

## Conky

The `/conky` directory contains a pre-configured [SeaMod](https://github.com/JPvRiel/conky-seamod) theme. Skipped automatically on headless systems.

**Install:**
```bash
mkdir -p ~/.conky/seamod
cp conky/seamod_rings.lua ~/.conky/seamod/seamod_rings.lua
cp conky/conkyrc.lua ~/.conky/seamod/conkyrc.lua
conky -c ~/.conky/seamod/conkyrc.lua &
```

**Restart after editing:**
```bash
killall conky && sleep 1 && conky -c ~/.conky/seamod/conkyrc.lua &
```

> ⚠️ Conky config contains hardware-specific sensor paths (`hwmon` indices).
> Run the following on a new machine to find your indices:
> ```bash
> for h in /sys/class/hwmon/hwmon?; do echo "$h = $(cat "$h/name")"; done
> ```

---

## After First Run

```bash
# 1. Reload shell aliases
source ~/.bashrc

# 2. Log out and back in (docker / wireshark / dialout groups)

# 3. Take a clean system snapshot
sudo timeshift --create --comments "Post LinuxKeeper setup - clean baseline"

# 4. Install IDEs via JetBrains Toolbox
jetbrains-toolbox

# 5. Run a health check
sudo itechniqs-health

# 6. Run diagnostics on any drives you want to test
bash diag.sh
```

---

## Logs

| Log | Contents |
|---|---|
| `/var/log/itechniqs-setup.log` | Full setup history — appended every run |
| `/var/log/itechniqs-setup.last` | Boot sequence sentinel — timestamp + status |
| `/var/log/itechniqs-health.log` | Weekly cron output |
| `/var/log/itechniqs-reports/` | Health reports (last 12 kept) |
| `/var/log/itechniqs-alerts.log` | Real-time security alerts |
| `/var/log/linuxkeeper-diag/` | Drive & system diagnostic reports |

---

## License

MIT — use freely, modify as needed.

---

<div align="center">
  <img src="assets/lkLogoWhite.png" width="60"/>
  <br/>
  <em>iTechniqs — "From code, to Core"</em>
</div>
