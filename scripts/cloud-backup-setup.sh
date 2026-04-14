#!/usr/bin/env bash
# Minecraft Bedrock Server - Cloud Backup Setup
#
# Interactive script to configure offsite backups to Google Drive via rclone.
# Uses rclone's built-in OAuth client ID — no Google Cloud project needed.
#
# Usage:
#   sudo /opt/minecraft-bedrock/scripts/cloud-backup-setup.sh
#
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config

# --- Pre-flight checks ---

if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] This script must be run as root (use sudo)"
  exit 1
fi

echo ""
echo "======================================"
echo "  Cloud Backup Setup (Google Drive)"
echo "======================================"
echo ""
echo "This will configure offsite backups to your Google Drive."
echo ""
echo "Security scope:"
echo "  - Uses the 'drive.file' permission, which ONLY allows access"
echo "    to files and folders created by this backup tool."
echo "  - Cannot see or modify any of your personal Drive files."
echo "  - You can revoke access at any time from:"
echo "    https://myaccount.google.com/permissions"
echo ""

# --- Step 1: Check/install rclone ---

if ! command -v rclone &>/dev/null; then
  echo "rclone is not installed."
  read -rp "Install rclone now? [Y/n]: " install_choice
  install_choice="${install_choice:-Y}"

  if [[ "$install_choice" =~ ^[Yy] ]]; then
    echo ""
    echo "Installing rclone..."
    curl -sfL https://rclone.org/install.sh | bash
    echo ""

    if ! command -v rclone &>/dev/null; then
      echo "[ERROR] rclone installation failed"
      exit 1
    fi
    echo "rclone installed: $(rclone version | head -1)"
  else
    echo ""
    echo "rclone is required for cloud backups."
    echo "Install manually: https://rclone.org/install/"
    exit 1
  fi
else
  echo "rclone found: $(rclone version | head -1)"
fi

echo ""

# --- Step 2: Configure remote name ---

REMOTE_NAME="${CLOUD_BACKUP_REMOTE:-gdrive}"
if [[ -z "$REMOTE_NAME" ]]; then
  REMOTE_NAME="gdrive"
fi

# --- Step 3: Choose backup folder ---

DEFAULT_FOLDER="${CLOUD_BACKUP_FOLDER:-minecraft-backups}"
if [[ -z "$DEFAULT_FOLDER" ]]; then
  DEFAULT_FOLDER="minecraft-backups"
fi
read -rp "Google Drive folder name [${DEFAULT_FOLDER}]: " folder_input
BACKUP_FOLDER="${folder_input:-$DEFAULT_FOLDER}"

# --- Step 4: Authorize with Google Drive ---

RCLONE_CONF="${INSTALL_DIR}/.rclone.conf"

echo ""
echo "--------------------------------------"
echo "  Google Drive Authorization"
echo "--------------------------------------"
echo ""
echo "A browser window will open (or a URL will be shown) for you to"
echo "grant access to Google Drive with the 'drive.file' scope."
echo ""

# Detect if we can open a browser
is_headless=true
if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -z "${SSH_CONNECTION:-}" ]]; then
    is_headless=false
  fi
fi

# Create the remote config entry
rclone config create "$REMOTE_NAME" drive \
  scope drive.file \
  --config "$RCLONE_CONF" \
  --non-interactive 2>/dev/null || true

if [[ "$is_headless" == "false" ]]; then
  # Desktop: direct browser authorization
  echo "Opening browser for authorization..."
  echo ""
  rclone config reconnect "${REMOTE_NAME}:" --config "$RCLONE_CONF"
else
  # Headless: manual token flow
  echo "This appears to be a headless server (no display detected)."
  echo ""
  echo "To authorize, run this command on a computer with a web browser:"
  echo ""
  echo "  rclone authorize \"drive\" --drive-scope \"drive.file\""
  echo ""
  echo "After authorizing in the browser, rclone will print a token."
  echo "Copy the entire JSON token (starts with { and ends with })."
  echo ""
  read -rp "Paste the token here: " token_json

  if [[ -z "$token_json" ]]; then
    echo "[ERROR] No token provided"
    exit 1
  fi

  # Update the remote config with the token
  rclone config update "$REMOTE_NAME" token "$token_json" --config "$RCLONE_CONF"
fi

# --- Step 5: Set permissions on rclone config ---

chown "${SERVICE_USER}:${SERVICE_GROUP}" "$RCLONE_CONF"
chmod 600 "$RCLONE_CONF"

# --- Step 6: Test connection ---

echo ""
echo "Testing connection..."

TEST_FILE="$(mktemp)"
echo "cloud-backup-setup test $(date)" > "$TEST_FILE"

if rclone copyto --config "$RCLONE_CONF" "$TEST_FILE" "${REMOTE_NAME}:${BACKUP_FOLDER}/.connection-test"; then
  # Verify the file exists on remote
  if rclone lsf --config "$RCLONE_CONF" "${REMOTE_NAME}:${BACKUP_FOLDER}/.connection-test" &>/dev/null; then
    # Clean up test file
    rclone deletefile --config "$RCLONE_CONF" "${REMOTE_NAME}:${BACKUP_FOLDER}/.connection-test" 2>/dev/null || true
    echo "Connection test passed."
  else
    echo "[WARN] Upload succeeded but file not found on remote"
  fi
else
  echo "[ERROR] Connection test failed. Check the authorization and try again."
  rm -f "$TEST_FILE"
  exit 1
fi
rm -f "$TEST_FILE"

# --- Step 7: Update config.env ---

CONFIG_FILE="${INSTALL_DIR}/config.env"

update_config_var() {
  local var="$1"
  local value="$2"
  if grep -q "^${var}=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^${var}=.*|${var}=${value}|" "$CONFIG_FILE"
  else
    echo "${var}=${value}" >> "$CONFIG_FILE"
  fi
}

update_config_var "CLOUD_BACKUP_ENABLED" "true"
update_config_var "CLOUD_BACKUP_REMOTE" "\"${REMOTE_NAME}\""
update_config_var "CLOUD_BACKUP_FOLDER" "\"${BACKUP_FOLDER}\""

chown "${SERVICE_USER}:${SERVICE_GROUP}" "$CONFIG_FILE"

# --- Step 8: Success ---

echo ""
echo "======================================"
echo "  Cloud Backup Configured"
echo "======================================"
echo ""
echo "  Remote:   ${REMOTE_NAME} (Google Drive)"
echo "  Folder:   ${BACKUP_FOLDER}"
echo "  Scope:    drive.file (backup files only)"
echo "  Config:   ${RCLONE_CONF}"
echo ""
echo "  Backups will sync to Google Drive after each local backup."
echo ""
echo "  Retention policy:"
echo "    Past 7 days:      daily"
echo "    7 days - 1 month: 2 per week"
echo "    1 month - 1 year: monthly"
echo "    1 - 10 years:     every 6 months"
echo ""
echo "  To disable:  set CLOUD_BACKUP_ENABLED=false in ${CONFIG_FILE}"
echo "  To re-auth:  re-run this script"
echo "  To revoke:   https://myaccount.google.com/permissions"
echo ""
