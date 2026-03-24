#!/usr/bin/env bash
# test_offsite_backup.sh - Tests for offsite backup via rclone
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Uses rclone with a local destination (no cloud credentials needed).

OFFSITE_DIR="$(mktemp -d)"
OFFSITE_CONFIG="${INSTALL_DIR}/config.env"

# Save original config so we can modify and restore it
ORIGINAL_CONFIG="$(cat "$OFFSITE_CONFIG")"

restore_config() {
  echo "$ORIGINAL_CONFIG" | sudo tee "$OFFSITE_CONFIG" >/dev/null
  sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$OFFSITE_CONFIG"
  rm -rf "$OFFSITE_DIR"
}

# --- Test: offsite backup syncs files when enabled ---

test_start "offsite backup syncs to local rclone destination"
if ! command -v rclone &>/dev/null; then
  test_fail "rclone not installed, cannot test offsite backup"
else
  # Enable offsite backup with a local path as the remote
  sudo sed -i "s|^OFFSITE_BACKUP_ENABLED=.*|OFFSITE_BACKUP_ENABLED=true|" "$OFFSITE_CONFIG"
  sudo sed -i "s|^OFFSITE_BACKUP_REMOTE=.*|OFFSITE_BACKUP_REMOTE=${OFFSITE_DIR}|" "$OFFSITE_CONFIG"
  sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$OFFSITE_CONFIG"
  sudo chmod 777 "$OFFSITE_DIR"

  output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)"
  if echo "$output" | grep -q "Offsite sync complete"; then
    # Check that files were actually synced
    synced_zips=("${OFFSITE_DIR}"/${WORLD_NAME}_*.zip)
    if [[ ${#synced_zips[@]} -gt 0 && -f "${synced_zips[0]}" ]]; then
      test_pass
    else
      test_fail "rclone reported success but no files found in ${OFFSITE_DIR}"
    fi
  else
    test_fail "offsite sync did not complete: ${output}"
  fi
fi

# --- Test: offsite backup skips when disabled ---

test_start "offsite backup skips when OFFSITE_BACKUP_ENABLED=false"
sudo sed -i "s|^OFFSITE_BACKUP_ENABLED=.*|OFFSITE_BACKUP_ENABLED=false|" "$OFFSITE_CONFIG"
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$OFFSITE_CONFIG"

# Clear the offsite dir to confirm nothing new arrives
rm -rf "${OFFSITE_DIR:?}"/*

output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)"
if echo "$output" | grep -q "Offsite sync complete"; then
  test_fail "offsite sync ran despite being disabled"
else
  test_pass
fi

# --- Test: offsite backup warns when remote is empty ---

test_start "offsite backup warns when OFFSITE_BACKUP_REMOTE is empty"
sudo sed -i "s|^OFFSITE_BACKUP_ENABLED=.*|OFFSITE_BACKUP_ENABLED=true|" "$OFFSITE_CONFIG"
sudo sed -i "s|^OFFSITE_BACKUP_REMOTE=.*|OFFSITE_BACKUP_REMOTE=|" "$OFFSITE_CONFIG"
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$OFFSITE_CONFIG"

output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)"
if echo "$output" | grep -q "OFFSITE_BACKUP_REMOTE not set"; then
  test_pass
else
  test_fail "expected warning about empty remote"
fi

# --- Test: offsite backup errors when rclone is missing ---

test_start "offsite backup errors when rclone is not installed"
sudo sed -i "s|^OFFSITE_BACKUP_REMOTE=.*|OFFSITE_BACKUP_REMOTE=${OFFSITE_DIR}|" "$OFFSITE_CONFIG"
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$OFFSITE_CONFIG"

# Temporarily hide rclone
RCLONE_PATH="$(command -v rclone 2>/dev/null || true)"
if [[ -n "$RCLONE_PATH" ]]; then
  sudo mv "$RCLONE_PATH" "${RCLONE_PATH}.hidden"

  output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)" || true
  if echo "$output" | grep -q "rclone not found"; then
    test_pass
  else
    test_fail "expected error about missing rclone"
  fi

  sudo mv "${RCLONE_PATH}.hidden" "$RCLONE_PATH"
else
  test_fail "rclone not installed, cannot test missing-rclone path"
fi

# --- Test: offsite backup reports failure on bad remote ---

test_start "offsite backup reports failure on invalid remote"
sudo sed -i "s|^OFFSITE_BACKUP_REMOTE=.*|OFFSITE_BACKUP_REMOTE=nonexistent-remote:bucket/path|" "$OFFSITE_CONFIG"
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$OFFSITE_CONFIG"

output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)" || true
if echo "$output" | grep -q "Offsite backup sync failed"; then
  test_pass
else
  test_fail "expected error about sync failure, got: ${output}"
fi

# --- Restore original config ---

restore_config
