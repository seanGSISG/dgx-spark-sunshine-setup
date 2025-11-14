# NVIDIA DGX Spark Sunshine Streaming Setup

Automated installer for [Sunshine](https://github.com/LizardByte/Sunshine) game streaming with virtual display configuration on NVIDIA DGX Spark (GB10) systems.

Stream your DGX Spark desktop at high quality (up to 1440p @ 120Hz or 4K @ 60Hz) without needing a physical monitor attached.

## Features

- **Virtual Display Configuration**: Creates a virtual display using NVIDIA's CustomEDID feature
- **No Physical Monitor Required**: Works completely headless using EDID emulation
- **Interactive Installation**: Guided prompts for resolution, codec, and bitrate selection
- **Automatic Backups**: All existing configurations are backed up before modification
- **Hardware-Accelerated Encoding**: Uses NVENC (NVIDIA's hardware encoder) for optimal performance
- **NVIDIA Branding**: Beautiful terminal interface with NVIDIA green color scheme

## Supported Configurations

### Display Resolutions
- **4K @ 60Hz** (3840x2160) - Maximum resolution, lower refresh rate
- **1440p @ 120Hz** (2560x1440) - **Recommended** - Best balance of quality and smoothness
- **1080p @ 120Hz** (1920x1080) - Lower resolution, maximum smoothness

### Video Codecs
- **HEVC (H.265)** - **Recommended** - Best compatibility, good compression
- **AV1** - Better compression, requires newer client devices
- **H.264** - Maximum compatibility, larger bandwidth requirements

### Bitrate Recommendations
- **LAN (Gigabit)**: 100-200 Mbps
- **LAN (Wi-Fi)**: 50-100 Mbps
- **Remote (VPN)**: 20-50 Mbps

## Hardware Limitations

The GB10's unified memory architecture has a **165 MHz pixel clock limitation**, which prevents native 4K @ 120Hz (requires ~1200 MHz pixel clock). This is a hardware constraint, not a software limitation.

**What Works**:
- ✅ 4K @ 60Hz
- ✅ 1440p @ 120Hz
- ✅ 1080p @ 120Hz

**What Doesn't Work**:
- ❌ 4K @ 120Hz (hardware limitation)

## Prerequisites

### Required
- **Hardware**: NVIDIA DGX Spark with GB10 GPU
- **OS**: Ubuntu 24.04 (or similar Debian-based distribution)
- **NVIDIA Driver**: Version 580.95.05 or newer
- **Desktop Environment**: X11-based (GDM, GNOME, etc.)
- **Auto-login**: Configured for your user account (required for headless operation)

### Automatic
The installer will automatically check for and guide you through any missing prerequisites.

## Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/seanGSISG/dgx-spark-sunshine-setup.git
cd dgx-spark-sunshine-setup

# Run the installer
./install.sh
```

### Installation Steps

The installer will:

1. **Check Prerequisites** - Verify hardware, drivers, and required software
2. **Interactive Configuration** - Prompt you to select:
   - Display resolution and refresh rate
   - Video codec (HEVC, AV1, or H.264)
   - Streaming bitrate
   - EDID source (bundled or custom)
3. **Create Backups** - Automatically backup existing configurations
4. **Install Sunshine** - Download and install the latest ARM64 build
5. **Configure Virtual Display** - Set up NVIDIA CustomEDID with your selected EDID
6. **Configure X11** - Generate and install optimized xorg.conf
7. **Configure Sunshine** - Set up hardware encoding with your preferences
8. **Validate Installation** - Verify all components are correctly installed

### Post-Installation

After running the installer:

1. **Reboot your system**
   ```bash
   sudo reboot
   ```

2. **Verify virtual display**
   ```bash
   xrandr
   # Look for your selected resolution and refresh rate
   ```

3. **Start Sunshine**
   ```bash
   systemctl --user start sunshine
   ```

4. **Configure Sunshine credentials**
   - Open: https://localhost:47990
   - Set your username and password

5. **Connect with Moonlight**
   - Download Moonlight client: https://moonlight-stream.org
   - Scan for your DGX Spark on the network
   - Enter PIN to pair

## Repository Structure

```
dgx-spark-sunshine-setup/
├── install.sh                    # Main installation script
├── edid/
│   └── samsung-q800t.bin        # Bundled EDID file (4K@60Hz, 1440p@120Hz)
├── templates/
│   ├── xorg.conf.template       # X11 configuration template
│   ├── sunshine.conf.template   # Sunshine configuration template
│   └── sunshine-override.conf   # Systemd environment variables
├── docs/
│   └── implementation-plan.md   # Detailed implementation documentation
└── README.md                    # This file
```

## Configuration Files

After installation, you'll find:

### X11 Configuration
- **Location**: `/etc/X11/xorg.conf`
- **Purpose**: Configures virtual display with CustomEDID
- **Backup**: Automatically backed up before installation

### EDID File
- **Location**: `/etc/X11/4k120.edid`
- **Purpose**: Display capability information for virtual monitor
- **Source**: Samsung Q800T HDMI 2.1 EDID (or custom)

### Sunshine Configuration
- **Location**: `~/.config/sunshine/sunshine.conf`
- **Purpose**: Streaming quality settings, encoder configuration
- **Backup**: Automatically backed up before installation

### Systemd Override
- **Location**: `~/.config/systemd/user/sunshine.service.d/override.conf`
- **Purpose**: Sets DISPLAY and XAUTHORITY environment variables
- **Auto-start**: Sunshine will start automatically on login

## Troubleshooting

### Display Not Detected

**Problem**: After reboot, xrandr doesn't show the virtual display

**Solutions**:
```bash
# Check X11 logs for errors
sudo grep -i "edid\|dfp" /var/log/Xorg.0.log

# Verify EDID file exists
ls -lh /etc/X11/4k120.edid

# Check xorg.conf syntax
sudo nvidia-xconfig --query-gpu-info
```

### Sunshine Not Starting

**Problem**: Sunshine service fails to start

**Solutions**:
```bash
# Check service status
systemctl --user status sunshine

# View logs
journalctl --user -u sunshine -f

# Verify environment variables
systemctl --user show sunshine -p Environment
```

### Connection Issues

**Problem**: Moonlight can't find or connect to the DGX Spark

**Solutions**:
```bash
# Verify Sunshine is running
systemctl --user status sunshine

# Check firewall (allow ports 47984-47990)
sudo ufw status
sudo ufw allow 47984:47990/tcp
sudo ufw allow 47998:48010/udp

# Test local connection
curl -k https://localhost:47990
```

### Low Performance / Stuttering

**Problem**: Streaming is choppy or low quality

**Solutions**:
```bash
# Check GPU utilization
nvidia-smi

# Monitor encoding performance
journalctl --user -u sunshine -f | grep -i "encoder\|fps"

# Adjust bitrate in ~/.config/sunshine/sunshine.conf
# Lower bitrate for unstable connections
# Increase bitrate for LAN with stable gigabit connection
```

### Credentials Reset

**Problem**: Forgot Sunshine username/password

**Solution**:
```bash
# Stop Sunshine
systemctl --user stop sunshine

# Remove credentials file
rm ~/.config/sunshine/sunshine_state.json

# Start Sunshine
systemctl --user start sunshine

# Reconfigure at https://localhost:47990
```

## Backups

All backups are automatically created in `~/.sunshine-setup-backups/` with timestamps:

```
~/.sunshine-setup-backups/YYYYMMDD-HHMMSS/
├── xorg.conf                    # Original X11 configuration
├── *.edid                       # Original EDID files
├── sunshine/                    # Original Sunshine configuration
└── sunshine-override.conf       # Original systemd override
```

To restore a backup:
```bash
# Navigate to backup directory
cd ~/.sunshine-setup-backups/YYYYMMDD-HHMMSS/

# Restore xorg.conf
sudo cp xorg.conf /etc/X11/xorg.conf

# Restore Sunshine config
cp -r sunshine/* ~/.config/sunshine/

# Reboot
sudo reboot
```

## Advanced Usage

### Custom EDID Files

If the bundled Samsung Q800T EDID doesn't work for your use case:

1. Extract EDID from your monitor (on another system):
   ```bash
   # Linux
   cat /sys/class/drm/card0-HDMI-A-1/edid > my-monitor.bin

   # Windows (use tools like Custom Resolution Utility)
   ```

2. Run installer and select "custom EDID" option
3. Provide path to your .bin file

**Note**: Custom EDIDs must respect GB10's 165 MHz pixel clock limitation.

### Changing Configuration

To change resolution, codec, or bitrate after installation:

1. Edit `~/.config/sunshine/sunshine.conf`
2. Restart Sunshine:
   ```bash
   systemctl --user restart sunshine
   ```

For display resolution changes, you'll need to:
1. Obtain a compatible EDID file
2. Replace `/etc/X11/4k120.edid`
3. Reboot

### Uninstalling

To remove the installation:

```bash
# Stop and disable Sunshine
systemctl --user stop sunshine
systemctl --user disable sunshine

# Remove Sunshine
sudo apt-get remove sunshine

# Restore original configurations from backup
cd ~/.sunshine-setup-backups/YYYYMMDD-HHMMSS/
sudo cp xorg.conf /etc/X11/xorg.conf

# Reboot
sudo reboot
```

## Technical Details

### Virtual Display Technology

This setup uses NVIDIA's proprietary **CustomEDID** option in xorg.conf to create a virtual display without a physical monitor. The EDID (Extended Display Identification Data) file tells the GPU what resolutions and refresh rates the "monitor" supports.

Key differences from other approaches:
- **No kernel parameters needed** - Works with NVIDIA's proprietary driver
- **No dummy HDMI plug required** - Completely virtual
- **Persistent across reboots** - Configured in X11, not runtime

### Hardware Encoding

Sunshine is configured to use NVIDIA's **NVENC** hardware encoder, which:
- Offloads video encoding from CPU to dedicated GPU hardware
- Achieves high quality at high bitrates with minimal performance impact
- Supports HEVC, H.264, and AV1 codecs
- Uses negligible VRAM (~100-200 MB)

### Performance Impact

When idle (not streaming):
- **CPU**: ~0%
- **GPU**: ~0%
- **Memory**: ~100 MB

When actively streaming 1440p @ 120Hz:
- **CPU**: ~5-10% (one core)
- **GPU**: ~10-20% (encoding only)
- **Memory**: ~200 MB
- **Network**: Based on your selected bitrate

## Contributing

This is a community project for DGX Spark users. Contributions welcome!

### Reporting Issues

Please include:
- DGX OS version (`cat /etc/dgx-release`)
- NVIDIA driver version (`nvidia-smi`)
- Selected configuration (resolution, codec, bitrate)
- Relevant logs (`journalctl --user -u sunshine`)

### Pull Requests

Improvements to the installer, documentation, or EDID files are welcome.

## Resources

### Official Documentation
- **Sunshine GitHub**: https://github.com/LizardByte/Sunshine
- **Sunshine Docs**: https://docs.lizardbyte.dev/projects/sunshine/
- **Moonlight**: https://moonlight-stream.org
- **NVIDIA DGX Spark**: https://docs.nvidia.com/dgx/dgx-spark/

### Related Playbooks
- **DGX Spark Playbooks**: https://github.com/NVIDIA/dgx-spark-playbooks
- **DGX Spark Portal**: https://build.nvidia.com/spark

### EDID Resources
- **Linux TV EDID Repository**: https://git.linuxtv.org/v4l-utils.git/tree/utils/edid-decode/data
- **EDID Decode Tool**: `apt-get install edid-decode`

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- **Sunshine/Moonlight Team** - For the excellent streaming protocol
- **NVIDIA** - For DGX Spark hardware and driver support
- **Linux TV Project** - For the EDID database
- **Community Contributors** - For testing and feedback
