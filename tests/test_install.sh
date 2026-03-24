#!/usr/bin/env bash
# test_install.sh - Tests for install.sh
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects TESTS_DIR, REPO_DIR, and test_config.env variables to be set.

# --- Run the installer ---

test_start "install.sh runs successfully"
if sudo bash "${REPO_DIR}/install.sh" --config "${TESTS_DIR}/test_config.env"; then
  test_pass
else
  test_fail "install.sh exited with non-zero status"
fi

# --- Verify systemd service ---

test_start "minecraft service is registered in systemd"
if systemctl list-unit-files | grep -q "minecraft.service"; then
  test_pass
else
  test_fail "minecraft.service not found in systemd unit files"
fi

# --- Verify install directory ---

test_start "install directory exists with correct ownership"
if assert_dir_exists "${INSTALL_DIR}"; then
  owner="$(stat -c '%U:%G' "${INSTALL_DIR}")"
  if [[ "$owner" == "${SERVICE_USER}:${SERVICE_GROUP}" ]]; then
    test_pass
  else
    test_fail "ownership is ${owner}, expected ${SERVICE_USER}:${SERVICE_GROUP}"
  fi
fi

# --- Verify bedrock_server binary ---

test_start "bedrock_server binary exists"
if [[ -f "${INSTALL_DIR}/bedrock_server" ]]; then
  test_pass
else
  test_fail "${INSTALL_DIR}/bedrock_server not found"
fi

# --- Verify server.properties ---

test_start "server.properties exists with correct values"
if assert_file_exists "${INSTALL_DIR}/server.properties"; then
  errors=""
  if ! grep -q "^server-name=${SERVER_NAME}$" "${INSTALL_DIR}/server.properties"; then
    errors="${errors} server-name mismatch;"
  fi
  if ! grep -q "^level-name=${WORLD_NAME}$" "${INSTALL_DIR}/server.properties"; then
    errors="${errors} level-name mismatch;"
  fi
  if ! grep -q "^gamemode=${GAMEMODE}$" "${INSTALL_DIR}/server.properties"; then
    errors="${errors} gamemode mismatch;"
  fi
  if ! grep -q "^difficulty=${DIFFICULTY}$" "${INSTALL_DIR}/server.properties"; then
    errors="${errors} difficulty mismatch;"
  fi
  if ! grep -q "^server-port=${SERVER_PORT}$" "${INSTALL_DIR}/server.properties"; then
    errors="${errors} server-port mismatch;"
  fi

  if [[ -z "$errors" ]]; then
    test_pass
  else
    test_fail "server.properties values incorrect:${errors}"
  fi
fi

# --- Verify config.env in install dir ---

test_start "config.env exists in install directory"
if assert_file_exists "${INSTALL_DIR}/config.env"; then
  test_pass
fi

# --- Verify scripts are installed ---

test_start "management scripts are installed"
scripts_ok=true
for script_name in start.sh stop.sh backup.sh update.sh restore.sh lib.sh; do
  if [[ ! -f "${INSTALL_DIR}/scripts/${script_name}" ]]; then
    test_fail "missing script: ${INSTALL_DIR}/scripts/${script_name}"
    scripts_ok=false
    break
  fi
  if [[ ! -x "${INSTALL_DIR}/scripts/${script_name}" ]]; then
    test_fail "script not executable: ${INSTALL_DIR}/scripts/${script_name}"
    scripts_ok=false
    break
  fi
done
if [[ "$scripts_ok" == "true" ]]; then
  test_pass
fi
