# VHF Maritime Emergency Monitoring System

A GNU Radio-based VHF monitoring system that captures marine emergency communications (Channel 16) and streams audio via Icecast for real-time emergency detection and analysis.

# Table of Contents

- [Overview](#overview)
- [Raspberry Pi Setup Guide](#raspberry-pi-setup-guide)
  - [System Dependencies](#system-dependencies)
  - [RTL-SDR Blog v4 Driver Installation](#rtl-sdr-blog-v4-driver-installation)
  - [Install GNU Radio](#install-gnu-radio)
  - [Verify Installation](#verify-installation)
  - [Optional: Static IP Configuration](#optional-static-ip-configuration)
  - [Python Environment Setup](#python-environment-setup)
  - [Configuration Setup](#configuration-setup)
  - [Service Installation](#service-installation)
- [AWS Cloud Deployment](#aws-cloud-deployment)
  - [Set up SSH key](#set-up-ssh-key)
  - [Deploy AWS Icecast Server](#deploy-aws-icecast-server)
  - [Update Pi Configuration](#update-pi-configuration)
  - [Test Public Stream](#test-public-stream)
- [Development Workflow](#development-workflow)
  - [Opening GNU Radio Companion on Raspberry Pi](#opening-gnu-radio-companion-on-raspberry-pi-with-gui)
  - [Raspberry Pi Service Management](#raspberry-pi-service-management)
  - [Restoring the Custom Icecast Sink](#restoring-the-custom-icecast-sink)

# Overview

## System Architecture

```
RTL-SDR Hardware → GNU Radio Processing → Direct Icecast Streaming → Web Stream
```

### Core Components
- GNU Radio Companion: Development tool, visual flowgraph environment
- Headless GNU Radio: Production signal processing with embedded Icecast sink (gnuradio/options_0.py)
- RTL-SDR V4: Software Defined Radio hardware
- Custom Icecast Sink: Real-time MP3 encoding and direct streaming
- Icecast: Web audio streaming server

### Hardware Requirements
- RTL-SDR dongle
- VHF antenna
- Raspberry Pi or Linux system
- Internet connection for streaming

### Helpful Resources
- [GNU Radio Wiki - RTL-SDR Tutorial](https://wiki.gnuradio.org/index.php?title=RTL-SDR_FM_Receiver)
- [PySDR Guide - RTL-SDR and WSL use](https://pysdr.org/content/rtlsdr.html#ubuntu-or-ubuntu-within-wsl)
- [RTL-SDR V4 Driver Information](https://www.rtl-sdr.com/V4/)

---

# Raspberry Pi Setup Guide

## System Dependencies

Starting with a blank Raspberry Pi OS installation:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install audio streaming dependencies
sudo apt install -y libshout3-dev libvorbis-dev

# Install Python development tools
sudo apt install -y python3-pip python3-venv

```

## RTL-SDR Blog v4 Driver Installation

The v4 uses updated circuitry that requires newer drivers for proper functionality. Without these drivers, you may experience no signals, wrong frequencies, or corrupted reception.

```bash
# Remove any existing RTL-SDR drivers (if present)
sudo apt purge --auto-remove ^librtlsdr rtl-sdr
sudo rm -rf /usr/bin/rtl_* /usr/local/bin/rtl_* /usr/lib/*/librtlsdr* /usr/local/lib/librtlsdr* /usr/include/rtl-sdr* /usr/local/include/rtl_*

# Remove any existing GNU Radio and related packages (if present)
sudo apt remove --purge gnuradio gnuradio-dev gr-osmosdr soapysdr-tools soapysdr-module-rtlsdr
sudo apt autoremove

# Clear library cache
sudo ldconfig

# Install build dependencies for RTL-SDR v4 
sudo apt install -y libusb-1.0-0-dev git cmake pkg-config

# Clone and build RTL-SDR Blog v4 drivers
cd ~
git clone https://github.com/rtlsdrblog/rtl-sdr-blog
cd rtl-sdr-blog
mkdir build
cd build
cmake ../ -DINSTALL_UDEV_RULES=ON
make
sudo make install
sudo cp ../rtl-sdr.rules /etc/udev/rules.d/
sudo ldconfig

# Blacklist conflicting drivers
echo 'blacklist dvb_usb_rtl28xxu' | sudo tee --append /etc/modprobe.d/blacklist-dvb_usb_rtl28xxu.conf

# Update PATH to prioritize RTL-SDR Blog v4 executables (prevents using system rtl_test, rtl_fm, etc.)
echo 'export PATH=/usr/local/bin:$PATH' >> ~/.bashrc

# Update library path to prioritize RTL-SDR Blog v4 libraries (prevents GNU Radio from loading system librtlsdr)  
echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >> ~/.bashrc

# Apply both environment changes
source ~/.bashrc

# Reboot to apply driver changes
sudo reboot
```

## Install GNU Radio

**Only after rebooting from RTL-SDR v4 driver installation:**

```bash
# Install GNU Radio and RTL-SDR tools
sudo apt install -y gnuradio gnuradio-dev gr-osmosdr
```

> If you recieve an error: Remove the problematic xtrx-dkms package, we don't need XTRX hardware
> ```
> sudo apt remove --purge xtrx-dkms
> ```
> Fix any broken package dependencies
> ``` 
> sudo apt --fix-broken install
> ```

```bash
# Install SoapySDR RTL-SDR module for GNU Radio compatibility
sudo apt install -y soapysdr-module-rtlsdr

# Install SoapySDR tools
sudo apt install -y soapysdr-tools

# Second reboot required after GNU Radio installation:
sudo reboot
```

## Verify Installation

After reboot, test that everything works:

```bash
# Test RTL-SDR v4 detection (should show "RTL-SDR Blog V4 Detected")
rtl_test

# Test signal reception - should hear FM radio music
rtl_fm -f 101500000 -M wbfm -s 200000 -r 48000 -g 49.6 | aplay -r 48000 -f S16_LE

# Test that SoapySDR can find the RTL-SDR v4 (should show "RTL-SDR Blog V4 Detected")
SoapySDRUtil --find="driver=rtlsdr"

# Test GNU Radio installation
python3 -c "from gnuradio import gr; print('GNU Radio version:', gr.version())"
python3 -c "import osmosdr; print('osmoSDR available')"
```

## Optional: Static IP Configuration
Configure a static IP on the Raspberry Pi to ensure consistent SSH access and service reliability:

1. **Find your current network info:**
   ```bash
   ip addr show
   # Note your current IP (e.g., 192.168.0.141/24)
   
   # From Windows on same network, confirm gateway:
   # ipconfig /all
   # Look for "Default Gateway" (usually 192.168.0.1)
   ```

2. **Configure static IP via Network Manager GUI:**
   - Right-click network icon in taskbar
   - Select "Advanced Options" → "Edit Connections"
   - Select your WiFi/Ethernet connection → "Edit"
   - Go to "IPv4 Settings" tab
   - Change Method from "Automatic (DHCP)" to "Manual"
   - Click "Add" and enter:
     - **Address**: `192.168.0.200` (pick unused IP in your range)
     - **Netmask**: `255.255.255.0`
     - **Gateway**: `192.168.0.1` (or your confirmed gateway)
   - **DNS servers**: `192.168.0.1, 8.8.8.8`
   - Save and close

3. **Apply changes:**
   ```bash
   sudo reboot
   ```

4. **Verify static IP:**
   ```bash
   ip addr show
   # Should show your new static IP (e.g., 192.168.0.200)
   ```

## Python Environment Setup

```bash
# Navigate to project
cd vhf-listening

# Create Python virtual environment with system packages
python3 -m venv --system-site-packages venv
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt
```

## Configuration Setup

Before installing services, configure your environment variables. These are used by both Pi services and deployment scripts.

1. **Create your `.env` file** from the template:
   ```bash
   cp .env.default .env
   ```

2. **Edit `.env`** and fill in the values for your specific setup (AWS hostname, passwords, Pi IP address, etc.)

## Manual Testing

To test the GNU Radio pipeline manually before running as a service:

```bash
cd vhf-listening
source venv/bin/activate
gnuradio-companion gnuradio/vhfListeningGRC.grc
# Once GNU-Radio Companion opens, click "generate", then exit.
$VIRTUAL_ENV/bin/python3 gnuradio/options_0.py
```

This should show:
- RTL-SDR Blog V4 detection
- MP3 encoder initialization
- Icecast connection success
- Audio streaming to your configured Icecast server

## Service Installation

The system uses a single systemd service for direct Icecast streaming:
- **services/vhf-gnuradio.service**: Captures VHF audio and streams directly to Icecast with real-time MP3 encoding

The install script will clean up old services and install the new simplified service.

```bash
cd vhf-listening
chmod +x scripts/pi_install_services.sh
./scripts/pi_install_services.sh
```

> Note: Connection errors are normal until Icecast is deployed - the service will automatically connect once available.

---

# AWS Cloud Deployment

## Overview

For production use the Pi will stream to AWS where an Icecast server is deployed to make the VHF stream publicly accessible. 

**Prerequisites:**

- Configured AWS EC2 server
- SSH key file (`vhf-icecast-key.pem`)
- Environment variables configured (see Configuration Setup section)

## Set up SSH key
```bash
# Copy the SSH key file to your home directory:
cp /path/to/vhf-icecast-key.pem ~/.ssh/
chmod 600 ~/.ssh/vhf-icecast-key.pem
```

## Deploy AWS Icecast Server

1. **Make the setup script executable:**
   ```bash
   chmod +x scripts/aws_setup_icecast.sh
   ```

2. **Run the automated setup:**
   ```bash
   ./scripts/aws_setup_icecast.sh
   ```

   This script will:
   - Connect to your AWS server via SSH
   - Install and configure Icecast2
   - Set up firewall rules
   - Start the streaming service
   - Display the public stream URLs

## Update Pi Configuration
If any environment variables were updated during the icecast server set up, send the updates to the pi to ensure it is up to date.

1. **Deploy configuration to Pi:**
   ```bash
   ./scripts/deploy_to_pi.sh
   ```

   OR use Rustdesk.

2. **Restart Pi services:**
   ```bash
   ssh pi@192.168.0.200
   sudo systemctl restart vhf-gnuradio
   ```

## Test Public Stream

Your VHF stream will now be publicly accessible at:
```
http://your-aws-server:8888/vhf_stream.mp3
```

---

# Development Workflow

## Opening GNU Radio Companion on Raspberry Pi (with GUI)

For GNU Radio Companion development, flowgraph customization, and parameter tuning, see the **[GNU Radio Companion Development Guide](/docs/GRC_DEVELOPMENT_GUIDE.md)**.

The development guide covers:
- Understanding GNU Radio Companion blocks and variables
- GUI vs headless mode switching
- Signal processing chain explanation
- Complete variable reference for tuning
- Frequency planning and development tips

```bash
# Open the flowgraph for editting
gnuradio-companion gnuradio/vhfListeningGRC.grc
```

## Raspberry Pi Service Management

#### Start Service
```bash
# Start the VHF listening service
sudo systemctl start vhf-gnuradio

# Enable auto-start on boot
sudo systemctl enable vhf-gnuradio
```

#### Monitor Service
```bash
# Check service status
sudo systemctl status vhf-gnuradio

# View real-time logs
journalctl -u vhf-gnuradio -f

# View recent logs
journalctl -u vhf-gnuradio --since "1 hour ago"
```

#### Restart Service
```bash
# If you need to restart service after configuration changes:
sudo systemctl restart vhf-gnuradio
```

#### Stop Service
```bash
sudo systemctl stop vhf-gnuradio
```

## Restoring the Custom Icecast Sink

The VHF system uses a custom GNU Radio block for streaming audio directly to Icecast with MP3 encoding. This functionality is embedded in the GRC file as an "Embedded Python Block".

### Quick Recovery

If the custom icecast sink gets accidentally deleted:

1. **Git restore (recommended):**
   ```bash
   git checkout -- gnuradio/vhfListeningGRC.grc
   cd gnuradio && gnuradio-companion vhfListeningGRC.grc
   # Click "Generate", then exit
   ```

2. **Master copy backup:** The complete implementation is in `gnuradio/icecast_sink.py`

### For Developers

For detailed restoration instructions, manual recreation steps, and development notes, see the **[Custom Icecast Sink Development](/docs/GRC_DEVELOPMENT_GUIDE.md#custom-icecast-sink-development)** section in the GNU Radio Companion Development Guide.

**Key files to protect in git:**
- `gnuradio/vhfListeningGRC.grc` (embedded block)
- `gnuradio/icecast_sink.py` (master copy)
- `services/vhf-gnuradio.service` (RTL-SDR v4 fix)