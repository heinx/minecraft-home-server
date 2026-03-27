#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config
check_dependencies

API_URL="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"

# Collect result — single notification sent at exit
UPDATE_SUBJECT=""
UPDATE_BODY=""

notify_and_exit() {
  local exit_code="$1"
  if [[ -n "$UPDATE_SUBJECT" ]]; then
    if [[ $exit_code -ne 0 ]] || [[ "${NOTIFY_ON_UPDATE_CHECK:-false}" == "true" ]]; then
      send_notification "$UPDATE_SUBJECT" "$UPDATE_BODY"
    elif [[ "$UPDATE_SUBJECT" == *"Successful"* ]]; then
      send_notification "$UPDATE_SUBJECT" "$UPDATE_BODY"
    fi
  fi
  exit "$exit_code"
}

fetch_download_url() {
  local json
  json="$(curl -sf "$API_URL")" || {
    log_error "Failed to fetch download links from ${API_URL}"
    UPDATE_SUBJECT="Minecraft Update Failed"
    UPDATE_BODY="Could not fetch download links from ${API_URL}"
    notify_and_exit 1
  }

  local url=""
  if command -v jq &>/dev/null; then
    url="$(echo "$json" | jq -r '.result.links[] | select(.downloadType == "serverBedrockLinux") | .downloadUrl')"
  else
    url="$(echo "$json" | grep -o 'https://[^"]*bin-linux/[^"]*')"
  fi

  if [[ -z "$url" ]]; then
    log_error "Could not extract Bedrock Linux server URL from API response"
    UPDATE_SUBJECT="Minecraft Update Failed"
    UPDATE_BODY="Could not parse download URL from API"
    notify_and_exit 1
  fi

  echo "$url"
}

log_info "Checking for Bedrock server updates"
DOWNLOAD_URL="$(fetch_download_url)"

if ! validate_download_url "$DOWNLOAD_URL"; then
  UPDATE_SUBJECT="Minecraft Update Failed"
  UPDATE_BODY="Download URL failed validation: ${DOWNLOAD_URL}"
  notify_and_exit 1
fi

FILENAME="${DOWNLOAD_URL##*/}"
log_info "Latest version: ${FILENAME}"

if [[ -f "${INSTALL_DIR}/${FILENAME}" ]]; then
  log_info "Already up to date"
  UPDATE_SUBJECT="Minecraft Update Check"
  UPDATE_BODY="Server is already up to date (${FILENAME})"
  notify_and_exit 0
fi

log_info "Update available. Downloading ${DOWNLOAD_URL}"
curl -sfL -A "Mozilla/5.0" -o "${INSTALL_DIR}/${FILENAME}" "$DOWNLOAD_URL" || {
  log_error "Failed to download ${DOWNLOAD_URL}"
  UPDATE_SUBJECT="Minecraft Update Failed"
  UPDATE_BODY="Download failed: ${DOWNLOAD_URL}"
  notify_and_exit 1
}

log_info "Stopping Minecraft service"
if ! sudo systemctl stop minecraft; then
  log_error "Failed to stop minecraft service"
  UPDATE_SUBJECT="Minecraft Update Failed"
  UPDATE_BODY="Could not stop minecraft service"
  notify_and_exit 1
fi

log_info "Backing up server.properties and config.env"
cp "${INSTALL_DIR}/server.properties" "${INSTALL_DIR}/server.properties.pre-update" 2>/dev/null || true
cp "${INSTALL_DIR}/config.env" "${INSTALL_DIR}/config.env.pre-update" 2>/dev/null || true

log_info "Extracting ${FILENAME}"
if ! unzip -o "${INSTALL_DIR}/${FILENAME}" -d "${INSTALL_DIR}"; then
  log_error "Failed to extract update"
  log_info "Restoring server.properties"
  mv "${INSTALL_DIR}/server.properties.pre-update" "${INSTALL_DIR}/server.properties" 2>/dev/null || true
  mv "${INSTALL_DIR}/config.env.pre-update" "${INSTALL_DIR}/config.env" 2>/dev/null || true
  sudo systemctl start minecraft || true
  UPDATE_SUBJECT="Minecraft Update Failed"
  UPDATE_BODY="Extraction of ${FILENAME} failed"
  notify_and_exit 1
fi

log_info "Restoring server.properties and config.env"
mv "${INSTALL_DIR}/server.properties.pre-update" "${INSTALL_DIR}/server.properties" 2>/dev/null || true
mv "${INSTALL_DIR}/config.env.pre-update" "${INSTALL_DIR}/config.env" 2>/dev/null || true

log_info "Starting Minecraft service"
if ! sudo systemctl start minecraft; then
  log_error "Failed to start minecraft service after update"
  UPDATE_SUBJECT="Minecraft Update Failed"
  UPDATE_BODY="Server did not start after updating to ${FILENAME}"
  notify_and_exit 1
fi

log_info "Update to ${FILENAME} complete"
UPDATE_SUBJECT="Minecraft Update Successful"
UPDATE_BODY="Server updated to ${FILENAME} and is running."
notify_and_exit 0
