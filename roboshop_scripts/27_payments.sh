#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Payment Service Setup Script for RoboShop
#
# Files used:
#   - payment.sh                    (this script)
#   - payment_util_packages.txt     (utility package list)
#   - payment.service               (systemd unit template)
#
# What this script does:
#   - Ensures 'roboshop' user exists
#   - Ensures /app and /app/logs exist & owned by roboshop
#   - Installs Python 3.6 + build deps + pip
#   - Downloads payment.zip to /tmp and unzips into /app
#   - Installs Python dependencies (including pyuwsgi) as root
#   - Copies payment.service → /etc/systemd/system/payment.service
#   - Reloads systemd, enables & restarts payment.service
# ==========================================================

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---------- Config ----------
APP_DIR="/app"
LOGS_DIR="${APP_DIR}/logs"
PAYMENT_ZIP_URL="https://roboshop-builds.s3.amazonaws.com/payment.zip"

SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UTIL_PKG_FILE="${SCRIPT_DIR}/payment_util_packages.txt"
PAYMENT_SERVICE_TEMPLATE="${SCRIPT_DIR}/29_payment.service"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/payment.service"

LOG_FILE="${LOGS_DIR}/${SCRIPT_BASE}-$(date +%F).log"

PKG_MGR=""

# ==========================================================
# Helper Functions
# ==========================================================

print_header() {
  echo -e "${BLUE}===========================================${RESET}"
  echo -e "${CYAN} Payment Service Setup Script Execution${RESET}"
  echo -e "${YELLOW} Started @ $(date +"%F %T")${RESET}"
  echo -e "${BLUE}===========================================${RESET}"
}

validate_step() {
  local EXIT_CODE="$1"
  local SUCCESS_MSG="$2"
  local FAILURE_MSG="$3"

  if [[ "${EXIT_CODE}" -eq 0 ]]; then
    echo -e "${GREEN}[SUCCESS]${RESET} ${SUCCESS_MSG}"
  else
    echo -e "${RED}[FAILURE]${RESET} ${FAILURE_MSG} (exit code: ${EXIT_CODE})"
    exit "${EXIT_CODE}"
  fi
}

ensure_root() {
  echo -e "${CYAN}Checking for root privileges...${RESET}"
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${RED}This script must be run as root (or with sudo).${RESET}"
    exit 1
  fi
  echo -e "${GREEN}Running as root. Continuing...${RESET}"
}

detect_pkg_mgr() {
  echo -e "${CYAN}Detecting package manager...${RESET}"
  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
  else
    echo -e "${RED}Neither dnf nor yum found. Cannot continue.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}Using package manager: ${PKG_MGR}${RESET}"
}

basic_app_requirements() {
  echo -e "${CYAN}Ensuring basic app requirements (/app, /app/logs, roboshop user)...${RESET}"

  # /app
  if [[ -d "${APP_DIR}" ]]; then
    echo -e "${YELLOW}${APP_DIR} already exists. Skipping creation.${RESET}"
  else
    mkdir -p "${APP_DIR}"
    validate_step $? \
      "Created ${APP_DIR} directory." \
      "Failed to create ${APP_DIR} directory."
  fi

  # /app/logs
  mkdir -p "${LOGS_DIR}"
  validate_step $? \
    "Logs directory ${LOGS_DIR} is ready." \
    "Failed to create logs directory ${LOGS_DIR}."

  # roboshop user
  if id roboshop >/dev/null 2>&1; then
    echo -e "${YELLOW}User 'roboshop' already exists. Skipping creation.${RESET}"
  else
    useradd roboshop
    validate_step $? \
      "User 'roboshop' created successfully." \
      "Failed to create user 'roboshop'."
  fi

  chown -R roboshop:roboshop "${APP_DIR}"
  validate_step $? \
    "Ownership of ${APP_DIR} set to roboshop:roboshop." \
    "Failed to set ownership on ${APP_DIR}."
}

install_util_packages() {
  echo -e "${CYAN}Installing utility packages from ${UTIL_PKG_FILE}...${RESET}"

  if [[ ! -f "${UTIL_PKG_FILE}" ]]; then
    echo -e "${YELLOW}Utility package file ${UTIL_PKG_FILE} not found. Skipping util package install.${RESET}"
    return
  fi

  local PKGS=()
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    PKGS+=("${line}")
  done < "${UTIL_PKG_FILE}"

  if [[ "${#PKGS[@]}" -eq 0 ]]; then
    echo -e "${YELLOW}No packages listed in ${UTIL_PKG_FILE}. Skipping util package install.${RESET}"
    return
  fi

  echo -e "${CYAN}Installing: ${PKGS[*]}${RESET}"
  ${PKG_MGR} install -y "${PKGS[@]}"
  validate_step $? \
    "Utility packages installed successfully." \
    "Failed to install one or more utility packages."
}

install_python_and_build_deps() {
  echo -e "${CYAN}Installing Python 3.6 + build dependencies...${RESET}"

  # Matching the doc: python36, gcc, python3-devel - we also add python3-pip to be safe
  local pkgs=(python36 python36-devel gcc python3-pip)

  ${PKG_MGR} install -y "${pkgs[@]}"
  validate_step $? \
    "Python 3.6, build deps and pip installed (or already present)." \
    "Failed to install Python 3.6 and build deps."

  if command -v python3.6 >/dev/null 2>&1; then
    local ver
    ver="$(python3.6 -c 'import sys; print("{}.{}".format(sys.version_info.major, sys.version_info.minor))')"
    echo -e "${GREEN}python3.6 detected. Version: ${ver}${RESET}"
  else
    echo -e "${RED}python3.6 not found on PATH even after installation.${RESET}"
    exit 1
  fi
}

deploy_payment_code() {
  echo -e "${CYAN}Deploying payment application into ${APP_DIR}...${RESET}"

  echo -e "${CYAN}Downloading payment.zip to /tmp/payment.zip...${RESET}"
  curl -s -L -o /tmp/payment.zip "${PAYMENT_ZIP_URL}"
  validate_step $? \
    "Downloaded payment.zip successfully." \
    "Failed to download payment.zip."

  echo -e "${CYAN}Cleaning old payment files (payment.py, rabbitmq.py, payment.ini, requirements.txt) from ${APP_DIR}...${RESET}"
  rm -f "${APP_DIR}/payment.py" \
        "${APP_DIR}/rabbitmq.py" \
        "${APP_DIR}/payment.ini" \
        "${APP_DIR}/requirements.txt" 2>/dev/null || true

  echo -e "${CYAN}Unzipping payment.zip into ${APP_DIR}...${RESET}"
  unzip -o /tmp/payment.zip -d "${APP_DIR}" >/dev/null
  validate_step $? \
    "Unzipped payment application into ${APP_DIR}." \
    "Failed to unzip payment application."

  chown -R roboshop:roboshop "${APP_DIR}"
  validate_step $? \
    "Re-applied ownership of ${APP_DIR} to roboshop:roboshop." \
    "Failed to set ownership on ${APP_DIR}."
}

install_python_dependencies() {
  echo -e "${CYAN}Installing Python dependencies (including pyuwsgi) as root...${RESET}"

  local REQ_FILE="${APP_DIR}/requirements.txt"

  if [[ ! -f "${REQ_FILE}" ]]; then
    echo -e "${RED}requirements.txt not found at ${REQ_FILE}. Cannot install dependencies.${RESET}"
    exit 1
  fi

  python3.6 -m pip install -r "${REQ_FILE}"
  validate_step $? \
    "Installed Python dependencies from requirements.txt." \
    "Failed to install Python dependencies."

  if [[ -x "/usr/local/bin/uwsgi" ]]; then
    echo -e "${GREEN}uwsgi binary found at /usr/local/bin/uwsgi.${RESET}"
  else
    echo -e "${YELLOW}WARNING: /usr/local/bin/uwsgi not found. Check pyuwsgi installation if service fails to start.${RESET}"
  fi
}

install_systemd_service() {
  echo -e "${CYAN}Configuring systemd payment.service using template: ${PAYMENT_SERVICE_TEMPLATE}${RESET}"

  if [[ ! -f "${PAYMENT_SERVICE_TEMPLATE}" ]]; then
    echo -e "${RED}Template ${PAYMENT_SERVICE_TEMPLATE} not found. Cannot create systemd service.${RESET}"
    exit 1
  fi

  if [[ -f "${SYSTEMD_SERVICE_FILE}" ]]; then
    local backup="${SYSTEMD_SERVICE_FILE}.$(date +%F-%H-%M-%S).bak"
    echo -e "${YELLOW}Existing payment.service found. Backing up to ${backup}.${RESET}"
    cp "${SYSTEMD_SERVICE_FILE}" "${backup}"
    validate_step $? \
      "Backed up existing payment.service." \
      "Failed to backup existing payment.service."
  fi

  cp "${PAYMENT_SERVICE_TEMPLATE}" "${SYSTEMD_SERVICE_FILE}"
  validate_step $? \
    "Copied payment.service template to ${SYSTEMD_SERVICE_FILE}." \
    "Failed to copy payment.service template."

  echo -e "${CYAN}Reloading systemd daemon...${RESET}"
  systemctl daemon-reload
  validate_step $? \
    "systemd daemon reloaded." \
    "Failed to reload systemd daemon."

  echo -e "${CYAN}Enabling payment.service at boot...${RESET}"
  systemctl enable payment >/dev/null 2>&1
  validate_step $? \
    "payment.service enabled." \
    "Failed to enable payment.service."

  echo -e "${CYAN}Restarting payment.service...${RESET}"
  systemctl restart payment
  validate_step $? \
    "payment.service restarted successfully." \
    "Failed to start/restart payment.service."
}

# ==========================================================
# Main
# ==========================================================

main() {
  # Setup logging to file
  mkdir -p "${LOGS_DIR}"
  exec >>"${LOG_FILE}" 2>&1

  print_header
  echo -e "${CYAN}Script Name   : ${SCRIPT_NAME}${RESET}"
  echo -e "${CYAN}Script Dir    : ${SCRIPT_DIR}${RESET}"
  echo -e "${CYAN}App Directory : ${APP_DIR}${RESET}"
  echo -e "${CYAN}Logs Directory: ${LOGS_DIR}${RESET}"
  echo -e "${CYAN}Log File      : ${LOG_FILE}${RESET}"

  ensure_root
  detect_pkg_mgr
  basic_app_requirements
  install_util_packages
  install_python_and_build_deps
  deploy_payment_code
  install_python_dependencies
  install_systemd_service

  echo -e "${GREEN}Payment setup script completed successfully.${RESET}"
  echo -e "${CYAN}Check status with:${RESET} systemctl status payment.service -l"
}

main "$@"
