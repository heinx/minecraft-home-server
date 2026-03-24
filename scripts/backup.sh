#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config

TIMESTAMP="$(date +%Y_%m_%d-%H%M%S)"
WORLD_DIR="${INSTALL_DIR}/worlds/${WORLD_NAME}"

mkdir -p "$BACKUP_DIR"

if [[ ! -d "$WORLD_DIR" ]]; then
  log_error "World directory not found: ${WORLD_DIR}"
  send_notification "Minecraft Backup Failed" "World directory not found: ${WORLD_DIR}"
  exit 1
fi

backup() {
  log_info "Backing up world '${WORLD_NAME}'"
  if ! zip -r "${BACKUP_DIR}/${WORLD_NAME}_${TIMESTAMP}.zip" "$WORLD_DIR"; then
    log_error "Failed to create world backup"
    send_notification "Minecraft Backup Failed" "Failed to zip world '${WORLD_NAME}'"
    exit 1
  fi

  log_info "Backing up server.properties"
  if [[ -f "${INSTALL_DIR}/server.properties" ]]; then
    cp "${INSTALL_DIR}/server.properties" "${BACKUP_DIR}/server.properties.${TIMESTAMP}"
  else
    log_warn "server.properties not found, skipping"
  fi
}

cleanup() {
  local keep="${BACKUP_KEEP_COUNT:-20}"
  log_info "Pruning backups, keeping ${keep} most recent"

  prune_old_files() {
    local glob_pattern="$1"
    local -a files=()

    for f in "${BACKUP_DIR}"/${glob_pattern}; do
      [[ -f "$f" ]] && files+=("$f")
    done

    if [[ ${#files[@]} -le $keep ]]; then
      return 0
    fi

    # Sort by modification time, newest first
    local -a sorted=()
    while IFS= read -r line; do
      sorted+=("$line")
    done < <(printf '%s\n' "${files[@]}" | xargs ls -1t)

    local count=0
    for f in "${sorted[@]}"; do
      count=$((count + 1))
      if [[ $count -gt $keep ]]; then
        rm -f "$f"
        log_info "Removed old backup: $(basename "$f")"
      fi
    done
  }

  prune_old_files "${WORLD_NAME}_*.zip"
  prune_old_files "server.properties.*"
}

offsite_sync() {
  if [[ "${OFFSITE_BACKUP_ENABLED:-false}" != "true" ]]; then
    return 0
  fi

  if [[ -z "${OFFSITE_BACKUP_REMOTE:-}" ]]; then
    log_warn "OFFSITE_BACKUP_REMOTE not set, skipping offsite sync"
    return 0
  fi

  if ! command -v rclone &>/dev/null; then
    log_error "rclone not found but OFFSITE_BACKUP_ENABLED=true"
    send_notification "Minecraft Offsite Backup Failed" "rclone is not installed"
    return 1
  fi

  log_info "Syncing backups to ${OFFSITE_BACKUP_REMOTE}"
  if ! rclone sync "$BACKUP_DIR" "$OFFSITE_BACKUP_REMOTE" --log-level INFO; then
    log_error "Offsite backup sync failed"
    send_notification "Minecraft Offsite Backup Failed" "rclone sync to ${OFFSITE_BACKUP_REMOTE} failed"
    return 1
  fi
  log_info "Offsite sync complete"
}

backup
cleanup
offsite_sync

log_info "Backup complete"
