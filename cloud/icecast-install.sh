#!/bin/bash

# Icecast Auto-Installer Script for Debian/Ubuntu
# Installs Icecast2 and generates configuration based on user input
# This script is idempotent - safe to run multiple times

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to prompt user with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    read -p "$prompt [$default]: " input
    if [[ -z "$input" ]]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

# Function to load existing configuration values
load_existing_config() {
    local config_file="/etc/icecast2/icecast.xml"
    if [[ -f "$config_file" ]]; then
        log_info "Loading existing configuration values as defaults..."
        
        # Extract existing values using xmllint if available, otherwise use sed/grep
        if command -v xmllint &> /dev/null; then
            EXISTING_HOSTNAME=$(xmllint --xpath "string(//hostname)" "$config_file" 2>/dev/null || echo "")
            EXISTING_PORT=$(xmllint --xpath "string(//listen-socket/port)" "$config_file" 2>/dev/null || echo "")
            EXISTING_SERVER_NAME=$(xmllint --xpath "string(//server-name)" "$config_file" 2>/dev/null || echo "")
            EXISTING_LOCATION=$(xmllint --xpath "string(//location)" "$config_file" 2>/dev/null || echo "")
            EXISTING_ADMIN=$(xmllint --xpath "string(//admin)" "$config_file" 2>/dev/null || echo "")
            EXISTING_MAX_CLIENTS=$(xmllint --xpath "string(//limits/clients)" "$config_file" 2>/dev/null || echo "")
            EXISTING_MAX_SOURCES=$(xmllint --xpath "string(//limits/sources)" "$config_file" 2>/dev/null || echo "")
            EXISTING_LOG_LEVEL=$(xmllint --xpath "string(//logging/loglevel)" "$config_file" 2>/dev/null || echo "")
            EXISTING_LOG_DIR=$(xmllint --xpath "string(//paths/logdir)" "$config_file" 2>/dev/null || echo "")
        else
            EXISTING_HOSTNAME=$(grep -oP '<hostname>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_PORT=$(grep -oP '<port>\K[^<]*' "$config_file" 2>/dev/null | head -1 || echo "")
            EXISTING_SERVER_NAME=$(grep -oP '<server-name>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_LOCATION=$(grep -oP '<location>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_ADMIN=$(grep -oP '<admin>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_MAX_CLIENTS=$(grep -oP '<clients>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_MAX_SOURCES=$(grep -oP '<sources>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_LOG_LEVEL=$(grep -oP '<loglevel>\K[^<]*' "$config_file" 2>/dev/null || echo "")
            EXISTING_LOG_DIR=$(grep -oP '<logdir>\K[^<]*' "$config_file" 2>/dev/null || echo "")
        fi
    fi
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root for security reasons."
    log_info "Please run as a regular user with sudo privileges."
    exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    log_error "sudo is required but not installed. Please install sudo first."
    exit 1
fi

log_info "Icecast2 Auto-Installer Starting..."
log_info "Icecast2 service will run as user: icecast"
echo

# Function to create icecast user if it doesn't exist
create_icecast_user() {
    if ! getent passwd icecast &> /dev/null; then
        log_step "Creating icecast system user..."
        if getent group icecast &> /dev/null; then
            # Group exists, create user with existing group
            sudo useradd --system --home /var/lib/icecast2 --shell /bin/false -g icecast icecast
        else
            # Create both user and group
            sudo useradd --system --home /var/lib/icecast2 --shell /bin/false --group icecast icecast
        fi
        
        # Create home directory
        sudo mkdir -p /var/lib/icecast2
        sudo chown icecast:icecast /var/lib/icecast2
        log_info "✓ Created icecast user and group"
    else
        log_info "icecast user already exists"
    fi
}

# Check if this is a reconfiguration
RECONFIGURE=false
if dpkg -l | grep -q "^ii.*icecast2"; then
    log_info "Icecast2 is already installed."
    echo
    read -p "Do you want to reconfigure Icecast2? (y/N): " reconfigure_choice
    if [[ "$reconfigure_choice" =~ ^[Yy]$ ]]; then
        RECONFIGURE=true
        log_info "Proceeding with reconfiguration..."
    else
        log_info "Exiting without changes."
        exit 0
    fi
fi

# Step 1: Update system and install Icecast2 (only if not already installed)
if [[ "$RECONFIGURE" == false ]]; then
    log_step "Installing Icecast2..."
    sudo apt update
    sudo apt install -y icecast2
else
    log_step "Icecast2 already installed, proceeding with reconfiguration..."
fi

# Step 1.5: Create icecast user if it doesn't exist
create_icecast_user

# Step 2: Stop Icecast2 service for configuration (only if running)
if sudo systemctl is-active --quiet icecast2; then
    log_step "Stopping Icecast2 service for configuration..."
    sudo systemctl stop icecast2
else
    log_step "Icecast2 service is not running..."
fi

# Step 3: Load existing configuration if available
if [[ "$RECONFIGURE" == true ]]; then
    load_existing_config
fi

# Step 4: Gather configuration information
log_step "Gathering configuration information..."
echo
log_info "Please provide the following configuration details:"
echo

# Use existing values as defaults if available, otherwise use sensible defaults
DEFAULT_HOST="${EXISTING_HOSTNAME:-$(hostname -I | awk '{print $1}')}"
DEFAULT_PORT="${EXISTING_PORT:-8000}"
DEFAULT_MAX_CLIENTS="${EXISTING_MAX_CLIENTS:-100}"
DEFAULT_MAX_SOURCES="${EXISTING_MAX_SOURCES:-2}"
DEFAULT_SERVER_NAME="${EXISTING_SERVER_NAME:-VHF Monitoring Station}"
DEFAULT_LOCATION="${EXISTING_LOCATION:-Earth}"
DEFAULT_ADMIN="${EXISTING_ADMIN:-admin@localhost}"
# Changed default log directory to be accessible by icecast user
DEFAULT_LOG_DIR="${EXISTING_LOG_DIR:-/var/log/icecast2}"
DEFAULT_LOG_LEVEL="${EXISTING_LOG_LEVEL:-3}"

# Basic server settings
prompt_with_default "Server hostname/IP (what clients will connect to)" "$DEFAULT_HOST" "SERVER_HOST"
prompt_with_default "Icecast port" "$DEFAULT_PORT" "SERVER_PORT"
prompt_with_default "Maximum number of clients" "$DEFAULT_MAX_CLIENTS" "MAX_CLIENTS"
prompt_with_default "Maximum number of sources" "$DEFAULT_MAX_SOURCES" "MAX_SOURCES"

echo
log_info "Password Configuration:"
read -p "Source password (for streaming clients to connect): " SOURCE_PASSWORD
read -p "Admin password (for web interface access): " ADMIN_PASSWORD

echo
log_info "Server Information:"
prompt_with_default "Server name (descriptive name for your station)" "${EXISTING_SERVER_NAME:-VHF Monitoring Station}" "SERVER_NAME"
prompt_with_default "Server location" "$DEFAULT_LOCATION" "SERVER_LOCATION"
prompt_with_default "Server admin email" "$DEFAULT_ADMIN" "SERVER_ADMIN"

echo
log_info "Logging Configuration:"
prompt_with_default "Log directory" "$DEFAULT_LOG_DIR" "LOG_DIR"
prompt_with_default "Log level (1=errors only, 2=warnings, 3=info, 4=debug)" "$DEFAULT_LOG_LEVEL" "LOG_LEVEL"

echo
log_info "Security & Performance:"
prompt_with_default "Enable HTTPS? (yes/no)" "no" "ENABLE_HTTPS"

# Step 5: Create backup of original config (only if it exists and we're not reconfiguring)
if [[ -f "/etc/icecast2/icecast.xml" ]]; then
    log_step "Creating backup of existing configuration..."
    sudo cp /etc/icecast2/icecast.xml /etc/icecast2/icecast.xml.backup.$(date +%Y%m%d_%H%M%S)
fi

# Step 6: Generate new configuration file
log_step "Generating Icecast2 configuration file..."

# Create temporary config file
cat > /tmp/icecast.xml << EOF
<icecast>
    <location>$SERVER_LOCATION</location>
    <admin>$SERVER_ADMIN</admin>
    <server-name>$SERVER_NAME</server-name>

    <hostname>$SERVER_HOST</hostname>

    <listen-socket>
        <port>$SERVER_PORT</port>
    </listen-socket>

    <http-headers>
        <header name="Access-Control-Allow-Origin" value="*" />
    </http-headers>

    <mount type="default">
        <public>1</public>
    </mount>

    <fileserve>1</fileserve>

    <paths>
        <basedir>/usr/share/icecast2</basedir>
        <logdir>$LOG_DIR</logdir>
        <webroot>/usr/share/icecast2/web</webroot>
        <adminroot>/usr/share/icecast2/admin</adminroot>
        <alias source="/" dest="/status.xsl"/>
    </paths>

    <logging>
        <accesslog>access.log</accesslog>
        <errorlog>error.log</errorlog>
        <loglevel>$LOG_LEVEL</loglevel>
        <logsize>10000</logsize>
    </logging>

    <security>
        <chroot>0</chroot>
        <changeowner>
            <user>icecast</user>
            <group>icecast</group>
        </changeowner>
    </security>

    <authentication>
        <source-password>$SOURCE_PASSWORD</source-password>
        <admin-user>admin</admin-user>
        <admin-password>$ADMIN_PASSWORD</admin-password>
    </authentication>

    <limits>
        <clients>$MAX_CLIENTS</clients>
        <sources>$MAX_SOURCES</sources>
        <threadpool>5</threadpool>
        <queue-size>524288</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <burst-on-connect>0</burst-on-connect>
    </limits>
</icecast>
EOF

# Step 7: Install the new configuration
log_step "Installing updated configuration..."
sudo mv /tmp/icecast.xml /etc/icecast2/icecast.xml
# Keep system config files as root:root with proper permissions
sudo chown root:root /etc/icecast2/icecast.xml
sudo chmod 644 /etc/icecast2/icecast.xml

# Step 8: Create log directory if it doesn't exist
if [[ ! -d "$LOG_DIR" ]]; then
    log_step "Creating log directory: $LOG_DIR"
    sudo mkdir -p "$LOG_DIR"
    sudo chown icecast:icecast "$LOG_DIR"
else
    log_info "Log directory already exists: $LOG_DIR"
    # Ensure correct ownership for icecast user
    sudo chown icecast:icecast "$LOG_DIR"
fi

# Step 9: Configure Icecast2 to start automatically and fix user configuration
if ! grep -q "ENABLE=true" /etc/default/icecast2; then
    log_step "Enabling Icecast2 to start automatically..."
    sudo sed -i 's/ENABLE=false/ENABLE=true/' /etc/default/icecast2
else
    log_info "Icecast2 already enabled for automatic startup."
fi

# Step 10: Configure firewall (if UFW is active and rule doesn't exist)
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    if ! sudo ufw status | grep -q "$SERVER_PORT/tcp"; then
        log_step "Configuring UFW firewall..."
        sudo ufw allow $SERVER_PORT/tcp
        log_info "Opened port $SERVER_PORT in UFW firewall"
    else
        log_info "Port $SERVER_PORT already open in UFW firewall."
    fi
else
    log_warn "UFW not active. Make sure port $SERVER_PORT is open in your firewall/security groups."
fi

# Step 11: Start Icecast2 service
log_step "Starting/restarting Icecast2 service..."
sudo systemctl restart icecast2
sudo systemctl enable icecast2

# Step 12: Verify installation
log_step "Verifying installation..."
sleep 2

if sudo systemctl is-active --quiet icecast2; then
    log_info "✓ Icecast2 is running successfully!"
else
    log_error "✗ Icecast2 failed to start. Check logs with: sudo journalctl -u icecast2"
    exit 1
fi

# Step 13: Display summary
echo
log_info "========================================="
if [[ "$RECONFIGURE" == true ]]; then
    log_info "Icecast2 Reconfiguration Complete!"
else
    log_info "Icecast2 Installation Complete!"
fi
log_info "========================================="
echo
log_info "Server Details:"
echo "  • URL: http://$SERVER_HOST:$SERVER_PORT/"
echo "  • Admin URL: http://$SERVER_HOST:$SERVER_PORT/admin/"
echo "  • Admin Username: admin"
echo "  • Admin Password: $ADMIN_PASSWORD"
echo
log_info "For Source Clients (streaming to server):"
echo "  • Server: $SERVER_HOST"
echo "  • Port: $SERVER_PORT"
echo "  • Source Password: $SOURCE_PASSWORD"
echo "  • Mount Point: Choose any (e.g., /mystream)"
echo
log_info "Service Management:"
echo "  • Start: sudo systemctl start icecast2"
echo "  • Stop: sudo systemctl stop icecast2"
echo "  • Restart: sudo systemctl restart icecast2"
echo "  • Status: sudo systemctl status icecast2"
echo "  • Logs: sudo journalctl -u icecast2 -f"
echo
log_info "Configuration file: /etc/icecast2/icecast.xml"
log_info "Log directory: $LOG_DIR"
log_info "Icecast2 service runs as user: icecast"
echo
log_warn "Remember to:"
echo "  • Open port $SERVER_PORT in your cloud provider's security groups"
echo "  • Update DNS if using a domain name"
echo "  • Consider setting up SSL/TLS for production use"
echo
log_info "Installation completed successfully!"