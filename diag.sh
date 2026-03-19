#!/usr/bin/env bash
# =============================================================================
#  iTechniqs LinuxKeeper — Hardware Diagnostic Tool
#  "From code, to Core"
#  Author  : Graham Adams
#  Version : 1.0.0
#
#  Usage   : bash diag.sh
#  Purpose : System diagnostics, drive stress testing, and refurb reporting
#
#  Supported: Ubuntu 22.04 LTS, 24.04 LTS / Debian 12+
#
#  !! NEVER runs destructive tests on mounted drives !!
#  !! Always produces a timestamped report for every test !!
#
# =============================================================================

set -uo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ─── Globals ─────────────────────────────────────────────────────────────────
DIAG_VERSION="1.0.0"
LOG_DIR="/var/log/linuxkeeper-diag"
REPORT=""          # set per-test run
CURRENT_DRIVE=""   # set when user selects a drive

# Test duration profiles (seconds)
DURATION_SHORT=300    #  5 minutes — quick triage
DURATION_FULL=3600    # 60 minutes — pre-sale certification
DURATION_BURN=86400   # 24 hours  — burn-in / long-haul stress

# ─── Logging ─────────────────────────────────────────────────────────────────
log()   { echo -e "${DIM}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "$REPORT"; }
ok()    { echo -e "${GREEN}✔${RESET}  $*" | tee -a "$REPORT"; }
warn()  { echo -e "${YELLOW}⚠${RESET}  $*" | tee -a "$REPORT"; }
err()   { echo -e "${RED}✖${RESET}  $*" | tee -a "$REPORT"; }
hdr()   { echo -e "\n${CYAN}${BOLD}── $* ──${RESET}" | tee -a "$REPORT"; }
pass()  { echo -e "${GREEN}${BOLD}  ✔ PASS${RESET}  $*" | tee -a "$REPORT"; }
fail()  { echo -e "${RED}${BOLD}  ✖ FAIL${RESET}  $*" | tee -a "$REPORT"; }
info()  { echo -e "  ${DIM}$*${RESET}" | tee -a "$REPORT"; }

# ─── Whiptail theme (matches setup.sh) ───────────────────────────────────────
apply_theme() {
    local newt_patch
    newt_patch=$(dpkg-query -W -f='${Version}' libnewt0.52 2>/dev/null \
        | grep -oP '(?<=0\.52\.)\d+' | head -1)
    newt_patch="${newt_patch:-0}"
    if (( newt_patch >= 21 )); then
        export NEWT_COLORS="root=white,#1a1b26:window=white,#1a1b26:shadow=black,black:title=#2ab32a,#1a1b26:checkbox=white,#1a1b26:button=black,#2ab32a:actbutton=white,#1a1b26:compactbutton=white,#1a1b26:listbox=white,#1a1b26:actlistbox=black,#2ab32a:sellistbox=black,#2ab32a:actsellistbox=black,#2ab32a:entry=white,#1a1b26:disentry=white,#1a1b26:label=white,#1a1b26"
    else
        export NEWT_COLORS="root=white,black:window=white,black:shadow=black,black:title=green,black:checkbox=white,black:button=black,green:actbutton=white,black:compactbutton=white,black:listbox=white,black:actlistbox=black,green:sellistbox=black,green:actsellistbox=black,green:entry=white,black:disentry=white,black:label=white,black"
    fi
    rm -f "$HOME/.newtrc"
}

# ─── Banner ──────────────────────────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║     iTechniqs LinuxKeeper — Hardware Diagnostics     ║"
    echo "  ║              v${DIAG_VERSION}  \"From code, to Core\"            ║"
    echo "  ╠══════════════════════════════════════════════════════╣"
    echo "  ║  !! Destructive tests ONLY run on unmounted drives !! ║"
    echo "  ║  !! Every test produces a timestamped report        !! ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${DIM}System  : $(lsb_release -ds 2>/dev/null || uname -rs)${RESET}"
    echo -e "  ${DIM}User    : $USER${RESET}"
    echo -e "  ${DIM}Reports : $LOG_DIR${RESET}"
    echo
}

# ─── Bootstrap ───────────────────────────────────────────────────────────────
bootstrap() {
    # Must not run as root
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Running as root. Recommended: run as normal user (sudo called internally).${RESET}"
        sleep 2
    fi

    # Create report directory
    sudo mkdir -p "$LOG_DIR"
    sudo chmod 777 "$LOG_DIR"

    # Start a default report file for session logging
    REPORT="$LOG_DIR/session_$(date '+%Y%m%d_%H%M%S').log"
    touch "$REPORT"

    # Check for required tools — offer to install missing ones
    local missing=()
    command -v smartctl  &>/dev/null || missing+=(smartmontools)
    command -v fio       &>/dev/null || missing+=(fio)
    command -v badblocks &>/dev/null || missing+=(e2fsprogs)
    command -v nvme      &>/dev/null || missing+=(nvme-cli)
    command -v stress-ng &>/dev/null || missing+=(stress-ng)
    command -v hdparm    &>/dev/null || missing+=(hdparm)
    command -v lsblk     &>/dev/null || missing+=(util-linux)
    command -v inxi      &>/dev/null || missing+=(inxi)

    if (( ${#missing[@]} > 0 )); then
        whiptail --yesno \
            "The following diagnostic tools are not installed:\n\n$(printf '  • %s\n' "${missing[@]}")\n\nInstall them now? (Recommended)" \
            18 55 --title "Missing Tools" --yes-button "Install" --no-button "Skip" \
            3>&1 1>&2 2>&3
        if [[ $? -eq 0 ]]; then
            sudo apt-get update -qq
            sudo apt-get install -y "${missing[@]}"
            ok "Diagnostic tools installed."
        else
            warn "Some tests may not be available without the missing tools."
        fi
    fi
}

# =============================================================================
#  DRIVE SELECTION
#  Lists all block devices, lets user pick one, detects type and mount state
# =============================================================================

# Returns: HDD, SSD, NVMe, or UNKNOWN
detect_drive_type() {
    local dev="$1"
    local base
    base=$(basename "$dev")

    # NVMe — device name always starts with nvme
    [[ "$base" == nvme* ]] && echo "NVMe" && return

    # Check rotational flag
    local rot
    rot=$(cat "/sys/block/${base}/queue/rotational" 2>/dev/null || echo "")
    if [[ "$rot" == "1" ]]; then
        echo "HDD"
    elif [[ "$rot" == "0" ]]; then
        echo "SSD"
    else
        echo "UNKNOWN"
    fi
}

# Returns true if drive has any mounted partitions
is_mounted() {
    local dev="$1"
    lsblk -no MOUNTPOINT "$dev" 2>/dev/null | grep -q "/"
}

select_drive() {
    local drives=()
    local dev size type mounted label

    while IFS= read -r line; do
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $4}')
        [[ -z "$dev" ]] && continue

        type=$(detect_drive_type "/dev/$dev")
        if is_mounted "/dev/$dev"; then
            mounted="[MOUNTED]"
        else
            mounted="[unmounted]"
        fi

        label="$size  $type  $mounted"
        drives+=("/dev/$dev" "$label")
    done < <(lsblk -dno NAME,TYPE,MODEL,SIZE | grep -v "loop\|rom" | awk '{print $1, $2, $3, $4}')

    if [[ ${#drives[@]} -eq 0 ]]; then
        whiptail --msgbox "No block devices found." 8 40
        return 1
    fi

    CURRENT_DRIVE=$(whiptail --menu \
        "Select a drive to test:\n\n[MOUNTED] drives cannot run destructive tests." \
        22 65 10 \
        "${drives[@]}" \
        3>&1 1>&2 2>&3) || return 1

    ok "Selected drive: $CURRENT_DRIVE ($(detect_drive_type "$CURRENT_DRIVE"))"
}

# Guard — refuses destructive tests on mounted drives
require_unmounted() {
    local dev="$1"
    if is_mounted "$dev"; then
        whiptail --msgbox \
            "⚠ DRIVE IS MOUNTED\n\n$dev has mounted partitions.\n\nDestructive tests (badblocks write, fio write) CANNOT run on mounted drives.\n\nUnmount all partitions first, or select a different drive." \
            14 58 --title "Safety Check — Aborted"
        return 1
    fi
    return 0
}

# =============================================================================
#  REPORT HELPERS
# =============================================================================

new_report() {
    local test_name="$1" drive="$2"
    local stamp
    stamp=$(date '+%Y%m%d_%H%M%S')
    local safe_dev
    safe_dev=$(echo "$drive" | tr '/' '_')
    REPORT="$LOG_DIR/${test_name}${safe_dev}_${stamp}.txt"
    touch "$REPORT"

    {
    echo "══════════════════════════════════════════════════════"
    echo "  iTechniqs LinuxKeeper — Diagnostic Report"
    printf "  Test     : %s\n" "$test_name"
    printf "  Drive    : %s\n" "$drive"
    printf "  Type     : %s\n" "$(detect_drive_type "$drive")"
    printf "  Date     : %s\n" "$(date '+%A, %d %B %Y  %H:%M:%S')"
    printf "  System   : %s\n" "$(lsb_release -ds 2>/dev/null || uname -rs)"
    echo "══════════════════════════════════════════════════════"
    echo ""
    } | tee "$REPORT"
}

show_report() {
    whiptail --textbox "$REPORT" 30 78 --title "Report: $(basename "$REPORT")" \
        --scrolltext 3>&1 1>&2 2>&3 || true
    echo ""
    ok "Report saved: $REPORT"
}

# =============================================================================
#  MODULE: SMART HEALTH CHECK
#  Works on HDD, SSD, NVMe — read-only, safe on mounted drives
# =============================================================================

run_smart_check() {
    select_drive || return
    local drive="$CURRENT_DRIVE"
    local drive_type
    drive_type=$(detect_drive_type "$drive")

    new_report "SMART_" "$drive"
    hdr "SMART Health Check — $drive ($drive_type)"

    if ! command -v smartctl &>/dev/null; then
        err "smartctl not installed. Run bootstrap to install smartmontools."
        return
    fi

    # Enable SMART if not already active
    sudo smartctl -s on "$drive" >> "$REPORT" 2>&1 || true

    # Overall health
    local health
    health=$(sudo smartctl -H "$drive" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
    if [[ "$health" == "PASSED" ]]; then
        pass "Overall SMART health: PASSED"
    else
        fail "Overall SMART health: ${health:-UNKNOWN}"
    fi

    # Key attributes
    hdr "Key SMART Attributes"
    local reallocated
    reallocated=$(sudo smartctl -A "$drive" 2>/dev/null \
        | awk '/Reallocated_Sector/{print $10}' | head -1 || echo "0")
    reallocated="${reallocated:-0}"
    if (( reallocated == 0 )); then
        pass "Reallocated sectors: 0"
    else
        fail "Reallocated sectors: $reallocated — drive has bad sectors"
    fi

    local pending
    pending=$(sudo smartctl -A "$drive" 2>/dev/null \
        | awk '/Current_Pending_Sector/{print $10}' | head -1 || echo "0")
    pending="${pending:-0}"
    if (( pending == 0 )); then
        pass "Pending sectors: 0"
    else
        fail "Pending sectors: $pending — sectors waiting to be reallocated"
    fi

    local uncorrectable
    uncorrectable=$(sudo smartctl -A "$drive" 2>/dev/null \
        | awk '/Offline_Uncorrectable/{print $10}' | head -1 || echo "0")
    uncorrectable="${uncorrectable:-0}"
    if (( uncorrectable == 0 )); then
        pass "Uncorrectable errors: 0"
    else
        fail "Uncorrectable errors: $uncorrectable"
    fi

    # Temperature
    local temp
    temp=$(sudo smartctl -A "$drive" 2>/dev/null \
        | awk '/Temperature_Celsius|Airflow_Temperature/{print $10}' | head -1 || echo "")
    [[ -n "$temp" ]] && info "Temperature: ${temp}°C" || info "Temperature: not available"

    # SSD wear level
    if [[ "$drive_type" == "SSD" ]]; then
        local wear
        wear=$(sudo smartctl -A "$drive" 2>/dev/null \
            | awk '/Wear_Leveling_Count|Media_Wearout_Indicator|Percent_Lifetime_Remain/{print $4, $10}' \
            | head -1 || echo "")
        [[ -n "$wear" ]] && info "Wear indicator: $wear" || info "Wear level: not available for this drive"
    fi

    # NVMe specific
    if [[ "$drive_type" == "NVMe" ]]; then
        hdr "NVMe SMART Log"
        sudo smartctl -a "$drive" 2>/dev/null | tee -a "$REPORT" || true
    fi

    # Full SMART attributes
    hdr "Full SMART Attribute Table"
    sudo smartctl -A "$drive" 2>/dev/null | tee -a "$REPORT" || true

    # Run short self-test offer
    whiptail --yesno \
        "Run a SHORT SMART self-test on $drive?\n\nThis takes ~2 minutes and is non-destructive.\nThe drive stays online during the test." \
        10 55 --title "Short Self-Test" --yes-button "Run" --no-button "Skip" \
        3>&1 1>&2 2>&3
    if [[ $? -eq 0 ]]; then
        log "Running SMART short self-test…"
        sudo smartctl -t short "$drive" >> "$REPORT" 2>&1
        log "Test started — waiting 90 seconds for completion…"
        # Show progress gauge
        (
            for i in $(seq 1 90); do
                echo $(( i * 100 / 90 ))
                sleep 1
            done
        ) | whiptail --gauge "Running SMART short self-test on $drive…" 8 55 0
        local result
        result=$(sudo smartctl -l selftest "$drive" 2>/dev/null \
            | grep "Short offline" | head -1 | awk '{print $NF}')
        if [[ "$result" == "Completed without error" ]] || echo "$result" | grep -qi "completed"; then
            pass "SMART self-test: Completed without error"
        else
            fail "SMART self-test result: ${result:-unknown}"
        fi
    fi

    show_report
}

# =============================================================================
#  MODULE: BAD SECTOR SCAN (badblocks)
#  Non-destructive: read-only, safe on mounted drives
#  Destructive: write mode — REQUIRES unmounted drive, ERASES DATA
# =============================================================================

run_badblocks() {
    select_drive || return
    local drive="$CURRENT_DRIVE"
    local drive_type
    drive_type=$(detect_drive_type "$drive")

    # NVMe — badblocks not appropriate, use nvme-cli instead
    if [[ "$drive_type" == "NVMe" ]]; then
        whiptail --msgbox \
            "badblocks is not recommended for NVMe drives.\n\nNVMe drives use internal error correction and wear leveling that badblocks cannot account for.\n\nUse the NVMe Tests module instead." \
            12 58 --title "NVMe — Use NVMe Tests"
        return
    fi

    local mode
    mode=$(whiptail --menu \
        "Select scan mode for $drive ($drive_type):" \
        16 62 3 \
        "readonly"    "Read-only scan — safe, drive stays mounted" \
        "nondestructive" "Non-destructive write — drive must be UNMOUNTED" \
        "destructive" "Destructive write — ERASES ALL DATA — UNMOUNTED only" \
        3>&1 1>&2 2>&3) || return

    # Safety checks for write modes
    if [[ "$mode" != "readonly" ]]; then
        require_unmounted "$drive" || return

        if [[ "$mode" == "destructive" ]]; then
            whiptail --yesno \
                "⚠ DESTRUCTIVE MODE — ALL DATA WILL BE ERASED ⚠\n\nDrive : $drive\nType  : $drive_type\n\nThis CANNOT be undone. Every byte will be overwritten.\n\nAre you absolutely sure?" \
                14 58 --title "DATA DESTRUCTION WARNING" \
                --yes-button "ERASE AND TEST" --no-button "Cancel" \
                3>&1 1>&2 2>&3 || return
        fi
    fi

    # Duration
    local blocks
    blocks=$(sudo blockdev --getsz "$drive" 2>/dev/null || echo "unknown")
    info "Drive size: $blocks 512-byte sectors"

    new_report "BADBLOCKS_${mode}_" "$drive"
    hdr "Bad Sector Scan ($mode) — $drive ($drive_type)"

    local bb_flags
    case "$mode" in
        readonly)        bb_flags="-sv" ;;
        nondestructive)  bb_flags="-nsv" ;;
        destructive)     bb_flags="-wsv" ;;
    esac

    log "Starting badblocks scan — this may take a long time…"
    log "Command: sudo badblocks $bb_flags $drive"

    # Run with output to report — no progress gauge since badblocks outputs its own
    if sudo badblocks $bb_flags "$drive" 2>&1 | tee -a "$REPORT"; then
        # Check if any bad blocks were found (badblocks outputs nothing if clean)
        local bad_count
        bad_count=$(grep -c "^[0-9]" "$REPORT" 2>/dev/null || echo "0")
        if (( bad_count == 0 )); then
            pass "Bad sector scan complete — No bad blocks found"
        else
            fail "Bad sector scan complete — $bad_count bad block(s) found"
            warn "Drive should NOT be used for important data"
        fi
    else
        err "badblocks scan failed or was interrupted"
    fi

    show_report
}

# =============================================================================
#  MODULE: FIO BENCHMARK
#  Tests sequential and random read/write performance
#  Write tests require unmounted drive — read tests are safe mounted
# =============================================================================

run_fio_benchmark() {
    select_drive || return
    local drive="$CURRENT_DRIVE"
    local drive_type
    drive_type=$(detect_drive_type "$drive")

    if ! command -v fio &>/dev/null; then
        whiptail --msgbox "fio not installed. Run bootstrap to install it." 8 45
        return
    fi

    local profile
    profile=$(whiptail --menu \
        "Select benchmark profile for $drive ($drive_type):" \
        18 65 5 \
        "quick"       "Quick benchmark — read only, ~2 min, safe mounted" \
        "sequential"  "Sequential R/W — full throughput test, UNMOUNTED" \
        "random"      "Random 4K R/W — IOPS test, UNMOUNTED" \
        "full"        "Full benchmark — all tests, UNMOUNTED, ~15 min" \
        3>&1 1>&2 2>&3) || return

    # Write tests require unmounted
    if [[ "$profile" != "quick" ]]; then
        require_unmounted "$drive" || return
        whiptail --yesno \
            "⚠ Write benchmark on $drive\n\nThis will write test data to the drive.\nAll existing data will be OVERWRITTEN.\n\nProceed?" \
            12 52 --title "Write Benchmark Warning" \
            --yes-button "Proceed" --no-button "Cancel" \
            3>&1 1>&2 2>&3 || return
    fi

    new_report "FIO_${profile}_" "$drive"
    hdr "fio Benchmark ($profile) — $drive ($drive_type)"

    # Common fio options
    local fio_base="--filename=$drive --direct=1 --ioengine=libaio --group_reporting --output-format=normal"
    # Adjust queue depth by drive type
    local iodepth=32
    [[ "$drive_type" == "HDD" ]] && iodepth=4

    run_fio_test() {
        local name="$1" rw="$2" bs="$3" runtime="$4"
        hdr "$name"
        log "Running: fio --name=$name --rw=$rw --bs=$bs --runtime=$runtime --iodepth=$iodepth $fio_base"
        sudo fio \
            --name="$name" \
            --rw="$rw" \
            --bs="$bs" \
            --runtime="$runtime" \
            --time_based \
            --iodepth="$iodepth" \
            $fio_base \
            2>&1 | tee -a "$REPORT" || warn "$name test failed"
    }

    case "$profile" in
        quick)
            run_fio_test "Sequential_Read" "read"       "128k" "30"
            ;;
        sequential)
            run_fio_test "Sequential_Read"  "read"      "128k" "60"
            run_fio_test "Sequential_Write" "write"     "128k" "60"
            ;;
        random)
            run_fio_test "Random_Read_4K"   "randread"  "4k"   "60"
            run_fio_test "Random_Write_4K"  "randwrite" "4k"   "60"
            run_fio_test "Random_Mixed_4K"  "randrw"    "4k"   "60"
            ;;
        full)
            run_fio_test "Sequential_Read"   "read"      "128k" "120"
            run_fio_test "Sequential_Write"  "write"     "128k" "120"
            run_fio_test "Random_Read_4K"    "randread"  "4k"   "120"
            run_fio_test "Random_Write_4K"   "randwrite" "4k"   "120"
            run_fio_test "Random_Mixed_4K"   "randrw"    "4k"   "120"
            run_fio_test "Sequential_RW_64K" "rw"        "64k"  "120"
            ;;
    esac

    show_report
}

# =============================================================================
#  MODULE: NVME TESTS
#  Uses nvme-cli for NVMe-specific health and diagnostics
# =============================================================================

run_nvme_tests() {
    select_drive || return
    local drive="$CURRENT_DRIVE"
    local drive_type
    drive_type=$(detect_drive_type "$drive")

    if [[ "$drive_type" != "NVMe" ]]; then
        whiptail --msgbox \
            "$drive is a $drive_type drive.\n\nNVMe tests only apply to NVMe drives.\nUse SMART or fio for this drive type." \
            10 52 --title "Wrong Drive Type"
        return
    fi

    if ! command -v nvme &>/dev/null; then
        whiptail --msgbox "nvme-cli not installed. Run bootstrap to install it." 8 50
        return
    fi

    new_report "NVME_" "$drive"
    hdr "NVMe Diagnostics — $drive"

    # SMART / Health log
    hdr "NVMe SMART Health Log"
    sudo nvme smart-log "$drive" 2>/dev/null | tee -a "$REPORT" \
        || warn "Could not read NVMe SMART log"

    # Check critical warning field
    local critical
    critical=$(sudo nvme smart-log "$drive" 2>/dev/null \
        | grep "critical_warning" | awk '{print $3}' | tr -d ',')
    if [[ "${critical:-0}" == "0" ]]; then
        pass "Critical warning: none"
    else
        fail "Critical warning flags set: $critical"
    fi

    # Percentage used (wear indicator)
    local pct_used
    pct_used=$(sudo nvme smart-log "$drive" 2>/dev/null \
        | grep "percentage_used" | awk '{print $3}' | tr -d ',%')
    if [[ -n "$pct_used" ]]; then
        if (( pct_used < 80 )); then
            pass "Drive wear: ${pct_used}% used"
        elif (( pct_used < 95 )); then
            warn "Drive wear: ${pct_used}% used — approaching end of life"
        else
            fail "Drive wear: ${pct_used}% used — replace soon"
        fi
    fi

    # Error log
    hdr "NVMe Error Log"
    sudo nvme error-log "$drive" 2>/dev/null | tee -a "$REPORT" \
        || warn "Could not read NVMe error log"

    # Device info
    hdr "NVMe Device Info"
    sudo nvme id-ctrl "$drive" 2>/dev/null | tee -a "$REPORT" \
        || warn "Could not read NVMe controller info"

    # Short self-test
    whiptail --yesno \
        "Run NVMe short self-test on $drive?\n\nNon-destructive, ~2 minutes." \
        9 52 --title "NVMe Self-Test" \
        --yes-button "Run" --no-button "Skip" \
        3>&1 1>&2 2>&3
    if [[ $? -eq 0 ]]; then
        log "Starting NVMe short self-test…"
        sudo nvme device-self-test "$drive" -s 1 >> "$REPORT" 2>&1
        (
            for i in $(seq 1 90); do
                echo $(( i * 100 / 90 ))
                sleep 1
            done
        ) | whiptail --gauge "Running NVMe self-test…" 8 52 0
        hdr "NVMe Self-Test Log"
        sudo nvme self-test-log "$drive" 2>/dev/null | tee -a "$REPORT" \
            || warn "Could not read self-test log"
    fi

    show_report
}

# =============================================================================
#  MODULE: SYSTEM INFO
#  Full hardware profile — CPU, RAM, drives, GPU, network
# =============================================================================

run_system_info() {
    new_report "SYSINFO_" "system"
    hdr "System Information"

    if command -v inxi &>/dev/null; then
        log "Running full system profile (inxi)…"
        inxi -Fxxxz --no-host 2>/dev/null | tee -a "$REPORT" || true
    else
        # Fallback without inxi
        hdr "CPU"
        lscpu 2>/dev/null | tee -a "$REPORT" || true

        hdr "Memory"
        free -h 2>/dev/null | tee -a "$REPORT" || true

        hdr "Block Devices"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,VENDOR,MODEL 2>/dev/null | tee -a "$REPORT" || true

        hdr "PCI Devices"
        sudo lspci 2>/dev/null | tee -a "$REPORT" || true

        hdr "USB Devices"
        lsusb 2>/dev/null | tee -a "$REPORT" || true
    fi

    hdr "Kernel & OS"
    uname -a | tee -a "$REPORT"
    lsb_release -a 2>/dev/null | tee -a "$REPORT" || true

    hdr "Disk Overview"
    lsblk -dno NAME,SIZE,TYPE,VENDOR,MODEL,ROTA,TRAN 2>/dev/null \
        | awk '!/loop/{
            rota=$6=="1"?"HDD":"SSD";
            if($5~/nvme/) rota="NVMe";
            printf "  %-10s %-8s %-8s %-20s %-20s\n", $1, $2, rota, $4, $5
        }' | tee -a "$REPORT" || true

    hdr "Temperatures"
    if command -v sensors &>/dev/null; then
        sensors 2>/dev/null | tee -a "$REPORT" || true
    else
        warn "lm-sensors not installed — run Module 1 (System Essentials) in setup.sh"
    fi

    show_report
}

# =============================================================================
#  MODULE: CPU & MEMORY STRESS TEST
# =============================================================================

run_cpu_stress() {
    if ! command -v stress-ng &>/dev/null; then
        whiptail --msgbox "stress-ng not installed. Run bootstrap to install it." 8 50
        return
    fi

    local duration
    duration=$(whiptail --menu \
        "Select stress test duration:" \
        14 52 4 \
        "60"    "1 minute  — quick sanity check" \
        "300"   "5 minutes — short burn" \
        "3600"  "1 hour    — stability test" \
        "14400" "4 hours   — overnight burn" \
        3>&1 1>&2 2>&3) || return

    local cores
    cores=$(nproc)

    whiptail --yesno \
        "CPU & Memory Stress Test\n\nCores : $cores\nRAM   : $(free -h | awk '/^Mem/{print $2}')\nDuration : ${duration}s\n\nThis will max out all CPU cores and memory.\nSystem may become unresponsive during test.\n\nProceed?" \
        14 52 --title "Stress Test" \
        --yes-button "Start" --no-button "Cancel" \
        3>&1 1>&2 2>&3 || return

    new_report "CPU_STRESS_" "system"
    hdr "CPU & Memory Stress Test"
    log "Cores: $cores | Duration: ${duration}s"

    # Capture baseline temps
    hdr "Baseline Temperatures"
    sensors 2>/dev/null | tee -a "$REPORT" || true

    log "Starting stress-ng — ${duration}s, $cores CPU workers + VM workers…"

    (
        sudo stress-ng \
            --cpu "$cores" \
            --vm 2 \
            --vm-bytes 75% \
            --timeout "${duration}s" \
            --metrics-brief \
            >> "$REPORT" 2>&1 &
        local pid=$!
        local elapsed=0
        while kill -0 $pid 2>/dev/null; do
            echo $(( elapsed * 100 / duration ))
            sleep 5
            elapsed=$(( elapsed + 5 ))
            (( elapsed > duration )) && break
        done
        echo 100
        wait $pid 2>/dev/null || true
    ) | whiptail --gauge "Stress testing CPU & memory for ${duration}s…" 8 55 0

    hdr "Post-Test Temperatures"
    sensors 2>/dev/null | tee -a "$REPORT" || true

    pass "Stress test complete. Check temperatures above for throttling."

    show_report
}

# =============================================================================
#  MODULE: VIEW & MANAGE REPORTS
# =============================================================================

manage_reports() {
    while true; do
        # List available reports
        local reports=()
        while IFS= read -r f; do
            local fname size date_str
            fname=$(basename "$f")
            size=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
            date_str=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
            reports+=("$f" "$size  $date_str  $fname")
        done < <(ls -t "$LOG_DIR"/*.txt "$LOG_DIR"/*.log 2>/dev/null | head -20)

        if [[ ${#reports[@]} -eq 0 ]]; then
            whiptail --msgbox "No reports found in $LOG_DIR" 8 50
            return
        fi

        reports+=("CLEAR" "── Delete all reports older than 30 days")
        reports+=("EXPORT" "── Export latest report to ~/Desktop")

        local selected
        selected=$(whiptail --menu \
            "Select a report to view:" \
            24 78 14 \
            "${reports[@]}" \
            3>&1 1>&2 2>&3) || return

        case "$selected" in
            CLEAR)
                whiptail --yesno "Delete all reports older than 30 days?" 8 50 || continue
                find "$LOG_DIR" -name "*.txt" -mtime +30 -delete
                find "$LOG_DIR" -name "*.log" -mtime +30 -delete
                ok "Old reports deleted."
                ;;
            EXPORT)
                local latest
                latest=$(ls -t "$LOG_DIR"/*.txt 2>/dev/null | head -1)
                if [[ -n "$latest" ]]; then
                    cp "$latest" "$HOME/Desktop/" 2>/dev/null \
                        && whiptail --msgbox "Exported to ~/Desktop/$(basename "$latest")" 8 55 \
                        || whiptail --msgbox "Could not export — Desktop not found.\nReport is at: $latest" 10 55
                fi
                ;;
            *)
                REPORT="$selected"
                show_report
                ;;
        esac
    done
}

# =============================================================================
#  SUBMENUS
# =============================================================================

menu_drives() {
    while true; do
        local CHOICE
        CHOICE=$(whiptail \
            --title "iTechniqs Diagnostics — 💾 Drives" \
            --menu "\nSelect a drive test:" \
            20 65 6 \
            "1" "SMART Health Check     — read-only, all drive types" \
            "2" "Bad Sector Scan        — HDD/SSD only, read or write" \
            "3" "fio Benchmark          — performance & throughput" \
            "4" "NVMe Tests             — NVMe drives only" \
            "B" "← Back to Main Menu" \
            3>&1 1>&2 2>&3) || break

        case "$CHOICE" in
            1) run_smart_check ;;
            2) run_badblocks ;;
            3) run_fio_benchmark ;;
            4) run_nvme_tests ;;
            B) break ;;
        esac
    done
}

menu_system() {
    while true; do
        local CHOICE
        CHOICE=$(whiptail \
            --title "iTechniqs Diagnostics — 🖥 System" \
            --menu "\nSelect a system test:" \
            18 65 4 \
            "1" "System Information     — full hardware profile" \
            "2" "CPU & Memory Stress    — stability & thermal test" \
            "B" "← Back to Main Menu" \
            3>&1 1>&2 2>&3) || break

        case "$CHOICE" in
            1) run_system_info ;;
            2) run_cpu_stress ;;
            B) break ;;
        esac
    done
}

menu_reports() {
    manage_reports
}

# =============================================================================
#  MAIN MENU
# =============================================================================

main_menu() {
    while true; do
        local CHOICE
        CHOICE=$(whiptail \
            --title "iTechniqs LinuxKeeper — Hardware Diagnostics v${DIAG_VERSION}" \
            --menu "\nSelect a category:" \
            18 65 5 \
            "1" "💾  Drives     — SMART, bad sectors, benchmark, NVMe" \
            "2" "🖥  System     — hardware info, CPU/RAM stress test" \
            "3" "📋  Reports    — view, export, manage test reports" \
            "Q" "Exit" \
            3>&1 1>&2 2>&3) || break

        case "$CHOICE" in
            1) menu_drives ;;
            2) menu_system ;;
            3) menu_reports ;;
            Q|q) break ;;
        esac
    done
}

# =============================================================================
#  ENTRY POINT
# =============================================================================
main() {
    apply_theme
    show_banner
    bootstrap
    main_menu

    echo ""
    echo -e "${CYAN}${BOLD}iTechniqs Diagnostics complete.${RESET}"
    echo -e "${DIM}Reports : $LOG_DIR${RESET}"
    echo ""
}

main "$@"
