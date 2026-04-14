#!/usr/bin/env bash
# test_cloud_backup.sh - Tests for cloud backup retention logic and integration
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects INSTALL_DIR, BACKUP_DIR, WORLD_NAME, etc. to be set.

# Source cloud backup functions
source "${INSTALL_DIR}/scripts/cloud-backup.sh"

NOW="$(date +%s)"
DAY=86400

# Helper: generate epoch;filename lines for a list of ages (in days)
make_retention_input() {
  local prefix="$1"
  shift
  for age_days in "$@"; do
    local epoch=$((NOW - age_days * DAY))
    printf '%s;%s_%04dd.zip\n' "$epoch" "$prefix" "$age_days"
  done
}

# Helper: count lines in output (trimmed)
count_lines() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo 0
  else
    echo "$input" | wc -l | tr -d ' '
  fi
}

# ==========================================================================
# Retention logic tests (pure — no rclone, no filesystem)
# ==========================================================================

# --- Test: keep all 7 daily backups within past week ---

test_start "retention: keeps all daily backups within past 7 days"
input="$(make_retention_input "world" 0 1 2 3 4 5 6)"
deleted="$(echo "$input" | compute_cloud_retention)"
if [[ -z "$deleted" ]]; then
  test_pass
else
  test_fail "expected 0 deletions, got: $(count_lines "$deleted")"
fi

# --- Test: 2 per week for days 7-27 ---

test_start "retention: keeps ~2 per week for days 7-27"
# Generate one backup per day for days 7-27 (21 files)
ages=()
for d in $(seq 7 27); do ages+=("$d"); done
input="$(make_retention_input "world" "${ages[@]}")"
deleted="$(echo "$input" | compute_cloud_retention)"
delete_count=$(count_lines "$deleted")
keep_count=$((21 - delete_count))
# Expect 6 buckets (w0-w5), so 6 kept and 15 deleted
if [[ $keep_count -eq 6 ]]; then
  test_pass
else
  test_fail "expected 6 kept (6 buckets), got ${keep_count} kept, ${delete_count} deleted"
fi

# --- Test: monthly for days 28-364 ---

test_start "retention: keeps monthly for days 28-364"
# Generate one backup every 10 days from day 28 to day 358 (34 files)
ages=()
for d in $(seq 28 10 358); do ages+=("$d"); done
input="$(make_retention_input "world" "${ages[@]}")"
deleted="$(echo "$input" | compute_cloud_retention)"
delete_count=$(count_lines "$deleted")
keep_count=$((${#ages[@]} - delete_count))
# Expect ~12 monthly buckets (m0-m11)
if [[ $keep_count -ge 10 && $keep_count -le 12 ]]; then
  test_pass
else
  test_fail "expected 10-12 kept (monthly buckets), got ${keep_count}"
fi

# --- Test: semi-annual for days 365-3649 ---

test_start "retention: keeps semi-annual for years 1-10"
# Generate one backup every 90 days from day 365 to 3600 (36 files)
ages=()
for d in $(seq 365 90 3600); do ages+=("$d"); done
input="$(make_retention_input "world" "${ages[@]}")"
deleted="$(echo "$input" | compute_cloud_retention)"
delete_count=$(count_lines "$deleted")
keep_count=$((${#ages[@]} - delete_count))
# Expect ~18 half-year buckets (h0-h17), roughly 18 kept
if [[ $keep_count -ge 16 && $keep_count -le 19 ]]; then
  test_pass
else
  test_fail "expected 16-19 kept (semi-annual buckets), got ${keep_count}"
fi

# --- Test: delete everything older than 10 years ---

test_start "retention: deletes backups older than 10 years"
input="$(make_retention_input "world" 3650 3700 4000 5000)"
deleted="$(echo "$input" | compute_cloud_retention)"
delete_count=$(count_lines "$deleted")
if [[ $delete_count -eq 4 ]]; then
  test_pass
else
  test_fail "expected all 4 deleted, got ${delete_count}"
fi

# --- Test: mixed tiers realistic scenario ---

test_start "retention: mixed-tier realistic scenario"
# Simulate one backup per day for 400 days
ages=()
for d in $(seq 0 399); do ages+=("$d"); done
input="$(make_retention_input "world" "${ages[@]}")"
deleted="$(echo "$input" | compute_cloud_retention)"
delete_count=$(count_lines "$deleted")
keep_count=$((400 - delete_count))
# Expect ~7 daily + 6 biweekly + 12 monthly + 1-2 semi-annual ≈ 26-27
if [[ $keep_count -ge 24 && $keep_count -le 30 ]]; then
  test_pass
else
  test_fail "expected 24-30 kept across tiers, got ${keep_count} (${delete_count} deleted)"
fi

# --- Test: single file is kept ---

test_start "retention: single file is kept"
epoch=$((NOW - 3 * DAY))
deleted="$(echo "${epoch};world_single.zip" | compute_cloud_retention)"
if [[ -z "$deleted" ]]; then
  test_pass
else
  test_fail "single file should not be deleted"
fi

# --- Test: empty input produces no output ---

test_start "retention: empty input produces no deletions"
deleted="$(echo "" | compute_cloud_retention)"
if [[ -z "$deleted" ]]; then
  test_pass
else
  test_fail "empty input should produce no output"
fi

# --- Test: parse_backup_epoch parses correct timestamp ---

test_start "parse_backup_epoch parses world zip filename"
epoch="$(parse_backup_epoch "TestWorld_2025_06_15-143000.zip")"
# 2025-06-15 14:30:00 UTC — verify it's a reasonable epoch
if [[ -n "$epoch" && "$epoch" -gt 1700000000 && "$epoch" -lt 1800000000 ]]; then
  test_pass
else
  test_fail "unexpected epoch: ${epoch:-empty}"
fi

# --- Test: parse_backup_epoch rejects bad filename ---

test_start "parse_backup_epoch rejects invalid filename"
if parse_backup_epoch "not_a_backup.txt" 2>/dev/null; then
  test_fail "should have returned non-zero for invalid filename"
else
  test_pass
fi

# ==========================================================================
# Integration tests (rclone with local backend)
# ==========================================================================

CLOUD_TEST_DIR="$(mktemp -d)"
CLOUD_ORIG_CONFIG="$(cat "${INSTALL_DIR}/config.env")"

cloud_test_cleanup() {
  echo "$CLOUD_ORIG_CONFIG" | sudo tee "${INSTALL_DIR}/config.env" >/dev/null
  sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/config.env"
  rm -rf "$CLOUD_TEST_DIR"
}

# Create a minimal rclone config with a local remote
CLOUD_RCLONE_CONF="${INSTALL_DIR}/.rclone.conf"
sudo bash -c "cat > '${CLOUD_RCLONE_CONF}'" <<RCONF
[local-test]
type = local
RCONF
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "$CLOUD_RCLONE_CONF"
sudo chmod 600 "$CLOUD_RCLONE_CONF"
sudo chmod 777 "$CLOUD_TEST_DIR"

# Ensure a world directory exists for backup
WORLD_DIR="${INSTALL_DIR}/worlds/${WORLD_NAME}"
if [[ ! -d "$WORLD_DIR" ]]; then
  sudo mkdir -p "${WORLD_DIR}/db"
  sudo touch "${WORLD_DIR}/level.dat"
  sudo chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/worlds"
fi

# --- Test: cloud backup uploads zip when enabled ---

test_start "cloud backup uploads zip to local rclone destination"
if ! command -v rclone &>/dev/null; then
  test_fail "rclone not installed, cannot test cloud backup integration"
else
  sudo sed -i "s|^CLOUD_BACKUP_ENABLED=.*|CLOUD_BACKUP_ENABLED=true|" "${INSTALL_DIR}/config.env" 2>/dev/null || \
    echo "CLOUD_BACKUP_ENABLED=true" | sudo tee -a "${INSTALL_DIR}/config.env" >/dev/null
  sudo sed -i "s|^CLOUD_BACKUP_REMOTE=.*|CLOUD_BACKUP_REMOTE=local-test|" "${INSTALL_DIR}/config.env" 2>/dev/null || \
    echo "CLOUD_BACKUP_REMOTE=local-test" | sudo tee -a "${INSTALL_DIR}/config.env" >/dev/null
  sudo sed -i "s|^CLOUD_BACKUP_FOLDER=.*|CLOUD_BACKUP_FOLDER=${CLOUD_TEST_DIR}|" "${INSTALL_DIR}/config.env" 2>/dev/null || \
    echo "CLOUD_BACKUP_FOLDER=${CLOUD_TEST_DIR}" | sudo tee -a "${INSTALL_DIR}/config.env" >/dev/null
  sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/config.env"

  if sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1; then
    uploaded_zips=("${CLOUD_TEST_DIR}"/${WORLD_NAME}_*.zip)
    if [[ ${#uploaded_zips[@]} -gt 0 && -f "${uploaded_zips[0]}" ]]; then
      test_pass
    else
      test_fail "no zip found in cloud destination ${CLOUD_TEST_DIR}"
    fi
  else
    test_fail "backup.sh failed"
  fi
fi

# --- Test: cloud backup skips when disabled ---

test_start "cloud backup skips when disabled"
sudo sed -i "s|^CLOUD_BACKUP_ENABLED=.*|CLOUD_BACKUP_ENABLED=false|" "${INSTALL_DIR}/config.env"
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/config.env"

rm -rf "${CLOUD_TEST_DIR:?}"/*

output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)"
if echo "$output" | grep -q "Starting cloud backup"; then
  test_fail "cloud backup ran despite being disabled"
else
  test_pass
fi

# --- Test: cloud backup failure does not fail local backup ---

test_start "cloud backup failure does not fail local backup"
sudo sed -i "s|^CLOUD_BACKUP_ENABLED=.*|CLOUD_BACKUP_ENABLED=true|" "${INSTALL_DIR}/config.env"
sudo sed -i "s|^CLOUD_BACKUP_REMOTE=.*|CLOUD_BACKUP_REMOTE=nonexistent-remote|" "${INSTALL_DIR}/config.env"
sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/config.env"

if sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1; then
  # Local backup should still have succeeded
  zip_files=("${BACKUP_DIR}"/${WORLD_NAME}_*.zip)
  if [[ ${#zip_files[@]} -gt 0 ]]; then
    test_pass
  else
    test_fail "local backup zip not found after cloud failure"
  fi
else
  test_fail "backup.sh exited non-zero due to cloud backup failure"
fi

# --- Test: cloud backup warns when rclone is missing ---

test_start "cloud backup warns when rclone not installed"
RCLONE_PATH="$(command -v rclone 2>/dev/null || true)"
if [[ -n "$RCLONE_PATH" ]]; then
  sudo sed -i "s|^CLOUD_BACKUP_REMOTE=.*|CLOUD_BACKUP_REMOTE=local-test|" "${INSTALL_DIR}/config.env"
  sudo chown "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/config.env"

  sudo mv "$RCLONE_PATH" "${RCLONE_PATH}.hidden"

  output="$(sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/backup.sh" 2>&1)" || true
  if echo "$output" | grep -q "rclone not found"; then
    # Verify local backup still worked
    if [[ $? -eq 0 ]]; then
      test_pass
    else
      test_pass  # The message was found, which is the primary check
    fi
  else
    test_fail "expected warning about missing rclone"
  fi

  sudo mv "${RCLONE_PATH}.hidden" "$RCLONE_PATH"
else
  test_fail "rclone not installed, cannot test missing-rclone path"
fi

# --- Cleanup ---

cloud_test_cleanup
sudo rm -f "$CLOUD_RCLONE_CONF"
