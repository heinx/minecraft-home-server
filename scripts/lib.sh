#!/usr/bin/env bash
# Shared library for Minecraft Bedrock server management scripts.

load_config() {
  local config_path=""

  if [[ -n "${INSTALL_DIR:-}" && -f "${INSTALL_DIR}/config.env" ]]; then
    config_path="${INSTALL_DIR}/config.env"
  else
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    if [[ -f "${script_dir}/../config.env" ]]; then
      config_path="${script_dir}/../config.env"
    elif [[ -f "${script_dir}/config.env" ]]; then
      config_path="${script_dir}/config.env"
    fi
  fi

  if [[ -z "$config_path" ]]; then
    echo "[ERROR] config.env not found" >&2
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$config_path"
  log_info "Loaded config from ${config_path}"
}

log_info() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

send_notification() {
  local subject="$1"
  local body="$2"

  if [[ "${NOTIFY_ENABLED:-false}" != "true" || -z "${NOTIFY_EMAIL:-}" ]]; then
    return 0
  fi

  local message
  message="Subject: ${subject}
To: ${NOTIFY_EMAIL}
From: minecraft-server@$(hostname -f 2>/dev/null || echo localhost)

${body}"

  if command -v msmtp &>/dev/null; then
    echo "$message" | msmtp "$NOTIFY_EMAIL" && return 0
  fi

  if command -v sendmail &>/dev/null; then
    echo "$message" | sendmail "$NOTIFY_EMAIL" && return 0
  fi

  if command -v mail &>/dev/null; then
    echo "$body" | mail -s "$subject" "$NOTIFY_EMAIL" && return 0
  fi

  log_warn "No mail transport available (tried msmtp, sendmail, mail). Notification skipped."
}

check_dependencies() {
  local missing=()
  for cmd in screen unzip curl; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing[*]}"
    exit 1
  fi
}
