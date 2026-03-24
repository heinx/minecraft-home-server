#!/usr/bin/env bash
# Minecraft Bedrock Dedicated Server - Installer
# https://github.com/heinx/minecraft-home-server
#
# Usage:
#   From extracted release archive:
#     sudo ./install.sh
#     sudo ./install.sh --config /path/to/config.env
#
#   One-liner:
#     curl -sL https://github.com/heinx/minecraft-home-server/releases/latest/download/minecraft-home-server.tar.gz | tar xz && cd minecraft-home-server && sudo ./install.sh
#
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_DIRS=()

cleanup() {
  local exit_code=$?
  for dir in "${CLEANUP_DIRS[@]}"; do
    rm -rf "$dir" 2>/dev/null || true
  done
  if [[ $exit_code -ne 0 ]]; then
    echo ""
    echo "[ERROR] Installation failed (exit code ${exit_code})."
    echo "        Check the output above for details."
  fi
}
trap cleanup EXIT

# --- Logging ---

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# --- Argument parsing ---

CONFIG_FILE=""
RELEASE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --version)
      RELEASE_VERSION="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --config FILE    Path to config.env file (required for non-interactive installs)"
      echo "  --version VER    Install a specific release version of management scripts"
      echo "  -h, --help       Show this help message"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# --- Pre-flight checks ---

if [[ "$(id -u)" -ne 0 ]]; then
  log_error "This script must be run as root (use sudo)"
  exit 1
fi

check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Missing required dependency: $1"
    log_error "Install it with: apt-get install $1"
    return 1
  fi
}

log_info "Checking dependencies"
missing=0
for cmd in curl unzip zip screen; do
  if ! check_dependency "$cmd"; then
    missing=1
  fi
done
if [[ $missing -ne 0 ]]; then
  exit 1
fi

# --- Verify archive structure ---

if [[ ! -d "${SCRIPT_DIR}/scripts" || ! -d "${SCRIPT_DIR}/templates" ]]; then
  log_error "Cannot find scripts/ and templates/ directories relative to install.sh"
  log_error "Run this script from within the extracted release archive."
  exit 1
fi

# --- Load or prompt for configuration ---

load_defaults() {
  SERVER_NAME="${SERVER_NAME:-Minecraft Server}"
  WORLD_NAME="${WORLD_NAME:-world}"
  GAMEMODE="${GAMEMODE:-survival}"
  DIFFICULTY="${DIFFICULTY:-normal}"
  MAX_PLAYERS="${MAX_PLAYERS:-10}"
  VIEW_DISTANCE="${VIEW_DISTANCE:-32}"
  SERVER_PORT="${SERVER_PORT:-19132}"
  SERVER_PORTV6="${SERVER_PORTV6:-19133}"
  INSTALL_DIR="${INSTALL_DIR:-/opt/minecraft-bedrock}"
  BACKUP_DIR="${BACKUP_DIR:-/opt/minecraft-bedrock/backups}"
  SERVICE_USER="${SERVICE_USER:-minecraft}"
  SERVICE_GROUP="${SERVICE_GROUP:-minecraft}"
  BACKUP_KEEP_COUNT="${BACKUP_KEEP_COUNT:-20}"
  BACKUP_CRON="${BACKUP_CRON:-15 3 * * *}"
  OFFSITE_BACKUP_ENABLED="${OFFSITE_BACKUP_ENABLED:-false}"
  OFFSITE_BACKUP_REMOTE="${OFFSITE_BACKUP_REMOTE:-}"
  UPDATE_ENABLED="${UPDATE_ENABLED:-true}"
  UPDATE_CRON="${UPDATE_CRON:-15 4 * * *}"
  NOTIFY_ENABLED="${NOTIFY_ENABLED:-false}"
  NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
  IMPORT_WORLD="${IMPORT_WORLD:-}"
  IMPORT_SERVER_PROPERTIES="${IMPORT_SERVER_PROPERTIES:-}"
}

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local default_val="$3"
  local current_val="${!var_name}"

  read -rp "${prompt_text} [${current_val}]: " input
  if [[ -n "$input" ]]; then
    eval "${var_name}=\"${input}\""
  fi
}

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: ${CONFIG_FILE}"
    exit 1
  fi
  log_info "Loading configuration from ${CONFIG_FILE}"
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  load_defaults
elif [[ -t 0 ]]; then
  # Interactive terminal - prompt for values
  log_info "Interactive configuration (press Enter to accept defaults)"
  echo ""
  load_defaults

  prompt_value SERVER_NAME       "Server name"         "$SERVER_NAME"
  prompt_value WORLD_NAME        "World name"          "$WORLD_NAME"
  prompt_value GAMEMODE          "Game mode"            "$GAMEMODE"
  prompt_value DIFFICULTY        "Difficulty"           "$DIFFICULTY"
  prompt_value MAX_PLAYERS       "Max players"          "$MAX_PLAYERS"
  prompt_value SERVER_PORT       "Server port"          "$SERVER_PORT"
  prompt_value INSTALL_DIR       "Install directory"    "$INSTALL_DIR"
  prompt_value BACKUP_DIR        "Backup directory"     "$BACKUP_DIR"
  prompt_value SERVICE_USER      "Service user"         "$SERVICE_USER"
  prompt_value SERVICE_GROUP     "Service group"        "$SERVICE_GROUP"
  prompt_value IMPORT_WORLD      "Import world (path to dir or zip, blank to skip)" "$IMPORT_WORLD"
  prompt_value IMPORT_SERVER_PROPERTIES "Import server.properties (path, blank to skip)" "$IMPORT_SERVER_PROPERTIES"

  echo ""
else
  # Non-interactive (piped) - use defaults
  log_info "Non-interactive mode, using default configuration"
  load_defaults
fi

log_info "Configuration:"
log_info "  Server name:    ${SERVER_NAME}"
log_info "  World name:     ${WORLD_NAME}"
log_info "  Install dir:    ${INSTALL_DIR}"
log_info "  Backup dir:     ${BACKUP_DIR}"
log_info "  Service user:   ${SERVICE_USER}:${SERVICE_GROUP}"

# --- Step 1: Create service user ---

if ! id "$SERVICE_USER" &>/dev/null; then
  log_info "Creating system user '${SERVICE_USER}'"
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
else
  log_info "User '${SERVICE_USER}' already exists"
fi

if ! getent group "$SERVICE_GROUP" &>/dev/null; then
  log_info "Creating group '${SERVICE_GROUP}'"
  groupadd --system "$SERVICE_GROUP"
fi

# Allow service user to start/stop the minecraft service without a password
SUDOERS_FILE="/etc/sudoers.d/minecraft"
log_info "Configuring sudoers for ${SERVICE_USER}"
cat > "$SUDOERS_FILE" <<SUDOEOF
# Allow the minecraft service user to manage the systemd service
${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop minecraft, /usr/bin/systemctl start minecraft, /usr/bin/systemctl restart minecraft
SUDOEOF
chmod 0440 "$SUDOERS_FILE"

# --- Step 2: Create directories ---

log_info "Creating directories"
mkdir -p "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/logs"
mkdir -p "${INSTALL_DIR}/scripts"
mkdir -p "${BACKUP_DIR}"

# --- Step 3: Copy scripts ---

log_info "Installing management scripts to ${INSTALL_DIR}/scripts/"
cp -f "${SCRIPT_DIR}/scripts/"*.sh "${INSTALL_DIR}/scripts/"
chmod +x "${INSTALL_DIR}/scripts/"*.sh

# --- Step 4: Write config.env ---

if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  log_info "Copying config.env from ${CONFIG_FILE}"
  cp -f "$CONFIG_FILE" "${INSTALL_DIR}/config.env"
else
  log_info "Generating ${INSTALL_DIR}/config.env"
  cat > "${INSTALL_DIR}/config.env" <<ENVEOF
# Minecraft Bedrock Dedicated Server - Configuration
# Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')

# --- Server Settings ---
SERVER_NAME="${SERVER_NAME}"
WORLD_NAME="${WORLD_NAME}"
GAMEMODE="${GAMEMODE}"
DIFFICULTY="${DIFFICULTY}"
MAX_PLAYERS=${MAX_PLAYERS}
VIEW_DISTANCE=${VIEW_DISTANCE}
SERVER_PORT=${SERVER_PORT}
SERVER_PORTV6=${SERVER_PORTV6}

# --- Paths ---
INSTALL_DIR="${INSTALL_DIR}"
BACKUP_DIR="${BACKUP_DIR}"

# --- Service User ---
SERVICE_USER="${SERVICE_USER}"
SERVICE_GROUP="${SERVICE_GROUP}"

# --- Backups ---
BACKUP_KEEP_COUNT=${BACKUP_KEEP_COUNT}
BACKUP_CRON="${BACKUP_CRON}"

# Offsite backup via rclone (optional)
OFFSITE_BACKUP_ENABLED=${OFFSITE_BACKUP_ENABLED}
OFFSITE_BACKUP_REMOTE="${OFFSITE_BACKUP_REMOTE}"

# --- Auto-Update ---
UPDATE_ENABLED=${UPDATE_ENABLED}
UPDATE_CRON="${UPDATE_CRON}"

# --- Email Notifications (optional) ---
NOTIFY_ENABLED=${NOTIFY_ENABLED}
NOTIFY_EMAIL="${NOTIFY_EMAIL}"
ENVEOF
fi

# --- Step 5: Download Bedrock server ---

API_URL="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"

log_info "Fetching latest Bedrock server download URL"
log_info "  GET ${API_URL}"

API_RESPONSE="$(curl -sf "$API_URL")" || {
  log_error "Failed to fetch download links from ${API_URL}"
  exit 1
}

if command -v jq &>/dev/null; then
  DOWNLOAD_URL="$(echo "$API_RESPONSE" | jq -r '.result.links[] | select(.downloadType == "serverBedrockLinux") | .downloadUrl')"
else
  DOWNLOAD_URL="$(echo "$API_RESPONSE" | grep -o 'https://[^"]*bin-linux/[^"]*' || true)"
fi

if [[ -z "$DOWNLOAD_URL" ]]; then
  log_error "Could not extract Bedrock Linux server URL from API response"
  exit 1
fi

SERVER_ZIP="${DOWNLOAD_URL##*/}"
log_info "Downloading ${DOWNLOAD_URL}"
log_info "  -> ${INSTALL_DIR}/${SERVER_ZIP}"

curl -sfL -A "Mozilla/5.0" -o "${INSTALL_DIR}/${SERVER_ZIP}" "$DOWNLOAD_URL" || {
  log_error "Failed to download Bedrock server"
  exit 1
}

# --- Step 6: Extract server ---

log_info "Extracting ${SERVER_ZIP} to ${INSTALL_DIR}"
unzip -o "${INSTALL_DIR}/${SERVER_ZIP}" -d "${INSTALL_DIR}" > /dev/null

# --- Step 7: Generate server.properties ---

if [[ -n "$IMPORT_SERVER_PROPERTIES" ]]; then
  # Step 9 (handled here): import existing server.properties
  if [[ ! -f "$IMPORT_SERVER_PROPERTIES" ]]; then
    log_error "Import server.properties not found: ${IMPORT_SERVER_PROPERTIES}"
    exit 1
  fi
  log_info "Importing server.properties from ${IMPORT_SERVER_PROPERTIES}"
  cp -f "$IMPORT_SERVER_PROPERTIES" "${INSTALL_DIR}/server.properties"
else
  log_info "Generating server.properties"
  cat > "${INSTALL_DIR}/server.properties" <<PROPEOF
server-name=${SERVER_NAME}
gamemode=${GAMEMODE}
difficulty=${DIFFICULTY}
max-players=${MAX_PLAYERS}
view-distance=${VIEW_DISTANCE}
server-port=${SERVER_PORT}
server-portv6=${SERVER_PORTV6}
level-name=${WORLD_NAME}
online-mode=true
allow-cheats=false
default-player-permission-level=member
texturepack-required=false
content-log-file-enabled=false
compression-threshold=1
server-authoritative-movement=server-auth
player-movement-score-threshold=20
player-movement-action-direction-threshold=0.85
player-movement-distance-threshold=0.3
player-movement-duration-threshold-in-ms=500
correct-player-movement=false
server-authoritative-block-breaking=false
PROPEOF
fi

# --- Step 8: Import existing world ---

if [[ -n "$IMPORT_WORLD" ]]; then
  WORLD_DEST="${INSTALL_DIR}/worlds/${WORLD_NAME}"
  mkdir -p "${INSTALL_DIR}/worlds"

  if [[ -d "$IMPORT_WORLD" ]]; then
    log_info "Importing world from directory: ${IMPORT_WORLD}"
    cp -r "$IMPORT_WORLD" "$WORLD_DEST"
  elif [[ -f "$IMPORT_WORLD" && "$IMPORT_WORLD" == *.zip ]]; then
    log_info "Importing world from zip: ${IMPORT_WORLD}"
    IMPORT_TMP="$(mktemp -d)"
    CLEANUP_DIRS+=("$IMPORT_TMP")
    unzip -o "$IMPORT_WORLD" -d "$IMPORT_TMP" > /dev/null

    # Find the world directory inside the zip (look for level.dat)
    LEVEL_DAT="$(find "$IMPORT_TMP" -name "level.dat" -print -quit 2>/dev/null || true)"
    if [[ -z "$LEVEL_DAT" ]]; then
      log_error "Could not find level.dat in ${IMPORT_WORLD} - not a valid world archive"
      exit 1
    fi
    WORLD_SRC="$(dirname "$LEVEL_DAT")"
    cp -r "$WORLD_SRC" "$WORLD_DEST"
  else
    log_error "Import world path is not a directory or .zip file: ${IMPORT_WORLD}"
    exit 1
  fi
  log_info "World imported to ${WORLD_DEST}"
fi

# --- Step 10: Process templates ---

process_template() {
  local template="$1"
  local output="$2"

  if [[ ! -f "$template" ]]; then
    log_error "Template not found: ${template}"
    exit 1
  fi

  local content
  content="$(cat "$template")"
  content="${content//%%SERVICE_USER%%/${SERVICE_USER}}"
  content="${content//%%SERVICE_GROUP%%/${SERVICE_GROUP}}"
  content="${content//%%INSTALL_DIR%%/${INSTALL_DIR}}"
  content="${content//%%BACKUP_CRON%%/${BACKUP_CRON}}"
  content="${content//%%UPDATE_CRON%%/${UPDATE_CRON}}"

  echo "$content" > "$output"
}

log_info "Installing systemd service"
process_template "${SCRIPT_DIR}/templates/minecraft.service.template" "/etc/systemd/system/minecraft.service"

log_info "Installing crontab entries for ${SERVICE_USER}"
CRON_TMP="$(mktemp)"
CLEANUP_DIRS+=("$CRON_TMP")
process_template "${SCRIPT_DIR}/templates/crontab.template" "$CRON_TMP"

# Merge with existing crontab (remove old managed entries, add new ones)
EXISTING_CRON="$(crontab -u "$SERVICE_USER" -l 2>/dev/null || true)"
{
  # Keep existing entries that are not managed by us
  echo "$EXISTING_CRON" | grep -v "# Managed by minecraft-home-server" | grep -v "${INSTALL_DIR}/scripts/backup.sh" | grep -v "${INSTALL_DIR}/scripts/update.sh" || true
  # Add our entries
  cat "$CRON_TMP"
} | crontab -u "$SERVICE_USER" -

# --- Step 11: Set ownership ---

log_info "Setting ownership of ${INSTALL_DIR} to ${SERVICE_USER}:${SERVICE_GROUP}"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${BACKUP_DIR}"

# --- Step 12: Enable and start service ---

log_info "Enabling and starting minecraft service"
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft

# --- Step 13: Success ---

echo ""
echo "======================================"
echo "  Minecraft Bedrock Server installed"
echo "======================================"
echo ""
echo "  Server name:  ${SERVER_NAME}"
echo "  World name:   ${WORLD_NAME}"
echo "  Port:         ${SERVER_PORT}/UDP"
echo "  Install dir:  ${INSTALL_DIR}"
echo "  Backup dir:   ${BACKUP_DIR}"
echo "  Service user: ${SERVICE_USER}"
echo ""
echo "  Backup schedule: ${BACKUP_CRON}"
echo "  Update schedule: ${UPDATE_CRON}"
echo ""
echo "  Manage the server:"
echo "    systemctl status minecraft"
echo "    systemctl stop minecraft"
echo "    systemctl start minecraft"
echo "    journalctl -u minecraft -f"
echo ""
echo "  Server console:"
echo "    sudo -u ${SERVICE_USER} screen -r minecraft"
echo "    (detach with Ctrl-A, D)"
echo ""
echo "  Configuration: ${INSTALL_DIR}/config.env"
echo "  Logs:          ${INSTALL_DIR}/logs/"
echo ""
