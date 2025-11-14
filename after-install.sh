#!/bin/bash
# ============================================================================
# DGX Spark Sunshine - Post-Installation Helper
# ============================================================================
# Run this script after rebooting to verify installation and troubleshoot
# ============================================================================

set -e

# ============================================================================
# Colors and Formatting (NVIDIA Green Theme)
# ============================================================================
readonly NVIDIA_GREEN='\033[38;5;112m'
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
# Utility Functions
# ============================================================================
log_info() {
    echo -e "${NVIDIA_GREEN}▶${RESET} $1"
}

log_success() {
    echo -e "${BRIGHT_GREEN}✓${RESET} $1"
}

log_error() {
    echo -e "${RED}✗${RESET} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}${BOLD}$1${RESET}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

print_header() {
    clear
    echo ""
    echo -e "${NVIDIA_GREEN}${BOLD}"
    echo "  ██████╗  ██████╗ ██╗  ██╗    ███████╗██████╗  █████╗ ██████╗ ██╗  ██╗"
    echo "  ██╔══██╗██╔════╝ ╚██╗██╔╝    ██╔════╝██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝"
    echo "  ██║  ██║██║  ███╗ ╚███╔╝     ███████╗██████╔╝███████║██████╔╝█████╔╝ "
    echo "  ██║  ██║██║   ██║ ██╔██╗     ╚════██║██╔═══╝ ██╔══██║██╔══██╗██╔═██╗ "
    echo "  ██████╔╝╚██████╔╝██╔╝ ██╗    ███████║██║     ██║  ██║██║  ██║██║  ██╗"
    echo "  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝    ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${RESET}"
    echo -e "${GRAY}  Post-Installation Helper${RESET}"
    echo -e "${DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ============================================================================
# System Checks
# ============================================================================
check_virtual_display() {
    log_section "Virtual Display Status"

    if ! command -v xrandr &> /dev/null; then
        log_error "xrandr not found - X11 may not be running"
        return 1
    fi

    local xrandr_output
    xrandr_output=$(xrandr 2>&1)

    # Check for connected displays
    if echo "$xrandr_output" | grep -q "connected"; then
        log_success "Virtual display detected"
        echo ""
        echo -e "${WHITE}${BOLD}Available Modes:${RESET}"
        echo "$xrandr_output" | grep -E "^\s+[0-9]+x[0-9]+" | head -10 | while read -r line; do
            if echo "$line" | grep -q "\*"; then
                echo -e "${NVIDIA_GREEN}  → $line ${DIM}(current)${RESET}"
            else
                echo -e "${GRAY}    $line${RESET}"
            fi
        done
    else
        log_error "No virtual display detected"
        echo ""
        log_info "Troubleshooting steps:"
        echo -e "${GRAY}  1. Check X11 logs: ${DIM}sudo grep -i 'edid\|dfp' /var/log/Xorg.0.log${RESET}"
        echo -e "${GRAY}  2. Verify EDID file: ${DIM}ls -lh /etc/X11/4k120.edid${RESET}"
        echo -e "${GRAY}  3. Check xorg.conf: ${DIM}grep CustomEDID /etc/X11/xorg.conf${RESET}"
        return 1
    fi
}

check_sunshine_service() {
    log_section "Sunshine Service Status"

    if ! systemctl --user is-enabled sunshine &> /dev/null; then
        log_warning "Sunshine service is not enabled for auto-start"
        echo -e "${GRAY}  To enable: ${DIM}systemctl --user enable sunshine${RESET}"
    else
        log_success "Sunshine service is enabled for auto-start"
    fi

    echo ""

    if systemctl --user is-active sunshine &> /dev/null; then
        log_success "Sunshine service is running"

        # Check if web interface is accessible
        if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:47990 | grep -q "200\|301\|302"; then
            log_success "Web interface is accessible at https://localhost:47990"
        else
            log_warning "Web interface may not be ready yet"
        fi
    else
        log_warning "Sunshine service is not running"
        echo ""
        echo -e "${GRAY}  To start: ${DIM}systemctl --user start sunshine${RESET}"
        echo -e "${GRAY}  To check logs: ${DIM}journalctl --user -u sunshine -f${RESET}"
    fi
}

check_gpu_encoding() {
    log_section "GPU Encoding Capabilities"

    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found"
        return 1
    fi

    local gpu_name
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    log_success "GPU: $gpu_name"

    # Check for encoder sessions
    local encoder_sessions
    encoder_sessions=$(nvidia-smi --query-gpu=encoder.stats.sessionCount --format=csv,noheader 2>/dev/null || echo "N/A")

    if [[ "$encoder_sessions" != "N/A" ]]; then
        if [[ "$encoder_sessions" -gt 0 ]]; then
            log_info "Active encoding sessions: $encoder_sessions"
        else
            log_info "No active encoding sessions (idle)"
        fi
    fi

    # Show GPU utilization
    local gpu_util
    gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader)
    echo -e "${GRAY}  GPU Utilization: ${WHITE}${gpu_util}${RESET}"

    local gpu_mem
    gpu_mem=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader)
    echo -e "${GRAY}  Memory Usage: ${WHITE}${gpu_mem}${RESET}"
}

check_network_access() {
    log_section "Network Accessibility"

    # Get local IP
    local local_ip
    local_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

    if [[ -n "$local_ip" ]]; then
        log_success "Local IP: $local_ip"
        echo -e "${GRAY}  LAN Access: ${DIM}http://${local_ip}:47990${RESET}"
    fi

    # Check Tailscale
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        local tailscale_ip
        tailscale_ip=$(tailscale ip -4 2>/dev/null | head -1)
        if [[ -n "$tailscale_ip" ]]; then
            log_success "Tailscale IP: $tailscale_ip"
            local hostname
            hostname=$(hostname)
            echo -e "${GRAY}  Remote Access: ${DIM}http://${tailscale_ip}:47990${RESET}"
        fi
    else
        log_info "Tailscale not configured (optional)"
    fi

    # Check firewall
    if command -v ufw &> /dev/null; then
        if sudo ufw status 2>/dev/null | grep -q "inactive"; then
            log_info "Firewall is inactive (all ports open)"
        else
            log_info "Firewall is active - ensure ports 47984-47990 are allowed"
        fi
    fi
}

view_sunshine_logs() {
    log_section "Sunshine Logs (Last 20 Lines)"

    echo ""
    if systemctl --user is-active sunshine &> /dev/null; then
        journalctl --user -u sunshine -n 20 --no-pager | sed "s/^/${GRAY}  /"
        echo -e "${RESET}"
        echo ""
        log_info "To follow live logs: ${DIM}journalctl --user -u sunshine -f${RESET}"
    else
        log_warning "Sunshine service is not running - no logs available"
    fi
}

view_x11_logs() {
    log_section "X11 Logs (EDID/Display Related)"

    echo ""
    if [[ -f /var/log/Xorg.0.log ]]; then
        sudo grep -i "edid\|dfp\|connected\|CustomEDID" /var/log/Xorg.0.log | tail -15 | sed "s/^/${GRAY}  /"
        echo -e "${RESET}"
    else
        log_error "X11 log not found at /var/log/Xorg.0.log"
    fi
}

# ============================================================================
# Quick Actions
# ============================================================================
start_sunshine() {
    log_section "Starting Sunshine Service"
    echo ""

    if systemctl --user is-active sunshine &> /dev/null; then
        log_warning "Sunshine is already running"
        return
    fi

    log_info "Starting Sunshine..."
    systemctl --user start sunshine
    sleep 2

    if systemctl --user is-active sunshine &> /dev/null; then
        log_success "Sunshine started successfully"
        log_info "Web interface: ${DIM}https://localhost:47990${RESET}"
    else
        log_error "Failed to start Sunshine"
        log_info "Check logs: ${DIM}journalctl --user -u sunshine -n 50${RESET}"
    fi
}

restart_sunshine() {
    log_section "Restarting Sunshine Service"
    echo ""

    log_info "Restarting Sunshine..."
    systemctl --user restart sunshine
    sleep 2

    if systemctl --user is-active sunshine &> /dev/null; then
        log_success "Sunshine restarted successfully"
    else
        log_error "Failed to restart Sunshine"
    fi
}

stop_sunshine() {
    log_section "Stopping Sunshine Service"
    echo ""

    log_info "Stopping Sunshine..."
    systemctl --user stop sunshine
    sleep 1

    if ! systemctl --user is-active sunshine &> /dev/null; then
        log_success "Sunshine stopped"
    else
        log_error "Failed to stop Sunshine"
    fi
}

reset_credentials() {
    log_section "Reset Sunshine Credentials"
    echo ""

    if [[ ! -f ~/.config/sunshine/sunshine_state.json ]]; then
        log_warning "No credentials file found - Sunshine may not be configured yet"
        return
    fi

    log_warning "This will delete your current username and password"
    echo -ne "${YELLOW}?${RESET} Continue? ${DIM}[y/N]${RESET}: "
    read -r response

    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        return
    fi

    systemctl --user stop sunshine
    rm -f ~/.config/sunshine/sunshine_state.json
    log_success "Credentials file deleted"

    systemctl --user start sunshine
    sleep 2

    log_success "Sunshine restarted - configure new credentials at https://localhost:47990"
}

test_encoding() {
    log_section "Test Hardware Encoding"
    echo ""

    if ! command -v ffmpeg &> /dev/null; then
        log_error "ffmpeg not found - cannot test encoding"
        return 1
    fi

    log_info "Testing NVENC HEVC encoding (10 seconds)..."
    echo ""

    # Create a test pattern and encode with NVENC
    if ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
        -c:v hevc_nvenc -preset p7 -b:v 10M \
        -f null - 2>&1 | grep -q "frame="; then
        log_success "NVENC encoding test passed"
        log_info "Hardware encoding is working correctly"
    else
        log_error "NVENC encoding test failed"
        log_info "Check NVIDIA driver installation"
    fi
}

# ============================================================================
# Interactive Menu
# ============================================================================
show_menu() {
    echo ""
    echo -e "${NVIDIA_GREEN}${BOLD}Available Actions:${RESET}"
    echo ""
    echo -e "${GRAY}  [1]${RESET} Run all checks (recommended)"
    echo -e "${GRAY}  [2]${RESET} Check virtual display"
    echo -e "${GRAY}  [3]${RESET} Check Sunshine service"
    echo -e "${GRAY}  [4]${RESET} Check GPU encoding"
    echo -e "${GRAY}  [5]${RESET} Check network access"
    echo ""
    echo -e "${GRAY}  [6]${RESET} View Sunshine logs"
    echo -e "${GRAY}  [7]${RESET} View X11 logs"
    echo ""
    echo -e "${GRAY}  [8]${RESET} Start Sunshine"
    echo -e "${GRAY}  [9]${RESET} Restart Sunshine"
    echo -e "${GRAY}  [10]${RESET} Stop Sunshine"
    echo -e "${GRAY}  [11]${RESET} Reset credentials"
    echo -e "${GRAY}  [12]${RESET} Test hardware encoding"
    echo ""
    echo -e "${GRAY}  [q]${RESET} Quit"
    echo ""
    echo -ne "${NVIDIA_GREEN}?${RESET} Select option: "
}

run_all_checks() {
    print_header
    check_virtual_display
    check_sunshine_service
    check_gpu_encoding
    check_network_access

    echo ""
    log_section "Summary"
    echo ""
    log_info "All checks complete. Review results above."
    echo ""
    echo -e "${WHITE}${BOLD}Next Steps:${RESET}"
    echo -e "${GRAY}  1. If virtual display detected → Configure Sunshine at https://localhost:47990${RESET}"
    echo -e "${GRAY}  2. If Sunshine running → Connect with Moonlight client${RESET}"
    echo -e "${GRAY}  3. If errors → Review logs and troubleshooting steps above${RESET}"
    echo ""
}

# ============================================================================
# Main Loop
# ============================================================================
main() {
    # If argument provided, run specific command
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --check-all)
                run_all_checks
                exit 0
                ;;
            --check-display)
                check_virtual_display
                exit 0
                ;;
            --check-sunshine)
                check_sunshine_service
                exit 0
                ;;
            --start)
                start_sunshine
                exit 0
                ;;
            --restart)
                restart_sunshine
                exit 0
                ;;
            --logs)
                view_sunshine_logs
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--check-all|--check-display|--check-sunshine|--start|--restart|--logs]"
                exit 1
                ;;
        esac
    fi

    # Interactive mode
    print_header

    while true; do
        show_menu
        read -r choice

        case "$choice" in
            1) run_all_checks ;;
            2) check_virtual_display ;;
            3) check_sunshine_service ;;
            4) check_gpu_encoding ;;
            5) check_network_access ;;
            6) view_sunshine_logs ;;
            7) view_x11_logs ;;
            8) start_sunshine ;;
            9) restart_sunshine ;;
            10) stop_sunshine ;;
            11) reset_credentials ;;
            12) test_encoding ;;
            q|Q)
                echo ""
                log_info "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac

        echo ""
        echo -ne "${DIM}Press Enter to continue...${RESET}"
        read -r
        print_header
    done
}

# ============================================================================
# Entry Point
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
