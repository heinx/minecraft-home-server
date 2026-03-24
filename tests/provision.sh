#!/usr/bin/env bash
set -euo pipefail

echo "=== Provisioning test VM ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl unzip screen jq zip

echo "=== Provisioning complete ==="
