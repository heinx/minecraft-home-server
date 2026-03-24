#!/usr/bin/env bash
# test_package.sh - Tests for scripts/package.sh (local, no VM needed)
#
# Run directly: ./tests/test_package.sh
# Or sourced by run_tests.sh (inside VM)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Minimal test framework (standalone mode when run outside run_tests.sh)
if ! declare -f test_start &>/dev/null; then
  PASS_COUNT=0
  FAIL_COUNT=0
  test_start() { echo ""; echo "--- TEST: $1"; }
  test_pass() { echo "    PASS"; PASS_COUNT=$((PASS_COUNT + 1)); }
  test_fail() { echo "    FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
  STANDALONE=true
else
  STANDALONE=false
fi

TEST_VERSION="v0.0.0-test"
TARBALL="minecraft-home-server-${TEST_VERSION}.tar.gz"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Test: package.sh creates a versioned tarball ---

test_start "package.sh creates a versioned tarball"
if (cd "$WORK_DIR" && bash "${REPO_DIR}/scripts/package.sh" "$TEST_VERSION" >/dev/null 2>&1); then
  if [[ -f "${WORK_DIR}/${TARBALL}" ]]; then
    test_pass
  else
    test_fail "tarball not found: ${WORK_DIR}/${TARBALL}"
  fi
else
  test_fail "package.sh exited with non-zero status"
fi

# --- Test: tarball contains correct directory structure ---

test_start "tarball contains versioned root directory"
root_dir="$(tar -tzf "${WORK_DIR}/${TARBALL}" | head -1)"
if [[ "$root_dir" == "minecraft-home-server-${TEST_VERSION}/" ]]; then
  test_pass
else
  test_fail "expected 'minecraft-home-server-${TEST_VERSION}/', got '${root_dir}'"
fi

# --- Test: tarball contains required files ---

test_start "tarball contains all required files"
missing=""
for required in install.sh config.env.example scripts/lib.sh scripts/start.sh scripts/stop.sh scripts/backup.sh scripts/update.sh scripts/restore.sh templates/minecraft.service.template templates/crontab.template; do
  if ! tar -tzf "${WORK_DIR}/${TARBALL}" | grep -q "${required}$"; then
    missing="${missing} ${required}"
  fi
done
if [[ -z "$missing" ]]; then
  test_pass
else
  test_fail "missing files:${missing}"
fi

# --- Test: tarball does NOT contain package.sh (dev tool) ---

test_start "tarball excludes package.sh"
if tar -tzf "${WORK_DIR}/${TARBALL}" | grep -q "package.sh"; then
  test_fail "package.sh should not be in the release tarball"
else
  test_pass
fi

# --- Test: tarball does NOT contain test files or mine/ ---

test_start "tarball excludes tests"
leaked=""
for excluded in tests/ .git/ .github/ AGENTS.md; do
  if tar -tzf "${WORK_DIR}/${TARBALL}" | grep -q "$excluded"; then
    leaked="${leaked} ${excluded}"
  fi
done
if [[ -z "$leaked" ]]; then
  test_pass
else
  test_fail "tarball contains dev files:${leaked}"
fi

# --- Test: SHA256 checksum file is valid ---

test_start "SHA256 checksum file is valid"
if (cd "$WORK_DIR" && sha256sum -c "${TARBALL}.sha256" >/dev/null 2>&1); then
  test_pass
else
  test_fail "checksum verification failed"
fi

# --- Test: package.sh fails without version ---

test_start "package.sh fails when no version is provided"
EMPTY_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR" "$EMPTY_DIR"' EXIT
if (cd "$EMPTY_DIR" && bash "${REPO_DIR}/scripts/package.sh" 2>/dev/null); then
  test_fail "should have exited with error when no version given"
else
  test_pass
fi

# --- Standalone summary ---

if [[ "$STANDALONE" == "true" ]]; then
  TOTAL=$((PASS_COUNT + FAIL_COUNT))
  echo ""
  echo "============================================"
  echo "  RESULTS: ${PASS_COUNT} passed, ${FAIL_COUNT} failed (${TOTAL} total)"
  echo "============================================"
  if [[ $FAIL_COUNT -gt 0 ]]; then exit 1; fi
fi
