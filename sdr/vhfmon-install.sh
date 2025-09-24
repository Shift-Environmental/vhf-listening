#!/bin/bash
# VHF Maritime Monitoring - Installer (template unit + small runner)
# - Uses existing .env files only; exits if none found
# - Creates /usr/local/bin/vhfmon-run.sh and /etc/systemd/system/vhfmon@.service
# - Enables instances for ENABLED=true envs
# - Prunes prior managed units (vhfmon@*.service instances) before installing template

set -e

# --- UI helpers ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check RTL-SDR driver status (0=Blog drivers, 1=Standard drivers, 2=None)
check_rtlsdr_version() {
  if ! command -v rtl_test >/dev/null; then
    return 2
  elif rtl_test -t 2>&1 | grep -q "RTL-SDR Blog"; then
    return 0
  else
    return 1
  fi
}

# --- Preconditions ---
[[ $EUID -ne 0 ]] || { log_error "Run as a regular user with sudo."; exit 1; }
command -v sudo >/dev/null || { log_error "sudo required."; exit 1; }

USER_NAME="$(whoami)"
HOME_DIR="$(eval echo ~"$USER_NAME")"
PROJECT_DIR="$HOME_DIR/vhf-listening"
CONFIG_DIR="$PROJECT_DIR/sdr/config"
RUNNER="/usr/local/bin/vhfmon-run.sh"
UNIT_TEMPLATE="/etc/systemd/system/vhfmon@.service"
MARKER="Managed-By: vhfmon-install"

log_info "VHF Maritime Monitoring - systemd installer (template + runner)"
echo

# --- Step 1: Optional driver install/upgrade ---
log_step "Checking RTL-SDR installation..."
rtlsdr_status=$(check_rtlsdr_version; echo $?)
INSTALL_RTLSDR=false
case $rtlsdr_status in
  0) log_info "RTL-SDR Blog drivers present."; read -p "Reinstall drivers? (y/N): " -r; [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_RTLSDR=true ;;
  1) log_warn "Standard drivers detected. Blog drivers recommended for V4."; read -p "Install Blog drivers? (Y/n): " -r; [[ ! $REPLY =~ ^[Nn]$ ]] && INSTALL_RTLSDR=true ;;
  2) log_info "No drivers detected. Installing Blog drivers."; INSTALL_RTLSDR=true ;;
esac

if [[ "$INSTALL_RTLSDR" == true ]]; then
  log_step "Installing RTL-SDR Blog V4 drivers..."
  sudo apt update
  sudo apt purge --auto-remove -y ^librtlsdr rtl-sdr
  sudo rm -rf /usr/bin/rtl_* /usr/local/bin/rtl_* /usr/lib/*/librtlsdr* /usr/local/lib/librtlsdr* /usr/include/rtl-sdr* /usr/local/include/rtl_*
  sudo apt autoremove -y
  echo -e 'blacklist dvb_usb_rtl28xxu\nblacklist rtl2832' | sudo tee /etc/modprobe.d/blacklist-dvb_usb_rtl28xxu.conf >/dev/null
  sudo update-initramfs -u
  sudo ldconfig
  sudo apt install -y libusb-1.0-0-dev git cmake pkg-config build-essential
  cd /tmp
  rm -rf rtl-sdr-blog
  git clone --depth 1 https://github.com/rtlsdrblog/rtl-sdr-blog || { log_error "Git clone failed"; exit 1; }
  cd rtl-sdr-blog
  mkdir build && cd build || { log_error "Failed to create build directory"; exit 1; }
  cmake ../ -DINSTALL_UDEV_RULES=ON || { log_error "CMake failed"; exit 1; }
  make -j"$(nproc)" || { log_error "Make failed"; exit 1; }
  sudo make install
  sudo cp ../rtl-sdr.rules /etc/udev/rules.d/
  sudo ldconfig
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  log_info "RTL-SDR Blog drivers installed."
fi

# --- Step 2: Dependencies ---
log_step "Installing dependencies..."
sudo apt install -y ffmpeg alsa-utils

# --- Step 3: Verify configs ---
log_step "Scanning for .env configs in $CONFIG_DIR ..."
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
if [[ ! -d "$CONFIG_DIR" ]]; then
  log_error "Failed to create directory: $CONFIG_DIR"
  exit 2
fi

shopt -s nullglob
envs=("$CONFIG_DIR"/*.env)
if (( ${#envs[@]} == 0 )); then
  log_warn "No .env files found in $CONFIG_DIR"
  log_info "Create one or more .env files, then re-run."
  exit 2
fi
log_info "Found ${#envs[@]} config(s)."
shopt -u nullglob

# --- Step 4: Prune legacy managed units ---
log_step "Pruning legacy vhfmon units..."
if systemctl list-units --state=running | grep -q "vhfmon@"; then
  log_warn "Active vhfmon@ instances detected. They will be stopped."
fi
while IFS= read -r -d '' f; do
  if [[ "$(basename "$f")" =~ ^vhfmon(@.*)?\.service$ ]] && grep -q "$MARKER" "$f" 2>/dev/null; then
    u="$(basename "$f")"
    log_info "Stopping & disabling $u"
    sudo systemctl reset-failed "$u" 2>/dev/null || true
    sudo systemctl stop "$u" 2>/dev/null || true
    sudo systemctl disable "$u" 2>/dev/null || true
    log_info "Removing $u"
    sudo rm -f "$f"
  fi
done < <(find /etc/systemd/system /lib/systemd/system -maxdepth 1 -type f -name 'vhfmon*.service' -print0)
sudo rm -f /etc/systemd/system/multi-user.target.wants/vhfmon@*.service
if compgen -G "/etc/systemd/system/vhfmon@*.service" >/dev/null; then
  log_warn "Some vhfmon@*.service files remain; manual cleanup may be needed."
fi

# --- Step 5: Write/refresh systemd template ---
log_step "Installing unit template: $UNIT_TEMPLATE"
sudo tee "$UNIT_TEMPLATE" >/dev/null <<EOF
# $MARKER
[Unit]
Description=VHF Monitor (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$CONFIG_DIR/%i.env
WorkingDirectory=$PROJECT_DIR
ExecStart=$RUNNER $CONFIG_DIR/%i.env
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- Step 6: Install/update runner script ---
log_step "Installing runner: $RUNNER"
sudo tee "$RUNNER" >/dev/null <<'EOF'
#!/bin/bash
# vhfmon-run.sh  (# Managed-By: vhfmon-install)
# Usage: vhfmon-run.sh /absolute/path/to/config.env
set -e

ENV_FILE="$1"
[[ -f "$ENV_FILE" ]] || { echo "Config not found: $ENV_FILE"; exit 1; }

set -a
source "$ENV_FILE"
set +a

CODEC=${CODEC:-opus}
BITRATE=${BITRATE:-32k}
MOUNT="${ICECAST_MOUNT_POINT}.${CODEC}"

case "${CODEC,,}" in
  opus)
    ENC_OPTS=(-c:a libopus -b:a "$BITRATE" -application voip -frame_duration 60 -f ogg -content_type application/ogg)
    ;;
  mp3)
    ENC_OPTS=(-c:a libmp3lame -b:a "$BITRATE" -ar "$RTL_OUTPUT_RATE" -content_type audio/mpeg)
    ;;
  *)
    echo "Unsupported CODEC: $CODEC"; exit 1
    ;;
esac

dev_opt=""
if [[ -n "$SDR_DEVICE_INDEX" ]]; then
  if [[ ! "$SDR_DEVICE_INDEX" =~ ^[0-9]+$ ]]; then
    echo "Error: SDR_DEVICE_INDEX must be a non-negative integer, got: $SDR_DEVICE_INDEX"
    exit 1
  fi
  dev_opt="-d $SDR_DEVICE_INDEX"
fi

echo "======================================================================"
echo "VHF Monitoring Station Starting: $(basename "$ENV_FILE" .env)"
echo "Description: ${DESCRIPTION}"
echo "Frequency: ${VHF_FREQUENCY} Hz"
echo "Device Index: ${SDR_DEVICE_INDEX:-0 (default)}"
echo "Warning: Device indices may change on reboot or USB re-plug"
echo "Codec: ${CODEC}  Bitrate: ${BITRATE}"
echo "Stream: http://${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT}"
echo "======================================================================"

exec rtl_fm $dev_opt -f "$VHF_FREQUENCY" -M fm -s "$RTL_SAMPLE_RATE" -r "$RTL_AUDIO_RATE" -E agc - \
 | ffmpeg -hide_banner -loglevel warning -f s16le -ar "$RTL_AUDIO_RATE" -ac 1 -i pipe:0 -vn \
     -filter:a "highpass=f=${AUDIO_HIGHPASS:-300},lowpass=f=${AUDIO_LOWPASS:-3000},volume=${AUDIO_VOLUME:-2.0}" \
     "${ENC_OPTS[@]}" \
     "icecast://source:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT}"
EOF
sudo chmod +x "$RUNNER"

# --- Step 7: Reload systemd, enable instances for ENABLED=true ---
log_step "Reloading systemd..."
sudo systemctl daemon-reload

# Verify template exists
if [[ ! -f "$UNIT_TEMPLATE" ]]; then
  log_error "Systemd template $UNIT_TEMPLATE not found. Installation failed."
  exit 1
fi

log_step "Configuring instances from .env files..."
enabled_any=false
for cfg in "${envs[@]}"; do
  source "$cfg"
  name="$(basename "$cfg" .env)"
  # Validate instance name
  if [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]]; then
    log_error "Invalid .env filename: $(basename "$cfg"). Use alphanumeric or hyphens only (e.g., sdr-o.env)."
    exit 1
  fi
  # Validate required variables
  required_vars=("SDR_DEVICE_INDEX" "VHF_FREQUENCY" "ICECAST_HOST" "ICECAST_PORT" "ICECAST_SOURCE_PASSWORD" "ICECAST_MOUNT_POINT")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
      log_error "Missing $var in $cfg"
      exit 1
    fi
  done
  if [[ ! "$SDR_DEVICE_INDEX" =~ ^[0-9]+$ ]]; then
    log_error "Invalid SDR_DEVICE_INDEX in $cfg; must be a non-negative integer"
    exit 1
  fi
  if grep -q "^ENABLED=true" "$cfg"; then
    log_info "Enabling vhfmon@${name}.service"
    sudo systemctl enable "vhfmon@${name}.service" || {
      log_error "Failed to enable vhfmon@${name}.service"
      exit 1
    }
    enabled_any=true
  else
    sudo systemctl disable "vhfmon@${name}.service" 2>/dev/null || true
  fi
done
$enabled_any && log_info "Enabled ENABLED instances." || log_warn "No ENABLED=true instances to enable."

# --- Step 8: Summary ---
echo
log_info "Template installed: $(basename "$UNIT_TEMPLATE")"
log_info "Runner installed:   $RUNNER"
echo "Instances available:"
for cfg in "${envs[@]}"; do echo "  - vhfmon@$(basename "$cfg" .env).service"; done
echo
log_info "Start enabled ones now with:"
echo "  sudo systemctl start vhfmon@*.service"
echo
[[ "$INSTALL_RTLSDR" == true ]] && log_warn "Drivers updated; a reboot may be needed."
log_info "Done."