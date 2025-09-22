#!/bin/bash
# VHF Maritime Monitoring - Installer (template unit + small runner)
# - Uses existing .env files only; exits if none found
# - Creates /usr/local/bin/vhfmon-run.sh and /etc/systemd/system/vhfmon@.service
# - Enables instances for ACTIVE=true envs
# - Prunes prior managed units (vhfmon@*.service instances)

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
CONFIG_DIR="$PROJECT_DIR/config"
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
  git clone --depth 1 https://github.com/rtlsdrblog/rtl-sdr-blog
  cd rtl-sdr-blog
  mkdir build && cd build
  cmake ../ -DINSTALL_UDEV_RULES=ON
  make -j"$(nproc)"
  sudo make install
  sudo cp ../rtl-sdr.rules /etc/udev/rules.d/
  sudo ldconfig
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  log_info "RTL-SDR Blog drivers installed."
fi

# --- Step 2: Dependencies ---
log_step "Installing dependencies..."
sudo apt install -y ffmpeg alsa-utils bc

# --- Step 3: Verify configs ---
log_step "Scanning for .env configs in $CONFIG_DIR ..."
if [[ ! -d "$CONFIG_DIR" ]]; then
  log_warn "Directory missing: $CONFIG_DIR"
  log_info "Create one or more .env files, then re-run."
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

# --- Step 4: Install/update runner script ---
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
if [[ -n "$SDR_SERIAL" && "$SDR_SERIAL" != "auto" ]]; then
  dev_opt="-d serial=$SDR_SERIAL"
fi

echo "========================================="
echo "VHF Monitoring Station Starting: $(basename "$ENV_FILE" .env)"
echo "Description: ${DESCRIPTION}"
mhz=$(echo "scale=3; ${VHF_FREQUENCY}/1000000" | bc -l)
echo "Frequency: ${VHF_FREQUENCY} Hz (${mhz} MHz)"
echo "Codec: ${CODEC}  Bitrate: ${BITRATE}"
echo "Stream: http://${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT}"
echo "========================================="

exec rtl_fm $dev_opt -f "$VHF_FREQUENCY" -M fm -s "$RTL_SAMPLE_RATE" -r "$RTL_OUTPUT_RATE" -g "$RTL_GAIN" \
     -p "${RTL_PPM_ERROR:-0}" -l "${RTL_SQUELCH:-0}" - \
 | ffmpeg -hide_banner -loglevel warning -f s16le -ar "$RTL_OUTPUT_RATE" -ac 1 -i pipe:0 -vn \
     -filter:a "highpass=f=${AUDIO_HIGHPASS:-300},lowpass=f=${AUDIO_LOWPASS:-3000},volume=${AUDIO_VOLUME:-2.0}" \
     "${ENC_OPTS[@]}" \
     "icecast://source:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${MOUNT}"
EOF
sudo chmod +x "$RUNNER"

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

# --- Step 6: Prune legacy managed units ---
log_step "Pruning legacy vhfmon-* unit files..."
while IFS= read -r -d '' f; do
  if grep -q "$MARKER" "$f" 2>/dev/null; then
    u="$(basename "$f")"
    log_info "Stopping & disabling $u"
    sudo systemctl stop "$u" 2>/dev/null
    sudo systemctl disable "$u" 2>/dev/null
    log_info "Removing $u"
    sudo rm -f "$f"
  fi
done < <(find /etc/systemd/system -maxdepth 1 -type f -name 'vhfmon-*.service' -print0)

# --- Step 7: Reload systemd, enable instances for ACTIVE=true ---
log_step "Reloading systemd..."
sudo systemctl daemon-reload

log_step "Configuring instances from .env files..."
enabled_any=false
for cfg in "${envs[@]}"; do
  name="$(basename "$cfg" .env)"
  if grep -q "^ACTIVE=true" "$cfg"; then
    sudo systemctl enable "vhfmon@${name}.service"
    enabled_any=true
  else
    sudo systemctl disable "vhfmon@${name}.service" 2>/dev/null
  fi
done
$enabled_any && log_info "Enabled ACTIVE instances." || log_warn "No ACTIVE=true instances to enable."

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
[[ "$INSTALL_RTLSDR" == true ]] && log_warn "Drivers updated; a reboot may help."
log_info "Done."