#!/bin/bash
# ============================================================================
# NVIDIA DGX Spark Sunshine Streaming Setup Installer
# ============================================================================
# Automated installer for Sunshine game streaming with virtual display
# on NVIDIA DGX Spark (GB10) systems
# ============================================================================

set -eo pipefail  # Exit on error, catch pipeline failures

# ============================================================================
# Colors and Formatting (NVIDIA Green Theme)
# ============================================================================
readonly NVIDIA_GREEN='\033[38;5;112m'  # NVIDIA signature green
readonly BRIGHT_GREEN='\033[1;32m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly RED='\033[1;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;34m'
readonly RESET='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

# ============================================================================
# Configuration
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly EDID_DIR="${SCRIPT_DIR}/edid"
readonly TEMPLATES_DIR="${SCRIPT_DIR}/templates"
readonly BACKUP_DIR="${HOME}/.sunshine-setup-backups/$(date +%Y%m%d-%H%M%S)"

readonly SUNSHINE_RELEASE_URL="https://api.github.com/repos/LizardByte/Sunshine/releases/latest"
readonly SUNSHINE_FALLBACK_DEB="https://github.com/LizardByte/Sunshine/releases/download/v2025.924.154138/sunshine-ubuntu-24.04-arm64.deb"
readonly SUNSHINE_CONFIG_DIR="${HOME}/.config/sunshine"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

# User selections (set via prompts)
INSTALL_MODE=""
RESOLUTION=""
REFRESH_RATE=""
CODEC=""
BITRATE=""
EDID_SOURCE=""
CUSTOM_EDID_PATH=""

# Cleanup state
TEMP_FILES=()
INSTALLATION_STARTED=false

# ============================================================================
# ASCII Logo and Header
# ============================================================================
print_logo() {
    echo ""
    echo -e "${NVIDIA_GREEN}${BOLD}"
    echo "  ██████╗  ██████╗ ██╗  ██╗    ███████╗██████╗  █████╗ ██████╗ ██╗  ██╗"
    echo "  ██╔══██╗██╔════╝ ╚██╗██╔╝    ██╔════╝██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝"
    echo "  ██║  ██║██║  ███╗ ╚███╔╝     ███████╗██████╔╝███████║██████╔╝█████╔╝ "
    echo "  ██║  ██║██║   ██║ ██╔██╗     ╚════██║██╔═══╝ ██╔══██║██╔══██╗██╔═██╗ "
    echo "  ██████╔╝╚██████╔╝██╔╝ ██╗    ███████║██║     ██║  ██║██║  ██║██║  ██╗"
    echo "  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝    ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${RESET}"
    echo -e "${GRAY}  Sunshine Streaming Setup${RESET}"
    echo -e "${DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

cleanup() {
    local exit_code=$?
    # Remove temp files
    for f in "${TEMP_FILES[@]}"; do
        [[ -f "$f" ]] && rm -f "$f" 2>/dev/null
    done
    # On failure, inform user about backups
    if [[ ${exit_code} -ne 0 && "${INSTALLATION_STARTED}" == true ]]; then
        echo -e "${RED}Installation failed.${RESET}" >&2
        if [[ -n "${BACKUP_DIR:-}" && -d "${BACKUP_DIR}" ]]; then
            echo -e "Backups available at: ${BACKUP_DIR}" >&2
            echo -e "To restore: sudo cp ${BACKUP_DIR}/xorg.conf /etc/X11/ 2>/dev/null" >&2
        fi
    fi
    exit ${exit_code}
}
trap cleanup EXIT
trap 'echo -e "${RED}Error at line ${LINENO}${RESET}" >&2' ERR

# ============================================================================
# Utility Functions
# ============================================================================
log_info() {
    echo -e "${NVIDIA_GREEN}▶${RESET} $1"
}

log_success() {
    echo -e "${BRIGHT_GREEN}✓${RESET} $1"
}

log_error() {
    echo -e "${RED}✗${RESET} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET} $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}${BOLD}┌─ $1${RESET}"
}

log_substep() {
    echo -e "${GRAY}│${RESET}  $1"
}

log_complete() {
    echo -e "${BLUE}${BOLD}└─${RESET} ${BRIGHT_GREEN}Complete${RESET}"
}

prompt_user() {
    local prompt="$1"
    local var_name="$2"
    echo -ne "${NVIDIA_GREEN}?${RESET} ${prompt}: "
    read -r "${var_name}"
}

prompt_secret() {
    local prompt="$1"
    local var_name="$2"
    echo -ne "${NVIDIA_GREEN}?${RESET} ${prompt}: "
    read -rs "$var_name"
    echo ""
}

confirm() {
    local prompt="$1"
    local response
    echo -ne "${YELLOW}?${RESET} ${prompt} ${DIM}[y/N]${RESET}: "
    read -r response
    [[ "${response}" =~ ^[Yy]$ ]]
}

# ============================================================================
# Prerequisites Check
# ============================================================================
check_prerequisites() {
    log_step "Checking Prerequisites"

    local errors=0

    # Refuse to run as root — the script uses sudo as needed, and running
    # as root would put root in the video/input groups, write root's ~/.xprofile,
    # and configure AutomaticLogin=root in /etc/gdm3/custom.conf. None of those
    # are what the user actually wants.
    log_substep "Checking effective user..."
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this installer as root — it uses sudo as needed"
        log_error "Run as your normal user: ./install.sh"
        exit 1
    fi
    log_success "Running as ${USER} (uid ${EUID})"

    # Check if running on DGX Spark
    log_substep "Checking hardware platform..."
    if command -v nvidia-smi &> /dev/null && nvidia-smi -L 2>/dev/null | grep -q "GB10"; then
        log_success "GB10 GPU detected"
    else
        log_warning "GB10 GPU not detected - this script is designed for DGX Spark"
        if ! confirm "Continue anyway?"; then
            exit 1
        fi
    fi

    # Check for NVIDIA driver
    log_substep "Checking NVIDIA driver..."
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "NVIDIA driver not found (nvidia-smi missing)"
        ((errors++))
    else
        log_success "NVIDIA driver found: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
    fi

    # Check for X11
    log_substep "Checking X11..."
    if ! command -v Xorg &> /dev/null; then
        log_error "X11 not found - desktop environment required"
        ((errors++))
    else
        log_success "X11 found"
    fi

    # Check for systemd
    log_substep "Checking systemd..."
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd not found"
        ((errors++))
    else
        log_success "systemd found"
    fi

    # Check for required commands
    local required_cmds=("curl" "sed" "lspci")
    for cmd in "${required_cmds[@]}"; do
        log_substep "Checking for ${cmd}..."
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "${cmd} not found"
            ((errors++))
        else
            log_success "${cmd} found"
        fi
    done

    if [[ ${errors} -gt 0 ]]; then
        log_error "Prerequisites check failed with ${errors} error(s)"
        exit 1
    fi

    log_complete
}

# ============================================================================
# Interactive Configuration
# ============================================================================
# Two ways to set up a Spark for sunshine:
#
#   monitor  - A real monitor or an HDMI dummy plug is always connected.
#              The NVIDIA driver auto-detects whatever is plugged in, and
#              no synthetic xorg.conf is installed. Recommended for most.
#
#   headless - Truly headless, with nothing plugged into the GPU. Installs
#              an xorg.conf that drives a virtual TV-0 connector with a
#              custom EDID so sunshine can still capture a display.
#              Will break if a real monitor is later connected.
#
# Sets the INSTALL_MODE global. install_edid, configure_x11, and the
# validation step honor it.
configure_install_mode() {
    log_step "Installation Mode"

    # Honor a pre-exported INSTALL_MODE so the installer works under CI,
    # Ansible, or any other non-interactive re-run path without blocking
    # on a prompt. Accepts exactly the two values the interactive path can set.
    if [[ "${INSTALL_MODE:-}" =~ ^(monitor|headless)$ ]]; then
        log_substep "Mode: ${INSTALL_MODE} (from environment)"
        log_complete
        return 0
    fi

    echo ""
    echo -e "${WHITE}${BOLD}How will this Spark be used?${RESET}"
    echo ""
    echo -e "${GRAY}  1)${RESET} ${BOLD}Monitor or HDMI dummy plug attached${RESET} ${NVIDIA_GREEN}[Recommended]${RESET}"
    echo -e "${GRAY}     Streams whatever the GPU sees. Suitable for desktop use and"
    echo -e "${GRAY}     for streaming with a real monitor or a passive HDMI dummy plug.${RESET}"
    echo ""
    echo -e "${GRAY}  2)${RESET} ${BOLD}Truly headless${RESET} ${DIM}(no monitor, no dummy plug, ever)${RESET}"
    echo -e "${GRAY}     Installs a virtual-display xorg.conf with a custom EDID so"
    echo -e "${GRAY}     sunshine can capture with nothing physically connected.${RESET}"
    echo -e "${GRAY}     Streaming will break if you later plug a monitor in.${RESET}"
    echo ""

    local choice
    while true; do
        prompt_user "Select installation mode (1-2) [1]" choice
        # Bare Enter selects 1 (Recommended), matching the [1] hint in the prompt.
        case "${choice:-1}" in
            1)
                INSTALL_MODE="monitor"
                log_substep "Mode: monitor or dummy plug"
                break
                ;;
            2)
                INSTALL_MODE="headless"
                log_substep "Mode: truly headless"
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1-2."
                ;;
        esac
    done

    log_complete
}

configure_resolution() {
    log_step "Display Configuration"

    echo ""
    echo -e "${WHITE}${BOLD}Available Resolutions:${RESET}"
    echo -e "${GRAY}  1)${RESET} 3840x2160 @ 60Hz  ${DIM}(4K, lower refresh rate)${RESET}"
    echo -e "${GRAY}  2)${RESET} 3440x1440 @ 60Hz  ${DIM}(Dell AW3420DW Ultrawide 21:9)${RESET}"
    echo -e "${GRAY}  3)${RESET} 2732x2048 @ 60Hz  ${DIM}(iPad Pro 12.9 M2)${RESET}"
    echo -e "${GRAY}  4)${RESET} 2560x1440 @ 120Hz ${DIM}(1440p, higher refresh rate)${RESET} ${NVIDIA_GREEN}[Recommended]${RESET}"
    echo -e "${GRAY}  5)${RESET} 1920x1080 @ 120Hz ${DIM}(1080p, higher refresh rate)${RESET}"
    echo ""

    local choice
    while true; do
        prompt_user "Select resolution (1-5)" choice
        case "${choice}" in
            1)
                RESOLUTION="3840x2160"
                REFRESH_RATE="60"
                break
                ;;
            2)
                RESOLUTION="3440x1440"
                REFRESH_RATE="60"
                break
                ;;
            3)
                RESOLUTION="2732x2048"
                REFRESH_RATE="60"
                break
                ;;
            4)
                RESOLUTION="2560x1440"
                REFRESH_RATE="120"
                break
                ;;
            5)
                RESOLUTION="1920x1080"
                REFRESH_RATE="120"
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1-5."
                ;;
        esac
    done

    log_success "Selected: ${RESOLUTION} @ ${REFRESH_RATE}Hz"
    log_complete
}

configure_codec() {
    log_step "Video Codec Configuration"

    echo ""
    echo -e "${WHITE}${BOLD}Available Codecs:${RESET}"
    echo -e "${GRAY}  1)${RESET} HEVC (H.265) ${DIM}(Better compatibility)${RESET} ${NVIDIA_GREEN}[Recommended]${RESET}"
    echo -e "${GRAY}  2)${RESET} AV1         ${DIM}(Better compression, newer clients)${RESET}"
    echo -e "${GRAY}  3)${RESET} H.264       ${DIM}(Maximum compatibility)${RESET}"
    echo ""

    local choice
    while true; do
        prompt_user "Select codec (1-3)" choice
        case "${choice}" in
            1)
                CODEC="hevc"
                break
                ;;
            2)
                CODEC="av1"
                break
                ;;
            3)
                CODEC="h264"
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1-3."
                ;;
        esac
    done

    log_success "Selected: ${CODEC}"
    log_complete
}

configure_bitrate() {
    log_step "Bitrate Configuration"

    echo ""
    echo -e "${WHITE}${BOLD}Recommended Bitrates:${RESET}"
    echo -e "${GRAY}  •${RESET} LAN (Gigabit):  ${DIM}100-200 Mbps${RESET}"
    echo -e "${GRAY}  •${RESET} LAN (Wi-Fi):    ${DIM}50-100 Mbps${RESET}"
    echo -e "${GRAY}  •${RESET} Remote (VPN):   ${DIM}20-50 Mbps${RESET}"
    echo ""

    local input
    while true; do
        prompt_user "Enter bitrate in Mbps [50-200]" input
        if [[ "${input}" =~ ^[0-9]+$ ]] && [ "${input}" -ge 20 ] && [ "${input}" -le 300 ]; then
            BITRATE=$((input * 1000))  # Convert to Kbps
            break
        else
            log_error "Invalid bitrate. Please enter a number between 20 and 300."
        fi
    done

    log_success "Selected: ${input} Mbps"
    log_complete
}

configure_edid() {
    log_step "EDID Configuration"

    if [[ "${INSTALL_MODE}" == "monitor" ]]; then
        log_substep "Monitor mode: using whatever EDID the connected display provides"
        EDID_SOURCE="none"
        log_complete
        return 0
    fi

    echo ""
    echo -e "${WHITE}${BOLD}EDID Options:${RESET}"
    echo -e "${GRAY}  1)${RESET} Use bundled Samsung Q800T EDID ${DIM}(4K@60Hz, 1440p@120Hz)${RESET} ${NVIDIA_GREEN}[Recommended]${RESET}"
    echo -e "${GRAY}  2)${RESET} Provide custom EDID file path"
    echo ""

    local choice
    while true; do
        prompt_user "Select EDID source (1-2)" choice
        case "${choice}" in
            1)
                EDID_SOURCE="bundled"
                break
                ;;
            2)
                EDID_SOURCE="custom"
                while true; do
                    prompt_user "Enter path to custom EDID .bin file" CUSTOM_EDID_PATH
                    if [[ -f "${CUSTOM_EDID_PATH}" ]]; then
                        log_success "Custom EDID file found"
                        break
                    else
                        log_error "File not found: ${CUSTOM_EDID_PATH}"
                    fi
                done
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1-2."
                ;;
        esac
    done

    log_complete
}

print_configuration_summary() {
    echo ""
    echo -e "${NVIDIA_GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}${BOLD}Configuration Summary${RESET}"
    echo -e "${NVIDIA_GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GRAY}  Mode:${RESET}        ${INSTALL_MODE}"
    echo -e "${GRAY}  Resolution:${RESET}  ${RESOLUTION} @ ${REFRESH_RATE}Hz"
    echo -e "${GRAY}  Codec:${RESET}       ${CODEC}"
    echo -e "${GRAY}  Bitrate:${RESET}     $((BITRATE / 1000)) Mbps"
    if [[ "${INSTALL_MODE}" == "headless" ]]; then
        echo -e "${GRAY}  EDID Source:${RESET} ${EDID_SOURCE}"
        if [[ "${EDID_SOURCE}" == "custom" ]]; then
            echo -e "${GRAY}  EDID Path:${RESET}   ${CUSTOM_EDID_PATH}"
        fi
    fi
    echo -e "${NVIDIA_GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""

    if ! confirm "Proceed with installation?"; then
        log_warning "Installation cancelled by user"
        exit 0
    fi
}

# ============================================================================
# Backup Functions
# ============================================================================
create_backup() {
    log_step "Creating Backups"

    mkdir -p -m 700 "${BACKUP_DIR}"
    log_substep "Backup directory: ${BACKUP_DIR}"
    INSTALLATION_STARTED=true

    # Backup xorg.conf (EAFP: try copy, handle failure)
    if sudo cp /etc/X11/xorg.conf "${BACKUP_DIR}/xorg.conf" 2>/dev/null; then
        log_success "xorg.conf backed up"
    else
        log_substep "No existing xorg.conf to backup"
    fi

    # Backup existing EDID files (EAFP: try copy, handle failure)
    shopt -s nullglob
    local edid_files=(/etc/X11/*.edid)
    if [[ ${#edid_files[@]} -gt 0 ]]; then
        if sudo cp "${edid_files[@]}" "${BACKUP_DIR}/" 2>/dev/null; then
            log_success "EDID files backed up"
        else
            log_warning "Failed to backup some EDID files"
        fi
    else
        log_substep "No existing EDID files to backup"
    fi
    shopt -u nullglob

    # Backup Sunshine config if it exists
    if [[ -d "${SUNSHINE_CONFIG_DIR}" ]]; then
        if cp -r "${SUNSHINE_CONFIG_DIR}" "${BACKUP_DIR}/sunshine" 2>/dev/null; then
            log_success "Sunshine config backed up"
        else
            log_warning "Failed to backup Sunshine config"
        fi
    fi

    # Backup systemd override if it exists
    if [[ -f "${SYSTEMD_USER_DIR}/sunshine.service.d/override.conf" ]]; then
        log_substep "Backing up systemd override..."
        cp "${SYSTEMD_USER_DIR}/sunshine.service.d/override.conf" "${BACKUP_DIR}/sunshine-override.conf"
        log_success "systemd override backed up"
    fi

    log_success "All backups created in: ${BACKUP_DIR}"
    log_complete
}

# ============================================================================
# Sunshine Installation
# ============================================================================
install_sunshine() {
    log_step "Installing Sunshine"

    # Check if already installed
    if command -v sunshine &> /dev/null; then
        log_warning "Sunshine is already installed"
        local current_version
        current_version=$(sunshine --version 2>/dev/null || echo "unknown")
        log_substep "Current version: ${current_version}"

        if ! confirm "Reinstall/upgrade Sunshine?"; then
            log_info "Skipping Sunshine installation"
            log_complete
            return
        fi
    fi

    log_substep "Fetching latest release information..."
    local release_info download_url

    # Try GitHub API for latest release, fall back to pinned version on failure
    if release_info=$(curl -sL --fail-with-body "${SUNSHINE_RELEASE_URL}" 2>/dev/null) && [[ -n "${release_info}" ]]; then
        # Specifically get Ubuntu 24.04 ARM64 package (not Debian Trixie which has library version mismatches)
        download_url=$(echo "${release_info}" | grep -o "https://[^\"]*sunshine-ubuntu-24\.04-arm64\.deb" | head -1)

        # Fallback to any Ubuntu ARM64 package
        if [[ -z "${download_url}" ]]; then
            download_url=$(echo "${release_info}" | grep -o "https://[^\"]*sunshine-ubuntu.*arm64\.deb" | head -1)
        fi
    fi

    if [[ -z "${download_url:-}" ]]; then
        log_warning "GitHub API unavailable or no ARM64 .deb found — using pinned fallback version"
        download_url="${SUNSHINE_FALLBACK_DEB}"
    fi

    local deb_file
    deb_file=$(mktemp /tmp/sunshine-XXXXXX.deb)
    TEMP_FILES+=("${deb_file}")

    log_substep "Downloading: ${download_url##*/}"
    if ! curl -L --fail -o "${deb_file}" "${download_url}"; then
        log_error "Failed to download Sunshine .deb package"
        log_substep "URL: ${download_url}"
        exit 1
    fi

    log_substep "Installing Sunshine package..."
    if ! sudo apt-get install -y "${deb_file}"; then
        log_error "Failed to install Sunshine .deb package"
        exit 1
    fi

    rm -f "${deb_file}"

    log_success "Sunshine installed successfully"
    log_substep "Version: $(sunshine --version 2>/dev/null || echo 'unknown')"
    log_complete
}

# ============================================================================
# EDID Configuration
# ============================================================================
install_edid() {
    log_step "Installing EDID File"

    if [[ "${INSTALL_MODE}" == "monitor" ]]; then
        log_substep "Monitor mode: skipping EDID file install"
        log_complete
        return 0
    fi

    local source_edid
    if [[ "${EDID_SOURCE}" == "bundled" ]]; then
        source_edid="${EDID_DIR}/samsung-q800t.bin"
    else
        source_edid="${CUSTOM_EDID_PATH}"
    fi

    if [[ ! -f "${source_edid}" ]]; then
        log_error "EDID file not found: ${source_edid}"
        exit 1
    fi

    log_substep "Source: ${source_edid}"
    log_substep "Installing to: /etc/X11/4k120.edid"

    sudo cp "${source_edid}" /etc/X11/4k120.edid
    sudo chmod 644 /etc/X11/4k120.edid

    # Validate EDID
    log_substep "Validating EDID file..."
    if file /etc/X11/4k120.edid | grep -q "EDID"; then
        log_success "EDID file validated"
    else
        log_warning "EDID validation uncertain - file may not be valid EDID data"
    fi

    log_complete
}

# ============================================================================
# X11 Configuration
# ============================================================================
configure_x11() {
    log_step "Configuring X11"

    if [[ "${INSTALL_MODE}" == "monitor" ]]; then
        if [[ -f "/etc/X11/xorg.conf" ]]; then
            if sudo grep -q "DGX Spark Sunshine Setup Installer" /etc/X11/xorg.conf 2>/dev/null; then
                log_substep "Monitor mode: removing previous installer-managed /etc/X11/xorg.conf"
                sudo rm -f /etc/X11/xorg.conf
                log_success "Removed installer-managed xorg.conf"
            else
                log_warning "Existing /etc/X11/xorg.conf was not created by this installer; leaving it in place"
                log_substep "If display issues persist, inspect or remove it manually"
            fi
        else
            log_substep "Monitor mode: no xorg.conf installed"
        fi
        log_substep "The NVIDIA driver will auto-detect connected displays"
        log_complete
        return 0
    fi

    # Detect GPU BusID
    log_substep "Detecting NVIDIA GPU BusID..."
    local bus_id
    # Prefer fully-qualified domain:bus:device.function (via -D) and match both
    # "VGA compatible controller" and "3D controller" classes.
    bus_id=$(lspci -D | grep -Ei "NVIDIA" | grep -Ei "VGA compatible controller|3D controller" | awk '{print $1}' | head -n 1)

    # Fallback: try to find any NVIDIA GPU-like device (still with -D for domain)
    if [[ -z "${bus_id}" ]]; then
        bus_id=$(lspci -D | grep -Ei "nvidia.*gb10" | awk '{print $1}' | head -n 1)
    fi

    if [[ -z "${bus_id}" ]]; then
        log_error "Failed to detect NVIDIA GPU BusID"
        log_substep "Please check 'lspci -D | grep -i nvidia' output"
        exit 1
    fi

    # Convert from domain:bus:device.function to PCI:bus:device:function format
    # lspci shows: 000f:01:00.0 -> we need: PCI:15:1:0
    # Extract components
    local domain bus device func
    domain=$(echo "${bus_id}" | cut -d: -f1)
    bus=$(echo "${bus_id}" | cut -d: -f2)
    device=$(echo "${bus_id}" | cut -d: -f3 | cut -d. -f1)
    func=$(echo "${bus_id}" | cut -d. -f2)

    # Validate hex format before conversion
    if [[ ! "${domain}" =~ ^[0-9a-fA-F]+$ ]] || \
       [[ ! "${bus}" =~ ^[0-9a-fA-F]+$ ]] || \
       [[ ! "${device}" =~ ^[0-9a-fA-F]+$ ]] || \
       [[ ! "${func}" =~ ^[0-9a-fA-F]+$ ]]; then
        log_error "GPU BusID contains non-hex values: ${bus_id}"
        log_substep "Expected format: domain:bus:device.function (hex digits)"
        exit 1
    fi

    # Convert hex to decimal
    domain=$((16#${domain}))
    bus=$((16#${bus}))
    device=$((16#${device}))
    func=$((16#${func}))

    local pci_bus_id="PCI:${bus}:${device}:${func}"

    # Validate BusID format for safe sed substitution
    if [[ ! "${pci_bus_id}" =~ ^PCI:[0-9]+:[0-9]+:[0-9]+$ ]]; then
        log_error "Invalid BusID format generated: ${pci_bus_id}"
        exit 1
    fi

    log_success "Detected BusID: ${pci_bus_id}"

    # Generate xorg.conf from template
    log_substep "Generating xorg.conf from template..."
    if [[ ! -f "${TEMPLATES_DIR}/xorg.conf.template" ]]; then
        log_error "xorg.conf template not found: ${TEMPLATES_DIR}/xorg.conf.template"
        exit 1
    fi
    local temp_xorg
    temp_xorg=$(mktemp /tmp/xorg.conf.XXXXXX)
    TEMP_FILES+=("${temp_xorg}")
    sed -e "s|{{BUS_ID}}|${pci_bus_id}|g" \
        -e "s|{{EDID_PATH}}|/etc/X11/4k120.edid|g" \
        "${TEMPLATES_DIR}/xorg.conf.template" > "${temp_xorg}"

    log_substep "Installing xorg.conf to /etc/X11/xorg.conf"
    sudo cp "${temp_xorg}" /etc/X11/xorg.conf
    sudo chmod 644 /etc/X11/xorg.conf
    rm -f "${temp_xorg}"

    log_success "X11 configuration installed"
    log_warning "X11 restart required - display will be reconfigured on next login"
    log_complete
}

# ============================================================================
# Permissions Configuration
# ============================================================================
configure_permissions() {
    log_step "Configuring Permissions"

    log_substep "Adding current user to 'video' and 'input' groups..."
    sudo usermod -aG video,input "${USER}"
    log_success "User added to groups"

    # NOTE: uinput access allows Sunshine to forward remote input (keyboard/mouse).
    # This grants the logged-in user the ability to create virtual input devices.
    log_substep "Configuring udev rules for uinput..."
    local udev_rule='KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess"'
    echo "${udev_rule}" | sudo tee /etc/udev/rules.d/85-sunshine.rules > /dev/null

    log_substep "Reloading udev rules..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    log_success "udev rules configured"

    log_complete
}

# ============================================================================
# X Session Environment
# ============================================================================
# Sunshine runs as a systemd user service and needs DISPLAY and XAUTHORITY
# in its environment to capture an X session. This step adds the
# upstream-recommended dbus-update line to ~/.xprofile so those values are
# propagated to systemd user services after graphical login.
configure_xprofile() {
    log_step "Configuring X Session Environment"

    local xprofile="${HOME}/.xprofile"
    local dbus_line='dbus-update-activation-environment --systemd DISPLAY XAUTHORITY'

    # ~/.xprofile is only sourced under X11 sessions. Under Wayland (default
    # in Ubuntu 25.04+ and possible on 24.04 if WaylandEnable was flipped),
    # the dbus-update line never runs and Sunshine's ExecStartPre will time
    # out after 60s on every boot. configure_autologin (next step) flips
    # WaylandEnable=false for the auto-login path, but a user who declines
    # auto-login and logs in to a Wayland session manually will silently hit
    # this. Warn loudly; don't abort — the write is still correct for the
    # next X11 login.
    local session_type
    session_type=$(loginctl show-session "${XDG_SESSION_ID:-}" -p Type --value 2>/dev/null || echo "unknown")
    if [[ "${session_type}" == "wayland" ]]; then
        log_warning "Current session is Wayland — ~/.xprofile is NOT sourced under Wayland."
        log_warning "Sunshine needs an X11 session. Either accept the GDM auto-login"
        log_warning "prompt in the next step (it disables Wayland), or log out and pick"
        log_warning "'Ubuntu on Xorg' from the GDM gear menu before starting Sunshine."
    fi

    log_substep "Ensuring ~/.xprofile runs dbus-update on X login..."

    if [[ -f "${xprofile}" ]] && grep -qF -- "${dbus_line}" "${xprofile}"; then
        log_success "~/.xprofile already configured"
    else
        if [[ -f "${xprofile}" ]]; then
            cp "${xprofile}" "${BACKUP_DIR}/.xprofile"
            log_substep "Existing ~/.xprofile backed up"
        fi
        {
            printf '\n# Propagate DISPLAY and XAUTHORITY to systemd user services\n'
            printf '%s\n' "${dbus_line}"
        } >> "${xprofile}"
        log_success "~/.xprofile updated"
    fi

    log_complete
}

# ============================================================================
# GDM Auto-login (Optional)
# ============================================================================
# Sunshine can only stream when an X session is active. On a headless
# Spark there is no one to log in at the console, so GDM needs to do
# it automatically at boot. WaylandEnable=false forces the session to
# be X11, which sunshine's X11 capture path requires.
configure_autologin() {
    log_step "Configuring GDM Auto-login (Optional)"

    if [[ ! -d /etc/gdm3 ]]; then
        log_substep "GDM not detected; skipping auto-login configuration"
        log_complete
        return 0
    fi

    echo -e "${GRAY}For headless streaming, an X session must exist before sunshine"
    echo -e "starts. GDM auto-login provides that on every boot without anyone"
    echo -e "sitting at the console. Decline if this Spark is a desktop you"
    echo -e "always log in at manually.${RESET}"
    echo ""

    local response
    echo -ne "${NVIDIA_GREEN}?${RESET} Enable GDM auto-login as '${USER}' and disable Wayland? ${DIM}[y/N]${RESET}: "
    read -r response

    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        log_substep "Skipped GDM auto-login configuration"
        log_complete
        return 0
    fi

    local gdm_conf="/etc/gdm3/custom.conf"
    local temp_gdm
    temp_gdm=$(mktemp /tmp/gdm-custom.conf.XXXXXX)
    TEMP_FILES+=("${temp_gdm}")

    if [[ -f "${gdm_conf}" ]]; then
        sudo cp "${gdm_conf}" "${BACKUP_DIR}/gdm-custom.conf"
        log_substep "Existing ${gdm_conf} backed up"
        log_substep "Updating [daemon] keys in ${gdm_conf}..."
        if ! sudo awk -v login_user="${USER}" '
            function emit_daemon_keys() {
                if (!seen_auto_enable) {
                    print "AutomaticLoginEnable=true"
                }
                if (!seen_auto_login) {
                    print "AutomaticLogin=" login_user
                }
                if (!seen_wayland) {
                    print "WaylandEnable=false"
                }
            }
            /^[[:space:]]*\[daemon\][[:space:]]*$/ {
                if (in_daemon) {
                    emit_daemon_keys()
                }
                in_daemon = 1
                seen_daemon = 1
                print
                next
            }
            /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
                if (in_daemon) {
                    emit_daemon_keys()
                    in_daemon = 0
                }
                print
                next
            }
            in_daemon && /^[[:space:]]*#?[[:space:]]*AutomaticLoginEnable[[:space:]]*=/ {
                if (!seen_auto_enable) {
                    print "AutomaticLoginEnable=true"
                }
                seen_auto_enable = 1
                next
            }
            in_daemon && /^[[:space:]]*#?[[:space:]]*AutomaticLogin[[:space:]]*=/ {
                if (!seen_auto_login) {
                    print "AutomaticLogin=" login_user
                }
                seen_auto_login = 1
                next
            }
            in_daemon && /^[[:space:]]*#?[[:space:]]*WaylandEnable[[:space:]]*=/ {
                if (!seen_wayland) {
                    print "WaylandEnable=false"
                }
                seen_wayland = 1
                next
            }
            { print }
            END {
                if (in_daemon) {
                    emit_daemon_keys()
                } else if (!seen_daemon) {
                    print ""
                    print "[daemon]"
                    print "# Auto-login the streaming user so an X session exists at boot for"
                    print "# sunshine to capture. Wayland is disabled because sunshine'\''s X11"
                    print "# capture path requires an X server."
                    print "AutomaticLoginEnable=true"
                    print "AutomaticLogin=" login_user
                    print "WaylandEnable=false"
                }
            }
        ' "${gdm_conf}" > "${temp_gdm}"; then
            log_error "Failed to update ${gdm_conf}"
            exit 1
        fi
    else
        log_substep "Creating ${gdm_conf}..."
        {
            printf '# GNOME Display Manager configuration\n'
            printf '# Managed by dgx-spark-sunshine-setup\n'
            printf '[daemon]\n'
            printf '# Auto-login the streaming user so an X session exists at boot for\n'
            printf '# sunshine to capture. Wayland is disabled because sunshine'\''s X11\n'
            printf '# capture path requires an X server.\n'
            printf 'AutomaticLoginEnable=true\n'
            printf 'AutomaticLogin=%s\n' "${USER}"
            printf 'WaylandEnable=false\n'
        } > "${temp_gdm}"
    fi

    log_substep "Writing ${gdm_conf}..."
    sudo install -m 0644 "${temp_gdm}" "${gdm_conf}"
    log_success "GDM auto-login enabled for ${USER}"
    log_warning "Takes effect after reboot"

    log_complete
}

# ============================================================================
# Sunshine Configuration
# ============================================================================
configure_sunshine() {
    log_step "Configuring Sunshine"

    # Create config directory
    mkdir -p -m 700 "${SUNSHINE_CONFIG_DIR}"

    # Generate sunshine.conf from template
    log_substep "Generating sunshine.conf..."
    if [[ ! -f "${TEMPLATES_DIR}/sunshine.conf.template" ]]; then
        log_error "sunshine.conf template not found: ${TEMPLATES_DIR}/sunshine.conf.template"
        exit 1
    fi
    sed -e "s|{{CODEC}}|${CODEC}|g" \
        -e "s|{{BITRATE}}|${BITRATE}|g" \
        -e "s|{{FPS}}|${REFRESH_RATE}|g" \
        "${TEMPLATES_DIR}/sunshine.conf.template" > "${SUNSHINE_CONFIG_DIR}/sunshine.conf"

    log_success "sunshine.conf created"

    # Configure systemd user service
    log_substep "Configuring systemd user service..."
    mkdir -p "${SYSTEMD_USER_DIR}"
    mkdir -p "${SYSTEMD_USER_DIR}/sunshine.service.d"

    # Install the base service file (newer Sunshine versions don't include one)
    if [[ ! -f "${SYSTEMD_USER_DIR}/sunshine.service" ]]; then
        log_substep "Installing sunshine.service..."
        if [[ ! -f "${TEMPLATES_DIR}/sunshine.service" ]]; then
            log_error "sunshine.service template not found"
            exit 1
        fi
        cp "${TEMPLATES_DIR}/sunshine.service" "${SYSTEMD_USER_DIR}/sunshine.service"
    fi

    # Install the override configuration
    if [[ ! -f "${TEMPLATES_DIR}/sunshine-override.conf" ]]; then
        log_error "sunshine-override.conf template not found"
        exit 1
    fi
    cp "${TEMPLATES_DIR}/sunshine-override.conf" "${SYSTEMD_USER_DIR}/sunshine.service.d/override.conf"

    # Reload systemd
    log_substep "Reloading systemd configuration..."
    systemctl --user daemon-reload
    log_success "Systemd configuration reloaded"

    # Ask if they want auto-start
    echo ""
    if confirm "Enable Sunshine to start automatically on login?"; then
        systemctl --user enable sunshine
        log_success "Sunshine service enabled (will start automatically on next login)"

        # Enable lingering for user session persistence
        # This allows the user's systemd services to start at boot, even before GUI login
        log_substep "Enabling session persistence (lingering)..."
        if sudo loginctl enable-linger "$(whoami)"; then
            log_success "Session lingering enabled for reliable auto-start"
        else
            log_warning "Could not enable lingering - Sunshine may not start until first login"
            log_substep "To enable manually: ${DIM}sudo loginctl enable-linger $(whoami)${RESET}"
        fi
    else
        log_info "Sunshine service configured but not enabled for auto-start"
        log_substep "To start manually: ${DIM}systemctl --user start sunshine${RESET}"
        log_substep "To enable auto-start later: ${DIM}systemctl --user enable sunshine${RESET}"
    fi

    log_complete
}

# ============================================================================
# Optional: Tailscale (Remote Access)
# ============================================================================
configure_tailscale() {
    log_step "Optional: Tailscale Remote Access"

    echo ""
    if ! confirm "Install and configure Tailscale for remote access (VPN)?"; then
        log_info "Skipping Tailscale setup"
        log_complete
        return
    fi

    if ! command -v apt-get &> /dev/null; then
        log_warning "apt-get not found - cannot auto-install Tailscale on this system"
        log_substep "Install Tailscale manually: ${DIM}https://tailscale.com/download/linux${RESET}"
        log_complete
        return
    fi

    if command -v tailscale &> /dev/null; then
        log_success "Tailscale already installed"
    else
        log_substep "Installing Tailscale..."

        # Detect Ubuntu codename for the Tailscale apt repo
        local codename=""
        if [[ -f /etc/os-release ]]; then
            codename=$(. /etc/os-release && echo "${VERSION_CODENAME}")
        fi
        if [[ -z "${codename}" ]]; then
            codename=$(lsb_release -cs 2>/dev/null || true)
        fi

        if [[ -n "${codename}" ]]; then
            log_substep "Detected Ubuntu codename: ${DIM}${codename}${RESET}"
            log_substep "Adding Tailscale package repository..."

            local ts_base="https://pkgs.tailscale.com/stable/ubuntu"
            if curl -fsSL "${ts_base}/${codename}.noarmor.gpg" | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
                && curl -fsSL "${ts_base}/${codename}.tailscale-keyring.list" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null; then
                log_success "Tailscale repository added"
            else
                log_warning "Failed to add Tailscale repository for codename '${codename}'"
                log_substep "Falling back to Tailscale install script..."
                if curl -fsSL https://tailscale.com/install.sh | sh; then
                    log_success "Tailscale installed via install script"
                else
                    log_warning "Failed to install Tailscale"
                    log_substep "To install manually, see: ${DIM}https://tailscale.com/download/linux${RESET}"
                    log_complete
                    return
                fi
            fi
        else
            log_warning "Could not detect Ubuntu codename — using Tailscale install script"
            if curl -fsSL https://tailscale.com/install.sh | sh; then
                log_success "Tailscale installed via install script"
            else
                log_warning "Failed to install Tailscale"
                log_substep "To install manually, see: ${DIM}https://tailscale.com/download/linux${RESET}"
                log_complete
                return
            fi
        fi

        # Install the package if the repo was added (skip if install script already handled it)
        if ! command -v tailscale &> /dev/null; then
            if sudo apt-get update && sudo apt-get install -y tailscale; then
                log_success "Tailscale installed"
            else
                log_warning "Failed to install Tailscale via apt — trying official install script"
                if curl -fsSL https://tailscale.com/install.sh | sh; then
                    log_success "Tailscale installed via official install script"
                else
                    log_substep "To install manually, see: ${DIM}https://tailscale.com/download/linux${RESET}"
                    log_complete
                    return
                fi
            fi
        fi
    fi

    log_substep "Enabling tailscaled service..."
    if sudo systemctl enable --now tailscaled; then
        log_success "tailscaled service enabled and started"
    else
        log_warning "Could not enable/start tailscaled"
        log_substep "To start manually: ${DIM}sudo systemctl enable --now tailscaled${RESET}"
        log_complete
        return
    fi

    echo ""
    if confirm "Install a systemd service to auto-connect at boot?"; then
        if [[ -f "${TEMPLATES_DIR}/tailscale-autoconnect.service" ]] && [[ -f "${TEMPLATES_DIR}/tailscale-autoconnect.env.template" ]]; then
            log_substep "Installing Tailscale autoconnect configuration..."

            # Environment file (not secret)
            sudo install -m 0644 "${TEMPLATES_DIR}/tailscale-autoconnect.env.template" /etc/default/tailscale-autoconnect

            sudo install -m 0644 "${TEMPLATES_DIR}/tailscale-autoconnect.service" /etc/systemd/system/tailscale-autoconnect.service
            sudo systemctl daemon-reload
            sudo systemctl enable --now tailscale-autoconnect.service
            log_success "Tailscale autoconnect service installed (tailscale-autoconnect.service)"
            log_substep "Optional: edit ${DIM}/etc/default/tailscale-autoconnect${RESET} to add args like ${DIM}--ssh${RESET}"
        else
            log_warning "Tailscale autoconnect templates not found - skipping service install"
        fi
    else
        log_info "Skipping autoconnect service installation"
    fi

    echo ""
    if confirm "Bring Tailscale up now (connect this machine to your tailnet)?"; then
        local up_choice
        local auth_key

        echo ""
        echo -e "${WHITE}${BOLD}Tailscale login method:${RESET}"
        echo -e "${GRAY}  1)${RESET} Interactive login (recommended)"
        echo -e "${GRAY}  2)${RESET} Auth key (non-interactive)"
        echo ""
        while true; do
            prompt_user "Select (1-2)" up_choice
            case "${up_choice}" in
                1)
                    log_substep "Running: ${DIM}sudo tailscale up${RESET}"
                    if sudo tailscale up; then
                        log_success "Tailscale is up"
                    else
                        log_warning "tailscale up failed or was cancelled"
                        log_substep "To retry: ${DIM}sudo tailscale up${RESET}"
                    fi
                    break
                    ;;
                2)
                    # Security: auth key is read with terminal echo disabled (read -rs)
                    # and passed directly to tailscale up. The key is briefly visible
                    # in process listing (ps) while the command runs.
                    prompt_secret "Enter Tailscale auth key (tskey-auth-...)" auth_key
                    if [[ -z "${auth_key}" ]]; then
                        log_warning "No auth key provided; falling back to interactive login"
                        if sudo tailscale up; then
                            log_success "Tailscale is up"
                        else
                            log_warning "tailscale up failed or was cancelled"
                            log_substep "To retry: ${DIM}sudo tailscale up${RESET}"
                        fi
                    else
                        log_substep "Running: ${DIM}sudo tailscale up --authkey <hidden>${RESET}"
                        if sudo tailscale up --authkey "${auth_key}"; then
                            log_success "Tailscale is up"
                        else
                            log_warning "tailscale up failed"
                            log_substep "To retry interactively: ${DIM}sudo tailscale up${RESET}"
                        fi
                    fi
                    break
                    ;;
                *)
                    log_error "Invalid selection. Please choose 1-2."
                    ;;
            esac
        done
    else
        log_info "Tailscale installed; you can connect later"
        log_substep "To connect: ${DIM}sudo tailscale up${RESET}"
    fi

    log_complete
}

# ============================================================================
# Post-Install Validation
# ============================================================================
validate_installation() {
    log_step "Validating Installation"

    local errors=0

    # Check Sunshine binary
    log_substep "Checking Sunshine installation..."
    if command -v sunshine &> /dev/null; then
        log_success "Sunshine binary found"
    else
        log_error "Sunshine binary not found"
        ((errors++))
    fi

    # Check xorg.conf (only in headless mode)
    if [[ "${INSTALL_MODE}" == "headless" ]]; then
        log_substep "Checking xorg.conf..."
        if [[ -f "/etc/X11/xorg.conf" ]]; then
            log_success "xorg.conf exists"
            if grep -q "CustomEDID" /etc/X11/xorg.conf; then
                log_success "CustomEDID option found"
            else
                log_error "CustomEDID option not found in xorg.conf"
                ((errors++))
            fi
        else
            log_error "xorg.conf not found"
            ((errors++))
        fi

        # Check EDID file
        log_substep "Checking EDID file..."
        if [[ -f "/etc/X11/4k120.edid" ]]; then
            log_success "EDID file exists"
        else
            log_error "EDID file not found"
            ((errors++))
        fi
    else
        log_substep "Checking monitor-mode X11 configuration..."
        if [[ -f "/etc/X11/xorg.conf" ]]; then
            if sudo grep -q "DGX Spark Sunshine Setup Installer" /etc/X11/xorg.conf 2>/dev/null; then
                log_error "Installer-managed xorg.conf still exists in monitor mode"
                ((errors++))
            else
                log_warning "Custom /etc/X11/xorg.conf exists; monitor mode will not fully rely on auto-detection"
            fi
        else
            log_success "No installer-managed xorg.conf active"
        fi
    fi

    # Check Sunshine config
    log_substep "Checking Sunshine configuration..."
    if [[ -f "${SUNSHINE_CONFIG_DIR}/sunshine.conf" ]]; then
        log_success "sunshine.conf exists"
    else
        log_error "sunshine.conf not found"
        ((errors++))
    fi

    # Check systemd override
    log_substep "Checking systemd override..."
    if [[ -f "${SYSTEMD_USER_DIR}/sunshine.service.d/override.conf" ]]; then
        log_success "systemd override exists"
    else
        log_error "systemd override not found"
        ((errors++))
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_warning "Validation completed with ${errors} error(s)"
    else
        log_success "All validation checks passed"
    fi

    log_complete
}

# ============================================================================
# Final Instructions
# ============================================================================
print_final_instructions() {
    echo ""
    echo -e "${NVIDIA_GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}${BOLD}Installation Complete!${RESET}"
    echo -e "${NVIDIA_GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "${WHITE}${BOLD}Next Steps:${RESET}"
    echo ""
    echo -e "${NVIDIA_GREEN}1.${RESET} ${BOLD}Restart your system${RESET}"
    if [[ "${INSTALL_MODE}" == "headless" ]]; then
        echo -e "${GRAY}   └─${RESET} Required for X11 to load the new virtual display configuration"
    else
        echo -e "${GRAY}   └─${RESET} Recommended so group changes and session updates take effect"
        echo -e "${GRAY}   └─${RESET} Keep a monitor or HDMI dummy plug connected for sunshine to capture"
    fi
    echo -e "${GRAY}   └─${RESET} Run: ${DIM}sudo reboot${RESET}"
    echo ""
    echo -e "${NVIDIA_GREEN}2.${RESET} ${BOLD}Run the post-installation helper${RESET} ${DIM}(Recommended)${RESET}"
    echo -e "${GRAY}   └─${RESET} Run: ${DIM}./after-install.sh${RESET}"
    echo -e "${GRAY}   └─${RESET} The helper will verify your installation and guide you through setup"
    echo ""
    echo -e "${WHITE}${BOLD}What the helper does:${RESET}"
    echo -e "${GRAY}  ✓${RESET} Checks virtual display (${RESOLUTION} @ ${REFRESH_RATE}Hz)"
    echo -e "${GRAY}  ✓${RESET} Verifies Sunshine service status"
    echo -e "${GRAY}  ✓${RESET} Tests GPU encoding capabilities"
    echo -e "${GRAY}  ✓${RESET} Checks network accessibility"
    echo -e "${GRAY}  ✓${RESET} Provides troubleshooting guidance if needed"
    echo ""
    echo -e "${WHITE}${BOLD}Quick Commands:${RESET}"
    echo -e "${GRAY}  •${RESET} Interactive menu: ${DIM}./after-install.sh${RESET}"
    echo -e "${GRAY}  •${RESET} Run all checks: ${DIM}./after-install.sh --check-all${RESET}"
    echo -e "${GRAY}  •${RESET} View logs: ${DIM}./after-install.sh --logs${RESET}"
    echo ""
    echo -e "${WHITE}${BOLD}Manual Setup (if not using helper):${RESET}"
    echo -e "${GRAY}  1.${RESET} Verify display: ${DIM}xrandr${RESET}"
    echo -e "${GRAY}  2.${RESET} Start Sunshine: ${DIM}systemctl --user start sunshine${RESET}"
    echo -e "${GRAY}  3.${RESET} Configure at: ${DIM}https://localhost:47990${RESET}"
    echo -e "${GRAY}  4.${RESET} Connect with: ${DIM}Moonlight client (moonlight-stream.org)${RESET}"
    echo ""
    echo -e "${WHITE}${BOLD}Backups Saved To:${RESET}"
    echo -e "${GRAY}  •${RESET} ${BACKUP_DIR}"
    echo ""
    echo -e "${NVIDIA_GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ============================================================================
# Main Installation Flow
# ============================================================================
main() {
    # Display logo
    print_logo

    # Prerequisites
    check_prerequisites

    # Interactive configuration
    configure_install_mode
    configure_resolution
    configure_codec
    configure_bitrate
    configure_edid

    # Confirmation
    print_configuration_summary

    # Installation steps
    create_backup
    install_sunshine
    install_edid
    configure_x11
    configure_permissions
    configure_xprofile
    configure_autologin
    configure_sunshine
    validate_installation
    configure_tailscale

    # Final instructions
    print_final_instructions
}

# ============================================================================
# Entry Point
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
