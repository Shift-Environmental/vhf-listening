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

# Overview

## System Architecture

```
RTL-SDR Hardware → GNU Radio Processing → FFmpeg → Icecast Server → Web Stream
```

### Core Components
- GNU Radio Companion: Development tool, visual flowgraph environment  
- Headless GNU Radio: Production signal processing (gnuradio/options_0.py)
- RTL-SDR V4: Software Defined Radio hardware
- FFmpeg: Audio encoding and streaming
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

# Install FFmpeg for audio streaming  
sudo apt install -y ffmpeg

# Install Icecast server
sudo apt install -y icecast2

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

# Update PATH to prioritize RTL-SDR Blog drivers
echo 'export PATH=/usr/local/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Reboot to apply driver changes
sudo reboot
```

## Install GNU Radio

**Only after rebooting from RTL-SDR v4 driver installation:**

```bash
# Install GNU Radio and RTL-SDR tools
sudo apt install -y gnuradio gnuradio-dev gr-osmosdr

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

## Service Installation

 The system uses two systemd services:
  - **services/vhf-gnuradio.service**: Captures and processes VHF audio

  - **services/vhf-ffmpeg.service**: Streams audio to Icecast server

  The install script will start both services and enable auto-restart
  on failure.

```bash
cd vhf-listening
chmod +x scripts/pi_install_services.sh
./scripts/pi_install_services.sh
```

> Note: Connection errors are normal until Icecast is deployed - the 
  service will automatically connect once available.


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
   sudo systemctl restart vhf-gnuradio vhf-ffmpeg
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

#### Start Services
```bash
# Start both services
sudo systemctl start vhf-gnuradio vhf-ffmpeg

# Enable auto-start on boot
sudo systemctl enable vhf-gnuradio vhf-ffmpeg
```

#### Monitor Services
```bash
# Check service status
sudo systemctl status vhf-gnuradio
sudo systemctl status vhf-ffmpeg

# View real-time logs
journalctl -u vhf-gnuradio -f
journalctl -u vhf-ffmpeg -f

# View recent logs
journalctl -u vhf-gnuradio --since "1 hour ago"
```

#### Restart Servcies
```bash
# If you need to restart services after configuration changes:
sudo systemctl restart vhf-gnuradio vhf-ffmpeg
```

#### Stop Services
```bash
sudo systemctl stop vhf-gnuradio vhf-ffmpeg
```
