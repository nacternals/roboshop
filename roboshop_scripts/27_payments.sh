#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Payment Service Setup Script for RoboShop
#
# Responsibilities:
#   - Ensure /app and /app/logs exist and owned by 'roboshop'
#   - Install utility packages from 28_payments_util_packages.txt
#   - Ensure Python 3.6+, gcc, python3-devel are present
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

# Utility package list lives inside the git repo, next to script
UTIL_PKG_FILE="${SCRIPT_DIR}/28_payments_util_packages.txt"
PAYMENT_SERVICE_FILE="${SCRIPT_DIR}/29_payment.service"

# Package manager (dnf or yum)
PKG_MGR="dnf"
if ! command -v dnf >/dev/null 2>&1; then
	PKG_MGR="yum"
fi

# ==========================================================
# Helper Functions
# ==========================================================

# ---------- Function: printBoxHeader ----------
# Purpose : Print a nice header for script execution.
# Args    : $1 -> Title text
#           $2 -> Time string
printBoxHeader() {
	local TITLE="$1"
	local TIME="$2"

	echo -e "${BLUE}===========================================${RESET}"
	printf "${CYAN}%20s${RESET}\n" "$TITLE"
	printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
	echo -e "${BLUE}===========================================${RESET}"
}

# ---------- Function: validateStep ----------
# Purpose : Standardized status check for steps.
# Args    : $1 -> Exit code
#           $2 -> Success message
#           $3 -> Failure message
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

# ---------- Function: isItRootUser ----------
# Purpose : Ensure script has privileges (root or sudo).
# Effects : Sets global SUDO variable accordingly.
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

# ---------- Function: basicAppRequirements ----------
# Purpose : Ensure /app, logs dir, and roboshop user exist with proper ownership.
basicAppRequirements() {
	echo -e "${CYAN}Ensuring basic application requirements (${APP_DIR} dir, logs dir and roboshop user)...${RESET}"

	if [[ -d "${APP_DIR}" ]]; then
		echo -e "${YELLOW}${APP_DIR} directory already exists. Skipping creation....${RESET}"
	else
		echo -e "${CYAN}${APP_DIR} directory not found. Creating ${APP_DIR}....${RESET}"
		${SUDO:-} mkdir -p "${APP_DIR}"
		validateStep $? \
			"${APP_DIR} directory created successfully." \
			"Failed to create ${APP_DIR} directory."
	fi

	echo -e "${CYAN}Ensuring logs directory ${LOGS_DIRECTORY} exists...${RESET}"
	${SUDO:-} mkdir -p "${LOGS_DIRECTORY}"
	validateStep $? \
		"Logs directory ${LOGS_DIRECTORY} is ready." \
		"Failed to create logs directory ${LOGS_DIRECTORY}."

	echo -e "${CYAN}Checking if 'roboshop' user exists....${RESET}"
	if id roboshop >/dev/null 2>&1; then
		echo -e "${YELLOW}User 'roboshop' already exists. Skipping user creation....${RESET}"
	else
		echo -e "${CYAN}Creating application user 'roboshop'...${RESET}"
		${SUDO:-} useradd roboshop
		validateStep $? \
			"Application user 'roboshop' created successfully." \
			"Failed to create application user 'roboshop'."
	fi

	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

# ---------- Function: installUtilPackages ----------
# Purpose : Install common utility packages required by this script.
# Details : Reads package names from ${UTIL_PKG_FILE} (one per line).
installUtilPackages() {
	echo -e "${CYAN}Checking utility package list file: ${UTIL_PKG_FILE}${RESET}"

	# Ensure the util package file exists
	if [[ ! -f "${UTIL_PKG_FILE}" ]]; then
		echo -e "${RED}ERROR: Utility package file not found: ${UTIL_PKG_FILE}${RESET}"
		echo -e "${YELLOW}Create the file and add one package name per line, then rerun the script.${RESET}"
		exit 1
	fi

	# Read packages into an array (skip empty lines)
	local PACKAGES=()
	while IFS= read -r PKG; do
		# Trim simple whitespace and skip blank lines
		[[ -z "${PKG}" ]] && continue
		PACKAGES+=("${PKG}")
	done <"${UTIL_PKG_FILE}"

	if [[ "${#PACKAGES[@]}" -eq 0 ]]; then
		echo -e "${YELLOW}No packages found in ${UTIL_PKG_FILE}. Skipping utility installation.${RESET}"
		return
	fi

	echo -e "${CYAN}Utility packages to install: ${PACKAGES[*]}${RESET}"

	# Install each package individually to track success/failure per package
	for PKG in "${PACKAGES[@]}"; do
		echo -e "${CYAN}Installing utility package: ${PKG}${RESET}"
		${SUDO:-} "${PKG_MGR}" install -y "${PKG}"
		validateStep $? \
			"Utility package '${PKG}' installed successfully." \
			"Failed to install utility package '${PKG}'."
	done

	echo -e "${GREEN}All requested utility packages processed successfully.${RESET}"
}

# ---------- Function: installPython ----------
# Purpose : Ensure Python 3.6+, gcc, and python3-devel are installed.
# Notes   : Called from installPaymentApplication() so that the payment
#           setup is self-contained and safe to run independently.
installPython() {
	echo -e "${CYAN}Checking if Python 3 is already installed...${RESET}"

	local py_cmd=""
	if command -v python3 >/dev/null 2>&1; then
		py_cmd="python3"
	elif command -v python >/dev/null 2>&1; then
		py_cmd="python"
	fi

	if [[ -n "${py_cmd}" ]]; then
		local py_version
		py_version="$(${py_cmd} -c 'import sys; v=sys.version_info; print(f\"{v.major}.{v.minor}\")' 2>/dev/null || echo "0.0")"
		local py_major="${py_version%%.*}"
		local py_minor="${py_version#*.}"

		echo -e "${YELLOW}Found Python command: ${py_cmd} (version: ${py_version})${RESET}"

		if ((py_major > 3)) || ((py_major == 3 && py_minor >= 6)); then
			echo -e "${GREEN}Python version is already >= 3.6. Skipping Python core installation, ensuring gcc & python3-devel...${RESET}"
		else
			echo -e "${YELLOW}Python version is < 3.6. Will try to install/upgrade to Python 3.6+.${RESET}"
			py_cmd=""
		fi
	else
		echo -e "${YELLOW}Python is not installed. Proceeding with fresh installation of Python 3.6+...${RESET}"
	fi

	# Try to install python3 / python36 + gcc + python3-devel
	if [[ -z "${py_cmd}" ]]; then
		echo -e "${CYAN}Installing Python 3 (python3 / python36), gcc, and python3-devel...${RESET}"

		local python_candidates=(python3 python36)
		local python_pkg=""
		for pkg in "${python_candidates[@]}"; do
			if ${SUDO:-} "${PKG_MGR}" list available "${pkg}" >/dev/null 2>&1; then
				python_pkg="${pkg}"
				break
			fi
		done

		if [[ -z "${python_pkg}" ]]; then
			echo -e "${RED}ERROR: Could not find a suitable Python 3 package (tried: ${python_candidates[*]}).${RESET}"
			exit 1
		fi

		echo -e "${CYAN}Using Python package: ${python_pkg}${RESET}"
		${SUDO:-} "${PKG_MGR}" install -y "${python_pkg}" gcc python3-devel
		validateStep $? \
			"Installed ${python_pkg}, gcc, and python3-devel successfully." \
			"Failed to install ${python_pkg}, gcc, and/or python3-devel."
	else
		# Python 3.6+ already present; just ensure gcc & python3-devel
		echo -e "${CYAN}Ensuring gcc and python3-devel are installed...${RESET}"

		local ensure_pkgs=(gcc python3-devel)
		for pkg in "${ensure_pkgs[@]}"; do
			if rpm -q "${pkg}" >/dev/null 2>&1; then
				echo -e "${YELLOW}Package '${pkg}' already installed. Skipping....${RESET}"
			else
				echo -e "${CYAN}Installing missing package: ${pkg}${RESET}"
				${SUDO:-} "${PKG_MGR}" install -y "${pkg}"
				validateStep $? \
					"Package '${pkg}' installed successfully." \
					"Failed to install package '${pkg}'."
			fi
		done
	fi

	# Final verification
	echo -e "${CYAN}Verifying Python installation and version...${RESET}"
	if command -v python3 >/dev/null 2>&1; then
		local final_py_version
		final_py_version="$(python3 -c 'import sys; v=sys.version_info; print(f\"{v.major}.{v.minor}\")' 2>/dev/null || echo "0.0")"
		echo -e "${GREEN}Python 3 is installed. Version: ${final_py_version}${RESET}"
	else
		echo -e "${RED}Python3 command not found even after installation. Please check package manager logs and repository configuration.${RESET}"
		exit 1
	fi
}

# ---------- Function: installPaymentApplication ----------
# Purpose : Download, extract, and configure the Payment Python microservice.
# Notes   : Ensures Python and build deps by calling installPython() first.
installPaymentApplication() {
	echo -e "${CYAN}Setting up Payment application...${RESET}"

	# Ensure Python (3.6+), gcc, python3-devel are installed
	echo -e "${CYAN}Ensuring Python runtime and build dependencies are installed...${RESET}"
	installPython
	validateStep $? \
		"Python runtime and build dependencies are ready." \
		"Failed to ensure Python runtime/build dependencies."

	# Ensure payment app directory exists
	echo -e "${CYAN}Ensuring ${PAYMENT_APP_DIR} directory exists...${RESET}"
	${SUDO:-} mkdir -p "${PAYMENT_APP_DIR}"
	validateStep $? \
		"${PAYMENT_APP_DIR} directory is ready." \
		"Failed to create ${PAYMENT_APP_DIR} directory."

	# Download the payment code
	echo -e "${CYAN}Downloading payment application code to /tmp/payment.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/payment.zip "https://roboshop-builds.s3.amazonaws.com/payment.zip"
	validateStep $? \
		"Payment application zip downloaded successfully." \
		"Failed to download payment application zip."

	# Unzip into ${PAYMENT_APP_DIR}
	echo -e "${CYAN}Unzipping payment application into ${PAYMENT_APP_DIR}...${RESET}"
	${SUDO:-} unzip -o /tmp/payment.zip -d "${PAYMENT_APP_DIR}" >/dev/null
	validateStep $? \
		"Payment application unzipped into ${PAYMENT_APP_DIR} successfully." \
		"Failed to unzip payment application into ${PAYMENT_APP_DIR}."

	# Ownership
	echo -e "${CYAN}Setting ownership of ${PAYMENT_APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${PAYMENT_APP_DIR}"
	validateStep $? \
		"Ownership of ${PAYMENT_APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${PAYMENT_APP_DIR} to roboshop."

	# Install Python dependencies as roboshop user
	echo -e "${CYAN}Installing Python dependencies (pip3.6 install -r requirements.txt) as 'roboshop' user...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd ${PAYMENT_APP_DIR} && pip3.6 install -r requirements.txt" >/dev/null
	validateStep $? \
		"Python dependencies installed successfully for payment service." \
		"Failed to install Python dependencies for payment service."

	echo -e "${GREEN}Payment application setup completed.${RESET}"
}

# ---------- Function: createPaymentSystemDService ----------
# Purpose : Create, enable, and start payment.service SystemD unit.
createPaymentSystemDService() {
	echo -e "${CYAN}Checking Payment SystemD service...${RESET}"

	local TARGET_SERVICE_FILE="/etc/systemd/system/payment.service"

	if [[ -f "${TARGET_SERVICE_FILE}" ]]; then
		echo -e "${YELLOW}Payment SystemD service already exists. Taking backup and overwriting with latest definition....${RESET}"
		local BACKUP_FILE="${TARGET_SERVICE_FILE}.$(date +%F-%H-%M-%S).bak"
		${SUDO:-} cp "${TARGET_SERVICE_FILE}" "${BACKUP_FILE}"
		validateStep $? \
			"Existing payment.service backed up to ${BACKUP_FILE}." \
			"Failed to backup existing payment.service."
	else
		echo -e "${CYAN}Payment SystemD service not found. Creating new Payment SystemD service....${RESET}"
	fi

	echo "Payment service file source: ${PAYMENT_SERVICE_FILE}"

	# Always copy (create or overwrite)
	${SUDO:-} cp -f "${PAYMENT_SERVICE_FILE}" "${TARGET_SERVICE_FILE}"
	validateStep $? \
		"Payment SystemD service file has been created/updated at ${TARGET_SERVICE_FILE}." \
		"Failed to create/update Payment SystemD service file. Copy operation failed."

	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	echo -e "${CYAN}Enabling payment service to start on boot...${RESET}"
	${SUDO:-} systemctl enable payment
	validateStep $? \
		"Payment service enabled to start on boot." \
		"Failed to enable payment service."

	echo -e "${CYAN}Restarting payment service...${RESET}"
	${SUDO:-} systemctl restart payment
	validateStep $? \
		"Payment service restarted successfully with latest configuration." \
		"Failed to restart payment service."

	echo -e "${GREEN}Payment SystemD service created/updated and restarted successfully.${RESET}"
}


# ==========================================================
# Main Execution
# ==========================================================

main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Payment Service Setup Script Execution" "${TIMESTAMP}"

	# Echo all key variables for debugging / audit
	echo -e "${CYAN}==== Script Configuration ====${RESET}"
	echo "Script Name          : ${SCRIPT_NAME}"
	echo "Script Base          : ${SCRIPT_BASE}"
	echo "Script Directory     : ${SCRIPT_DIR}"
	echo "Timestamp            : ${TIMESTAMP}"
	echo "App Directory        : ${APP_DIR}"
	echo "Logs Directory       : ${LOGS_DIRECTORY}"
	echo "Log File             : ${LOG_FILE}"
	echo "Package Manager      : ${PKG_MGR}"
	echo "Utility Pkg File     : ${UTIL_PKG_FILE}"
	echo "Payment App Dir      : ${PAYMENT_APP_DIR}"
	echo "Payment Service File : ${PAYMENT_SERVICE_FILE}"
	echo -e "${CYAN}==============================${RESET}"

	isItRootUser

	# Now SUDO is known, echo it as well
	echo "SUDO helper          : ${SUDO:-<not set>}"

	basicAppRequirements
	installUtilPackages
	installPaymentApplication
	createPaymentSystemDService

	echo -e "${GREEN}Payment service setup script completed successfully.${RESET}"
}

main "$@"
