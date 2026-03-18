#!/usr/bin/env bash
# =============================================================================
#  iTechniqs Linux Setup Script  v2.1.0
#  "From code, to Core"
#  Author  : Graham Adams
#  Website : https://itechniqs.co.za
#
#  Usage   : curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/setup.sh | bash
#            OR: chmod +x setup.sh && ./setup.sh
#
#  Supported: Ubuntu 22.04 LTS, 24.04 LTS / Debian 12+
#
#  Install priority policy:
#    1. apt / PPA        — always preferred
#    2. AppImage         — when apt is outdated or has issues
#    3. Flatpak          — sandboxed apps that work better isolated
#    4. snap             — LAST RESORT only. NEVER for Firefox or JetBrains IDEs.
#
# =============================================================================

set -uo pipefail

# ─── USER CONFIG — edit before running ───────────────────────────────────────
# Your ~/.qwen git repo URL. Set this before running on a fresh machine.
QWEN_REPO_URL="https://github.com/YOUR_USERNAME/qwen-config.git"

# AppImage storage directory
APPIMAGE_DIR="$HOME/Applications"

# JetBrains Toolbox install location
TOOLBOX_DIR="$HOME/.local/share/JetBrains/Toolbox"
# ─────────────────────────────────────────────────────────────────────────────

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ─── Globals ─────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/itechniqs-setup.log"
DOTFILES_DIR="$HOME/.itechniqs/dotfiles"
HEALTH_SCRIPT="/usr/local/bin/itechniqs-health"
HEALTH_LOG="/var/log/itechniqs-health.log"
CRON_MARKER="# itechniqs-health-cron"
PKG_MGR=""
DISTRO=""
UBUNTU_CODENAME=""
UBUNTU_VERSION=""
HAS_SSD=false
HAS_HDD=false
HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL_GPU=false
IS_LAPTOP=false
IS_VM=false

# ─── Logging ─────────────────────────────────────────────────────────────────
log()  { echo -e "${DIM}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}✔${RESET}  $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}✖${RESET}  $*" | tee -a "$LOG_FILE"; }
die()  { err "$*"; exit 1; }
hdr()  { echo -e "\n${CYAN}${BOLD}── $* ──${RESET}" | tee -a "$LOG_FILE"; }

# ─── Banner ──────────────────────────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║       iTechniqs  Linux  Setup  v2.1.0                ║"
    echo "  ║           \"From code, to Core\"                       ║"
    echo "  ╠══════════════════════════════════════════════════════╣"
    echo "  ║  Install policy:                                      ║"
    echo "  ║  apt/PPA → AppImage → Flatpak → snap (last resort)   ║"
    echo "  ║  !! NEVER snap for Firefox or JetBrains IDEs !!      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${DIM}System  : $(lsb_release -ds 2>/dev/null || uname -rs)${RESET}"
    echo -e "  ${DIM}User    : $USER${RESET}"
    echo -e "  ${DIM}Log     : $LOG_FILE${RESET}"
    echo
}

# ─── Bootstrap checks ────────────────────────────────────────────────────────
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root. Dotfiles and user-level configs will target /root."
        warn "Recommended: run as your normal user (sudo will be called where needed)."
        sleep 2
    fi
}

detect_distro() {
    if ! command -v apt-get &>/dev/null; then
        die "This script supports Ubuntu/Debian only."
    fi
    PKG_MGR="apt"
    DISTRO="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null)"
    UBUNTU_VERSION="$(lsb_release -rs 2>/dev/null)"
    ok "Distro: $DISTRO ($UBUNTU_CODENAME $UBUNTU_VERSION) | Package manager: $PKG_MGR"
}

detect_hardware() {
    log "Detecting hardware…"

    # VM detection
    local virt
    virt=$(systemd-detect-virt 2>/dev/null) || virt="none"
    if [[ "$virt" != "none" ]]; then
        IS_VM=true
        warn "Virtual machine detected ($virt). Some modules will be skipped or adjusted."
    fi

    # Laptop detection
    if [[ -d /proc/acpi/battery ]] || ls /sys/class/power_supply/BAT* &>/dev/null 2>&1; then
        IS_LAPTOP=true
        ok "Laptop detected."
    fi

    # GPU detection
    if lspci 2>/dev/null | grep -qi "nvidia";                       then HAS_NVIDIA=true;    ok "GPU: NVIDIA detected."; fi
    if lspci 2>/dev/null | grep -qi "amd\|radeon";                  then HAS_AMD=true;       ok "GPU: AMD detected."; fi
    if lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*vga";  then HAS_INTEL_GPU=true; ok "GPU: Intel integrated detected."; fi

    # Disk type detection
    for bdev in /sys/block/sd? /sys/block/nvme?n?; do
        [[ -d "$bdev" ]] || continue
        local rot
        rot=$(cat "$bdev/queue/rotational" 2>/dev/null || echo "0")
        if [[ "$rot" == "1" ]]; then HAS_HDD=true; else HAS_SSD=true; fi
    done
    $HAS_SSD && ok "Storage: SSD/NVMe detected." || true
    $HAS_HDD && ok "Storage: HDD detected."      || true

    # USB serial (for Arduino) — || true prevents set -e exit on no match
    lsmod 2>/dev/null | grep -q "ch341\|cp210\|ftdi_sio\|cdc_acm" \
        && warn "USB serial device detected — Arduino IDE recommended." || true
}

ensure_log() {
    sudo touch "$LOG_FILE" 2>/dev/null || LOG_FILE="$HOME/itechniqs-setup.log"
    sudo chmod 666 "$LOG_FILE" 2>/dev/null || true
}

ensure_whiptail() {
    command -v whiptail &>/dev/null && return
    log "Installing whiptail…"
    sudo apt-get install -y -qq whiptail
}

# ─── Package helpers ─────────────────────────────────────────────────────────
apt_install() {
    sudo apt-get install -y -qq "$@" >> "$LOG_FILE" 2>&1 \
        && ok "apt: $*" \
        || warn "apt failed: $* (check $LOG_FILE)"
}

apt_update() {
    log "Updating apt package lists…"
    sudo apt-get update -qq >> "$LOG_FILE" 2>&1
}

add_ppa() {
    local ppa="$1"
    log "Adding PPA: $ppa"
    sudo add-apt-repository -y "$ppa" >> "$LOG_FILE" 2>&1 && apt_update
}

flatpak_install() {
    local app_id="$1"
    log "Flatpak: installing $app_id…"
    flatpak install -y flathub "$app_id" >> "$LOG_FILE" 2>&1 \
        && ok "Flatpak: $app_id" \
        || warn "Flatpak failed: $app_id"
}

download_appimage() {
    local name="$1" url="$2"
    local dest="$APPIMAGE_DIR/${name}.AppImage"
    mkdir -p "$APPIMAGE_DIR"
    log "Downloading AppImage: $name"
    wget -q --show-progress -O "$dest" "$url" 2>>"$LOG_FILE"
    chmod +x "$dest"
    ok "AppImage saved: $dest"
}

is_installed() { dpkg -s "$1" &>/dev/null 2>&1; }
is_flatpak()   { flatpak list --app 2>/dev/null | grep -q "$1"; }
cmd_exists()   { command -v "$1" &>/dev/null; }

# Returns true if Ubuntu version is >= the given version
ubuntu_min_version() {
    local required="$1"
    [[ "$(echo -e "$UBUNTU_VERSION\n$required" | sort -V | head -1)" == "$required" ]]
}

# Skips a tool with an explanation if it's not compatible
skip_incompatible() {
    local name="$1" reason="$2"
    warn "SKIPPED: $name — $reason"
}

# Check if running in a VM — some tools are pointless or broken in VMs
require_bare_metal() {
    local name="$1"
    if $IS_VM; then
        skip_incompatible "$name" "running in a VM — this tool requires bare metal hardware"
        return 1
    fi
    return 0
}

# =============================================================================
#  MODULE 1 — SYSTEM ESSENTIALS
# =============================================================================
install_essentials() {
    hdr "System Essentials"
    apt_update
    local pkgs=(
        # Core utilities
        curl wget git unzip zip tar xz-utils
        build-essential software-properties-common
        apt-transport-https ca-certificates gnupg lsb-release
        # System monitoring
        htop btop neofetch tree ncdu lm-sensors smartmontools
        # Network tools
        net-tools dnsutils nmap wget rsync
        # Shell quality of life
        bash-completion command-not-found
        # Compression
        p7zip-full p7zip-rar
        # Fonts (needed for IDEs)
        fonts-firacode fonts-noto
        # Terminal
        terminator
        # Misc
        fwupd xdg-utils
    )
    apt_install "${pkgs[@]}"

    # Detect sensors on first run
    sudo sensors-detect --auto >> "$LOG_FILE" 2>&1 || true

    # preload — only useful on HDD systems; wastes RAM on SSD/NVMe
    detect_hardware
    if $HAS_HDD && ! $HAS_SSD; then
        log "HDD-only system detected — installing preload (worthwhile on spinning drives)."
        apt_install preload
        ok "preload installed — will learn your most-used apps and preload them into RAM."
    elif $HAS_HDD && $HAS_SSD; then
        log "Mixed HDD+SSD system — skipping preload (your boot drive is SSD, preload not needed)."
    else
        log "SSD/NVMe system — skipping preload (apps already load in <1s, preload would just waste RAM)."
    fi

    ok "System essentials complete."
}

# =============================================================================
#  MODULE 2 — SYSTEM TWEAKS
# =============================================================================
apply_tweaks() {
    hdr "System Tweaks"

    # ── Swappiness & cache pressure (workstation-optimised)
    local SYSCTL_CONF="/etc/sysctl.d/99-itechniqs.conf"
    sudo tee "$SYSCTL_CONF" > /dev/null << 'EOF'
# iTechniqs — workstation performance tuning
vm.swappiness=10
vm.vfs_cache_pressure=50
# Increase max file watchers (required for Android Studio / IntelliJ / Gradle)
fs.inotify.max_user_watches=524288
fs.inotify.max_queued_events=32768
# Network performance
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
    sudo sysctl -p "$SYSCTL_CONF" >> "$LOG_FILE" 2>&1
    ok "sysctl: swappiness=10, inotify=524288, network buffers tuned."

    # ── Disable noise services on dev machines
    local disable_svcs=(
        apport.service       # crash reporter — spammy on dev machines
        whoopsie.service     # Ubuntu telemetry error reporting
    )
    for svc in "${disable_svcs[@]}"; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            sudo systemctl disable --now "$svc" >> "$LOG_FILE" 2>&1 \
                && ok "Disabled: $svc" || warn "Could not disable: $svc"
        fi
    done

    # ── I/O schedulers (udev rule — survives reboots)
    sudo tee /etc/udev/rules.d/60-itechniqs-scheduler.rules > /dev/null << 'EOF'
# iTechniqs — optimal I/O scheduler per device type
# SSD  → mq-deadline  (low latency, avoids rotational seek logic)
# HDD  → bfq          (budget fair queueing — best for desktop multitasking)
# NVMe → none         (NVMe has its own internal queue management)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF
    sudo udevadm control --reload-rules && sudo udevadm trigger
    ok "I/O scheduler udev rules installed."

    # ── Systemd journal cap
    sudo mkdir -p /etc/systemd/journald.conf.d/
    printf "[Journal]\nSystemMaxUse=500M\nMaxRetentionSec=3month\n" \
        | sudo tee /etc/systemd/journald.conf.d/itechniqs.conf > /dev/null
    sudo systemctl restart systemd-journald >> "$LOG_FILE" 2>&1
    ok "Journal capped at 500 MB, 3-month retention."

    # ── Disable screen blank for dev sessions (optional, desktop only)
    if cmd_exists gsettings; then
        gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
        ok "GNOME screen blank disabled."
    fi

    ok "System tweaks complete."
}

# =============================================================================
#  MODULE 3 — FLATPAK + APPIMAGE INFRASTRUCTURE
# =============================================================================
setup_package_infrastructure() {
    hdr "Package Infrastructure (Flatpak + AppImage)"

    # ── Flatpak + Flathub
    apt_install flatpak
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        >> "$LOG_FILE" 2>&1 && ok "Flathub remote added."

    # ── GNOME Software + Flatpak plugin (software centre integration)
    apt_install gnome-software gnome-software-plugin-flatpak
    ok "GNOME Software with Flatpak plugin installed."

    # ── AppImageLauncher (auto-integrates .AppImage files into desktop menu)
    # PPA is deprecated — install via .deb from GitHub, gracefully skip if unavailable
    if ! is_installed appimagelauncher; then
        log "Installing AppImageLauncher from GitHub release…"
        local AIL_URL AIL_DEB="/tmp/appimagelauncher.deb"
        AIL_URL=$(curl -sf --max-time 15 \
            https://api.github.com/repos/TheAssassin/AppImageLauncher/releases/latest \
            2>/dev/null \
            | grep "browser_download_url" \
            | grep "focal_amd64.deb" \
            | head -1 \
            | cut -d '"' -f 4 || true)
        if [[ -n "$AIL_URL" ]]; then
            wget -q --show-progress "$AIL_URL" -O "$AIL_DEB" 2>/dev/null \
                && sudo apt-get install -y "$AIL_DEB" >> "$LOG_FILE" 2>&1 \
                && ok "AppImageLauncher installed." \
                || warn "AppImageLauncher .deb install failed — AppImages still work, just won't auto-integrate."
            rm -f "$AIL_DEB"
        else
            warn "AppImageLauncher: could not reach GitHub API — skipping. AppImages still work without it."
        fi
    else
        ok "AppImageLauncher already installed."
    fi

    mkdir -p "$APPIMAGE_DIR"
    ok "AppImage directory: $APPIMAGE_DIR"
    ok "Package infrastructure complete."
}

# =============================================================================
#  MODULE 4 — DOTFILES & SHELL
# =============================================================================
setup_dotfiles() {
    hdr "Dotfiles & Shell"
    mkdir -p "$DOTFILES_DIR"

    # ── Nerd Fonts — AdwaitaMono (used by Starship + Terminator)
    install_nerd_font_adwaita

    # ── Starship prompt (replaces the manual PS1 below)
    install_starship

    # ── Main bashrc block
    local BASHRC_BLOCK="$DOTFILES_DIR/bashrc_itechniqs.sh"
    cat > "$BASHRC_BLOCK" << 'BASHRC'
# ═══════════════════════════════════════════════════════════════════
#  iTechniqs Shell Config
#  Managed by iTechniqs setup script — edit $DOTFILES_DIR/bashrc_itechniqs.sh
# ═══════════════════════════════════════════════════════════════════

# ── History ────────────────────────────────────────────────────────
export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:erasedups
export HISTTIMEFORMAT="%d/%m/%y %H:%M  "
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"

# ── Navigation ─────────────────────────────────────────────────────
alias ls='ls --color=auto'
alias ll='ls -lAh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ~='cd ~'
alias proj='cd ~/IdeaProjects'

# ── Safety nets ────────────────────────────────────────────────────
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ── System ─────────────────────────────────────────────────────────
alias update='sudo apt update && sudo apt upgrade -y && flatpak update -y'
alias ports='ss -tulnp'
alias myip='curl -s ifconfig.me && echo'
alias localip="ip route get 1 | awk '{print \$7}' | head -1"
alias health='sudo itechniqs-health'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias top='btop'

# ── Git ────────────────────────────────────────────────────────────
alias gs='git status -s'
alias gp='git pull'
alias gP='git push'
alias gc='git commit'
alias gca='git commit -a'
alias gco='git checkout'
alias gb='git branch'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'
alias gst='git stash'
alias gstp='git stash pop'

# ── Gradle / KMP ───────────────────────────────────────────────────
alias gw='./gradlew'
alias gwb='./gradlew build'
alias gwc='./gradlew clean'
alias gwcb='./gradlew clean build'
alias gwt='./gradlew test'
alias gwkb='./gradlew :composeApp:build'
alias gwkd='./gradlew :composeApp:runDebug'
alias gwas='./gradlew :composeApp:assembleDebug'

# ── Android / ADB ──────────────────────────────────────────────────
alias adb-restart='adb kill-server && adb start-server'
alias adb-devices='adb devices -l'
alias adb-log='adb logcat -c && adb logcat'
alias adb-ip='adb shell ip route | awk "{print \$9}"'

# ── Docker ─────────────────────────────────────────────────────────
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dcp='docker compose'
alias dcpu='docker compose up -d'
alias dcpd='docker compose down'
alias dcpl='docker compose logs -f'

# ── Agent system (iTechniqs) ───────────────────────────────────────
alias agent-start='python3 ~/.qwen/execution/startup_context.py'
alias agent-log='python3 ~/.qwen/execution/session_log.py'
alias qwen-dir='cd ~/.qwen'

# ── Starship prompt ────────────────────────────────────────────────
# Requires: starship installed + AdwaitaMono Nerd Font set in Terminator
if command -v starship &>/dev/null; then
    eval "$(starship init bash)"
else
    # Fallback prompt if Starship not yet installed
    export PS1='\[\033[01;36m\][iTechniqs]\[\033[00m\] \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

# ── Bash completion ────────────────────────────────────────────────
[[ -f /etc/bash_completion ]] && . /etc/bash_completion

# ── SDKMAN ─────────────────────────────────────────────────────────
export SDKMAN_DIR="$HOME/.sdkman"
# set +u required — sdkman-init.sh references unbound variables on first load
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && { set +u; source "$HOME/.sdkman/bin/sdkman-init.sh"; set -u; }

# ── Android SDK ────────────────────────────────────────────────────
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ── Local bin ──────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/Applications:$PATH"
BASHRC

    # Append source line to .bashrc if not already there
    local MARKER="# iTechniqs dotfiles v2"
    if ! grep -q "$MARKER" "$HOME/.bashrc"; then
        { echo ""; echo "$MARKER"; echo "source \"$BASHRC_BLOCK\""; } >> "$HOME/.bashrc"
        ok ".bashrc updated with iTechniqs config block."
    else
        ok ".bashrc already has iTechniqs block — refreshed dotfile content."
    fi

    # ── Git config
    setup_gitconfig

    ok "Dotfiles complete."
}

install_nerd_font_adwaita() {
    local FONT_DIR="$HOME/.local/share/fonts"
    local FONT_NAME="AdwaitaMono"
    # Check if already installed
    if fc-list 2>/dev/null | grep -qi "AdwaitaMono"; then
        ok "AdwaitaMono Nerd Font already installed."
        return
    fi
    log "Installing AdwaitaMono Nerd Font v3.4.0…"
    local FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/AdwaitaMono.zip"
    local TMP_ZIP="/tmp/AdwaitaMono.zip"
    mkdir -p "$FONT_DIR"
    wget -q --show-progress "$FONT_URL" -O "$TMP_ZIP"
    unzip -q -o "$TMP_ZIP" -d "$FONT_DIR/$FONT_NAME"
    rm -f "$TMP_ZIP"
    # Remove Windows-specific fonts if present
    find "$FONT_DIR/$FONT_NAME" -name "*Windows*" -delete 2>/dev/null || true
    fc-cache -f "$FONT_DIR" >> "$LOG_FILE" 2>&1
    ok "AdwaitaMono Nerd Font installed to $FONT_DIR/$FONT_NAME"
    ok "Font cache refreshed — set 'AdwaitaMono Nerd Font Mono' in Terminator preferences."
}

install_starship() {
    if cmd_exists starship; then
        ok "Starship already installed: $(starship --version 2>/dev/null | head -1)"
        return
    fi
    log "Installing Starship prompt…"
    # Official installer — downloads binary to /usr/local/bin
    curl -sS https://starship.rs/install.sh | sh -s -- --yes >> "$LOG_FILE" 2>&1
    ok "Starship installed: $(starship --version 2>/dev/null | head -1)"

    # Write a sensible default Starship config tuned for KMP dev
    local STARSHIP_CONF="$HOME/.config/starship.toml"
    mkdir -p "$(dirname "$STARSHIP_CONF")"
    if [[ ! -f "$STARSHIP_CONF" ]]; then
        cat > "$STARSHIP_CONF" << 'STARSHIPEOF'
# ── iTechniqs Starship Config ──────────────────────────────────────
# Requires: AdwaitaMono Nerd Font in Terminator
# Edit freely — see https://starship.rs/config/

"$schema" = 'https://starship.rs/config-schema.json'

format = """
[░▒▓](fg:#1a1b26)\
$os\
$username\
[](bg:#3b4261 fg:#1a1b26)\
$directory\
[](fg:#3b4261 bg:#16161e)\
$git_branch\
$git_status\
[](fg:#16161e bg:#1a1b26)\
$kotlin\
$java\
$docker_context\
[](fg:#1a1b26)\
$line_break\
$character"""

[os]
disabled = false
style = "bg:#1a1b26 fg:#a9b1d6"

[os.symbols]
Ubuntu = " "
Debian = " "
Linux  = " "

[username]
show_always = true
style_user   = "bg:#1a1b26 fg:#a9b1d6"
style_root   = "bg:#1a1b26 fg:#ff5555"
format       = "[ $user ]($style)"

[directory]
style            = "bg:#3b4261 fg:#c0caf5"
format           = "[ $path ]($style)"
truncation_length = 3
truncate_to_repo  = false

[git_branch]
symbol = " "
style  = "bg:#16161e fg:#7aa2f7"
format = "[ $symbol$branch ]($style)"

[git_status]
style  = "bg:#16161e fg:#e0af68"
format = "[$all_status$ahead_behind ]($style)"

[kotlin]
symbol = " "
style  = "bg:#1a1b26 fg:#7dcfff"
format = "[ $symbol$version ]($style)"

[java]
symbol = " "
style  = "bg:#1a1b26 fg:#bb9af7"
format = "[ $symbol$version ]($style)"

[docker_context]
symbol = " "
style  = "bg:#1a1b26 fg:#0db7ed"
format = "[ $symbol$context ]($style)"

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"
STARSHIPEOF
        ok "Starship config written: $STARSHIP_CONF"
        ok "Customise anytime at ~/.config/starship.toml — see https://starship.rs/config/"
    else
        warn "Starship config already exists at $STARSHIP_CONF — not overwritten."
    fi

    # Configure Terminator to use AdwaitaMono Nerd Font
    setup_terminator_config
}

setup_terminator_config() {
    local TERM_CONF="$HOME/.config/terminator/config"
    mkdir -p "$(dirname "$TERM_CONF")"
    if [[ -f "$TERM_CONF" ]]; then
        warn "Terminator config already exists at $TERM_CONF — not overwritten."
        warn "To use Starship glyphs: set font to 'AdwaitaMono Nerd Font Mono 12' in Terminator preferences."
        return
    fi
    cat > "$TERM_CONF" << 'TERMEOF'
[global_config]
  title_transmit_bg_color = "#3b4261"
  title_receive_bg_color  = "#1a1b26"
  title_inactive_bg_color = "#16161e"
[keybindings]
[layouts]
  [[default]]
    [[[window0]]]
      type = Window
      parent = ""
    [[[child1]]]
      type = Terminal
      parent = window0
[plugins]
[profiles]
  [[default]]
    background_color  = "#1a1b26"
    background_darkness = 0.92
    background_type     = transparent
    cursor_color        = "#c0caf5"
    font                = AdwaitaMono Nerd Font Mono 12
    foreground_color    = "#a9b1d6"
    show_titlebar       = False
    scrollbar_position  = hidden
    scrollback_lines    = 10000
    palette             = "#15161e:#f7768e:#9ece6a:#e0af68:#7aa2f7:#bb9af7:#7dcfff:#a9b1d6:#414868:#f7768e:#9ece6a:#e0af68:#7aa2f7:#bb9af7:#7dcfff:#c0caf5"
    use_system_font     = False
TERMEOF
    ok "Terminator configured: dark Tokyo Night theme + AdwaitaMono Nerd Font Mono 12"
    ok "Colour scheme matches Starship config — everything will feel cohesive."
}

setup_gitconfig() {
    log "Configuring git…"
    local GIT_NAME GIT_EMAIL
    GIT_NAME=$(git config --global user.name 2>/dev/null || true)
    GIT_EMAIL=$(git config --global user.email 2>/dev/null || true)

    if [[ -z "$GIT_NAME" ]]; then
        GIT_NAME=$(whiptail --inputbox "Git user name:" 8 50 "Graham Adams" \
            --title "Git Config" 3>&1 1>&2 2>&3) || GIT_NAME="Graham Adams"
        git config --global user.name "$GIT_NAME"
    fi
    if [[ -z "$GIT_EMAIL" ]]; then
        GIT_EMAIL=$(whiptail --inputbox "Git email:" 8 50 "" \
            --title "Git Config" 3>&1 1>&2 2>&3) || GIT_EMAIL=""
        [[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"
    fi

    git config --global core.editor "nano"
    git config --global pull.rebase false
    git config --global init.defaultBranch "main"
    git config --global color.ui auto
    git config --global alias.lg "log --oneline --graph --decorate --all"
    git config --global alias.st "status -s"
    git config --global core.autocrlf input
    git config --global push.default current
    ok "Git configured: $GIT_NAME <$GIT_EMAIL>"
}

# =============================================================================
#  MODULE 5 — SSH & GITHUB SETUP
# =============================================================================
setup_ssh() {
    hdr "SSH & GitHub Setup"
    local SSH_DIR="$HOME/.ssh"
    local KEY_FILE="$SSH_DIR/id_ed25519"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    if [[ -f "$KEY_FILE" ]]; then
        warn "SSH key already exists at $KEY_FILE — skipping generation."
    else
        local EMAIL
        EMAIL=$(git config --global user.email 2>/dev/null || true)
        if [[ -z "$EMAIL" ]]; then
            EMAIL=$(whiptail --inputbox "Email for SSH key:" 8 50 "" \
                --title "SSH Key" 3>&1 1>&2 2>&3) || EMAIL="graham@itechniqs.co.za"
        fi
        ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE" -N ""
        ok "SSH key generated: $KEY_FILE"
    fi

    # Start ssh-agent and add key
    eval "$(ssh-agent -s)" >> "$LOG_FILE" 2>&1
    ssh-add "$KEY_FILE" >> "$LOG_FILE" 2>&1

    # Add to .bashrc so agent starts on login
    local SSH_MARKER="# iTechniqs ssh-agent"
    if ! grep -q "$SSH_MARKER" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" << 'SSHEOF'

# iTechniqs ssh-agent
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" > /dev/null
    ssh-add ~/.ssh/id_ed25519 2>/dev/null
fi
SSHEOF
    fi

    # Show public key for GitHub
    echo ""
    echo -e "${CYAN}${BOLD}── Your public SSH key (add this to GitHub) ──${RESET}"
    cat "${KEY_FILE}.pub"
    echo ""
    echo -e "${YELLOW}Go to: https://github.com/settings/keys → New SSH key → paste above${RESET}"
    echo ""

    whiptail --msgbox \
        "Your SSH public key is shown in the terminal.\n\nAdd it to GitHub:\nhttps://github.com/settings/keys\n\nPress OK when done." \
        12 60 --title "GitHub SSH Key"

    # Test GitHub connection
    log "Testing GitHub SSH connection…"
    ssh -T git@github.com -o StrictHostKeyChecking=no >> "$LOG_FILE" 2>&1 \
        && ok "GitHub SSH connection successful." \
        || warn "GitHub SSH test inconclusive — check manually: ssh -T git@github.com"

    ok "SSH setup complete."
}

# =============================================================================
#  MODULE 6 — DEVELOPER TOOLS
# =============================================================================
install_dev_tools() {
    hdr "Developer Tools"

    local CHOICES
    CHOICES=$(whiptail --checklist \
        "Select developer tools to install:" 28 65 18 \
        "SDKMAN"         "SDKMAN — JDK/Kotlin/Gradle version manager"  ON  \
        "JDK17"          "OpenJDK 17 LTS (via SDKMAN)"                 ON  \
        "JDK21"          "OpenJDK 21 LTS (via SDKMAN)"                 OFF \
        "KOTLIN"         "Kotlin compiler (via SDKMAN)"                ON  \
        "GRADLE"         "Gradle build tool (via SDKMAN)"              ON  \
        "ANDROID_SDK"    "Android command-line tools"                  ON  \
        "TOOLBOX"        "JetBrains Toolbox (IDEs manager)"            ON  \
        "DOCKER"         "Docker Engine + Compose plugin"              ON  \
        "PYTHON"         "Python 3 + pip + venv + pipx"                ON  \
        "NODEJS"         "Node.js LTS (via NodeSource)"                ON  \
        "GEMINI_CLI"     "Gemini CLI (npm)"                            ON  \
        "QWEN_CLI"       "Qwen CLI (pip)"                              ON  \
        "DBEAVER"        "DBeaver CE (PostgreSQL GUI, .deb)"           ON  \
        "POSTMAN"        "Postman (Flatpak)"                           ON  \
        "PG_CLIENT"      "PostgreSQL client (psql)"                    ON  \
        "CHROME"         "Google Chrome (.deb, official repo)"         ON  \
        "APPIMAGE_TOOLS" "AppImage tools + aria2 downloader"           ON  \
        3>&1 1>&2 2>&3) || return

    apt_update

    [[ "$CHOICES" == *"SDKMAN"*      ]] && install_sdkman
    [[ "$CHOICES" == *"JDK17"*       ]] && sdkman_install java 17-open
    [[ "$CHOICES" == *"JDK21"*       ]] && sdkman_install java 21-open
    [[ "$CHOICES" == *"KOTLIN"*      ]] && sdkman_install kotlin
    [[ "$CHOICES" == *"GRADLE"*      ]] && sdkman_install gradle
    [[ "$CHOICES" == *"ANDROID_SDK"* ]] && install_android_sdk
    [[ "$CHOICES" == *"TOOLBOX"*     ]] && install_jetbrains_toolbox
    [[ "$CHOICES" == *"DOCKER"*      ]] && install_docker
    [[ "$CHOICES" == *"PYTHON"*      ]] && install_python
    [[ "$CHOICES" == *"NODEJS"*      ]] && install_nodejs
    [[ "$CHOICES" == *"GEMINI_CLI"*  ]] && install_gemini_cli
    [[ "$CHOICES" == *"QWEN_CLI"*    ]] && install_qwen_cli
    [[ "$CHOICES" == *"DBEAVER"*     ]] && install_dbeaver
    [[ "$CHOICES" == *"POSTMAN"*     ]] && flatpak_install "com.getpostman.Postman"
    [[ "$CHOICES" == *"PG_CLIENT"*   ]] && apt_install postgresql-client
    [[ "$CHOICES" == *"CHROME"*      ]] && install_chrome
    [[ "$CHOICES" == *"APPIMAGE_TOOLS"* ]] && apt_install aria2 libfuse2

    ok "Developer tools installation complete."
}

install_sdkman() {
    if [[ -d "$HOME/.sdkman" ]]; then
        ok "SDKMAN already installed."
        return
    fi
    log "Installing SDKMAN…"
    curl -s "https://get.sdkman.io" | bash >> "$LOG_FILE" 2>&1
    # Source for use in this session — set +u because sdkman-init.sh uses unbound vars
    export SDKMAN_DIR="$HOME/.sdkman"
    set +u
    [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh" || true
    set -u
    ok "SDKMAN installed."
}

sdkman_install() {
    local tool="$1" version="${2:-}"
    # Ensure SDKMAN is sourced — set +u because sdkman-init.sh uses unbound vars
    export SDKMAN_DIR="$HOME/.sdkman"
    set +u
    if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
    else
        set -u
        warn "SDKMAN not available — install SDKMAN first, then run: sdk install $tool $version"
        return
    fi
    set -u
    log "SDKMAN: installing $tool $version…"
    sdk install "$tool" "$version" </dev/null >> "$LOG_FILE" 2>&1 \
        && ok "SDKMAN: $tool $version installed." \
        || warn "SDKMAN: $tool install failed — check $LOG_FILE"
}

install_android_sdk() {
    log "Installing Android command-line tools…"
    local ANDROID_HOME="$HOME/Android/Sdk"
    local CMDTOOLS_DIR="$ANDROID_HOME/cmdline-tools/latest"
    local CMDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

    if [[ -d "$CMDTOOLS_DIR" ]]; then
        ok "Android command-line tools already installed."
        return
    fi

    mkdir -p "$CMDTOOLS_DIR"
    local TMP_ZIP="/tmp/android-cmdtools.zip"
    wget -q --show-progress "$CMDTOOLS_URL" -O "$TMP_ZIP"
    unzip -q "$TMP_ZIP" -d /tmp/android-cmdtools-unpack
    cp -r /tmp/android-cmdtools-unpack/cmdline-tools/. "$CMDTOOLS_DIR/"
    rm -rf /tmp/android-cmdtools-unpack "$TMP_ZIP"

    export ANDROID_HOME="$ANDROID_HOME"
    export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

    yes | sdkmanager --licenses >> "$LOG_FILE" 2>&1 || true
    sdkmanager "platform-tools" "build-tools;35.0.0" "platforms;android-35" >> "$LOG_FILE" 2>&1

    ok "Android SDK installed at $ANDROID_HOME"
}

install_jetbrains_toolbox() {
    # !! NEVER use snap for JetBrains IDEs !!
    # Official .tar.gz installer — no sandbox, correct SDK paths, user-managed updates
    log "Installing JetBrains Toolbox (official .tar.gz)…"

    if [[ -f "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ]]; then
        ok "JetBrains Toolbox already installed."
        return
    fi

    local TMP_DIR="/tmp/jetbrains-toolbox"
    mkdir -p "$TMP_DIR"

    # Fetch latest download URL from JetBrains data API
    local TOOLBOX_URL
    TOOLBOX_URL=$(curl -s "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
        | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['TBA'][0]['downloads']['linux']['link'])" \
        2>/dev/null) || TOOLBOX_URL=""

    if [[ -z "$TOOLBOX_URL" ]]; then
        warn "Could not auto-detect Toolbox URL. Download manually from: https://www.jetbrains.com/toolbox-app/"
        return
    fi

    wget -q --show-progress "$TOOLBOX_URL" -O "$TMP_DIR/toolbox.tar.gz"
    tar -xzf "$TMP_DIR/toolbox.tar.gz" -C "$TMP_DIR" --strip-components=1
    mkdir -p "$HOME/.local/share/JetBrains/Toolbox/bin"
    mv "$TMP_DIR/jetbrains-toolbox" "$HOME/.local/share/JetBrains/Toolbox/bin/"
    chmod +x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
    rm -rf "$TMP_DIR"

    ok "JetBrains Toolbox installed at ~/.local/share/JetBrains/Toolbox/bin/"
    ok "Run 'jetbrains-toolbox' to install IntelliJ IDEA and Android Studio."
}

install_docker() {
    if cmd_exists docker; then
        ok "Docker already installed."
        return
    fi
    log "Installing Docker Engine…"

    # Remove legacy packages
    sudo apt-get remove -y docker docker-engine docker.io containerd runc >> "$LOG_FILE" 2>&1 || true

    # Add Docker's official GPG key and repo
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt_update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    ok "Docker installed. Log out and back in to use Docker without sudo."
}

install_python() {
    log "Installing Python 3 + pip + venv + pipx…"
    apt_install python3 python3-pip python3-venv python3-dev
    python3 -m pip install --user pipx >> "$LOG_FILE" 2>&1
    python3 -m pipx ensurepath >> "$LOG_FILE" 2>&1
    ok "Python $(python3 --version) + pip + venv + pipx installed."
}

install_nodejs() {
    if cmd_exists node; then
        ok "Node.js already installed: $(node --version)"
        return
    fi
    log "Installing Node.js LTS via NodeSource…"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - >> "$LOG_FILE" 2>&1
    apt_install nodejs
    ok "Node.js $(node --version) installed."
}

install_gemini_cli() {
    log "Installing Gemini CLI…"
    if ! cmd_exists node; then
        warn "Node.js not found — install Node.js first, then run: npm install -g @google/gemini-cli"
        return
    fi
    npm install -g @google/gemini-cli >> "$LOG_FILE" 2>&1 \
        && ok "Gemini CLI installed." \
        || warn "Gemini CLI install failed."
}

install_qwen_cli() {
    log "Installing Qwen CLI (pip)…"
    if ! cmd_exists pip3; then
        warn "pip3 not found — install Python first."
        return
    fi
    pip3 install --user qwen-agent >> "$LOG_FILE" 2>&1 \
        && ok "Qwen CLI installed." \
        || warn "Qwen CLI install failed — check PyPI package name."
}

install_dbeaver() {
    if is_installed dbeaver-ce; then
        ok "DBeaver CE already installed."
        return
    fi
    log "Installing DBeaver CE (official .deb repo)…"
    # Add DBeaver repo (apt/PPA priority — official .deb, no snap, no flatpak)
    curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/dbeaver.gpg
    echo "deb [signed-by=/etc/apt/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver-ce /" \
        | sudo tee /etc/apt/sources.list.d/dbeaver.list > /dev/null
    apt_update
    apt_install dbeaver-ce
    ok "DBeaver CE installed."
}

install_chrome() {
    if is_installed google-chrome-stable; then
        ok "Google Chrome already installed."
        return
    fi
    log "Installing Google Chrome (official .deb + auto-update repo)…"
    # !! NEVER install Firefox via snap — this is Chrome, using official Google repo !!
    local TMP_DEB="/tmp/google-chrome.deb"
    wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O "$TMP_DEB"
    sudo apt-get install -y "$TMP_DEB" >> "$LOG_FILE" 2>&1
    rm -f "$TMP_DEB"
    ok "Google Chrome installed with auto-update repo."
}

# =============================================================================
#  MODULE 7 — CREATIVE & ENGINEERING TOOLS
# =============================================================================
install_creative_tools() {
    hdr "Creative & Engineering Tools"

    local CHOICES
    CHOICES=$(whiptail --checklist \
        "Select creative/engineering tools:" 24 65 12 \
        "GIMP"       "GIMP (apt — image editor)"                  ON  \
        "INKSCAPE"   "Inkscape (apt PPA — vector graphics)"       ON  \
        "FFMPEG"     "FFmpeg (apt — video/audio processing)"      ON  \
        "KICAD"      "KiCad (apt PPA — PCB/electronics design)"   ON  \
        "ARDUINO"    "Arduino IDE (AppImage — avoids snap bugs)"  ON  \
        "FROG"       "Frog OCR (Flatpak — text from images)"      ON  \
        "CONKY"      "Conky (apt — desktop system monitor)"       ON  \
        "GUFW"       "gufw (apt — firewall GUI)"                  ON  \
        3>&1 1>&2 2>&3) || return

    [[ "$CHOICES" == *"GIMP"*     ]] && apt_install gimp gimp-plugin-registry
    [[ "$CHOICES" == *"INKSCAPE"* ]] && install_inkscape
    [[ "$CHOICES" == *"FFMPEG"*   ]] && apt_install ffmpeg
    [[ "$CHOICES" == *"KICAD"*    ]] && install_kicad
    [[ "$CHOICES" == *"ARDUINO"*  ]] && install_arduino_appimage
    [[ "$CHOICES" == *"FROG"*     ]] && flatpak_install "com.github.tenderowl.frog"
    [[ "$CHOICES" == *"CONKY"*    ]] && install_conky
    [[ "$CHOICES" == *"GUFW"*     ]] && apt_install gufw

    ok "Creative & engineering tools complete."
}

install_inkscape() {
    log "Installing Inkscape via PPA…"
    # Official Inkscape PPA — more current than Ubuntu repos
    add_ppa "ppa:inkscape.dev/stable"
    apt_install inkscape
    ok "Inkscape installed."
}

install_kicad() {
    log "Installing KiCad 9 via official PPA…"
    add_ppa "ppa:kicad/kicad-9-releases"
    apt_install kicad kicad-footprints kicad-symbols kicad-templates
    ok "KiCad 9 installed."
}

install_arduino_appimage() {
    # !! AppImage preferred — snap version has USB/serial port permission bugs !!
    log "Installing Arduino IDE (AppImage)…"
    local ARDUINO_URL="https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.4_Linux_64bit.AppImage"
    download_appimage "Arduino-IDE" "$ARDUINO_URL"

    # Add user to dialout group (required for serial port / USB access)
    sudo usermod -aG dialout "$USER"
    ok "Arduino IDE AppImage saved to $APPIMAGE_DIR/Arduino-IDE.AppImage"
    ok "User added to dialout group (USB serial access). Log out and back in."
}

install_conky() {
    log "Installing Conky + default config…"
    apt_install conky-all
    local CONKY_CONF="$HOME/.config/conky/conky.conf"
    mkdir -p "$(dirname "$CONKY_CONF")"
    if [[ ! -f "$CONKY_CONF" ]]; then
        cat > "$CONKY_CONF" << 'CONKYEOF'
conky.config = {
    alignment = 'top_right',
    background = false,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = 'white',
    default_outline_color = 'white',
    default_shade_color = 'white',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = false,
    use_xft = true,
    font = 'FiraCode:size=10',
    gap_x = 20,
    gap_y = 40,
    minimum_height = 5,
    minimum_width = 260,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_stderr = false,
    extra_newline = false,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_argb_visual = true,
    own_window_argb_value = 180,
    own_window_colour = '000000',
    stippled_borders = 0,
    update_interval = 2.0,
    uppercase = false,
    use_spacer = 'none',
    show_graph_scale = false,
    show_graph_range = false,
}

conky.text = [[
${color cyan}iTechniqs System Monitor${color}
${hr 2}
${color white}Host   :${color} $nodename
${color white}Distro :${color} $distribution $kernel
${hr 1}
${color cyan}CPU${color}
${color white}Usage  :${color} ${cpu cpu0}% ${cpubar cpu0 8,200}
${color white}Temp   :${color} ${hwmon 0 temp 1}°C
${color white}Load   :${color} ${loadavg 1} ${loadavg 5} ${loadavg 15}
${hr 1}
${color cyan}Memory${color}
${color white}RAM    :${color} $mem / $memmax ${membar 8,200}
${color white}Swap   :${color} $swap / $swapmax
${hr 1}
${color cyan}Disk${color}
${color white}/      :${color} ${fs_used /} / ${fs_size /} ${fs_bar 8,200 /}
${hr 1}
${color cyan}Network${color}
${color white}IP     :${color} ${addr eth0}
${color white}Up     :${color} ${upspeed eth0}/s  ${color white}Down:${color} ${downspeed eth0}/s
${hr 1}
${color cyan}Top Processes${color}
${color white}${top name 1}${alignr}${top cpu 1}%
${color white}${top name 2}${alignr}${top cpu 2}%
${color white}${top name 3}${alignr}${top cpu 3}%
]]
CONKYEOF
        ok "Default Conky config written to $CONKY_CONF"
    else
        warn "Conky config already exists — not overwritten."
    fi
}

# =============================================================================
#  MODULE 8 — SECURITY & NETWORK TOOLS
# =============================================================================
install_security_tools() {
    hdr "Security & Network Tools"

    # Aircrack-ng requires a real Wi-Fi adapter — useless in a VM
    local aircrack_label="Aircrack-ng (apt — Wi-Fi security)"
    $IS_VM && aircrack_label="Aircrack-ng — SKIPPED IN VM (needs real Wi-Fi adapter)"

    local CHOICES
    CHOICES=$(whiptail --checklist \
        "Select security/network tools:" 16 65 6 \
        "WIRESHARK"   "Wireshark (apt — network analyser)"         ON  \
        "AIRCRACK"    "$aircrack_label"                            ON  \
        "GPARTED"     "GParted (apt — partition editor)"           ON  \
        "NMAP"        "nmap + zenmap (apt)"                        ON  \
        "USBGUARD"    "USBGuard (apt — USB device policy)"         OFF \
        3>&1 1>&2 2>&3) || return

    [[ "$CHOICES" == *"WIRESHARK"* ]] && install_wireshark
    if [[ "$CHOICES" == *"AIRCRACK"* ]]; then
        if $IS_VM; then
            skip_incompatible "Aircrack-ng" "requires a physical Wi-Fi adapter — not available in a VM"
        else
            apt_install aircrack-ng
        fi
    fi
    [[ "$CHOICES" == *"GPARTED"*   ]] && apt_install gparted
    [[ "$CHOICES" == *"NMAP"*      ]] && apt_install nmap zenmap-kbx 2>/dev/null || apt_install nmap
    [[ "$CHOICES" == *"USBGUARD"*  ]] && apt_install usbguard

    ok "Security & network tools complete."
}

install_wireshark() {
    log "Installing Wireshark…"
    # Pre-answer the 'allow non-superusers to capture?' debconf question
    echo "wireshark-common wireshark-common/install-setuid boolean true" \
        | sudo debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt_install wireshark
    sudo usermod -aG wireshark "$USER"
    ok "Wireshark installed. User added to wireshark group. Log out and back in."
}

# =============================================================================
#  MODULE 9 — AGENT SYSTEM SCAFFOLD
# =============================================================================
setup_agent_system() {
    hdr "Agent System Scaffold (~/.qwen)"

    # ── Create directory structure
    local dirs=(
        "$HOME/.qwen"
        "$HOME/.qwen/execution"
        "$HOME/.qwen/templates"
        "$HOME/.qwen/templates/models"
        "$HOME/.qwen/docs"
        "$HOME/.qwen/config"
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$d"
        ok "Created: $d"
    done

    # ── Create ~/IdeaProjects
    mkdir -p "$HOME/IdeaProjects"
    ok "Created: ~/IdeaProjects"

    # ── Create ~/Applications (AppImage home)
    mkdir -p "$APPIMAGE_DIR"
    ok "Created: $APPIMAGE_DIR"

    # ── Git clone qwen config repo
    if [[ "$QWEN_REPO_URL" == "https://github.com/YOUR_USERNAME/qwen-config.git" ]]; then
        warn "QWEN_REPO_URL not set. Edit the USER CONFIG section at the top of this script."
        warn "Scaffold directories created but config files not cloned."
    else
        if [[ -z "$(ls -A "$HOME/.qwen")" ]]; then
            log "Cloning qwen config from $QWEN_REPO_URL…"
            git clone "$QWEN_REPO_URL" /tmp/qwen-config-clone >> "$LOG_FILE" 2>&1
            cp -r /tmp/qwen-config-clone/. "$HOME/.qwen/"
            rm -rf /tmp/qwen-config-clone
            ok "Qwen config cloned into ~/.qwen/"
        else
            warn "~/.qwen already has contents — skipping clone to avoid overwrite."
            warn "To re-clone: rm -rf ~/.qwen && run this module again."
        fi
    fi

    # ── Create placeholder config files if they don't exist
    local placeholders=(
        "$HOME/.qwen/IDENTITY.md"
        "$HOME/.qwen/USER.md"
        "$HOME/.qwen/KNOWLEDGE.md"
        "$HOME/.qwen/SOUL.md"
        "$HOME/.qwen/TOOLS.md"
        "$HOME/.qwen/AGENTS.md"
    )
    for f in "${placeholders[@]}"; do
        if [[ ! -f "$f" ]]; then
            local fname
            fname=$(basename "$f" .md)
            printf "# %s\n# iTechniqs Agent Config\n# Populate from your backup or qwen config repo.\n" \
                "$fname" > "$f"
            ok "Placeholder created: $f"
        fi
    done

    ok "Agent system scaffold complete."
}

# =============================================================================
#  MODULE 10 — DRIVERS & HARDWARE
# =============================================================================
install_drivers() {
    hdr "Drivers & Hardware"

    if $IS_VM; then
        warn "Virtual machine detected — GPU driver installation skipped."
        warn "VM guest tools (open-vm-tools / virtualbox-guest-utils) handle display in a VM."
        local VM_TYPE
        VM_TYPE=$(systemd-detect-virt 2>/dev/null || echo "unknown")
        case "$VM_TYPE" in
            vmware)     apt_install open-vm-tools open-vm-tools-desktop ;;
            oracle)     apt_install virtualbox-guest-utils virtualbox-guest-x11 ;;
            kvm|qemu)   apt_install spice-vdagent qemu-guest-agent ;;
            *)          warn "Unknown VM type '$VM_TYPE' — install guest tools manually." ;;
        esac
        return
    fi

    # ── HWE kernel stack (better hardware support on LTS)
    local HWE_VER
    HWE_VER=$(lsb_release -rs)
    apt_install "linux-generic-hwe-${HWE_VER}" 2>/dev/null \
        || warn "HWE meta-package not found for $HWE_VER — may already be on HWE kernel."

    # ── GPU driver — use pre-detected flags from detect_hardware()
    if $HAS_NVIDIA; then
        install_nvidia_driver
    elif $HAS_AMD; then
        log "AMD GPU — AMDGPU is built into the kernel. Installing firmware extras…"
        apt_install firmware-amd-graphics 2>/dev/null || apt_install linux-firmware
        ok "AMD GPU firmware updated."
    elif $HAS_INTEL_GPU; then
        log "Intel GPU — installing Intel media VA drivers…"
        apt_install intel-media-va-driver vainfo i965-va-driver-shaders 2>/dev/null || true
        ok "Intel GPU media drivers installed."
    else
        warn "No discrete GPU detected — skipping GPU driver step."
    fi

    # ── General firmware + microcode
    apt_install linux-firmware
    if grep -qi "intel" /proc/cpuinfo; then
        apt_install intel-microcode
        ok "Intel CPU microcode installed."
    elif grep -qi "amd" /proc/cpuinfo; then
        apt_install amd64-microcode
        ok "AMD CPU microcode installed."
    fi

    # ── fwupd firmware updates
    if cmd_exists fwupdmgr; then
        log "Checking UEFI/firmware updates via fwupd…"
        fwupdmgr refresh 2>/dev/null || true
        fwupdmgr get-updates 2>/dev/null | tee -a "$LOG_FILE" || true
    fi

    ok "Drivers & hardware complete."
}

install_nvidia_driver() {
    log "NVIDIA GPU detected."
    local DRIVER_CHOICE
    DRIVER_CHOICE=$(whiptail --menu "Select NVIDIA driver:" 12 55 3 \
        "auto" "ubuntu-drivers autoinstall (recommended)" \
        "550"  "nvidia-driver-550 (stable)"               \
        "570"  "nvidia-driver-570 (latest)"               \
        3>&1 1>&2 2>&3) || return

    case "$DRIVER_CHOICE" in
        auto) sudo ubuntu-drivers autoinstall ;;
        *)    apt_install "nvidia-driver-${DRIVER_CHOICE}" ;;
    esac
    ok "NVIDIA driver installed. Reboot required."
}

# =============================================================================
#  MODULE 11 — HEALTH DAEMON
# =============================================================================
install_health_daemon() {
    hdr "Health Daemon"
    log "Writing health script to $HEALTH_SCRIPT…"

    sudo tee "$HEALTH_SCRIPT" > /dev/null << 'HEALTH_EOF'
#!/usr/bin/env bash
# =============================================================================
#  iTechniqs System Health Monitor  v2.0
#  Weekly cron: every Monday 03:00
#  Manual run : sudo itechniqs-health
# =============================================================================

set -euo pipefail

REPORT_DIR="/var/log/itechniqs-reports"
DATE=$(date '+%Y-%m-%d_%H-%M')
REPORT="$REPORT_DIR/health_$DATE.txt"
ALERT_LOG="$REPORT_DIR/alerts_$DATE.txt"
ISSUES=0

mkdir -p "$REPORT_DIR"

log()   { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$REPORT"; }
issue() { echo "  ⚠ ISSUE: $*" | tee -a "$REPORT" "$ALERT_LOG"; ISSUES=$((ISSUES+1)); }
ok()    { echo "  ✔ OK: $*"    | tee -a "$REPORT"; }
hdr()   { echo "" | tee -a "$REPORT"; echo "══ $* ══" | tee -a "$REPORT"; }

{
echo "╔══════════════════════════════════════════════════╗"
echo "║   iTechniqs System Health Report  v2.0           ║"
printf "║   %-49s║\n" "$(date '+%A, %d %B %Y  %H:%M')"
echo "╚══════════════════════════════════════════════════╝"
} | tee "$REPORT"

# ── 1. SMART / DISK HEALTH ────────────────────────────────────────
hdr "DISK HEALTH (SMART)"
for disk in /dev/sd? /dev/nvme?n?; do
    [[ -b "$disk" ]] || continue
    if command -v smartctl &>/dev/null; then
        STATUS=$(smartctl -H "$disk" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}' || echo "")
        if [[ "$STATUS" == "PASSED" ]]; then
            ok "SMART $disk: PASSED"
        elif [[ -n "$STATUS" ]]; then
            issue "SMART $disk: $STATUS — CHECK IMMEDIATELY"
        else
            log "  SMART $disk: unreadable (may need root)"
        fi
        # Reallocated sectors check
        REALLOCATED=$(smartctl -A "$disk" 2>/dev/null | awk '/Reallocated_Sector/{print $10}' || echo "0")
        (( REALLOCATED > 0 )) && issue "$disk: $REALLOCATED reallocated sectors — drive may be failing"
    fi
done

hdr "DISK USAGE"
df -h --output=source,pcent,target | grep -v "tmpfs\|udev\|overlay\|snap" | tail -n +2 | \
while read -r src pct mnt; do
    PCT="${pct//%/}"
    [[ "$PCT" =~ ^[0-9]+$ ]] || continue
    if   (( PCT >= 90 )); then issue "CRITICAL $mnt: ${PCT}% full ($src)"
    elif (( PCT >= 75 )); then issue "WARNING  $mnt: ${PCT}% full ($src)"
    else ok "$mnt: ${PCT}% used"
    fi
done

# ── 2. I/O SCHEDULER ──────────────────────────────────────────────
hdr "I/O SCHEDULER"
for bdev in /sys/block/sd? /sys/block/nvme?n?; do
    [[ -d "$bdev" ]] || continue
    SCHED=$(cat "$bdev/queue/scheduler" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
    ROT=$(cat "$bdev/queue/rotational" 2>/dev/null || echo "0")
    DNAME=$(basename "$bdev")
    if [[ "$ROT" == "0" ]]; then
        [[ "$SCHED" == "mq-deadline" || "$SCHED" == "none" ]] \
            && ok "$DNAME (SSD): scheduler=$SCHED" \
            || issue "$DNAME (SSD): scheduler='$SCHED', expected mq-deadline or none"
    else
        [[ "$SCHED" == "bfq" ]] \
            && ok "$DNAME (HDD): scheduler=$SCHED" \
            || issue "$DNAME (HDD): scheduler='$SCHED', expected bfq"
    fi
done

# ── 3. MEMORY ─────────────────────────────────────────────────────
hdr "MEMORY"
SWAP_VAL=$(cat /proc/sys/vm/swappiness | tr -d '[:space:]')
SWAP_VAL=${SWAP_VAL:-0}
(( SWAP_VAL > 15 )) \
    && issue "Swappiness=$SWAP_VAL (target ≤10). Fix: echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-itechniqs.conf" \
    || ok "Swappiness: $SWAP_VAL"

MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}' | tr -d '[:space:]')
MEM_AVAIL=$(free -m | awk '/Mem:/{print $7}' | tr -d '[:space:]')
MEM_AVAIL=${MEM_AVAIL:-0}
MEM_TOTAL=${MEM_TOTAL:-1}
MEM_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
if   (( MEM_PCT >= 90 )); then issue "Memory CRITICAL: ${MEM_PCT}% used (${MEM_AVAIL}MB free)"
elif (( MEM_PCT >= 75 )); then issue "Memory HIGH: ${MEM_PCT}% used (${MEM_AVAIL}MB free)"
else ok "Memory: ${MEM_PCT}% used (${MEM_AVAIL}MB of ${MEM_TOTAL}MB free)"
fi

# ── 4. CPU & TEMPERATURE ──────────────────────────────────────────
hdr "CPU & TEMPERATURE"
if command -v sensors &>/dev/null; then
    while IFS= read -r line; do
        TEMP=$(echo "$line" | grep -oP '\+\d+' | head -1 | tr -d '+' || echo "0")
        [[ "$TEMP" =~ ^[0-9]+$ ]] || continue
        if   (( TEMP >= 90 )); then issue "CRITICAL TEMP: $line"
        elif (( TEMP >= 75 )); then issue "HIGH TEMP: $line"
        else ok "Temp: $line"
        fi
    done < <(sensors 2>/dev/null | grep -E "(Core|temp|Package|Tdie)")
else
    log "  lm-sensors not installed — run: sudo apt install lm-sensors && sudo sensors-detect"
fi

# ── 5. SYSTEM LOGS ────────────────────────────────────────────────
hdr "SYSTEM LOGS (last 7 days)"
SINCE="$(date -d '7 days ago' '+%Y-%m-%d %H:%M:%S')"

log "Kernel errors:"
journalctl -k --since "$SINCE" -p err -q --no-pager 2>/dev/null | tail -15 | tee -a "$REPORT" || true

log "Failed systemd services:"
FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d '[:space:]')
FAILED=${FAILED:-0}
if (( FAILED > 0 )); then
    systemctl --failed --no-legend | while read -r line; do issue "Failed service: $line"; done
else
    ok "No failed services."
fi

log "Auth failures:"
AUTH_FAIL=$(journalctl --since "$SINCE" -q --no-pager 2>/dev/null \
    | grep -c "authentication failure\|Failed password" 2>/dev/null || echo 0)
AUTH_FAIL=$(echo "$AUTH_FAIL" | tr -d '[:space:]')
AUTH_FAIL=${AUTH_FAIL:-0}
(( AUTH_FAIL > 20 )) \
    && issue "High auth failure count: $AUTH_FAIL in 7 days — check for brute force" \
    || ok "Auth failures: $AUTH_FAIL in 7 days"

# ── 6. DRIVER STATUS ──────────────────────────────────────────────
hdr "DRIVER STATUS"
if lspci | grep -qi "nvidia"; then
    if command -v nvidia-smi &>/dev/null; then
        DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "unknown")
        ok "NVIDIA driver v$DRIVER_VER — $GPU_NAME"
        RECOMMENDED=$(ubuntu-drivers devices 2>/dev/null | grep "recommended" | awk '{print $3}' || echo "")
        [[ -n "$RECOMMENDED" ]] && log "  Recommended driver: $RECOMMENDED"
    else
        issue "NVIDIA GPU detected but nvidia-smi missing — driver not installed"
    fi
fi

if command -v fwupdmgr &>/dev/null; then
    fwupdmgr refresh 2>/dev/null || true
    FW_UPDATES=$(fwupdmgr get-updates 2>/dev/null | grep -c "Available" || echo 0)
    FW_UPDATES=$(echo "$FW_UPDATES" | tr -d '[:space:]')
    FW_UPDATES=${FW_UPDATES:-0}
    (( FW_UPDATES > 0 )) \
        && issue "$FW_UPDATES firmware update(s) available — run: sudo fwupdmgr update" \
        || ok "Firmware: up to date"
fi

# ── 7. SECURITY UPDATES ───────────────────────────────────────────
hdr "SECURITY UPDATES"
apt-get update -qq 2>/dev/null
SECURITY_PKGS=$(apt list --upgradable 2>/dev/null | grep -c "security" 2>/dev/null || echo 0)
SECURITY_PKGS=$(echo "$SECURITY_PKGS" | tr -d '[:space:]')
SECURITY_PKGS=${SECURITY_PKGS:-0}
ALL_PKGS=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l | tr -d '[:space:]')
ALL_PKGS=${ALL_PKGS:-0}
(( SECURITY_PKGS > 0 )) \
    && issue "$SECURITY_PKGS security update(s) pending — run: sudo apt upgrade" \
    || ok "No pending security updates."
log "  Total upgradable packages: $ALL_PKGS"

# ── 8. FLATPAK UPDATES ────────────────────────────────────────────
hdr "FLATPAK UPDATES"
if command -v flatpak &>/dev/null; then
    FLATPAK_UPDATES=$(flatpak remote-ls --updates 2>/dev/null | wc -l | tr -d '[:space:]')
    FLATPAK_UPDATES=${FLATPAK_UPDATES:-0}
    (( FLATPAK_UPDATES > 0 )) \
        && issue "$FLATPAK_UPDATES Flatpak update(s) pending — run: flatpak update" \
        || ok "Flatpak apps: up to date"
fi

# ── 9. KMP / IDE CONFIG ───────────────────────────────────────────
hdr "KMP / ANDROID STUDIO CONFIG"
WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null | tr -d '[:space:]')
WATCHES=${WATCHES:-0}
(( WATCHES < 524288 )) \
    && issue "Inotify watches=$WATCHES (need 524288 for Android Studio/IntelliJ)" \
    || ok "Inotify watches: $WATCHES"

# Docker group check
if groups "$USER" | grep -q docker; then
    ok "User in docker group."
else
    issue "User not in docker group — run: sudo usermod -aG docker $USER"
fi

# ── 10. SYSTEM SNAPSHOT (inxi) ────────────────────────────────────
hdr "SYSTEM SNAPSHOT"
if command -v inxi &>/dev/null; then
    log "Full system info:"
    inxi -Fxxxz --no-host 2>/dev/null | tee -a "$REPORT" || true
else
    log "  inxi not installed — install with: sudo apt install inxi"
fi

# ── 11. PENDING SECURITY ALERTS ───────────────────────────────────
hdr "SECURITY ALERTS (since last report)"
PENDING="/var/log/itechniqs-reports/pending-alerts.txt"
if [[ -f "$PENDING" && -s "$PENDING" ]]; then
    ALERT_COUNT=$(wc -l < "$PENDING")
    issue "$ALERT_COUNT security event(s) since last report:"
    cat "$PENDING" | tee -a "$REPORT"
    # Clear the staging file after including in report
    > "$PENDING"
else
    ok "No pending security alerts."
fi

# ── SUMMARY ───────────────────────────────────────────────────────
{
echo ""
echo "══════════════════════════════════════════════════"
if (( ISSUES == 0 )); then
    echo "  ✔  System healthy — no issues detected."
else
    printf "  ⚠  %d issue(s) found.\n" "$ISSUES"
    echo "  Alert summary : $ALERT_LOG"
fi
echo "  Full report   : $REPORT"
echo "  Generated     : $(date '+%d %b %Y  %H:%M')"
echo "══════════════════════════════════════════════════"
} | tee -a "$REPORT"

# Keep last 12 reports only
ls -t "$REPORT_DIR"/health_*.txt  2>/dev/null | tail -n +13 | xargs rm -f 2>/dev/null || true
ls -t "$REPORT_DIR"/alerts_*.txt  2>/dev/null | tail -n +13 | xargs rm -f 2>/dev/null || true
HEALTH_EOF

    sudo chmod +x "$HEALTH_SCRIPT"

    # Install cron job — every Monday at 03:00
    local CRON_FILE="/etc/cron.d/itechniqs-health"
    sudo tee "$CRON_FILE" > /dev/null << CRONEOF
# iTechniqs Health Monitor — runs every Monday at 03:00
# Manual run: sudo itechniqs-health
0 3 * * 1 root $HEALTH_SCRIPT >> $HEALTH_LOG 2>&1 $CRON_MARKER
CRONEOF
    sudo chmod 644 "$CRON_FILE"

    sudo touch "$HEALTH_LOG"
    sudo chmod 644 "$HEALTH_LOG"
    sudo mkdir -p /var/log/itechniqs-reports

    ok "Health daemon installed: $HEALTH_SCRIPT"
    ok "Cron job: every Monday 03:00 → $HEALTH_LOG"
    ok "Manual run: sudo itechniqs-health"
}

# =============================================================================
#  MAIN TUI MENU
# =============================================================================
# =============================================================================
#  MODULE 12 — MEDIA & SYSTEM TOOLS
# =============================================================================
install_media_system_tools() {
    hdr "Media & System Tools"

    # Build menu — flag items that won't work in a VM
    local kodi_label="Kodi (apt PPA — media centre)"
    $IS_VM && kodi_label="Kodi — NOTE: no GPU accel in VM, video may stutter"

    # gnome-tweaks only makes sense on GNOME
    local tweaks_label tweaks_default="ON"
    local DESKTOP_ENV="${XDG_CURRENT_DESKTOP:-unknown}"
    if echo "$DESKTOP_ENV" | grep -qi "gnome"; then
        tweaks_label="GNOME Tweaks (apt — fonts, extensions, theme)"
    else
        tweaks_label="GNOME Tweaks — SKIPPED: not on GNOME ($DESKTOP_ENV)"
        tweaks_default="OFF"
    fi

    local CHOICES
    CHOICES=$(whiptail --checklist \
        "Select media & system tools to install:" 26 68 12 \
        "RESTRICTED"  "ubuntu-restricted-extras (codecs, MS fonts)"  ON  \
        "VLC"         "VLC media player (apt)"                        ON  \
        "KODI"        "$kodi_label"                                   ON  \
        "STREMIO"     "Stremio (AppImage — streaming aggregator)"     ON  \
        "TIMESHIFT"   "Timeshift (apt — system snapshots, RSYNC)"     ON  \
        "TWEAKS"      "$tweaks_label"                                 "$tweaks_default" \
        "NALA"        "Nala (apt — prettier apt frontend)"            ON  \
        "INXI"        "inxi (apt — system info, feeds health report)" ON  \
        3>&1 1>&2 2>&3) || return

    apt_update

    [[ "$CHOICES" == *"RESTRICTED"* ]] && install_restricted_extras
    [[ "$CHOICES" == *"VLC"*        ]] && apt_install vlc
    [[ "$CHOICES" == *"KODI"*       ]] && install_kodi
    [[ "$CHOICES" == *"STREMIO"*    ]] && install_stremio_appimage
    [[ "$CHOICES" == *"TIMESHIFT"*  ]] && install_timeshift
    [[ "$CHOICES" == *"TWEAKS"*     ]] && install_gnome_tweaks
    [[ "$CHOICES" == *"NALA"*       ]] && apt_install nala
    [[ "$CHOICES" == *"INXI"*       ]] && apt_install inxi

    ok "Media & system tools complete."
}

install_restricted_extras() {
    log "Installing ubuntu-restricted-extras…"
    # Must pre-answer the Microsoft EULA debconf question or the install hangs
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula boolean true" \
        | sudo debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt_install ubuntu-restricted-extras
    ok "ubuntu-restricted-extras installed (codecs, MS fonts, DVD support)."
}

install_kodi() {
    log "Installing Kodi via official PPA…"
    # Official Kodi PPA — more current than Ubuntu universe repo
    add_ppa "ppa:team-xbmc/ppa"
    apt_install kodi
    $IS_VM && warn "Kodi installed but you're in a VM — hardware video decoding won't work. Expect stutter on HD content."
    ok "Kodi installed."
}

install_stremio_appimage() {
    # No apt package exists — AppImage is the official Linux distribution method
    log "Installing Stremio (AppImage)…"
    local STREMIO_URL="https://www.stremio.com/download-linux"
    # Fetch the actual AppImage URL from the download page
    local ACTUAL_URL
    ACTUAL_URL=$(curl -sL "$STREMIO_URL" 2>/dev/null \
        | grep -oP 'https://[^"]+\.AppImage' | head -1)

    if [[ -z "$ACTUAL_URL" ]]; then
        warn "Could not auto-detect Stremio AppImage URL."
        warn "Download manually from https://www.stremio.com/downloads and place in $APPIMAGE_DIR/"
        return
    fi

    download_appimage "Stremio" "$ACTUAL_URL"
    ok "Stremio AppImage saved to $APPIMAGE_DIR/Stremio.AppImage"
    ok "AppImageLauncher will integrate it into your app menu on first run."
}

install_timeshift() {
    log "Installing Timeshift…"
    # Timeshift moved to apt in Ubuntu 23.04+. For older releases use PPA.
    if ubuntu_min_version "23.04"; then
        apt_install timeshift
    else
        add_ppa "ppa:teejee2008/timeshift"
        apt_install timeshift
    fi

    # Detect filesystem type — BTRFS mode is only valid if root is BTRFS
    local ROOT_FS
    ROOT_FS=$(df -T / | awk 'NR==2{print $2}')
    log "Root filesystem: $ROOT_FS"

    if [[ "$ROOT_FS" == "btrfs" ]]; then
        log "BTRFS root detected — Timeshift can use fast BTRFS snapshot mode."
        whiptail --msgbox \
            "Your root partition is BTRFS.\n\nTimeshift can use BTRFS mode (instant, space-efficient snapshots)\ninstead of RSYNC mode.\n\nOpen Timeshift after setup and choose 'BTRFS' as the snapshot type." \
            12 60 --title "Timeshift — BTRFS available"
    fi

    # Ask which drive to store snapshots on
    configure_timeshift_rsync

    ok "Timeshift installed."
}

configure_timeshift_rsync() {
    log "Configuring Timeshift RSYNC mode…"

    # Build a list of available block devices for the user to choose from
    local DRIVE_LIST=()
    while IFS= read -r line; do
        local dev size fstype mountpoint
        dev=$(echo "$line"       | awk '{print $1}')
        size=$(echo "$line"      | awk '{print $4}')
        fstype=$(echo "$line"    | awk '{print $2}')
        mountpoint=$(echo "$line"| awk '{print $7}')
        # Skip tmpfs, loop, snap devices
        [[ "$dev" =~ ^(tmpfs|loop|udev) ]] && continue
        [[ "$dev" =~ snap ]] && continue
        DRIVE_LIST+=("$dev" "$size  $fstype  ${mountpoint:-(not mounted)}")
    done < <(lsblk -o NAME,FSTYPE,TYPE,SIZE,MOUNTPOINT -l 2>/dev/null | grep "part\|disk" | tail -n +1)

    if [[ ${#DRIVE_LIST[@]} -eq 0 ]]; then
        warn "Could not detect drives. Configure Timeshift manually."
        return
    fi

    local SELECTED_DRIVE
    SELECTED_DRIVE=$(whiptail --menu \
        "Select the drive/partition to store Timeshift snapshots:\n\nChoose a DIFFERENT drive from your system drive if possible.\nStoring on the same drive still protects against bad updates." \
        20 68 8 \
        "${DRIVE_LIST[@]}" \
        3>&1 1>&2 2>&3) || return

    log "Selected snapshot drive: $SELECTED_DRIVE"

    # Get the UUID of the selected device for the config
    local SNAP_UUID
    SNAP_UUID=$(blkid -s UUID -o value "$SELECTED_DRIVE" 2>/dev/null || echo "")

    if [[ -z "$SNAP_UUID" ]]; then
        warn "Could not get UUID for $SELECTED_DRIVE — configure Timeshift manually."
        return
    fi

    # Write Timeshift JSON config
    sudo mkdir -p /etc/timeshift
    sudo tee /etc/timeshift/timeshift.json > /dev/null << TIMESHIFTEOF
{
  "backup_device_uuid" : "$SNAP_UUID",
  "parent_device_uuid" : "",
  "do_first_run"       : "false",
  "btrfs_mode"         : "false",
  "include_btrfs_home_for_backup"  : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails"   : "true",
  "btrfs_use_qgroup"   : "true",
  "schedule_monthly"   : "false",
  "schedule_weekly"    : "true",
  "schedule_daily"     : "true",
  "schedule_hourly"    : "false",
  "schedule_boot"      : "false",
  "count_monthly"      : "2",
  "count_weekly"       : "3",
  "count_daily"        : "5",
  "count_hourly"       : "6",
  "count_boot"         : "5",
  "snapshot_size"      : "",
  "snapshot_count"     : "0",
  "date_format"        : "%Y-%m-%d %H:%M:%S",
  "exclude"            : [],
  "exclude-apps"       : []
}
TIMESHIFTEOF

    ok "Timeshift configured: RSYNC mode → $SELECTED_DRIVE (UUID: $SNAP_UUID)"
    ok "Schedule: daily (keep 5) + weekly (keep 3)"
    ok "Run 'sudo timeshift --create' to take your first snapshot now."
}

install_gnome_tweaks() {
    local DESKTOP_ENV="${XDG_CURRENT_DESKTOP:-unknown}"
    if ! echo "$DESKTOP_ENV" | grep -qi "gnome"; then
        skip_incompatible "GNOME Tweaks" "your desktop is '$DESKTOP_ENV', not GNOME — this tool would do nothing"
        return
    fi
    apt_install gnome-tweaks gnome-shell-extensions
    ok "GNOME Tweaks installed."
}

# =============================================================================
#  MODULE 13 — SECURITY MONITORING
# =============================================================================

# Global alert config
ALERT_LOG="/var/log/itechniqs-alerts.log"
ALERT_SCRIPT="/usr/local/bin/itechniqs-alert"

install_security_monitoring() {
    hdr "Security Monitoring"

    local CHOICES
    CHOICES=$(whiptail --checklist \
        "Select security monitoring tools:" 16 68 4 \
        "FAIL2BAN"  "fail2ban — ban IPs after repeated auth failures"   ON  \
        "RKHUNTER"  "rkhunter — weekly rootkit scanner"                 ON  \
        "UFW_LOG"   "UFW logging + watcher — real-time block alerts"    ON  \
        3>&1 1>&2 2>&3) || return

    # Install the central alert dispatcher first — everything else uses it
    install_alert_dispatcher

    [[ "$CHOICES" == *"UFW_LOG"*   ]] && configure_ufw_logging
    [[ "$CHOICES" == *"FAIL2BAN"*  ]] && install_fail2ban
    [[ "$CHOICES" == *"RKHUNTER"*  ]] && install_rkhunter

    ok "Security monitoring complete."
    ok "Alert log: $ALERT_LOG  (tail -f $ALERT_LOG)"
    ok "Desktop notifications: active (notify-send)"
}

install_alert_dispatcher() {
    # Central script that ALL security tools call when they want to alert you.
    # Writes to the alert log AND sends a desktop notify-send popup.
    log "Installing iTechniqs alert dispatcher…"

    sudo tee "$ALERT_SCRIPT" > /dev/null << 'ALERTEOF'
#!/usr/bin/env bash
# =============================================================================
#  iTechniqs Alert Dispatcher
#  Called by: fail2ban, rkhunter, UFW log watcher
#  Usage: itechniqs-alert "CATEGORY" "Short title" "Full message"
# =============================================================================

ALERT_LOG="/var/log/itechniqs-alerts.log"
CATEGORY="${1:-SECURITY}"
TITLE="${2:-iTechniqs Alert}"
MESSAGE="${3:-Unknown event}"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
URGENCY="normal"

# Escalate urgency for serious categories
case "$CATEGORY" in
    CRITICAL|ROOTKIT|INTRUSION) URGENCY="critical" ;;
    BAN|PORTSCAN)               URGENCY="normal"   ;;
esac

# 1. Write to alert log (always)
echo "[$TIMESTAMP] [$CATEGORY] $TITLE — $MESSAGE" | tee -a "$ALERT_LOG"

# 2. Desktop notification (if a display session is available)
# Find the active user's display and DBUS session
DISPLAY_USER=$(who | grep -v "(:0)" | awk '{print $1}' | head -1 || echo "")
[[ -z "$DISPLAY_USER" ]] && DISPLAY_USER=$(logname 2>/dev/null || echo "")

if [[ -n "$DISPLAY_USER" ]]; then
    local DBUS_ADDR
    DBUS_ADDR=$(sudo -u "$DISPLAY_USER" \
        bash -c 'ls /run/user/$(id -u)/bus 2>/dev/null | head -1' 2>/dev/null \
        || echo "")
    if [[ -n "$DBUS_ADDR" ]]; then
        sudo -u "$DISPLAY_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $DISPLAY_USER)/bus" \
            notify-send \
                --urgency="$URGENCY" \
                --app-name="iTechniqs Security" \
                --icon="security-high" \
                "[$CATEGORY] $TITLE" \
                "$MESSAGE" 2>/dev/null || true
    fi
fi

# 3. Also append to health report staging area (picked up by weekly health run)
HEALTH_STAGING="/var/log/itechniqs-reports/pending-alerts.txt"
echo "[$TIMESTAMP] [$CATEGORY] $TITLE — $MESSAGE" >> "$HEALTH_STAGING" 2>/dev/null || true
ALERTEOF

    sudo chmod +x "$ALERT_SCRIPT"
    sudo touch "$ALERT_LOG"
    sudo chmod 644 "$ALERT_LOG"
    sudo mkdir -p /var/log/itechniqs-reports
    sudo touch /var/log/itechniqs-reports/pending-alerts.txt
    ok "Alert dispatcher installed: $ALERT_SCRIPT"
}

configure_ufw_logging() {
    log "Configuring UFW logging…"
    sudo ufw logging medium 2>/dev/null || true

    # Install a systemd service that watches /var/log/ufw.log
    # and calls itechniqs-alert for anything interesting
    sudo tee /etc/systemd/system/itechniqs-ufw-watch.service > /dev/null << 'UFWEOF'
[Unit]
Description=iTechniqs UFW Log Watcher
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/itechniqs-ufw-watch
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UFWEOF

    sudo tee /usr/local/bin/itechniqs-ufw-watch > /dev/null << 'WATCHEOF'
#!/usr/bin/env bash
# Watches UFW log for BLOCK events and raises alerts for suspicious patterns
UFW_LOG="/var/log/ufw.log"
SEEN_IPS="/tmp/itechniqs-ufw-seen.tmp"
declare -A IP_COUNT

tail -Fn0 "$UFW_LOG" 2>/dev/null | while IFS= read -r line; do
    # Only care about BLOCK events
    echo "$line" | grep -q "\[UFW BLOCK\]" || continue

    SRC_IP=$(echo "$line" | grep -oP 'SRC=\K[\d.]+' || echo "")
    DST_PORT=$(echo "$line" | grep -oP 'DPT=\K\d+' || echo "?")
    PROTO=$(echo "$line" | grep -oP 'PROTO=\K\w+' || echo "?")
    [[ -z "$SRC_IP" ]] && continue

    # Count hits per IP in this session
    IP_COUNT["$SRC_IP"]=$(( ${IP_COUNT["$SRC_IP"]:-0} + 1 ))
    COUNT=${IP_COUNT["$SRC_IP"]}

    # Alert on first hit from an IP
    if (( COUNT == 1 )); then
        /usr/local/bin/itechniqs-alert "FIREWALL" \
            "Connection blocked" \
            "$SRC_IP → port $DST_PORT ($PROTO) blocked by UFW"
    fi

    # Escalate if same IP hits many ports (port scan pattern)
    if (( COUNT == 10 )); then
        /usr/local/bin/itechniqs-alert "PORTSCAN" \
            "Possible port scan" \
            "$SRC_IP has been blocked $COUNT times — possible port scan in progress"
    fi

    # Critical escalation at 50 hits
    if (( COUNT == 50 )); then
        /usr/local/bin/itechniqs-alert "CRITICAL" \
            "Sustained attack detected" \
            "$SRC_IP blocked $COUNT times — consider permanent ban: sudo ufw deny from $SRC_IP"
    fi
done
WATCHEOF

    sudo chmod +x /usr/local/bin/itechniqs-ufw-watch
    sudo systemctl daemon-reload
    sudo systemctl enable --now itechniqs-ufw-watch >> "$LOG_FILE" 2>&1
    ok "UFW log watcher installed and running."
    ok "Real-time alerts for: blocked connections, port scan patterns, sustained attacks."
}

install_fail2ban() {
    log "Installing fail2ban…"
    apt_install fail2ban libpam-runtime

    # Write iTechniqs custom jail config
    # Overrides defaults: stricter thresholds, longer bans, alerts wired in
    sudo tee /etc/fail2ban/jail.d/itechniqs.conf > /dev/null << 'F2BEOF'
# iTechniqs fail2ban config
# Extends /etc/fail2ban/jail.conf defaults

[DEFAULT]
# Ban for 1 hour on first offence
bantime  = 3600
# Watch 10 minute window
findtime = 600
# 5 failures triggers a ban
maxretry = 5
# Alert via iTechniqs dispatcher
action = %(action_)s
         itechniqs-notify

[sshd]
enabled  = true
port     = ssh
maxretry = 3
bantime  = 86400

[sshd-aggressive]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 2
bantime  = 604800
findtime = 86400
F2BEOF

    # Custom action that calls our alert dispatcher
    sudo tee /etc/fail2ban/action.d/itechniqs-notify.conf > /dev/null << 'F2BACTION'
[Definition]
actionban   = /usr/local/bin/itechniqs-alert "BAN" "IP Banned by fail2ban" "<ip> banned — <failures> failures in <name> jail (banned for <bantime>s)"
actionunban = /usr/local/bin/itechniqs-alert "UNBAN" "IP Unbanned" "<ip> unbanned from <name> jail"
F2BACTION

    sudo systemctl enable --now fail2ban >> "$LOG_FILE" 2>&1
    ok "fail2ban installed and running."
    ok "SSH: ban after 3 failures (1 day) or 2 failures in 24h (7 days)."
    ok "Check status: sudo fail2ban-client status sshd"
}

install_rkhunter() {
    log "Installing rkhunter (rootkit hunter)…"
    apt_install rkhunter

    # Update hashes database against CURRENT clean system
    # Must be run on a known-clean system — first install is the baseline
    sudo rkhunter --update >> "$LOG_FILE" 2>&1 || true
    sudo rkhunter --propupd >> "$LOG_FILE" 2>&1 || true

    # Write iTechniqs rkhunter config
    sudo tee /etc/rkhunter.conf.d/itechniqs.conf > /dev/null << 'RKHEOF'
# iTechniqs rkhunter config
# Suppress false positives common on Ubuntu
SCRIPTWHITELIST=/usr/bin/egrep
SCRIPTWHITELIST=/usr/bin/fgrep
SCRIPTWHITELIST=/usr/bin/which
ALLOWHIDDENDIR=/dev/.udev
ALLOWHIDDENDIR=/dev/.static
ALLOWHIDDENDIR=/dev/.initramfs
# Send output to syslog — picked up by our watcher below
LOGFILE=/var/log/rkhunter.log
APPEND_LOG=1
RKHEOF

    # rkhunter weekly cron — runs Sunday 02:00, alerts on findings
    sudo tee /etc/cron.d/itechniqs-rkhunter > /dev/null << 'RKHCRON'
# iTechniqs rkhunter scan — every Sunday at 02:00
0 2 * * 0 root /usr/local/bin/itechniqs-rkhunter-scan
RKHCRON

    sudo tee /usr/local/bin/itechniqs-rkhunter-scan > /dev/null << 'RKHSCAN'
#!/usr/bin/env bash
# Runs rkhunter and fires alerts if anything suspicious is found
RKHUNTER_LOG="/var/log/rkhunter.log"

rkhunter --check --skip-keypress --quiet 2>/dev/null
EXIT_CODE=$?

if (( EXIT_CODE != 0 )); then
    # Extract warnings from the log
    WARNINGS=$(grep -E "^Warning:|^\[ Warning \]" "$RKHUNTER_LOG" | tail -20 | tr '\n' ' ')
    /usr/local/bin/itechniqs-alert "ROOTKIT" \
        "rkhunter found suspicious items" \
        "$WARNINGS — full log: $RKHUNTER_LOG"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] rkhunter: clean scan." >> /var/log/itechniqs-alerts.log
fi
RKHSCAN

    sudo chmod +x /usr/local/bin/itechniqs-rkhunter-scan
    ok "rkhunter installed. Baseline fingerprint recorded."
    ok "Weekly scan: every Sunday 02:00 → alerts if anything changes."
    ok "Run manually: sudo itechniqs-rkhunter-scan"
    warn "IMPORTANT: run rkhunter baseline ONLY on a known-clean system (first install = best time)."
}

run_menu() {
    while true; do
        local CHOICE
        CHOICE=$(whiptail \
            --title "iTechniqs Linux Setup v2.1.0 — Main Menu" \
            --menu "\nSelect a module:  (arrow keys, Enter to run)\n" \
            30 72 15 \
            " 1" "System Essentials    — curl, git, sensors, Terminator…" \
            " 2" "System Tweaks        — swappiness, I/O scheduler, sysctl…" \
            " 3" "Package Infra        — Flatpak + Flathub + AppImageLauncher" \
            " 4" "Dotfiles & Shell     — Starship, AdwaitaMono, .bashrc, git…" \
            " 5" "SSH & GitHub         — keygen, ssh-agent, GitHub setup" \
            " 6" "Developer Tools      — SDKMAN, JDK, Android, Docker, Node…" \
            " 7" "Creative & Eng Tools — GIMP, Inkscape, KiCad, Arduino…" \
            " 8" "Network & Pentest    — Wireshark, Aircrack, GParted…" \
            " 9" "Agent System         — ~/.qwen scaffold + git clone" \
            "10" "Drivers & Hardware   — GPU, firmware, microcode…" \
            "11" "Health Daemon        — weekly cron + health script + inxi" \
            "12" "Media & System       — VLC, Kodi, Stremio, Timeshift, Nala…" \
            "13" "Security Monitoring  — fail2ban, rkhunter, UFW alerts" \
            "14" "Run All Modules      — full setup (recommended: fresh install)" \
            "15" "Run Health Check Now — manual health scan" \
            " Q" "Quit" \
            3>&1 1>&2 2>&3) || break

        case "${CHOICE// /}" in
            1)  install_essentials ;;
            2)  apply_tweaks ;;
            3)  setup_package_infrastructure ;;
            4)  setup_dotfiles ;;
            5)  setup_ssh ;;
            6)  install_dev_tools ;;
            7)  install_creative_tools ;;
            8)  install_security_tools ;;
            9)  setup_agent_system ;;
            10) install_drivers ;;
            11) install_health_daemon ;;
            12) install_media_system_tools ;;
            13) install_security_monitoring ;;
            14) run_all ;;
            15) run_health_now ;;
            Q|q) break ;;
        esac

        [[ "${CHOICE// /}" != "Q" && "${CHOICE// /}" != "q" ]] && \
            whiptail --msgbox "✔ Module complete.\n\nPress OK to return to the menu." \
                8 50 --title "Done"
    done
}

run_all() {
    whiptail --yesno \
        "This will run ALL modules in sequence.\n\nRecommended for a fresh machine install.\nThis will take 20-40 minutes depending on your connection.\n\nMake sure you have internet access.\n\nProceed?" \
        12 60 --title "Run All Modules" || return

    install_essentials
    apply_tweaks
    setup_package_infrastructure
    setup_dotfiles
    setup_ssh
    install_dev_tools
    install_creative_tools
    install_security_tools
    setup_agent_system
    install_drivers
    install_health_daemon
    install_media_system_tools
    install_security_monitoring

    echo ""
    ok "══════════════════════════════════════════════════"
    ok "  iTechniqs setup complete — v2.1.0"
    ok "══════════════════════════════════════════════════"
    ok "  Log        : $LOG_FILE"
    ok "  Alert log  : $ALERT_LOG"
    ok "  Health log : $HEALTH_LOG"
    ok ""
    ok "  Next steps:"
    ok "    1.  source ~/.bashrc   (load aliases + Starship)"
    ok "    2.  Log out and back in  (docker/wireshark groups)"
    ok "    3.  Set QWEN_REPO_URL at top of script, re-run module 9"
    ok "    4.  Run: jetbrains-toolbox  (install IntelliJ + Android Studio)"
    ok "    5.  Run: sudo timeshift --create  (first system snapshot)"
    ok "    6.  Open Terminator → Preferences → set font to"
    ok "        'AdwaitaMono Nerd Font Mono 12'"
    ok "══════════════════════════════════════════════════"
}

run_health_now() {
    if [[ -x "$HEALTH_SCRIPT" ]]; then
        sudo "$HEALTH_SCRIPT" && less /var/log/itechniqs-reports/health_*.txt 2>/dev/null \
            | tail -1 || true
    else
        whiptail --msgbox "Health daemon not installed yet.\nRun Module 11 first." 8 50
    fi
}

# =============================================================================
#  ENTRY POINT
# =============================================================================
main() {
    ensure_log
    show_banner
    check_not_root
    detect_distro
    detect_hardware
    ensure_whiptail
    run_menu
    echo ""
    echo -e "${CYAN}${BOLD}iTechniqs setup complete.${RESET}"
    echo -e "${DIM}Log    : $LOG_FILE${RESET}"
    echo -e "${DIM}Reload : source ~/.bashrc${RESET}"
    echo ""
}

main "$@"
