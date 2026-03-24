#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config
check_dependencies

LOG_DIR="${INSTALL_DIR}/logs"
LOG_FILE="${LOG_DIR}/server.log"
mkdir -p "$LOG_DIR"

# Clean up dead screen sockets (e.g. after kill -9)
screen -wipe 2>/dev/null || true

if screen -list 2>/dev/null | grep -q "[0-9]\.minecraft"; then
  log_warn "Minecraft screen session already running"
  exit 1
fi

log_info "Starting Bedrock server from ${INSTALL_DIR}"

export LD_LIBRARY_PATH="${INSTALL_DIR}"
screen -dmS minecraft -L -Logfile "$LOG_FILE" /bin/bash -c "cd ${INSTALL_DIR} && LD_LIBRARY_PATH=${INSTALL_DIR} ${INSTALL_DIR}/bedrock_server"

screen -rD minecraft -X multiuser on
screen -rD minecraft -X acladd root
screen -rD minecraft -X logstamp on

log_info "Minecraft server started in screen session 'minecraft'"
