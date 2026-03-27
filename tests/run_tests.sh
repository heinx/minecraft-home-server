#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Minecraft Bedrock Server - Test Runner
#
# Simple bash test framework and orchestrator. Runs all test_*.sh scripts
# in sequence and prints a summary.
#
# Usage (inside the Vagrant VM):
#   sudo /vagrant/tests/run_tests.sh
# =============================================================================

readonly TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"

# --- Test framework state ---
PASS_COUNT=0
FAIL_COUNT=0
CURRENT_TEST=""
FAILED_TESTS=()

# --- Test framework functions ---

test_start() {
  CURRENT_TEST="$1"
  echo ""
  echo "--- TEST: ${CURRENT_TEST}"
}

test_pass() {
  echo "    PASS: ${CURRENT_TEST}"
  PASS_COUNT=$((PASS_COUNT + 1))
}

test_fail() {
  local reason="${1:-no reason given}"
  echo "    FAIL: ${CURRENT_TEST} - ${reason}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_TESTS+=("${CURRENT_TEST}: ${reason}")
}

# Helper: assert a command succeeds (exit code 0)
assert_success() {
  local description="$1"
  shift
  if "$@"; then
    return 0
  else
    test_fail "${description} (command failed: $*)"
    return 1
  fi
}

# Helper: assert a file exists
assert_file_exists() {
  local filepath="$1"
  if [[ -f "$filepath" ]]; then
    return 0
  else
    test_fail "file not found: ${filepath}"
    return 1
  fi
}

# Helper: assert a directory exists
assert_dir_exists() {
  local dirpath="$1"
  if [[ -d "$dirpath" ]]; then
    return 0
  else
    test_fail "directory not found: ${dirpath}"
    return 1
  fi
}

# Helper: wait for a condition (polling with timeout)
wait_for() {
  local description="$1"
  local timeout_secs="$2"
  shift 2
  local elapsed=0
  while ! "$@" 2>/dev/null; do
    if [[ $elapsed -ge $timeout_secs ]]; then
      test_fail "${description} (timed out after ${timeout_secs}s)"
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 0
}

# --- Run test suites ---

echo "============================================"
echo "  Minecraft Bedrock Server - Test Suite"
echo "============================================"
echo "  Repo:  ${REPO_DIR}"
echo "  Tests: ${TESTS_DIR}"

# Source config values so test scripts can reference them
# shellcheck source=test_config.env
source "${TESTS_DIR}/test_config.env"

test_scripts=(
  "${TESTS_DIR}/test_install.sh"
  "${TESTS_DIR}/test_service.sh"
  "${TESTS_DIR}/test_backup.sh"
  "${TESTS_DIR}/test_restore.sh"
  "${TESTS_DIR}/test_update.sh"
)

for script in "${test_scripts[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo ""
    echo "WARNING: Test script not found: ${script}, skipping."
    continue
  fi
  echo ""
  echo "============================================"
  echo "  Running: $(basename "$script")"
  echo "============================================"
  # Source each test script so it has access to the framework functions
  source "$script"
done

# --- Summary ---

TOTAL=$((PASS_COUNT + FAIL_COUNT))

echo ""
echo "============================================"
echo "  RESULTS: ${PASS_COUNT} passed, ${FAIL_COUNT} failed (${TOTAL} total)"
echo "============================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
  echo ""
  echo "  Failed tests:"
  for entry in "${FAILED_TESTS[@]}"; do
    echo "    - ${entry}"
  done
  echo ""
  exit 1
fi

echo ""
exit 0
