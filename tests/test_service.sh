#!/usr/bin/env bash
# test_service.sh - Tests for the minecraft systemd service
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects INSTALL_DIR, SERVICE_USER, etc. from test_config.env to be set.

# --- Ensure service is started ---

test_start "minecraft service starts via systemctl"
# The installer already starts the service, but ensure it is running
if systemctl is-active --quiet minecraft; then
  test_pass
else
  # Try starting it
  if sudo systemctl start minecraft && systemctl is-active --quiet minecraft; then
    test_pass
  else
    test_fail "minecraft service failed to start"
  fi
fi

# --- Verify server process is running ---

test_start "bedrock_server process is running"
check_server_running() {
  pgrep -x bedrock_server >/dev/null 2>&1
}

if wait_for "server process to appear" 15 check_server_running; then
  test_pass
else
  # test_fail already called by wait_for
  true
fi

# --- Verify port 19132/UDP is listening ---

test_start "server port 19132/UDP is listening"
check_port_listening() {
  ss -ulnp | grep -q ":19132 "
}

if wait_for "port 19132/UDP to be listening" 60 check_port_listening; then
  test_pass
else
  true
fi

# --- Verify server started successfully via log ---

test_start "bedrock_server log shows successful startup"
LOG_FILE="${INSTALL_DIR}/logs/server.log"

check_server_started_log() {
  [[ -f "$LOG_FILE" ]] && grep -q "Server started\." "$LOG_FILE"
}

if wait_for "\"Server started.\" in log" 60 check_server_started_log; then
  test_pass
else
  if [[ -f "$LOG_FILE" ]]; then
    echo "    Last 5 lines of server.log:"
    tail -5 "$LOG_FILE" | sed 's/^/      /'
  fi
  true
fi

# --- Test restart on kill ---

test_start "service restarts after process is killed"

# systemd tracks the screen process (Type=forking), so kill that to trigger Restart=always
MAIN_PID="$(systemctl show -p MainPID minecraft --value 2>/dev/null || true)"
if [[ -z "$MAIN_PID" || "$MAIN_PID" == "0" ]]; then
  test_fail "could not determine service MainPID, cannot test restart"
else
  sudo kill -9 "$MAIN_PID" 2>/dev/null || true

  # Wait for systemd to restart the service (new MainPID differs from old)
  check_restarted() {
    local new_pid
    new_pid="$(systemctl show -p MainPID minecraft --value 2>/dev/null || true)"
    [[ -n "$new_pid" && "$new_pid" != "0" && "$new_pid" != "$MAIN_PID" ]]
  }

  if wait_for "service to restart after kill" 60 check_restarted; then
    test_pass
  else
    true
  fi
fi
