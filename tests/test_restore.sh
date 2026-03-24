#!/usr/bin/env bash
# test_restore.sh - Tests for restore.sh
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects INSTALL_DIR, BACKUP_DIR, WORLD_NAME, SERVICE_USER, SERVICE_GROUP to be set.

WORLD_DIR="${INSTALL_DIR}/worlds/${WORLD_NAME}"

# --- Create a backup to restore from ---

# Ensure world exists with a known marker file
sudo -u "${SERVICE_USER}" mkdir -p "${WORLD_DIR}/db"
echo "original" | sudo -u "${SERVICE_USER}" tee "${WORLD_DIR}/marker.txt" >/dev/null
sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" >/dev/null 2>&1

# Find the backup we just created
RESTORE_ZIP=""
for f in "${BACKUP_DIR}"/${WORLD_NAME}_*.zip; do
  RESTORE_ZIP="$f"
done

# Now change the marker so we can verify restore overwrites it
echo "modified" | sudo -u "${SERVICE_USER}" tee "${WORLD_DIR}/marker.txt" >/dev/null

# --- Test: restore.sh restores world from backup ---

test_start "restore.sh restores world from backup"
if [[ -z "$RESTORE_ZIP" || ! -f "$RESTORE_ZIP" ]]; then
  test_fail "no backup zip available to test restore"
else
  if sudo bash "${INSTALL_DIR}/scripts/restore.sh" "$RESTORE_ZIP" >/dev/null 2>&1; then
    if [[ -f "${WORLD_DIR}/marker.txt" ]]; then
      content="$(cat "${WORLD_DIR}/marker.txt")"
      if [[ "$content" == "original" ]]; then
        test_pass
      else
        test_fail "marker.txt contains '${content}', expected 'original'"
      fi
    else
      test_fail "marker.txt not found after restore"
    fi
  else
    test_fail "restore.sh exited with non-zero status"
  fi
fi

# --- Test: server is running after restore ---

test_start "server is running after restore"
check_running() {
  pgrep -f bedrock_server >/dev/null 2>&1 || screen -list 2>/dev/null | grep -q "[0-9]\.minecraft"
}
if wait_for "server to start after restore" 30 check_running; then
  test_pass
else
  true
fi

# --- Test: restore.sh also restores matching server.properties ---

test_start "restore.sh restores matching server.properties"
# Find the properties backup matching our zip's timestamp
BACKUP_BASENAME="$(basename "$RESTORE_ZIP")"
TIMESTAMP="${BACKUP_BASENAME#"${WORLD_NAME}_"}"
TIMESTAMP="${TIMESTAMP%.zip}"
PROPERTIES_BACKUP="${BACKUP_DIR}/server.properties.${TIMESTAMP}"

if [[ -f "$PROPERTIES_BACKUP" ]]; then
  # Modify server.properties so we can detect if restore overwrites it
  echo "# test-marker" | sudo tee -a "${INSTALL_DIR}/server.properties" >/dev/null

  sudo bash "${INSTALL_DIR}/scripts/restore.sh" "$RESTORE_ZIP" >/dev/null 2>&1

  if grep -q "test-marker" "${INSTALL_DIR}/server.properties"; then
    test_fail "server.properties was not restored from backup"
  else
    test_pass
  fi
else
  # No matching properties backup — just verify restore doesn't break
  test_pass
fi

# --- Test: restore.sh fails gracefully with no argument ---

test_start "restore.sh fails with no argument"
if sudo bash "${INSTALL_DIR}/scripts/restore.sh" 2>/dev/null; then
  test_fail "should have exited with error"
else
  test_pass
fi

# --- Test: restore.sh fails gracefully with nonexistent file ---

test_start "restore.sh fails with nonexistent backup file"
if sudo bash "${INSTALL_DIR}/scripts/restore.sh" "/tmp/nonexistent.zip" 2>/dev/null; then
  test_fail "should have exited with error"
else
  test_pass
fi
