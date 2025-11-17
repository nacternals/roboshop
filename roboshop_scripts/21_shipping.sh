#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Shipping Microservice Setup Script for RoboShop
# - Creates base /app and logs structure
# - Ensures roboshop user
# - Installs utility packages and Maven
# - Downloads, builds, and deploys Shipping microservice
# - Configures and manages shipping.service (systemd)
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
SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"
UTIL_PKG_FILE="${SCRIPT_DIR}/22_shipping_util_packages.txt"

SHIPPING_APP_DIR="${APP_DIR}/shipping"
SHIPPING_SERVICE_FILE="${SCRIPT_DIR}/23_shipping.service"


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

	# Ensure app directory
	if [[ -d "${APP_DIR}" ]]; then
		echo -e "${YELLOW}${APP_DIR} directory already exists. Skipping creation....${RESET}"
	else
		echo -e "${CYAN}${APP_DIR} directory not found. Creating ${APP_DIR}....${RESET}"
		${SUDO:-} mkdir -p "${APP_DIR}"
		validateStep $? \
			"${APP_DIR} directory created successfully." \
			"Failed to create ${APP_DIR} directory."
	fi

	# Ensure logs directory
	echo -e "${CYAN}Ensuring logs directory ${LOGS_DIRECTORY} exists...${RESET}"
	${SUDO:-} mkdir -p "${LOGS_DIRECTORY}"
	validateStep $? \
		"Logs directory ${LOGS_DIRECTORY} is ready." \
		"Failed to create logs directory ${LOGS_DIRECTORY}."

	# Ensure roboshop user
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

	# Ownership of /app
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
		echo -e "${YELLOW}Utility package file not found: ${UTIL_PKG_FILE}. Skipping utility installation.${RESET}"
		echo -e "${YELLOW}If you need utilities, create this file with one package name per line and rerun.${RESET}"
		return
	fi

	# Read packages into an array (skip empty lines)
	local PACKAGES=()
	while IFS= read -r PKG; do
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

# ---------- Function: installMaven ----------
# Purpose : Install Maven (and Java if required by the repo).
installMaven() {
	echo -e "${CYAN}Installing Maven (and Java if required)...${RESET}"
	${SUDO:-} "${PKG_MGR}" install -y maven
	validateStep $? \
		"Maven installed successfully." \
		"Failed to install Maven."
}

# ---------- Function: installShippingApplication ----------
# Purpose : Download, extract, and build the Shipping microservice.
installShippingApplication() {
    echo -e "${CYAN}Setting up Shipping application...${RESET}"

    # Ensure Java/Maven are ready (if you have dedicated installers, call them here)
    installMaven   # or installJava / installMavenJava etc, as per your pattern

    # Ensure app directory exists
    echo -e "${CYAN}Ensuring ${SHIPPING_APP_DIR} directory exists...${RESET}"
    ${SUDO:-} mkdir -p "${SHIPPING_APP_DIR}"
    validateStep $? \
        "${SHIPPING_APP_DIR} directory is ready." \
        "Failed to create ${SHIPPING_APP_DIR} directory."

    # Download shipping code bundle
    echo -e "${CYAN}Downloading shipping application code to /tmp/shipping.zip...${RESET}"
    ${SUDO:-} curl -s -L -o /tmp/shipping.zip "https://roboshop-builds.s3.amazonaws.com/shipping.zip"
    validateStep $? \
        "Shipping application zip downloaded successfully." \
        "Failed to download shipping application zip."

    # Unzip into /app/shipping (NOT directly into /app)
    echo -e "${CYAN}Unzipping shipping application into ${SHIPPING_APP_DIR}...${RESET}"
    ${SUDO:-} unzip -o /tmp/shipping.zip -d "${SHIPPING_APP_DIR}" >/dev/null
    validateStep $? \
        "Shipping application unzipped into ${SHIPPING_APP_DIR} successfully." \
        "Failed to unzip shipping application into ${SHIPPING_APP_DIR}."

    echo -e "${CYAN}Setting ownership of ${SHIPPING_APP_DIR} to user 'roboshop'...${RESET}"
    ${SUDO:-} chown -R roboshop:roboshop "${SHIPPING_APP_DIR}"
    validateStep $? \
        "Ownership of ${SHIPPING_APP_DIR} set to roboshop successfully." \
        "Failed to set ownership of ${SHIPPING_APP_DIR} to roboshop."

    # Build the jar as roboshop
    echo -e "${CYAN}Building Shipping JAR (mvn clean package) as 'roboshop'...${RESET}"
    ${SUDO:-} su - roboshop -s /bin/bash -c "cd ${SHIPPING_APP_DIR} && mvn clean package" >/dev/null
    validateStep $? \
        "Shipping application built successfully (mvn clean package)." \
        "Failed to build Shipping application (mvn clean package)."

    # Normalise jar name to /app/shipping/shipping.jar if your pom creates another name
    if [[ -f ${SHIPPING_APP_DIR}/target/shipping-1.0.jar && ! -f ${SHIPPING_APP_DIR}/shipping.jar ]]; then
        ${SUDO:-} cp "${SHIPPING_APP_DIR}/target/shipping-1.0.jar" "${SHIPPING_APP_DIR}/shipping.jar"
        ${SUDO:-} chown roboshop:roboshop "${SHIPPING_APP_DIR}/shipping.jar"
    fi

    echo -e "${GREEN}Shipping application setup completed.${RESET}"
}


# ---------- Function: createShippingSystemDService ----------
# Purpose : Create and enable the shipping.service SystemD unit.
createShippingSystemDService() {
	echo -e "${CYAN}Checking Shipping SystemD service...${RESET}"

	local TARGET_SERVICE_FILE="/etc/systemd/system/shipping.service"

	if [[ -f "${TARGET_SERVICE_FILE}" ]]; then
		echo -e "${YELLOW}Shipping SystemD service already exists. Taking backup and overwriting with latest definition....${RESET}"
		local BACKUP_FILE="${TARGET_SERVICE_FILE}.$(date +%F-%H-%M-%S).bak"
		${SUDO:-} cp "${TARGET_SERVICE_FILE}" "${BACKUP_FILE}"
		validateStep $? \
			"Existing shipping.service backed up to ${BACKUP_FILE}." \
			"Failed to backup existing shipping.service."
	else
		echo -e "${CYAN}Shipping SystemD service not found. Creating new Shipping SystemD service....${RESET}"
	fi

	echo "Shipping service file source: ${SHIPPING_SERVICE_FILE}"

	# Always copy (create or overwrite)
	${SUDO:-} cp -f "${SHIPPING_SERVICE_FILE}" "${TARGET_SERVICE_FILE}"
	validateStep $? \
		"Shipping SystemD service file has been created/updated at ${TARGET_SERVICE_FILE}." \
		"Failed to create/update Shipping SystemD service file. Copy operation failed."

	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	echo -e "${CYAN}Enabling shipping service to start on boot...${RESET}"
	${SUDO:-} systemctl enable shipping
	validateStep $? \
		"Shipping service enabled to start on boot." \
		"Failed to enable shipping service."

	echo -e "${CYAN}Restarting shipping service...${RESET}"
	${SUDO:-} systemctl restart shipping
	validateStep $? \
		"Shipping service restarted successfully with latest configuration." \
		"Failed to restart shipping service."

	echo -e "${GREEN}Shipping SystemD service created/updated and restarted successfully.${RESET}"
}

# ==========================================================
# Main Execution
# ==========================================================

main() {
	# Ensure logs directory exists before redirect
	mkdir -p "${LOGS_DIRECTORY}"
	# Redirect all stdout and stderr to log file
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Shipping Service Setup Script Execution" "${TIMESTAMP}"

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
	echo "Shipping Service File: ${SHIPPING_SERVICE_FILE}"
	echo "Utility Pkg File     : ${UTIL_PKG_FILE}"
	echo -e "${CYAN}==============================${RESET}"

	isItRootUser

	# Now SUDO is known, echo it as well
	echo "SUDO helper          : ${SUDO:-<not set>}"

	basicAppRequirements
	installUtilPackages
	installMaven
	installShippingApplication
	createShippingSystemDService

	echo -e "${GREEN}Shipping service setup script completed successfully.${RESET}"
}

main "$@"
