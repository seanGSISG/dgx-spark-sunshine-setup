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
- Bumped the pinned fallback Sunshine `.deb` from v2025.924.154138 to
  v2026.516.143833 (verified working on GB10 / driver 580.142 / Ubuntu 24.04.4).
  The fallback is only used when the GitHub releases API is unreachable.
