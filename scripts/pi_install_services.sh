#!/bin/bash
# Install VHF Listening Station systemd service (Direct Icecast Streaming)

echo "Installing VHF Listening Station service (Direct Icecast Streaming)..."

# Stop existing services if they're running
echo "Stopping existing services..."
sudo systemctl stop vhf-ffmpeg.service 2>/dev/null || true
sudo systemctl stop vhf-gnuradio.service 2>/dev/null || true
sudo systemctl stop vhf-simple.service 2>/dev/null || true

# Disable old services (no longer needed)
echo "Disabling old services..."
sudo systemctl disable vhf-ffmpeg.service 2>/dev/null || true
sudo systemctl disable vhf-simple.service 2>/dev/null || true

# Remove old service files
echo "Cleaning up old service files..."
sudo rm -f /etc/systemd/system/vhf-ffmpeg.service
sudo rm -f /etc/systemd/system/vhf-simple.service

# Copy new service file to systemd directory
echo "Installing VHF GNU Radio service..."
sudo cp services/vhf-gnuradio.service /etc/systemd/system/

# Set correct permissions
sudo chmod 644 /etc/systemd/system/vhf-gnuradio.service

# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
echo "Enabling VHF GNU Radio service..."
sudo systemctl enable vhf-gnuradio.service

# Start service
echo "Starting VHF Listening Station (Direct Icecast Streaming)..."
sudo systemctl start vhf-gnuradio.service

# Check service status
echo "Checking service status..."
sudo systemctl status vhf-gnuradio.service

echo ""
echo "✅ VHF Listening Station installed successfully!"
echo "✅ Direct GNU Radio → Icecast streaming (no FFmpeg needed)"
echo "✅ Single service solution"
echo ""
echo "Useful commands:"
echo "Check status:    sudo systemctl status vhf-gnuradio"
echo "View logs:       journalctl -u vhf-gnuradio -f"
echo "Stop service:    sudo systemctl stop vhf-gnuradio"
echo "Start service:   sudo systemctl start vhf-gnuradio"
echo "Restart service: sudo systemctl restart vhf-gnuradio"
echo ""
echo "Stream URL: http://vhf.shiftcims.com:8888/vhf_stream.mp3"