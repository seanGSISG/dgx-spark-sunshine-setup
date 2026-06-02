# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Non-interactive install mode: `./install.sh -y` / `--yes` (or `NONINTERACTIVE=1`)
  runs unattended, taking the default for every prompt. Defaults are overridable
  via env vars: `INSTALL_MODE`, `RESOLUTION`, `REFRESH_RATE`, `CODEC`,
  `BITRATE_MBPS`, `EDID_SOURCE`, `CUSTOM_EDID_PATH`, `ENABLE_AUTOSTART`,
  `ENABLE_AUTOLOGIN`, `INSTALL_TAILSCALE`. Added `./install.sh --help`.
- README "Non-interactive install" section with an env-var override table.
- README "Tested On" section: DGX Spark (GB10), Ubuntu 24.04.4, kernel
  6.17.0-1014-nvidia, NVIDIA driver 580.142, Sunshine 2026.516.143833,
  verified 2026-06-02 (headless · 2560x1440@120 · HEVC · 100 Mbps).
- This CHANGELOG.

### Fixed
- Headless streaming showed a black screen with only a cursor: the virtual
  display forced the custom EDID onto `TV-0`, a legacy TV encoder that does not
  exist on the GB10 (real heads are `DFP-0` = HDMI and `DFP-1..4` = USB-C DP).
  With no head forced connected, the NVIDIA driver fell back to an 8x8 / 640x480
  "NULL" mode, so the desktop had no framebuffer to render to. The virtual
  display is now forced onto `DFP-0`; verified live at 3840x2160 with Sunshine
  reporting `HDMI-0 connected: true`. Removed the deprecated, ignored
  `IgnoreEDID` option.
- Web UI actions were blocked by Sunshine 2026.516+ CSRF protection ("CSRF
  protection blocked request from origin ...") when the UI was reached by
  LAN/Tailscale IP or hostname rather than `localhost`. The installer now
  auto-detects the host's global IPv4 addresses (excluding docker/bridge
  interfaces), its short/FQDN hostname, and — when Tailscale is up — its
  MagicDNS name, and writes them to `csrf_allowed_origins`. Overridable via
  `CSRF_ALLOWED_ORIGINS`.
- Generated `xorg.conf` used a domain-less `BusID` (`PCI:1:0:0`) that matched no
  device on GB10 — the GPU sits in PCI domain `000f`, and the Xorg `BusID`
  format cannot encode a non-zero PCI domain. The autologin X session failed
  with "no screens found", so `XAUTHORITY` was never propagated and Sunshine
  never started. Single-GPU systems now omit `BusID` entirely and let the NVIDIA
  driver auto-detect the GPU.
- Exported selection variables (`INSTALL_MODE`, `RESOLUTION`, `CODEC`, …) were
  unconditionally reset to empty at startup, so values pre-set in the
  environment were ignored. They now initialize with `${VAR:-}` and are honored.
- `set -eo pipefail` aborted the installer when `grep | head` / `awk | head`
  command-substitutions received SIGPIPE — which happened precisely when the
  GitHub releases API *was* reachable and a download URL was found. Guarded the
  affected pipelines with `|| true`.
- Moved `StartLimitBurst` / `StartLimitIntervalSec` from `[Service]` to `[Unit]`
  in the Sunshine user service. systemd only honors them in `[Unit]`; in
  `[Service]` they were silently ignored, disabling the restart rate-limit.

### Changed
- Headless install now backs up a pre-existing `~/.xsession` (to
  `~/.xsession.disabled-by-sunshine-setup`) before enabling GDM auto-login, so a
  stale session file (e.g. leftover `exec startxfce4`) can't hijack the intended
  GNOME-on-Xorg session.
- Bumped the pinned fallback Sunshine `.deb` from v2025.924.154138 to
  v2026.516.143833 (verified working on GB10 / driver 580.142 / Ubuntu 24.04.4).
  The fallback is only used when the GitHub releases API is unreachable.
