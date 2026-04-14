#!/usr/bin/env bash
# Cloud backup functions for offsite Google Drive backups via rclone.
#
# Sourced by backup.sh. The main entry point is cloud_backup().
# All failures are caught internally — cloud backup never fails the local backup.

# --- Configuration helpers ---

rclone_conf_path() {
  echo "${INSTALL_DIR}/.rclone.conf"
}

# Parse YYYY_MM_DD-HHMMSS timestamp from a backup filename and print epoch seconds.
# Usage: parse_backup_epoch "world_2025_01_15-120000.zip"
parse_backup_epoch() {
  local filename="$1"

  # Extract the timestamp portion: YYYY_MM_DD-HHMMSS
  local ts
  ts="$(echo "$filename" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}-[0-9]{6}')" || return 1
  [[ -z "$ts" ]] && return 1

  # Convert to "YYYY-MM-DD HH:MM:SS" for date parsing
  local y="${ts:0:4}" mo="${ts:5:2}" d="${ts:8:2}"
  local H="${ts:11:2}" M="${ts:13:2}" S="${ts:15:2}"
  local formatted="${y}-${mo}-${d} ${H}:${M}:${S}"

  # GNU date (Linux)
  date -d "$formatted" +%s 2>/dev/null && return 0
  # BSD date (macOS) — fallback for development
  date -j -f "%Y-%m-%d %H:%M:%S" "$formatted" +%s 2>/dev/null && return 0
  return 1
}

# --- Retention policy ---

# Determine which retention bucket a backup belongs to based on its age.
# Prints a bucket key (e.g. "d3", "w1", "m5") or "expired".
# Usage: retention_bucket <age_in_seconds>
retention_bucket() {
  local age_secs="$1"

  local day=$((86400))
  local age_days=$((age_secs / day))

  if [[ $age_days -lt 7 ]]; then
    # Tier 1: daily for past 7 days — one bucket per day
    echo "d${age_days}"
  elif [[ $age_days -lt 28 ]]; then
    # Tier 2: ~2 per week for days 7-27 — bucket every 3.5 days
    # Use half-days for integer math: bucket = (age_days - 7) * 2 / 7
    local offset=$(( (age_days - 7) * 2 / 7 ))
    echo "w${offset}"
  elif [[ $age_days -lt 365 ]]; then
    # Tier 3: monthly for days 28-364 — bucket every ~30 days
    local offset=$(( (age_days - 28) / 30 ))
    echo "m${offset}"
  elif [[ $age_days -lt 3650 ]]; then
    # Tier 4: every 6 months for 1-10 years — bucket every ~182 days
    local offset=$(( (age_days - 365) / 182 ))
    echo "h${offset}"
  else
    # Older than 10 years — mark for deletion
    echo "expired"
  fi
}

# Pure retention function. Reads epoch;filename lines from stdin,
# prints filenames that should be DELETED to stdout.
#
# For each retention bucket, keeps the newest file and marks the rest
# for deletion. Files older than 10 years are always deleted.
#
# Usage: echo -e "1704067200;world_2024_01_01-000000.zip\n..." | compute_cloud_retention
compute_cloud_retention() {
  local now
  now="$(date +%s)"

  # Build augmented list: bucket;epoch;filename
  local augmented=""
  while IFS=';' read -r epoch filename; do
    [[ -z "$epoch" || -z "$filename" ]] && continue

    local age_secs=$((now - epoch))
    # Negative age means future timestamp — keep it (treat as day 0)
    if [[ $age_secs -lt 0 ]]; then
      age_secs=0
    fi

    local bucket
    bucket="$(retention_bucket "$age_secs")"
    augmented+="${bucket};${epoch};${filename}"$'\n'
  done

  [[ -z "$augmented" ]] && return 0

  # Sort by bucket (group same-bucket entries), then by epoch descending
  # (newest first within each bucket). First entry per bucket is kept.
  local sorted
  sorted="$(echo "$augmented" | sort -t';' -k1,1 -k2,2nr)"

  local prev_bucket=""
  while IFS=';' read -r bucket epoch filename; do
    [[ -z "$bucket" ]] && continue
    if [[ "$bucket" == "expired" ]]; then
      echo "$filename"
    elif [[ "$bucket" != "$prev_bucket" ]]; then
      # Newest entry for this bucket — keep it
      prev_bucket="$bucket"
    else
      # Extra entry in same bucket — delete it
      echo "$filename"
    fi
  done <<< "$sorted"
}

# --- Upload and prune ---

# Upload a single file to the cloud backup remote.
cloud_backup_upload() {
  local local_file="$1"
  local conf
  conf="$(rclone_conf_path)"

  local remote_path="${CLOUD_BACKUP_REMOTE}:${CLOUD_BACKUP_FOLDER}/$(basename "$local_file")"
  log_info "Uploading $(basename "$local_file") to ${remote_path}"

  rclone copyto --config "$conf" "$local_file" "$remote_path"
}

# Apply the retention policy to remote backups.
cloud_backup_prune() {
  local conf
  conf="$(rclone_conf_path)"
  local remote="${CLOUD_BACKUP_REMOTE}:${CLOUD_BACKUP_FOLDER}"

  log_info "Checking cloud backup retention policy"

  # List all files on remote (names only)
  local file_list
  file_list="$(rclone lsf --config "$conf" "$remote" 2>/dev/null)" || {
    log_warn "Could not list remote files for retention pruning"
    return 0
  }

  [[ -z "$file_list" ]] && return 0

  # Build epoch;filename input for compute_cloud_retention
  local retention_input=""
  while IFS= read -r filename; do
    [[ -z "$filename" ]] && continue
    # Only process world backup zips (skip server.properties backups)
    if [[ "$filename" == *.zip ]]; then
      local epoch
      epoch="$(parse_backup_epoch "$filename")" || continue
      retention_input+="${epoch};${filename}"$'\n'
    fi
  done <<< "$file_list"

  [[ -z "$retention_input" ]] && return 0

  # Compute which files to delete
  local to_delete
  to_delete="$(echo "$retention_input" | compute_cloud_retention)"

  [[ -z "$to_delete" ]] && {
    log_info "No cloud backups to prune"
    return 0
  }

  local count=0
  while IFS= read -r filename; do
    [[ -z "$filename" ]] && continue
    log_info "Pruning cloud backup: ${filename}"
    rclone deletefile --config "$conf" "${remote}/${filename}" || {
      log_warn "Failed to delete ${filename} from remote"
    }

    # Also delete the matching server.properties if it exists
    local props_name="server.properties.${filename%.zip}"
    props_name="${props_name#*_}"  # Remove world name prefix
    # Extract timestamp from zip filename for properties match
    local ts
    ts="$(echo "$filename" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}-[0-9]{6}')" || true
    if [[ -n "$ts" ]]; then
      rclone deletefile --config "$conf" "${remote}/server.properties.${ts}" 2>/dev/null || true
    fi

    count=$((count + 1))
  done <<< "$to_delete"

  log_info "Pruned ${count} cloud backup(s)"
}

# --- Main entry point ---

# Upload the latest local backup to Google Drive and apply retention.
# All errors are caught — this function never exits the calling script.
cloud_backup() {
  if [[ "${CLOUD_BACKUP_ENABLED:-false}" != "true" ]]; then
    return 0
  fi

  if [[ -z "${CLOUD_BACKUP_REMOTE:-}" ]]; then
    log_warn "CLOUD_BACKUP_REMOTE not set, skipping cloud backup"
    return 0
  fi

  if ! command -v rclone &>/dev/null; then
    log_error "rclone not found but CLOUD_BACKUP_ENABLED=true"
    send_notification "Minecraft Cloud Backup Failed" \
      "rclone is not installed. Run cloud-backup-setup.sh to configure."
    return 0
  fi

  local conf
  conf="$(rclone_conf_path)"
  if [[ ! -f "$conf" ]]; then
    log_error "rclone config not found: ${conf}"
    send_notification "Minecraft Cloud Backup Failed" \
      "rclone config not found at ${conf}. Run cloud-backup-setup.sh to configure."
    return 0
  fi

  log_info "Starting cloud backup to ${CLOUD_BACKUP_REMOTE}:${CLOUD_BACKUP_FOLDER}"

  # Find the latest world backup zip
  local latest_zip=""
  for f in "${BACKUP_DIR}"/${WORLD_NAME}_*.zip; do
    latest_zip="$f"
  done

  if [[ -z "$latest_zip" || ! -f "$latest_zip" ]]; then
    log_warn "No local backup zip found to upload"
    return 0
  fi

  # Upload the world zip
  if ! cloud_backup_upload "$latest_zip"; then
    log_error "Failed to upload $(basename "$latest_zip") to cloud"
    send_notification "Minecraft Cloud Backup Failed" \
      "Failed to upload $(basename "$latest_zip") to ${CLOUD_BACKUP_REMOTE}:${CLOUD_BACKUP_FOLDER}"
    return 0
  fi

  # Upload matching server.properties if it exists
  local ts
  ts="$(echo "$(basename "$latest_zip")" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}-[0-9]{6}')" || true
  if [[ -n "$ts" && -f "${BACKUP_DIR}/server.properties.${ts}" ]]; then
    cloud_backup_upload "${BACKUP_DIR}/server.properties.${ts}" || {
      log_warn "Failed to upload server.properties.${ts} to cloud (non-fatal)"
    }
  fi

  # Apply retention policy
  cloud_backup_prune || {
    log_warn "Cloud backup retention pruning failed (non-fatal)"
  }

  log_info "Cloud backup complete"
}
