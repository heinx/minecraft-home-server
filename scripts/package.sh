#!/usr/bin/env bash
# Build a release tarball for minecraft-home-server.
#
# Usage:
#   scripts/package.sh v1.0.0          # version from argument
#   VERSION=v1.0.0 scripts/package.sh  # version from env
#   scripts/package.sh                  # version from git tag
#
# Outputs: minecraft-home-server-<version>.tar.gz + .sha256 in current dir
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-${VERSION:-}}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$REPO_DIR" describe --tags --exact-match 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
  echo "ERROR: No version specified. Pass as argument, set VERSION env, or run from a git tag." >&2
  exit 1
fi

ARCHIVE_NAME="minecraft-home-server-${VERSION}"
TARBALL="${ARCHIVE_NAME}.tar.gz"

echo "Packaging ${TARBALL}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir "${WORK_DIR}/${ARCHIVE_NAME}"
cp -r "${REPO_DIR}/scripts/" "${WORK_DIR}/${ARCHIVE_NAME}/scripts/"
cp -r "${REPO_DIR}/templates/" "${WORK_DIR}/${ARCHIVE_NAME}/templates/"
cp "${REPO_DIR}/install.sh" "${WORK_DIR}/${ARCHIVE_NAME}/"
cp "${REPO_DIR}/config.env.example" "${WORK_DIR}/${ARCHIVE_NAME}/"
[[ -f "${REPO_DIR}/LICENSE" ]] && cp "${REPO_DIR}/LICENSE" "${WORK_DIR}/${ARCHIVE_NAME}/"

# Exclude package.sh from the release (it's a dev tool)
rm -f "${WORK_DIR}/${ARCHIVE_NAME}/scripts/package.sh"

tar -czf "$TARBALL" -C "$WORK_DIR" "${ARCHIVE_NAME}/"
sha256sum "$TARBALL" > "${TARBALL}.sha256"

echo "Created: ${TARBALL}"
echo "Checksum: $(cat "${TARBALL}.sha256")"
