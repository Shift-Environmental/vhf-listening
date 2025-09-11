#!/bin/bash
set -e

echo "=== AWS Icecast Server Automated Setup ==="
echo "This script will connect to your AWS server and install Icecast remotely"
echo

# Load configuration from .env file
if [ ! -f ".env" ]; then
    echo "❌ .env file not found in current directory"
    echo "Please run this script from the project root directory"
    exit 1
fi

echo "📝 Loading configuration from .env file..."
source .env

echo "Using configuration:"
echo "  Host: $ICECAST_HOST"
echo "  Port: $ICECAST_PORT" 
echo "  Mount: $ICECAST_MOUNT"
echo "  Source Password: $ICECAST_PASSWORD"
echo

# Verify SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key not found at: $SSH_KEY"
    echo ""
    echo "To set up AWS access:"
    echo "1. Obtain the vhf-icecast-key.pem file from your team"
    echo "2. Copy it to: $SSH_KEY"
    echo "3. Set correct permissions: chmod 600 $SSH_KEY"
    echo ""
    echo "Contact your team lead for the SSH key file if you don't have it."
    exit 1
fi

echo "🔑 SSH key found, connecting to AWS server..."
echo

# Create and execute the setup script remotely
ssh -i "$SSH_KEY" admin@"$ICECAST_HOST" \
  ICECAST_PORT="$ICECAST_PORT" \
  ICECAST_PASSWORD="$ICECAST_PASSWORD" \
  ICECAST_ADMIN_PASSWORD="$ICECAST_ADMIN_PASSWORD" \
  ICECAST_MOUNT="$ICECAST_MOUNT" \
  << EOF
set -e

echo "=== Remote Icecast Setup Starting ==="

# Update system
echo "📦 Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install required packages
echo "📦 Installing Icecast2 and dependencies..."
sudo apt install -y icecast2 curl wget ufw

# Create project directory
mkdir -p ~/vhf-icecast
cd ~/vhf-icecast

# Create .env file with configuration
echo "📝 Creating configuration file..."
cat > .env << ENVEOF
# AWS Icecast Server Configuration
ICECAST_HOST=0.0.0.0
ICECAST_PORT=$ICECAST_PORT
ICECAST_PASSWORD=$ICECAST_PASSWORD
ICECAST_ADMIN_PASSWORD=$ICECAST_ADMIN_PASSWORD
ICECAST_MOUNT=$ICECAST_MOUNT
SERVER_NAME=VHF Marine Radio Stream
SERVER_DESCRIPTION=Marine VHF Emergency Monitor
MAX_CLIENTS=100
MAX_SOURCES=5
ENVEOF

# Backup original Icecast config
sudo cp /etc/icecast2/icecast.xml /etc/icecast2/icecast.xml.backup

# Create new Icecast configuration
echo "⚙️  Configuring Icecast2..."
sudo tee /etc/icecast2/icecast.xml > /dev/null << CONFIGEOF
<icecast>
    <location>Marine VHF Monitor</location>
    <admin>admin@vhf-listening.local</admin>
    
    <limits>
        <clients>100</clients>
        <sources>5</sources>
        <queue-size>524288</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <burst-on-connect>1</burst-on-connect>
        <burst-size>65535</burst-size>
    </limits>

    <authentication>
        <source-password>$ICECAST_PASSWORD</source-password>
        <relay-password>$ICECAST_PASSWORD</relay-password>
        <admin-user>admin</admin-user>
        <admin-password>$ICECAST_ADMIN_PASSWORD</admin-password>
    </authentication>

    <hostname>localhost</hostname>

    <listen-socket>
        <port>$ICECAST_PORT</port>
        <bind-address>0.0.0.0</bind-address>
    </listen-socket>

    <mount type="normal">
        <mount-name>$ICECAST_MOUNT</mount-name>
        <username>source</username>
        <password>$ICECAST_PASSWORD</password>
        <max-listeners>50</max-listeners>
        <burst-size>65536</burst-size>
        <hidden>0</hidden>
        <no-yp>1</no-yp>
        <charset>UTF8</charset>
    </mount>

    <fileserve>1</fileserve>

    <paths>
        <basedir>/usr/share/icecast2</basedir>
        <logdir>/var/log/icecast2</logdir>
        <webroot>/usr/share/icecast2/web</webroot>
        <adminroot>/usr/share/icecast2/admin</adminroot>
        <alias source="/" destination="/status.xsl"/>
    </paths>

    <logging>
        <accesslog>access.log</accesslog>
        <errorlog>error.log</errorlog>
        <loglevel>3</loglevel>
        <logsize>10000</logsize>
    </logging>
</icecast>
CONFIGEOF

# Configure Icecast to start automatically
echo "🔧 Enabling Icecast service..."
sudo systemctl enable icecast2

# Configure firewall
echo "🔥 Configuring firewall..."
sudo ufw allow 22/tcp
sudo ufw allow $ICECAST_PORT/tcp
sudo ufw --force enable

# Start Icecast service
echo "🚀 Starting Icecast2 service..."
sudo systemctl start icecast2

# Wait and check status
sleep 3
if sudo systemctl is-active --quiet icecast2; then
    echo "✅ Icecast2 is running successfully!"
else
    echo "❌ Icecast2 failed to start. Checking logs:"
    sudo journalctl -u icecast2 --no-pager -n 10
    exit 1
fi

echo
echo "=== 🎉 SETUP COMPLETE ==="
echo "Icecast2 server is running on port $ICECAST_PORT"
echo
echo "📡 URLs:"
echo "Stream URL: http://$ICECAST_HOST:$ICECAST_PORT$ICECAST_MOUNT"
echo "Admin URL:  http://$ICECAST_HOST:$ICECAST_PORT/admin/"
echo

EOF

echo
echo "🎉 AWS Icecast server setup completed!"
echo
echo "Test stream at: http://$ICECAST_HOST:$ICECAST_PORT$ICECAST_MOUNT"
echo