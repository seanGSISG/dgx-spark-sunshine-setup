#!/usr/bin/env bash
# Branded status panel used to render the README "verified" still/GIF.
# Pure cosmetic output (no real IPs/hostnames) — safe to publish.
set -u

G=$'\033[38;5;112m'   # NVIDIA-ish green (check marks)
C=$'\033[38;5;81m'    # cyan (labels)
D=$'\033[38;5;245m'   # dim grey (detail)
B=$'\033[1m'
R=$'\033[0m'

row() { printf "  ${G}✔${R}  ${C}%-17s${R} ${B}%-16s${R} ${D}%s${R}\n" "$1" "$2" "$3"; }

printf '\033[2J\033[3J\033[H'   # clear screen + scrollback so the panel stands alone
echo

# DGX SPARK wordmark — mirrors print_logo() in install.sh (NVIDIA green)
NV=$'\033[38;5;112m'
echo -e "${NV}${B}"
echo "  ██████╗  ██████╗ ██╗  ██╗    ███████╗██████╗  █████╗ ██████╗ ██╗  ██╗"
echo "  ██╔══██╗██╔════╝ ╚██╗██╔╝    ██╔════╝██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝"
echo "  ██║  ██║██║  ███╗ ╚███╔╝     ███████╗██████╔╝███████║██████╔╝█████╔╝ "
echo "  ██║  ██║██║   ██║ ██╔██╗     ╚════██║██╔═══╝ ██╔══██║██╔══██╗██╔═██╗ "
echo "  ██████╔╝╚██████╔╝██╔╝ ██╗    ███████║██║     ██║  ██║██║  ██║██║  ██╗"
echo "  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝    ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝"
echo -e "${R}"
echo -e "  ${B}Sunshine Streaming${R}   ${D}headless 4K remote desktop · no dummy plug${R}"
echo
row "Virtual display"  "HDMI-0 / DFP-0" "3840×2160 · software EDID"
row "Encoder"          "hevc_nvenc"     "NVENC · Blackwell GB10"
row "Capture"          "X11"            "Ubuntu 24.04 · arm64"
row "Sunshine"         "active"         "Web UI :47990"
row "Auto-login"       "GDM"            "starts on every boot"
row "Remote access"    "Tailscale"      "direct P2P · MagicDNS"
echo
echo -e "  ${D}\$ ./install.sh -y${R}   ${G}one command → streaming${R}"
echo
