#!/usr/bin/env bash
# test_update.sh - Tests for update.sh
#
# Sourced by run_tests.sh; uses the test framework functions defined there.
# Expects INSTALL_DIR, etc. from test_config.env to be set.

API_URL="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"

# --- Test: URL extraction from the API ---

test_start "update.sh can fetch and extract download URL from API"

api_response="$(curl -sf "${API_URL}" 2>/dev/null || true)"
if [[ -z "$api_response" ]]; then
  test_fail "could not reach ${API_URL}"
else
  url=""
  if command -v jq &>/dev/null; then
    url="$(echo "$api_response" | jq -r '.result.links[] | select(.downloadType == "serverBedrockLinux") | .downloadUrl' 2>/dev/null || true)"
  fi
  if [[ -z "$url" ]]; then
    url="$(echo "$api_response" | grep -o 'https://[^"]*bin-linux/[^"]*' || true)"
  fi

  if [[ -n "$url" && "$url" == https://* ]]; then
    echo "    Extracted URL: ${url}"
    test_pass
  else
    test_fail "could not extract a valid download URL from API response"
  fi
fi

# --- Test: already up to date exits cleanly ---

test_start "update.sh exits cleanly when already up to date"

# Find out which zip was downloaded by install.sh so we can verify
# the "already up to date" path.
# The installed zip filename is stored in the install dir.
installed_zips=("${INSTALL_DIR}"/bedrock-server-*.zip)
if [[ ${#installed_zips[@]} -eq 0 ]]; then
  test_fail "no bedrock-server zip found in ${INSTALL_DIR}, cannot test up-to-date check"
else
  # update.sh will check the API, see the zip already exists, and exit 0
  if sudo -u "${SERVICE_USER}" bash "${INSTALL_DIR}/scripts/update.sh" 2>&1 | grep -q "Already up to date"; then
    test_pass
  else
    # It might have found a newer version and tried to update - that is also
    # a valid outcome (the server simply has a newer release available)
    exit_code=${PIPESTATUS[0]:-$?}
    if [[ $exit_code -eq 0 ]]; then
      echo "    (update.sh completed successfully - a newer version may have been applied)"
      test_pass
    else
      test_fail "update.sh exited with code ${exit_code}"
    fi
  fi
fi
