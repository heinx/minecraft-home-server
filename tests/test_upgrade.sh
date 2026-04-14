#!/usr/bin/env bash
# test_upgrade.sh - Tests for install.sh upgrade mode
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects a working installation from test_install.sh to already be in place.

# --- Capture pre-upgrade state ---

PRE_UPGRADE_PROPS="$(cat "${INSTALL_DIR}/server.properties")"
PRE_UPGRADE_CONFIG="$(cat "${INSTALL_DIR}/config.env")"
PRE_UPGRADE_SERVER_MD5="$(md5sum "${INSTALL_DIR}/bedrock_server" | awk '{print $1}')"

# Ensure the world directory exists (fresh install without IMPORT_WORLD doesn't create it)
WORLD_DIR="${INSTALL_DIR}/worlds/${WORLD_NAME}"
if [[ ! -d "$WORLD_DIR" ]]; then
  sudo mkdir -p "${WORLD_DIR}"
  sudo touch "${WORLD_DIR}/level.dat"
  sudo chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}/worlds"
fi

# Mark a file in the world dir so we can verify it survives
UPGRADE_MARKER="${WORLD_DIR}/.upgrade-test-marker"
sudo bash -c "echo 'do-not-delete' > '${UPGRADE_MARKER}' && chown ${SERVICE_USER}:${SERVICE_GROUP} '${UPGRADE_MARKER}'"

# Add a custom line to config.env to verify it's not overwritten
CUSTOM_MARKER="# UPGRADE_TEST_MARKER=keep-this"
echo "$CUSTOM_MARKER" | sudo tee -a "${INSTALL_DIR}/config.env" >/dev/null

# --- Test: upgrade detects existing installation (non-interactive) ---

test_start "upgrade: install.sh detects existing installation and upgrades"
output="$(sudo bash "${REPO_DIR}/install.sh" --config "${TESTS_DIR}/test_config.env" 2>&1)"
if echo "$output" | grep -q "Existing installation found"; then
  if echo "$output" | grep -q "upgrading management scripts"; then
    test_pass
  else
    test_fail "detected installation but did not enter upgrade mode"
  fi
else
  test_fail "did not detect existing installation"
fi

# --- Test: config.env is preserved ---

test_start "upgrade: config.env is preserved (not overwritten)"
if grep -q "UPGRADE_TEST_MARKER=keep-this" "${INSTALL_DIR}/config.env"; then
  test_pass
else
  test_fail "config.env was overwritten during upgrade"
fi

# --- Test: server.properties is preserved ---

test_start "upgrade: server.properties is preserved"
POST_UPGRADE_PROPS="$(cat "${INSTALL_DIR}/server.properties")"
if [[ "$PRE_UPGRADE_PROPS" == "$POST_UPGRADE_PROPS" ]]; then
  test_pass
else
  test_fail "server.properties changed during upgrade"
fi

# --- Test: bedrock_server binary is preserved ---

test_start "upgrade: bedrock_server binary is preserved"
POST_UPGRADE_SERVER_MD5="$(md5sum "${INSTALL_DIR}/bedrock_server" | awk '{print $1}')"
if [[ "$PRE_UPGRADE_SERVER_MD5" == "$POST_UPGRADE_SERVER_MD5" ]]; then
  test_pass
else
  test_fail "bedrock_server binary changed during upgrade"
fi

# --- Test: world data is preserved ---

test_start "upgrade: world data is preserved"
if [[ -f "$UPGRADE_MARKER" ]] && grep -q "do-not-delete" "$UPGRADE_MARKER"; then
  test_pass
else
  test_fail "world marker file missing or modified after upgrade"
fi

# --- Test: scripts are updated ---

test_start "upgrade: management scripts are updated"
scripts_ok=true
for script_name in start.sh stop.sh backup.sh update.sh restore.sh lib.sh; do
  if [[ ! -f "${INSTALL_DIR}/scripts/${script_name}" ]]; then
    test_fail "missing script after upgrade: ${script_name}"
    scripts_ok=false
    break
  fi
  if [[ ! -x "${INSTALL_DIR}/scripts/${script_name}" ]]; then
    test_fail "script not executable after upgrade: ${script_name}"
    scripts_ok=false
    break
  fi
done
if [[ "$scripts_ok" == "true" ]]; then
  test_pass
fi

# --- Test: service is still running after upgrade ---

test_start "upgrade: minecraft service is running after upgrade"
if systemctl is-active minecraft &>/dev/null; then
  test_pass
else
  test_fail "minecraft service is not running after upgrade"
fi

# --- Test: banner says updated not installed ---

test_start "upgrade: success banner says 'updated'"
if echo "$output" | grep -q "Management scripts updated"; then
  test_pass
else
  test_fail "expected 'Management scripts updated' banner"
fi

# --- Cleanup ---

sudo sed -i "/UPGRADE_TEST_MARKER/d" "${INSTALL_DIR}/config.env"
sudo rm -f "$UPGRADE_MARKER"
