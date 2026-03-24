#!/usr/bin/env bash
# test_backup.sh - Tests for backup.sh
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects INSTALL_DIR, BACKUP_DIR, WORLD_NAME, BACKUP_KEEP_COUNT, etc. to be set.

WORLD_DIR="${INSTALL_DIR}/worlds/${WORLD_NAME}"

# --- Ensure world directory and level.dat exist for backups ---

setup_world_dir() {
  sudo mkdir -p "${WORLD_DIR}/db"
  sudo touch "${WORLD_DIR}/level.dat"
  sudo touch "${WORLD_DIR}/level.dat_old"
  sudo touch "${WORLD_DIR}/levelname.txt"
  echo "${WORLD_NAME}" | sudo tee "${WORLD_DIR}/levelname.txt" >/dev/null
  sudo chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/worlds"
}

setup_world_dir

# --- Test: backup creates a zip ---

test_start "backup.sh creates a zip file in backup directory"
if sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh"; then
  zip_files=("${BACKUP_DIR}"/${WORLD_NAME}_*.zip)
  if [[ ${#zip_files[@]} -gt 0 && -f "${zip_files[0]}" ]]; then
    test_pass
  else
    test_fail "no zip file found in ${BACKUP_DIR}"
  fi
else
  test_fail "backup.sh exited with non-zero status"
fi

# --- Test: zip contains level.dat ---

test_start "backup zip contains world data (level.dat)"
# Use the most recent zip
latest_zip=""
for f in "${BACKUP_DIR}"/${WORLD_NAME}_*.zip; do
  latest_zip="$f"
done

if [[ -n "$latest_zip" && -f "$latest_zip" ]]; then
  if unzip -l "$latest_zip" | grep -q "level.dat"; then
    test_pass
  else
    test_fail "level.dat not found inside ${latest_zip}"
  fi
else
  test_fail "no backup zip found to inspect"
fi

# --- Test: server.properties backup is created ---

test_start "server.properties backup is created"
props_backups=("${BACKUP_DIR}"/server.properties.*)
if [[ ${#props_backups[@]} -gt 0 && -f "${props_backups[0]}" ]]; then
  test_pass
else
  test_fail "no server.properties backup found in ${BACKUP_DIR}"
fi

# --- Test: backup rotation keeps only BACKUP_KEEP_COUNT ---

test_start "backup rotation keeps only ${BACKUP_KEEP_COUNT} backups"

# Clean existing backups first
sudo rm -f "${BACKUP_DIR}"/${WORLD_NAME}_*.zip
sudo rm -f "${BACKUP_DIR}"/server.properties.*

# Create 21 dummy backups (one more than BACKUP_KEEP_COUNT=20)
for i in $(seq 1 21); do
  ts="$(printf '2025_01_%02d-120000' "$i")"
  # Create a valid zip with level.dat so the backup looks real
  sudo -u "${SERVICE_USER}" bash -c "cd / && zip -q '${BACKUP_DIR}/${WORLD_NAME}_${ts}.zip' -r '${WORLD_DIR}/level.dat'" 2>/dev/null || \
    sudo bash -c "cd / && zip -q '${BACKUP_DIR}/${WORLD_NAME}_${ts}.zip' -r '${WORLD_DIR}/level.dat' && chown ${SERVICE_USER}:${SERVICE_GROUP} '${BACKUP_DIR}/${WORLD_NAME}_${ts}.zip'"
  sudo touch -t "$(printf '202501%02d1200' "$i")" "${BACKUP_DIR}/${WORLD_NAME}_${ts}.zip"
  sudo -u "${SERVICE_USER}" cp "${INSTALL_DIR}/server.properties" "${BACKUP_DIR}/server.properties.${ts}" 2>/dev/null || \
    sudo bash -c "cp '${INSTALL_DIR}/server.properties' '${BACKUP_DIR}/server.properties.${ts}' && chown ${SERVICE_USER}:${SERVICE_GROUP} '${BACKUP_DIR}/server.properties.${ts}'"
  sudo touch -t "$(printf '202501%02d1200' "$i")" "${BACKUP_DIR}/server.properties.${ts}"
done

# Verify we have 21
count_before=$(ls -1 "${BACKUP_DIR}"/${WORLD_NAME}_*.zip 2>/dev/null | wc -l)

# Run backup (which creates a 22nd, then prunes to 20)
if sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh"; then
  count_after=$(ls -1 "${BACKUP_DIR}"/${WORLD_NAME}_*.zip 2>/dev/null | wc -l)
  if [[ $count_after -le ${BACKUP_KEEP_COUNT} ]]; then
    test_pass
  else
    test_fail "expected at most ${BACKUP_KEEP_COUNT} backups, found ${count_after} (had ${count_before} before run)"
  fi
else
  test_fail "backup.sh exited with non-zero status during rotation test"
fi
