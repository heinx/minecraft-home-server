#!/usr/bin/env bash
# Run the test suite inside a Docker container with systemd support.
# Usage: ./tests/docker-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="minecraft-home-server-test"
CONTAINER_NAME="minecraft-test-$$"

cleanup() {
  echo ""
  echo "=== Cleaning up ==="
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Building test image ==="
docker build -t "$IMAGE_NAME" "${SCRIPT_DIR}"

echo "=== Starting container with systemd ==="
docker run -d \
  --name "$CONTAINER_NAME" \
  --platform linux/amd64 \
  --privileged \
  --tmpfs /run \
  --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "${REPO_DIR}:/workspace:ro" \
  "$IMAGE_NAME"

echo "=== Waiting for systemd to initialise ==="
for i in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" systemctl is-system-running --wait 2>/dev/null | grep -qE "running|degraded"; then
    break
  fi
  sleep 1
done

echo "=== Copying project into container ==="
docker exec "$CONTAINER_NAME" bash -c "cp -r /workspace /test-repo"

echo "=== Running tests ==="
docker exec "$CONTAINER_NAME" bash /test-repo/tests/run_tests.sh
