#!/usr/bin/env bash


# Purpose:
#   - Ensure /app, /app/logs and roboshop user exist
#   - Install NodeJS (v18+ preferred)
#   - Download and configure the Cart microservice under /app/cart
#   - Install NodeJS dependencies as roboshop user
#   - Deploy / update SystemD unit for cart.service from 17_cart.service
#
# Notes:
#   - Expects 17_cart.service to be present in the same directory as this script
#   - Cart application code is deployed into /app/cart
#   - Logging for this script goes to /app/logs/17_cart-YYYY-MM-DD.log

set -euo pipefail

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---------- Config ----------
TIMESTAMP="$(date +"%F-%H-%M-%S")"

APP_DIR="/app"                   # Application root directory
LOGS_DIRECTORY="${APP_DIR}/logs" # Central logs directory

SCRIPT_NAME="$(basename "$0")"  # e.g. 17_cart.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}" # e.g. 17_cart
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

CART_APP_DIR="${APP_DIR}/cart"                    # Cart app root directory
CART_SERVICE_FILE="${SCRIPT_DIR}/17_cart.service" # Cart SystemD unit template

# Package manager (dnf or yum)
PKG_MGR="dnf"
if ! command -v dnf >/dev/null 2>&1; then
	PKG_MGR="yum"
fi

# ---------- Pretty header ----------
printBoxHeader() {
	local TITLE="$1"
	local TIME="$2"

	echo -e "${BLUE}===========================================${RESET}"
	printf "${CYAN}%20s${RESET}\n" "$TITLE"
	printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
	echo -e "${BLUE}===========================================${RESET}"
}

#---------- Helper: validate step ----------
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

#---------- Root / sudo handling ----------
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

#---------- Basic app requirements (/app + /app/logs + roboshop) ----------
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

	# 4) Ownership for /app
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

#---------- NodeJS installation ----------
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

#---------- Cart application setup ----------
installCartApplication() {
	echo -e "${CYAN}Setting up Cart application...${RESET}"

	# Ensure NodeJS is present
	installNodeJS

	# Ensure cart app directory exists
	echo -e "${CYAN}Ensuring ${CART_APP_DIR} directory exists...${RESET}"
	${SUDO:-} mkdir -p "${CART_APP_DIR}"
	validateStep $? \
		"${CART_APP_DIR} directory is ready." \
		"Failed to create ${CART_APP_DIR} directory."

	# Download the cart code
	echo -e "${CYAN}Downloading cart application code to /tmp/cart.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/cart.zip "https://roboshop-builds.s3.amazonaws.com/cart.zip"
	validateStep $? \
		"Cart application zip downloaded successfully." \
		"Failed to download cart application zip."

	# Unzip into /app/cart
	echo -e "${CYAN}Unzipping cart application into ${CART_APP_DIR}...${RESET}"
	${SUDO:-} unzip -o /tmp/cart.zip -d "${CART_APP_DIR}" >/dev/null
	validateStep $? \
		"Cart application unzipped into ${CART_APP_DIR} successfully." \
		"Failed to unzip cart application into ${CART_APP_DIR}."

	# Ownership
	echo -e "${CYAN}Setting ownership of ${CART_APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${CART_APP_DIR}"
	validateStep $? \
		"Ownership of ${CART_APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${CART_APP_DIR} to roboshop."

	# Install NodeJS dependencies as roboshop user
	echo -e "${CYAN}Installing NodeJS dependencies (npm install) as 'roboshop' user...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd ${CART_APP_DIR} && npm install" >/dev/null
	validateStep $? \
		"NodeJS dependencies installed successfully for cart service (npm install)." \
		"Failed to install NodeJS dependencies for cart service (npm install)."

	echo -e "${GREEN}Cart application setup completed.${RESET}"
}

#---------- SystemD service setup for Cart ----------
createCartSystemDService() {
	echo -e "${CYAN}Creating / updating Cart SystemD service...${RESET}"

	local SERVICE_TARGET="/etc/systemd/system/cart.service"

	echo "Cart service file source      : ${CART_SERVICE_FILE}"
	echo "Cart service file destination : ${SERVICE_TARGET}"

	# Ensure the source service file exists
	if [[ ! -f "${CART_SERVICE_FILE}" ]]; then
		echo -e "${RED}ERROR: Cart SystemD service template not found: ${CART_SERVICE_FILE}${RESET}"
		echo -e "${YELLOW}Create 17_cart.service in ${SCRIPT_DIR} with the required configuration.${RESET}"
		exit 1
	fi

	# If target already exists, take a backup
	if [[ -f "${SERVICE_TARGET}" ]]; then
		local BACKUP="${SERVICE_TARGET}.$(date +%F-%H-%M-%S).bak"
		echo -e "${YELLOW}Existing cart.service found. Taking backup as ${BACKUP}${RESET}"
		${SUDO:-} cp "${SERVICE_TARGET}" "${BACKUP}"
		validateStep $? \
			"Backup of existing cart.service created at ${BACKUP}." \
			"Failed to backup existing cart.service."
	fi

	# Copy new service file (overwrite if exists)
	echo -e "${CYAN}Copying ${CART_SERVICE_FILE} to ${SERVICE_TARGET}...${RESET}"
	${SUDO:-} cp "${CART_SERVICE_FILE}" "${SERVICE_TARGET}"
	validateStep $? \
		"cart.service SystemD unit copied to ${SERVICE_TARGET}." \
		"Failed to copy cart.service to ${SERVICE_TARGET}."

	# Reload systemd daemon
	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	# Enable & restart cart service
	echo -e "${CYAN}Enabling cart service to start on boot...${RESET}"
	${SUDO:-} systemctl enable cart
	validateStep $? \
		"Cart service enabled to start on boot." \
		"Failed to enable cart service."

	echo -e "${CYAN}Restarting cart service...${RESET}"
	${SUDO:-} systemctl restart cart
	validateStep $? \
		"Cart service restarted successfully." \
		"Failed to restart cart service."

	echo -e "${GREEN}Cart SystemD service deployed and running with latest configuration.${RESET}"
}

# ---------- Main ----------
main() {
	# Ensure log dir exists and redirect all output to log file
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Cart Service Setup Script Execution" "${TIMESTAMP}"

	# Echo key runtime variables
	echo "Script Name            : ${SCRIPT_NAME}"
	echo "Script Base            : ${SCRIPT_BASE}"
	echo "Script Directory       : ${SCRIPT_DIR}"
	echo "App Directory          : ${APP_DIR}"
	echo "Logs Directory         : ${LOGS_DIRECTORY}"
	echo "Cart App Directory     : ${CART_APP_DIR}"
	echo "Cart Service Template  : ${CART_SERVICE_FILE}"
	echo "Log File               : ${LOG_FILE}"
	echo "Package Manager        : ${PKG_MGR}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling installCartApplication()....${RESET}"
	installCartApplication

	echo -e "\n${CYAN}Calling createCartSystemDService()....${RESET}"
	createCartSystemDService

	echo -e "\n${GREEN}Cart service setup script completed successfully.${RESET}"
}

main "$@"
