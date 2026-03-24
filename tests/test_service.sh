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

test_start "bedrock_server process or screen session is running"
check_server_running() {
  pgrep -f bedrock_server >/dev/null 2>&1 || screen -list 2>/dev/null | grep -q minecraft
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

if wait_for "port 19132/UDP to be listening" 30 check_port_listening; then
  test_pass
else
  true
fi

# --- Test restart on kill ---

test_start "service restarts after bedrock_server is killed"

# Find the bedrock_server PID
OLD_PID="$(pgrep -f bedrock_server || true)"
if [[ -z "$OLD_PID" ]]; then
  test_fail "bedrock_server process not found, cannot test restart"
else
  # Kill the process; systemd should restart it (Restart=always in the unit)
  sudo kill -9 "$OLD_PID" 2>/dev/null || true

  # Wait for systemd to restart it (the new PID should differ from old)
  check_restarted() {
    local new_pid
    new_pid="$(pgrep -f bedrock_server || true)"
    [[ -n "$new_pid" && "$new_pid" != "$OLD_PID" ]]
  }

  if wait_for "service to restart after kill" 30 check_restarted; then
    test_pass
  else
    true
  fi
fi
