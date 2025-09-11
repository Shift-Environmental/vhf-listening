#!/bin/bash
# Deploy VHF Listening Station to Raspberry Pi
# Usage: ./deploy_to_pi.sh
# 
# Configuration: Edit .env file to set PI_HOST and PROJECT_DIR
# Files to copy: Comment out any scp lines below for files you don't want to deploy
# WARNING: This will overwrite existing files on the Pi

# Load configuration from .env file
if [ ! -f ".env" ]; then
    echo "❌ .env file not found in current directory"
    echo "Please create .env file with PI_HOST and PROJECT_DIR variables"
    exit 1
fi

source .env

# Check required variables
if [ -z "$PI_HOST" ]; then
    echo "❌ PI_HOST not set in .env file"
    echo "Please add: PI_HOST=pi@192.168.0.200"
    exit 1
fi

if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="vhf-listening"
    echo "ℹ️  PROJECT_DIR not set, using default: $PROJECT_DIR"
fi

echo "Deploying VHF Listening Station to Raspberry Pi..."
echo "Password: raspberry"

# Create project directory on Pi
echo "Creating project directory on Pi..."
ssh $PI_HOST "mkdir -p ~/$PROJECT_DIR/{docs,gnuradio,services,scripts}"

# Copy essential files
echo "Copying files to Pi..."
# Configuration and main files
scp .env $PI_HOST:~/$PROJECT_DIR/
scp README.md $PI_HOST:~/$PROJECT_DIR/
scp requirements.txt $PI_HOST:~/$PROJECT_DIR/

# Documentation
scp docs/GRC_DEVELOPMENT_GUIDE.md $PI_HOST:~/$PROJECT_DIR/docs/

# GNU Radio files
scp gnuradio/options_0.py $PI_HOST:~/$PROJECT_DIR/gnuradio/
scp gnuradio/vhfListeningGRC.grc $PI_HOST:~/$PROJECT_DIR/gnuradio/

# Service files
scp services/vhf-gnuradio.service $PI_HOST:~/$PROJECT_DIR/services/
scp services/vhf-ffmpeg.service $PI_HOST:~/$PROJECT_DIR/services/

# Scripts
scp scripts/pi_install_services.sh $PI_HOST:~/$PROJECT_DIR/scripts/

echo "Files copied successfully!"
echo ""
echo "Next steps on the Pi:"
echo "1. ssh $PI_HOST"
echo "2. cd $PROJECT_DIR"
echo "3. Install services: ./scripts/pi_install_services.sh"
echo "4. Start services: sudo systemctl start vhf-gnuradio vhf-ffmpeg"
echo "5. Check status: sudo systemctl status vhf-gnuradio"