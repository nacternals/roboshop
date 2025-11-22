#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Payment Service Setup Script for RoboShop
#
# What this script does:
#   - Detects package manager (dnf / yum)
#   - Installs Python 3.6 + build deps (python36, python36-devel, gcc)
#   - Creates 'roboshop' user
#   - Creates /app and deploys payment code there
#   - Installs Python dependencies (including pyuwsgi) as root
#   - Creates /etc/systemd/system/payment.service using uwsgi
#   - Reloads systemd, enables and starts payment.service
#
# Service is configured to run as 'roboshop' (NOT root).
# Adjust CART/USER/RABBITMQ hostnames as needed near the bottom.
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
PAYMENT_ZIP_URL="https://roboshop-builds.s3.amazonaws.com/payment.zip"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/payment.service"

# Use your actual hosts here (change if needed)
CART_HOST="cart.optimusprime.sbs"
CART_PORT="8080"
USER_HOST="user.optimusprime.sbs"
USER_PORT="8080"
AMQP_HOST="rabbitmq.optimusprime.sbs"
AMQP_USER="roboshop"
AMQP_PASS="roboshop123"

# Will be set after detection
PKG_MGR=""

# ==========================================================
# Helper Functions
# ==========================================================

print_header() {
  echo -e "${BLUE}===========================================${RESET}"
  echo -e "${CYAN} Payment Service Setup Script${RESET}"
  echo -e "${YELLOW} Started @ $(date +"%F %T")${RESET}"
  echo -e "${BLUE}===========================================${RESET}"
}

validate_step() {
  local EXIT_CODE="$1"
  local SUCCESS_MSG="$2"
  local FAILURE_MSG="$3"

  if [[ "${EXIT_CODE}" -eq 0 ]]; then
    echo -e "${GREEN}[OK]${RESET} ${SUCCESS_MSG}"
  else
    echo -e "${RED}[ERROR]${RESET} ${FAILURE_MSG} (exit code: ${EXIT_CODE})"
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

install_python_and_build_deps() {
  echo -e "${CYAN}Installing Python 3.6 and build dependencies...${RESET}"

  # The original doc uses: dnf install python36 gcc python3-devel -y
  # On CentOS Stream 8 we know python36 + python36-devel exist.
  # We'll install python36, python36-devel, gcc and ignore python3-devel.
  local pkgs=(python36 python36-devel gcc)

  ${PKG_MGR} install -y "${pkgs[@]}" >/dev/null 2>&1
  validate_step $? \
    "Python 3.6 and build deps installed (or already present)." \
    "Failed to install Python 3.6 and build deps."

  if command -v python3.6 >/dev/null 2>&1; then
    local ver
    ver="$(python3.6 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    echo -e "${GREEN}Python 3.6 is available. Detected version: ${ver}${RESET}"
  else
    echo -e "${RED}python3.6 not found on PATH even after installation.${RESET}"
    exit 1
  fi
}

create_app_user_and_dir() {
  echo -e "${CYAN}Ensuring 'roboshop' user and /app directory exist...${RESET}"

  if id roboshop >/dev/null 2>&1; then
    echo -e "${YELLOW}User 'roboshop' already exists. Skipping user creation.${RESET}"
  else
    useradd roboshop
    validate_step $? \
      "User 'roboshop' created successfully." \
      "Failed to create user 'roboshop'."
  fi

  if [[ -d "${APP_DIR}" ]]; then
    echo -e "${YELLOW}${APP_DIR} directory already exists.${RESET}"
  else
    mkdir -p "${APP_DIR}"
    validate_step $? \
      "Created ${APP_DIR} directory." \
      "Failed to create ${APP_DIR} directory."
  fi

  chown -R roboshop:roboshop "${APP_DIR}"
  validate_step $? \
    "Ownership of ${APP_DIR} set to roboshop:roboshop." \
    "Failed to set ownership for ${APP_DIR}."
}

deploy_payment_code() {
  echo -e "${CYAN}Deploying payment application to ${APP_DIR}...${RESET}"

  echo -e "${CYAN}Downloading payment.zip to /tmp/payment.zip...${RESET}"
  curl -s -L -o /tmp/payment.zip "${PAYMENT_ZIP_URL}"
  validate_step $? \
    "Downloaded payment.zip successfully." \
    "Failed to download payment.zip."

  # Optional: clean old contents (only payment-related files)
  # Careful here if you also store other apps in /app
  echo -e "${CYAN}Cleaning old payment files from ${APP_DIR} (keeping directory)...${RESET}"
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
    "Failed to apply ownership to ${APP_DIR}."
}

install_python_dependencies() {
  echo -e "${CYAN}Installing Python dependencies (including pyuwsgi) globally as root...${RESET}"

  if [[ ! -f "${APP_DIR}/requirements.txt" ]]; then
    echo -e "${RED}requirements.txt not found in ${APP_DIR}. Cannot install dependencies.${RESET}"
    exit 1
  fi

  # Install everything (including pyuwsgi) as root so that
  # /usr/local/bin/uwsgi and libraries are created without permission issues.
  pip3.6 install -r "${APP_DIR}/requirements.txt" >/dev/null
  validate_step $? \
    "Installed Python dependencies from requirements.txt." \
    "Failed to install Python dependencies."

  if [[ -x "/usr/local/bin/uwsgi" ]]; then
    echo -e "${GREEN}uwsgi binary found at /usr/local/bin/uwsgi.${RESET}"
  else
    echo -e "${YELLOW}WARNING: /usr/local/bin/uwsgi not found. Check pyuwsgi installation.${RESET}"
  fi
}

create_systemd_service() {
  echo -e "${CYAN}Creating systemd service file: ${SYSTEMD_SERVICE_FILE}${RESET}"

  if [[ -f "${SYSTEMD_SERVICE_FILE}" ]]; then
    local backup="${SYSTEMD_SERVICE_FILE}.$(date +%F-%H-%M-%S).bak"
    echo -e "${YELLOW}Existing payment.service found. Backing up to ${backup}.${RESET}"
    cp "${SYSTEMD_SERVICE_FILE}" "${backup}"
    validate_step $? \
      "Backed up existing payment.service." \
      "Failed to backup existing payment.service."
  fi

  cat > "${SYSTEMD_SERVICE_FILE}" <<EOF
[Unit]
Description=Payment Service
After=network.target

[Service]
User=roboshop
WorkingDirectory=${APP_DIR}
Environment=CART_HOST=${CART_HOST}
Environment=CART_PORT=${CART_PORT}
Environment=USER_HOST=${USER_HOST}
Environment=USER_PORT=${USER_PORT}
Environment=AMQP_HOST=${AMQP_HOST}
Environment=AMQP_USER=${AMQP_USER}
Environment=AMQP_PASS=${AMQP_PASS}

ExecStart=/usr/local/bin/uwsgi --ini payment.ini
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
SyslogIdentifier=payment

[Install]
WantedBy=multi-user.target
EOF

  validate_step $? \
    "Created ${SYSTEMD_SERVICE_FILE}." \
    "Failed to create ${SYSTEMD_SERVICE_FILE}."

  echo -e "${CYAN}Reloading systemd daemon...${RESET}"
  systemctl daemon-reload
  validate_step $? \
    "systemd daemon reloaded." \
    "Failed to reload systemd daemon."

  echo -e "${CYAN}Enabling payment.service to start on boot...${RESET}"
  systemctl enable payment >/dev/null 2>&1
  validate_step $? \
    "payment.service enabled." \
    "Failed to enable payment.service."

  echo -e "${CYAN}Starting (or restarting) payment.service...${RESET}"
  systemctl restart payment
  validate_step $? \
    "payment.service started successfully." \
    "Failed to start payment.service."

  echo -e "${GREEN}payment.service is now configured and running.${RESET}"
}

# ==========================================================
# Main
# ==========================================================

main() {
  print_header
  ensure_root
  detect_pkg_mgr
  install_python_and_build_deps
  create_app_user_and_dir
  deploy_payment_code
  install_python_dependencies
  create_systemd_service

  echo -e "${GREEN}Payment setup completed successfully.${RESET}"
  echo -e "${CYAN}You can check status with:${RESET} systemctl status payment.service -l"
}

main "$@"
