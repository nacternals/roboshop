#!/usr/bin/env bash

# This script will create and configure the Catalogue microservice.
# It:
#   - Installs required utility packages
#   - Ensures NodeJS (>= 18) is installed
#   - Creates roboshop application user and /app directory
#   - Downloads and sets up the catalogue application code under /app/catalogue
#   - Creates and starts the catalogue SystemD service
#
# Logging, colors, helper functions, and directory handling are similar to mongodb.sh.

set -euo pipefail

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---------- Config ----------
TIMESTAMP="$(date +"%F-%H-%M-%S")" # Full timestamp of this run

APP_DIR="/app"                           # Application root directory
CATALOGUE_APP_DIR="${APP_DIR}/catalogue" # Catalogue app directory
LOGS_DIRECTORY="${APP_DIR}/logs"         # Central log directory -> /app/logs

SCRIPT_NAME="$(basename "$0")"                             # e.g. catalogue.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. catalogue
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives

LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

UTIL_PKG_FILE="${SCRIPT_DIR}/05_catalogue_util_packages.txt"
CATALOGUE_SERVICE_FILE="${SCRIPT_DIR}/06_catalogue.service"

printBoxHeader() {
	local TITLE="$1"
	local TIME="$2"

	echo -e "${BLUE}===========================================${RESET}"
	printf "${CYAN}%20s${RESET}\n" "$TITLE"
	printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
	echo -e "${BLUE}===========================================${RESET}"
}

# ---------- Helper: validate step ----------
validateStep() {
	local STATUS="$1"
	local SUCCESS_MSG="$2"
	local FAILURE_MSG="$3"

	if [[ "${STATUS}" -eq 0 ]]; then
		echo -e "${GREEN}[SUCCESS]${RESET} ${SUCCESS_MSG}"
	else
		echo -e "${RED}[FAILURE]${RESET} ${_FAILURE_MSG} (exit code: ${STATUS})"
		exit "${STATUS}"
	fi
}

# ---------- Basic app requirements (/app + /app/logs + roboshop) ----------
basicAppRequirements() {
	echo -e "${CYAN}Ensuring basic application requirements (${APP_DIR} dir, logs dir and roboshop user)...${RESET}"

	# 1) Ensure /app exists
	echo -e "${CYAN}Checking ${APP_DIR} directory...${RESET}"
	if [[ -d "${APP_DIR}" ]]; then
		echo -e "${YELLOW}${APP_DIR} directory already exists. Skipping creation....${RESET}"
	else
		echo -e "${CYAN}${APP_DIR} directory not found. Creating ${APP_DIR}....${RESET}"
		${SUDO:-} mkdir -p "${APP_DIR}"
		validateStep $? \
			"${APP_DIR} directory created successfully." \
			"Failed to create ${APP_DIR} directory."
	fi

	# 2) Ensure /app/logs exists
	echo -e "${CYAN}Ensuring logs directory ${LOGS_DIRECTORY} exists...${RESET}"
	${SUDO:-} mkdir -p "${LOGS_DIRECTORY}"
	validateStep $? \
		"Logs directory ${LOGS_DIRECTORY} is ready." \
		"Failed to create logs directory ${LOGS_DIRECTORY}."

	# 3) Ensure roboshop user exists
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

	# 4) Ownership
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

# ---------- Root / sudo handling ----------
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

# ---------- Utility package installer ----------
installUtilPackages() {
	echo -e "${CYAN}Checking utility package list file: ${UTIL_PKG_FILE}${RESET}"

	if [[ ! -f "${UTIL_PKG_FILE}" ]]; then
		echo -e "${RED}ERROR: Utility package file not found: ${UTIL_PKG_FILE}${RESET}"
		echo -e "${YELLOW}Create the file and add one package name per line, then rerun the script.${RESET}"
		exit 1
	fi

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

	for PKG in "${PACKAGES[@]}"; do
		echo -e "${CYAN}Installing utility package: ${PKG}${RESET}"
		${SUDO:-} yum install -y "${PKG}"
		validateStep $? \
			"Utility package '${PKG}' installed successfully." \
			"Failed to install utility package '${PKG}'."
	done

	echo -e "${GREEN}All requested utility packages processed successfully.${RESET}"
}

# ---------- NodeJS installation ----------
installNodeJS() {
	echo -e "${CYAN}Checking if NodeJS is already installed...${RESET}"

	if command -v node >/dev/null 2>&1; then
		local node_version
		node_version="$(node -v | sed 's/^v//')"
		local node_major="${node_version%%.*}"

		echo -e "${YELLOW}Found NodeJS version: ${node_version}${RESET}"

		if ((node_major >= 18)); then
			echo -e "${GREEN}NodeJS version is already >= 18. Skipping installation.${RESET}"
			return
		else
			echo -e "${YELLOW}NodeJS version is < 18. Will try to upgrade.${RESET}"
		fi
	else
		echo -e "${YELLOW}NodeJS is not installed. Proceeding with fresh installation...${RESET}"
	fi

	echo -e "${CYAN}Checking if 'nodejs' module streams are available...${RESET}"
	if ${SUDO:-} yum module list nodejs >/dev/null 2>&1; then
		echo -e "${CYAN}NodeJS module stream detected. Using module-based installation...${RESET}"

		echo -e "${CYAN}Disabling existing NodeJS module stream (if any)...${RESET}"
		${SUDO:-} yum module disable -y nodejs
		validateStep $? \
			"Disabled existing NodeJS module stream successfully." \
			"Failed to disable existing NodeJS module stream."

		echo -e "${CYAN}Enabling NodeJS 18 module stream (nodejs:18)...${RESET}"
		${SUDO:-} yum module enable -y nodejs:18
		validateStep $? \
			"Enabled NodeJS 18 module stream (nodejs:18) successfully." \
			"Failed to enable NodeJS 18 module stream (nodejs:18)."

		echo -e "${CYAN}Installing NodeJS from the enabled module stream...${RESET}"
		${SUDO:-} yum install -y nodejs
		validateStep $? \
			"NodeJS installed successfully from module stream." \
			"Failed to install NodeJS from module stream."
	else
		echo -e "${YELLOW}No 'nodejs' module streams found. Falling back to plain package installation.${RESET}"

		local candidates=(nodejs18 nodejs nodejs16)
		local installed=false

		for pkg in "${candidates[@]}"; do
			echo -e "${CYAN}Checking availability of package: ${pkg}${RESET}"
			if ${SUDO:-} yum list available "${pkg}" >/dev/null 2>&1; then
				echo -e "${CYAN}Installing NodeJS package: ${pkg}${RESET}"
				${SUDO:-} yum install -y "${pkg}"
				validateStep $? \
					"NodeJS installed successfully via package '${pkg}'." \
					"Failed to install NodeJS package '${pkg}'."
				installed=true
				break
			fi
		done

		if [[ "${installed}" == false ]]; then
			echo -e "${RED}ERROR: Could not find a suitable NodeJS package (tried: ${candidates[*]}).${RESET}"
			exit 1
		fi
	fi

	echo -e "${CYAN}Verifying NodeJS installation and version...${RESET}"
	if command -v node >/dev/null 2>&1; then
		local final_node_version
		final_node_version="$(node -v | sed 's/^v//')"
		local final_node_major="${final_node_version%%.*}"

		echo -e "${GREEN}NodeJS is installed. Version: v${final_node_version}${RESET}"

		if ((final_node_major >= 18)); then
			echo -e "${GREEN}NodeJS final version is >= 18. Installation/upgrade successful.${RESET}"
		else
			echo -e "${YELLOW}NodeJS final version is < 18. Installation succeeded, but version is lower than expected.${RESET}"
		fi
	else
		echo -e "${RED}NodeJS command not found even after installation. Please check YUM/DNF logs and repository configuration.${RESET}"
		exit 1
	fi
}

# ---------- Catalogue application setup ----------
installCatalogue() {
	echo -e "${CYAN}Setting up Catalogue application...${RESET}"

	# Ensure catalogue app directory exists
	echo -e "${CYAN}Ensuring ${CATALOGUE_APP_DIR} directory exists...${RESET}"
	${SUDO:-} mkdir -p "${CATALOGUE_APP_DIR}"
	validateStep $? \
		"${CATALOGUE_APP_DIR} directory is ready." \
		"Failed to create ${CATALOGUE_APP_DIR} directory."

	# Download the catalogue code
	echo -e "${CYAN}Downloading catalogue application code to /tmp/catalogue.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/catalogue.zip "https://roboshop-builds.s3.amazonaws.com/catalogue.zip"
	validateStep $? \
		"Catalogue application zip downloaded successfully." \
		"Failed to download catalogue application zip."

	# Unzip into /app/catalogue
	echo -e "${CYAN}Unzipping catalogue application into ${CATALOGUE_APP_DIR}...${RESET}"
	${SUDO:-} unzip -o /tmp/catalogue.zip -d "${CATALOGUE_APP_DIR}" >/dev/null
	validateStep $? \
		"Catalogue application unzipped into ${CATALOGUE_APP_DIR} successfully." \
		"Failed to unzip catalogue application into ${CATALOGUE_APP_DIR}."

	# Ownership
	echo -e "${CYAN}Setting ownership of ${CATALOGUE_APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${CATALOGUE_APP_DIR}"
	validateStep $? \
		"Ownership of ${CATALOGUE_APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${CATALOGUE_APP_DIR} to roboshop."

	# Install NodeJS dependencies as roboshop user
	echo -e "${CYAN}Installing NodeJS dependencies (npm install) as 'roboshop' user...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd ${CATALOGUE_APP_DIR} && npm install" >/dev/null
	validateStep $? \
		"NodeJS dependencies installed successfully (npm install)." \
		"Failed to install NodeJS dependencies (npm install)."

	echo -e "${GREEN}Catalogue application setup completed.${RESET}"
}

# ---------- SystemD service setup ----------
createCatalogueSystemDService() {
	echo -e "${CYAN}Checking Catalogue SystemD service...${RESET}"

	local TARGET_SERVICE_FILE="/etc/systemd/system/catalogue.service"

	if [[ -f "${TARGET_SERVICE_FILE}" ]]; then
		echo -e "${YELLOW}Catalogue SystemD service already exists. Taking backup and overwriting with latest definition....${RESET}"
		local BACKUP_FILE="${TARGET_SERVICE_FILE}.$(date +%F-%H-%M-%S).bak"
		${SUDO:-} cp "${TARGET_SERVICE_FILE}" "${BACKUP_FILE}"
		validateStep $? \
			"Existing catalogue.service backed up to ${BACKUP_FILE}." \
			"Failed to backup existing catalogue.service."
	else
		echo -e "${CYAN}Catalogue SystemD service not found. Creating new Catalogue SystemD service....${RESET}"
	fi

	echo "Catalogue service file source: ${CATALOGUE_SERVICE_FILE}"

	# Always copy (create or overwrite)
	${SUDO:-} cp -f "${CATALOGUE_SERVICE_FILE}" "${TARGET_SERVICE_FILE}"
	validateStep $? \
		"Catalogue SystemD service file has been created/updated at ${TARGET_SERVICE_FILE}." \
		"Failed to create/update Catalogue SystemD service file. Copy operation failed."

	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	echo -e "${CYAN}Enabling catalogue service to start on boot...${RESET}"
	${SUDO:-} systemctl enable catalogue
	validateStep $? \
		"Catalogue service enabled to start on boot." \
		"Failed to enable catalogue service."

	echo -e "${CYAN}Restarting catalogue service...${RESET}"
	${SUDO:-} systemctl restart catalogue
	validateStep $? \
		"Catalogue service restarted successfully with latest configuration." \
		"Failed to restart catalogue service."

	echo -e "${GREEN}Catalogue SystemD service created/updated and restarted successfully.${RESET}"
}


# ---------- Main ----------
main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Catalogue Script Execution" "${TIMESTAMP}"
	echo "App Directory: ${APP_DIR}"
	echo "Catalogue App Directory: ${CATALOGUE_APP_DIR}"
	echo "Log Directory: ${LOGS_DIRECTORY}"
	echo "Log File Location and Name: ${LOG_FILE}"
	echo "Script Name: ${SCRIPT_NAME}"
	echo "Script Base: ${SCRIPT_BASE}"
	echo "Script Directory: ${SCRIPT_DIR}"
	echo "Util package location and name: ${UTIL_PKG_FILE}"
	echo "Catalogue service file location and name: ${CATALOGUE_SERVICE_FILE}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling installUtilPackages() to install utility packages from file...${RESET}"
	installUtilPackages

	echo -e "\n${CYAN}Calling installNodeJS()...${RESET}"
	installNodeJS

	echo -e "\n${CYAN}Calling installCatalogue()...${RESET}"
	installCatalogue

	echo -e "\n${CYAN}Calling createCatalogueSystemDService()...${RESET}"
	createCatalogueSystemDService

	echo -e "\n${GREEN}Catalogue setup script completed.${RESET}"
}

main "$@"
