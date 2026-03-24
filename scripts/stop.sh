#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config

if ! screen -list | grep -q "minecraft"; then
  log_warn "No minecraft screen session found"
  exit 0
fi

log_info "Sending stop command to Minecraft server"
screen -Rd minecraft -X stuff "stop\r"

elapsed=0
while screen -list | grep -q "minecraft"; do
  if [[ $elapsed -ge 30 ]]; then
    log_error "Server did not stop within 30 seconds"
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

log_info "Minecraft server stopped (took ${elapsed}s)"
