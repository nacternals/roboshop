#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Payment Service Setup Script for RoboShop
#
# Responsibilities:
#   - Ensure /app and /app/logs exist and owned by 'roboshop'
#   - Install utility packages from 28_payments_util_packages.txt
#   - Ensure Python 3.6+, gcc, python3-devel, python3-pip are present
#   - Download and configure Payment Python microservice in /app/payment
#   - Configure and enable payment.service (SystemD unit)
#
# NOTE:
#   - installPython() is called *inside* installPaymentApplication()
#     so the payment setup is self-contained.
# ==========================================================

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---------- Config ----------
TIMESTAMP="$(date +"%F-%H-%M-%S")"

APP_DIR="/app"
LOGS_DIRECTORY="${APP_DIR}/logs"
PAYMENT_APP_DIR="/app/payment"

SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

UTIL_PKG_FILE="${SCRIPT_DIR}/28_payments_util_packages.txt"
PAYMENT_SERVICE_FILE="${SCRIPT_DIR}/29_payment.service"

PKG_MGR="dnf"
if ! command -v dnf >/dev/null 2>&1; then PKG_MGR="yum"; fi

# ==========================================================
# Helper Functions
# ==========================================================

printBoxHeader() {
	local TITLE="$1"
	local TIME="$2"

	echo -e "${BLUE}===========================================${RESET}"
	printf "${CYAN}%20s${RESET}\n" "$TITLE"
	printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
	echo -e "${BLUE}===========================================${RESET}"
}

validateStep() {
	local STATUS="$1"
	local SUCCESS_MSG="$2"
	local FAILURE_MSG="$3"

	if [[ "${STATUS}" -eq 0 ]]; then
		echo -e "${GREEN}[SUCCESS]${RESET} ${SUCCESS_MSG}"
	else
		echo -e "${RED}[FAILURE]${RESET} ${FAILURE_MSG} (exit code: ${STATUS})"
		exit "${STATUS}"
	fi
}

isItRootUser() {
	echo -e "${CYAN}Checking whether script is running as ROOT...${RESET}"

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		if command -v sudo >/dev/null 2>&1; then
			SUDO="sudo"
			echo -e "${YELLOW}Not ROOT. Using 'sudo' for privileged operations.${RESET}"
		else
			echo -e "${RED}ERROR: Insufficient privileges. Run as ROOT or install sudo.${RESET}"
			exit 1
		fi
	else
		SUDO=""
		echo -e "${GREEN}Executing this script as ROOT user.${RESET}"
	fi
}

basicAppRequirements() {
	echo -e "${CYAN}Ensuring basic application requirements...${RESET}"

	[[ -d "${APP_DIR}" ]] || ${SUDO:-} mkdir -p "${APP_DIR}"
	validateStep $? "${APP_DIR} ready." "Failed to create ${APP_DIR}"

	${SUDO:-} mkdir -p "${LOGS_DIRECTORY}"
	validateStep $? "Logs directory ready." "Failed to create logs dir"

	if ! id roboshop >/dev/null 2>&1; then
		${SUDO:-} useradd roboshop
		validateStep $? "roboshop user created." "Failed creating roboshop user"
	fi

	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? "Ownership fixed for ${APP_DIR}." "Failed to chown ${APP_DIR}"
}

installUtilPackages() {
	if [[ ! -f "${UTIL_PKG_FILE}" ]]; then
		echo -e "${RED}Utility package file missing: ${UTIL_PKG_FILE}${RESET}"
		exit 1
	fi

	mapfile -t PACKAGES < <(grep -vE '^\s*$' "${UTIL_PKG_FILE}")

	for PKG in "${PACKAGES[@]}"; do
		${SUDO:-} "${PKG_MGR}" install -y "${PKG}"
		validateStep $? "Installed ${PKG}" "Failed installing ${PKG}"
	done
}

installPython() {
	echo -e "${CYAN}Installing Python & Build deps...${RESET}"

	${SUDO:-} "${PKG_MGR}" install -y python36 gcc python3-devel
	validateStep $? "Python installed." "Failed installing Python"

	local version
	version=$(
		python3 - <<'EOF'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
EOF
	)
	echo -e "${GREEN}Python version: $version${RESET}"
}

installPaymentApplication() {
	echo -e "${CYAN}Setting up Payment application...${RESET}"

	installPython

	${SUDO:-} mkdir -p "${PAYMENT_APP_DIR}"
	validateStep $? "App directory ready." "Failed creating app dir"

	${SUDO:-} curl -s -L -o /tmp/payment.zip "https://roboshop-builds.s3.amazonaws.com/payment.zip"
	validateStep $? "Downloaded payment.zip" "Failed downloading zip"

	${SUDO:-} unzip -o /tmp/payment.zip -d "${PAYMENT_APP_DIR}"
	validateStep $? "Unzipped payment" "Failed unzipping payment"

	${SUDO:-} chown -R roboshop:roboshop "${PAYMENT_APP_DIR}"

		echo -e "${CYAN}Installing pip dependencies as roboshop (user mode)...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c \
		"cd ${PAYMENT_APP_DIR} && pip3.6 install -r requirements.txt"
	validateStep $? "Dependencies installed." "pip install failed"
}

createPaymentSystemDService() {
	local TARGET="/etc/systemd/system/payment.service"

	if [[ -f "${TARGET}" ]]; then
		${SUDO:-} cp "${TARGET}" "${TARGET}.$(date +%F-%H-%M-%S).bak"
	fi

	${SUDO:-} cp -f "${PAYMENT_SERVICE_FILE}" "${TARGET}"
	validateStep $? "Service installed." "Failed copying systemd file"

	${SUDO:-} systemctl daemon-reload
	${SUDO:-} systemctl enable payment
	${SUDO:-} systemctl restart payment
	validateStep $? "Payment service running." "Failed starting service"
}

# ==========================================================
# Main Execution
# ==========================================================

main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Payment Service Setup Script Execution" "${TIMESTAMP}"

	isItRootUser
	basicAppRequirements
	installUtilPackages
	installPaymentApplication
	createPaymentSystemDService

	echo -e "${GREEN}Payment service setup completed successfully.${RESET}"
}

main "$@"
