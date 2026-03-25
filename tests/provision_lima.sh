#!/usr/bin/env bash
# Lima-specific provisioning: shared deps + x86_64 libs for Rosetta.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Shared provisioning (same deps as Vagrant) ---
bash "${SCRIPT_DIR}/provision.sh"

# --- Rosetta x86_64 support ---
echo "=== Configuring x86_64 (amd64) support via Rosetta ==="

dpkg --add-architecture amd64

# Pin existing arm64 sources to arm64-only (ports.ubuntu.com doesn't carry amd64)
sed -i 's/^deb http/deb [arch=arm64] http/g' /etc/apt/sources.list
sed -i 's/^deb-src http/deb-src [arch=arm64] http/g' /etc/apt/sources.list

# Add amd64 sources from archive.ubuntu.com
cat > /etc/apt/sources.list.d/amd64.list <<'EOF'
deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF

apt-get update -qq

# x86_64 system libraries that bedrock_server dynamically links against.
# The server bundles most .so files, but needs these base system libs.
apt-get install -y -qq \
  libc6:amd64 \
  libstdc++6:amd64 \
  libcurl4:amd64 \
  libssl3:amd64

echo "=== Verifying Rosetta ==="
if [[ -f /proc/sys/fs/binfmt_misc/rosetta ]]; then
  echo "Rosetta binfmt registered OK"
else
  echo "WARNING: Rosetta binfmt not found — x86_64 binaries may not run"
fi

echo "=== Lima provisioning complete ==="
