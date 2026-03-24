#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config
check_dependencies

API_URL="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"

fetch_download_url() {
  local json
  json="$(curl -sf "$API_URL")" || {
    log_error "Failed to fetch download links from ${API_URL}"
    send_notification "Minecraft Update Failed" "Could not fetch download links from ${API_URL}"
    exit 1
  }

  local url=""
  if command -v jq &>/dev/null; then
    url="$(echo "$json" | jq -r '.result.links[] | select(.downloadType == "serverBedrockLinux") | .downloadUrl')"
  else
    url="$(echo "$json" | grep -o 'https://[^"]*bin-linux/[^"]*')"
  fi

  if [[ -z "$url" ]]; then
    log_error "Could not extract Bedrock Linux server URL from API response"
    send_notification "Minecraft Update Failed" "Could not parse download URL from API"
    exit 1
  fi

  echo "$url"
}

log_info "Checking for Bedrock server updates"
DOWNLOAD_URL="$(fetch_download_url)"
FILENAME="${DOWNLOAD_URL##*/}"
log_info "Latest version: ${FILENAME}"

if [[ -f "${INSTALL_DIR}/${FILENAME}" ]]; then
  log_info "Already up to date"
  exit 0
fi

log_info "Update available. Downloading ${DOWNLOAD_URL}"
curl -sf -o "${INSTALL_DIR}/${FILENAME}" "$DOWNLOAD_URL" || {
  log_error "Failed to download ${DOWNLOAD_URL}"
  send_notification "Minecraft Update Failed" "Download failed: ${DOWNLOAD_URL}"
  exit 1
}

log_info "Stopping Minecraft service"
if ! sudo systemctl stop minecraft; then
  log_error "Failed to stop minecraft service"
  send_notification "Minecraft Update Failed" "Could not stop minecraft service"
  exit 1
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
  send_notification "Minecraft Update Failed" "Extraction of ${FILENAME} failed"
  sudo systemctl start minecraft || true
  exit 1
fi

log_info "Restoring server.properties and config.env"
mv "${INSTALL_DIR}/server.properties.pre-update" "${INSTALL_DIR}/server.properties" 2>/dev/null || true
mv "${INSTALL_DIR}/config.env.pre-update" "${INSTALL_DIR}/config.env" 2>/dev/null || true

log_info "Starting Minecraft service"
if ! sudo systemctl start minecraft; then
  log_error "Failed to start minecraft service after update"
  send_notification "Minecraft Update Failed" "Server did not start after updating to ${FILENAME}"
  exit 1
fi

log_info "Update to ${FILENAME} complete"
