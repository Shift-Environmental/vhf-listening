# VHF Monitoring System

An SDR powered VHF monitoring system that captures radio communications and streams to an Icecast server.

## Table of Contents

-  [Overview](#overview)
   -  [System Architecture](#system-architecture)
   -  [Hardware Requirements](#hardware-requirements)
   -  [Helpful Resources](#helpful-resources)
-  [Raspberry Pi Setup Guide](#raspberry-pi-setup-guide)
   -  [RTL-SDR Blog V4 Driver Installation](#rtl-sdr-blog-v4-driver-installation)
   -  [Verify Installation](#verify-installation)
   -  [Configuration Setup](#configuration-setup)
   -  [Service Installation](#service-installation)
-  [AWS Cloud Deployment](#aws-cloud-deployment)
   -  [Overview](#overview-1)
   -  [Deploy AWS Icecast Server](#deploy-aws-icecast-server)
   -  [Update Pi Configuration](#update-pi-configuration)
   -  [Test Public Stream](#test-public-stream)
-  [Development Workflow](#development-workflow)
   -  [Raspberry Pi Service Management](#raspberry-pi-service-management)

---

## Overview

### System Architecture

```
RTL-SDR Hardware → rtl_fm (narrow FM, PPM-corrected) → ffmpeg (Opus encode) → Icecast (cloud)
```

### Hardware Requirements

-  RTL-SDR V4 dongle(s)
-  VHF antenna
-  Raspberry Pi or Linux system
-  Internet connection for streaming

### Helpful Resources

-  [RTL-SDR V4 Driver Information](https://www.rtl-sdr.com/V4/)

---

## Raspberry Pi Setup Guide

The system supports **multiple SDR dongles**, each defined with its own frequency, gain, PPM, and stream parameters.

The configuration for each dongle is a .env file in the ./config folder

For each file with ACTIVE=true, it creates a system service.

Each defined SDR will have an independent systemd service.

```
sudo install-sdr.sh
```

---

### Configuration Setup

### Multiple SDRs

-  Use `rtl_eeprom -s <serial>` to assign a unique serial to each dongle.
-  Reference the serial in each .env file so each systemd service binds to the correct device.
-  Each dongle definition spawns its own service instance, e.g., `vhfmon@ch16.service`, `vhfmon@ch70.service`.

---

### Service Installation

The installer reads `sdr-config.yml` and creates one systemd service per dongle.

Key service features:

-  **Systemd Environment** includes `PATH` and `LD_LIBRARY_PATH` so the correct drivers are used.
-  Uses **Opus** for efficient low-bitrate streaming.

Example systemd template `/etc/systemd/system/vhf-listening@.service`:

```ini
[Unit]
Description=VHF SDR Stream (%i)
After=network-online.target
Wants=network-online.target

[Service]
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="LD_LIBRARY_PATH=/usr/local/lib"
Restart=always
RestartSec=3
ExecStart=/usr/local/bin/vhf-listening-runner /etc/sdr-config.yml %i

[Install]
WantedBy=multi-user.target
```

`vhf-listening-runner` is a small wrapper script that reads the YAML, selects the dongle by `%i` (the name in the config), and launches:

```bash
rtl_fm -d "serial=${SERIAL}" -f ${FREQ_HZ} -M fm -s ${SAMPLE_RATE} -r ${AUDIO_RATE} -g ${GAIN} -p ${PPM} -l ${SQL} | ffmpeg -hide_banner -loglevel warning -f s16le -ar ${AUDIO_RATE} -ac 1 -i pipe:0   -vn -c:a libopus -b:a ${OPUS_BITRATE} -application voip -frame_duration 60 -f ogg   "icecast://source:${ICECAST_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT}.opus"
```

Install and enable:

```bash
cd vhf-listening
chmod +x scripts/pi_install_services.sh
./scripts/pi_install_services.sh
```

---

## AWS Cloud Deployment

### Overview

For production, each Pi streams to an Icecast server running on AWS.

**Prerequisites**

-  AWS EC2 server with port 8888 open
-  `sdr-config.yml` filled with Icecast host, port, and password

### Deploy AWS Icecast Server

```bash
chmod +x scripts/aws_setup_icecast.sh
./scripts/aws_setup_icecast.sh
```

The script installs Icecast2, hardens configuration, and outputs the public Opus stream URLs.

### Update Pi Configuration

If you change `sdr-config.yml`, redeploy and restart:

```bash
./scripts/deploy_to_pi.sh
ssh pi@192.168.0.200
sudo systemctl daemon-reload
sudo systemctl restart vhf-listening@ch16
sudo systemctl restart vhf-listening@ch70
```

### Test Public Stream

Example for the config above:

```
http://your-aws-server:8888/vhf-ch16.opus
http://your-aws-server:8888/vhf-ch70.opus
```
