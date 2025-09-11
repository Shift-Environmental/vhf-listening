# VHF Maritime Emergency Monitoring System

A GNU Radio-based VHF monitoring system that captures marine emergency communications (Channel 16) and streams audio via Icecast for real-time emergency detection and analysis.

### System Architecture

```
RTL-SDR Hardware → GNU Radio Processing → FFmpeg → Icecast Server → Web Stream
```

### Core Components
- GNU Radio Companion: Development tool, visual flowgraph environment  
- Headless GNU Radio: Production signal processing (gnuradio/options_0.py)
- RTL-SDR: Software Defined Radio hardware
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

---

# Raspberry Pi Setup Guide

## System Dependencies

Starting with a blank Raspberry Pi OS installation:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install GNU Radio and RTL-SDR tools
sudo apt install -y gnuradio gnuradio-dev gr-osmosdr rtl-sdr

# If installation fails with xtrx-dkms errors, run:
# sudo apt remove xtrx-dkms
# sudo apt autoremove
# sudo apt update && sudo apt upgrade
# Then retry the installations above

# Install FFmpeg for audio streaming  
sudo apt install -y ffmpeg

# Install Icecast server
sudo apt install -y icecast2

# Install Python development tools
sudo apt install -y python3-pip python3-venv

```

**⚠️ Reboot required** after RTL-SDR setup:
```bash
sudo reboot
```

> ### Hardware Verification
>
> #### Test RTL-SDR Connection
> ```bash
> # Check if RTL-SDR is detected
> rtl_test -t
>
> # Expected output: "Found 1 device(s): 0: Realtek, RTL2838UHIDIR..."
> # Press Ctrl+C after a few seconds of successful testing
> ```
>
> #### Test GNU Radio Installation
> ```bash
> # Launch GNU Radio test
> python3 -c "from gnuradio import gr; print('GNU Radio version:', gr.version())"
>
> # Test RTL-SDR integration
> python3 -c "import osmosdr; print('osmoSDR available')"
> ```

### Optional: Static IP Configuration
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

For GNU Radio Companion development, flowgraph customization, and parameter tuning, see the **[GNU Radio Companion Development Guide](GRC_DEVELOPMENT_GUIDE.md)**.

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
