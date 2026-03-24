#!/usr/bin/env bash
set -euo pipefail

echo "=== Provisioning test VM ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl unzip screen jq zip

# Install rclone for offsite backup tests
if ! command -v rclone &>/dev/null; then
  echo "=== Installing rclone ==="
  curl -sfL https://rclone.org/install.sh | bash
fi

echo "=== Provisioning complete ==="
