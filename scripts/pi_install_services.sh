#!/bin/bash
# Install VHF Listening Station systemd services

echo "Installing VHF Listening Station services..."

# Stop existing services if they're running
echo "Stopping existing services..."
sudo systemctl stop vhf-ffmpeg.service 2>/dev/null || true
sudo systemctl stop vhf-gnuradio.service 2>/dev/null || true

# Copy service files to systemd directory
echo "Installing service files..."
sudo cp services/vhf-gnuradio.service /etc/systemd/system/
sudo cp services/vhf-ffmpeg.service /etc/systemd/system/

# Set correct permissions
sudo chmod 644 /etc/systemd/system/vhf-gnuradio.service
sudo chmod 644 /etc/systemd/system/vhf-ffmpeg.service

# Reload systemd
sudo systemctl daemon-reload

# Enable services (start on boot)
sudo systemctl enable vhf-gnuradio.service
sudo systemctl enable vhf-ffmpeg.service

# Start services in correct order
echo "Starting services in correct order..."
sudo systemctl start vhf-gnuradio.service
sleep 2  # Give GNU Radio time to create the pipe
sudo systemctl start vhf-ffmpeg.service

echo "Services installed and started successfully!"
echo ""
echo "To start services:"
echo "sudo systemctl start vhf-gnuradio"
echo "sudo systemctl start vhf-ffmpeg"
echo ""
echo "To check status:"
echo "sudo systemctl status vhf-gnuradio"
echo "sudo systemctl status vhf-ffmpeg"
echo ""
echo "To view logs:"
echo "journalctl -u vhf-gnuradio -f"
echo "journalctl -u vhf-ffmpeg -f"