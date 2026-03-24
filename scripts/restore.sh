#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config

BACKUP_ZIP="${1:-}"

if [[ -z "$BACKUP_ZIP" ]]; then
  log_error "Usage: $0 <backup.zip>"
  exit 1
fi

if [[ ! -f "$BACKUP_ZIP" ]]; then
  log_error "Backup file not found: ${BACKUP_ZIP}"
  exit 1
fi

WORLD_DIR="${INSTALL_DIR}/worlds/${WORLD_NAME}"

# Derive matching server.properties backup from the zip filename timestamp.
# Expected zip format: WORLD_NAME_YYYY_MM_DD-HHMMSS.zip
BACKUP_BASENAME="$(basename "$BACKUP_ZIP")"
TIMESTAMP="${BACKUP_BASENAME#"${WORLD_NAME}_"}"
TIMESTAMP="${TIMESTAMP%.zip}"
PROPERTIES_BACKUP="${BACKUP_DIR}/server.properties.${TIMESTAMP}"

log_info "Stopping Minecraft server"
"${SCRIPT_DIR}/stop.sh" || {
  log_warn "Server may not have been running"
}
sleep 2

log_info "Restoring world '${WORLD_NAME}' from ${BACKUP_ZIP}"
if [[ -d "$WORLD_DIR" ]]; then
  log_info "Moving existing world to ${WORLD_DIR}.old"
  rm -rf "${WORLD_DIR}.old"
  mv "$WORLD_DIR" "${WORLD_DIR}.old"
fi

mkdir -p "${INSTALL_DIR}/worlds"

# The zip may contain an absolute or relative path; extract and move into place.
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

if ! unzip -o "$BACKUP_ZIP" -d "$TEMP_DIR"; then
  log_error "Failed to extract backup"
  if [[ -d "${WORLD_DIR}.old" ]]; then
    log_info "Restoring previous world"
    mv "${WORLD_DIR}.old" "$WORLD_DIR"
  fi
  exit 1
fi

# Find the extracted world directory (it may be nested under paths from the zip).
EXTRACTED=""
for candidate in "$TEMP_DIR"/**/"$WORLD_NAME" "$TEMP_DIR"/"$WORLD_NAME"; do
  if [[ -d "$candidate" ]]; then
    EXTRACTED="$candidate"
    break
  fi
done
if [[ -z "$EXTRACTED" ]]; then
  log_error "Could not find '${WORLD_NAME}' directory inside backup"
  if [[ -d "${WORLD_DIR}.old" ]]; then
    log_info "Restoring previous world"
    mv "${WORLD_DIR}.old" "$WORLD_DIR"
  fi
  exit 1
fi

mv "$EXTRACTED" "$WORLD_DIR"
log_info "World restored to ${WORLD_DIR}"

if [[ -f "$PROPERTIES_BACKUP" ]]; then
  log_info "Restoring server.properties from ${PROPERTIES_BACKUP}"
  cp "$PROPERTIES_BACKUP" "${INSTALL_DIR}/server.properties"
else
  log_info "No matching server.properties backup found (looked for ${PROPERTIES_BACKUP})"
fi

log_info "Starting Minecraft server"
"${SCRIPT_DIR}/start.sh"

log_info "Restore complete"
