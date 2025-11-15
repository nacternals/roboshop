#!/usr/bin/env bash

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
APP_DIR="/app"
LOGS_DIRECTORY="${APP_DIR}/logs"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"
USER_SERVICE_FILE="${SCRIPT_DIR}/13_user.service"


# Package manager (dnf or yum)
PKG_MGR="dnf"
if ! command -v dnf >/dev/null 2>&1; then
	PKG_MGR="yum"
fi

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

installUserApplication() {
	echo -e "${CYAN}Setting up User microservice...${RESET}"

	installNodeJS

	echo -e "${CYAN}Downloading user application code...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/user.zip "https://roboshop-builds.s3.amazonaws.com/user.zip"
	validateStep $? \
		"User application zip downloaded successfully." \
		"Failed to download user application zip."

	echo -e "${CYAN}Extracting user application into /app...${RESET}"
	${SUDO:-} unzip -o /tmp/user.zip -d /app >/dev/null
	validateStep $? \
		"User application extracted into /app successfully." \
		"Failed to extract user application into /app."

	echo -e "${CYAN}Installing NodeJS dependencies (npm install) as 'roboshop'...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd /app && npm install" >/dev/null
	validateStep $? \
		"NodeJS dependencies installed successfully for user service." \
		"Failed to install NodeJS dependencies for user service."
}

createUserSystemDService() {
	echo -e "${CYAN}Creating / updating User SystemD service...${RESET}"

	local SERVICE_TARGET="/etc/systemd/system/user.service"

	echo "User service file source      : ${USER_SERVICE_FILE}"
	echo "User service file destination : ${SERVICE_TARGET}"

	# Ensure the source service file exists
	if [[ ! -f "${USER_SERVICE_FILE}" ]]; then
		echo -e "${RED}ERROR: User SystemD service template not found: ${USER_SERVICE_FILE}${RESET}"
		exit 1
	fi

	# If target already exists, take a backup
	if [[ -f "${SERVICE_TARGET}" ]]; then
		local BACKUP="${SERVICE_TARGET}.$(date +%F-%H-%M-%S).bak"
		echo -e "${YELLOW}Existing user.service found. Taking backup as ${BACKUP}${RESET}"
		${SUDO:-} cp "${SERVICE_TARGET}" "${BACKUP}"
		validateStep $? \
			"Backup of existing user.service created at ${BACKUP}." \
			"Failed to backup existing user.service."
	fi

	# Copy new service file (overwrite if exists)
	echo -e "${CYAN}Copying ${USER_SERVICE_FILE} to ${SERVICE_TARGET}...${RESET}"
	${SUDO:-} cp "${USER_SERVICE_FILE}" "${SERVICE_TARGET}"
	validateStep $? \
		"user.service SystemD unit copied to ${SERVICE_TARGET}." \
		"Failed to copy user.service to ${SERVICE_TARGET}."

	# Reload systemd daemon
	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	# Enable & restart user service
	echo -e "${CYAN}Enabling user service to start on boot...${RESET}"
	${SUDO:-} systemctl enable user
	validateStep $? \
		"User service enabled to start on boot." \
		"Failed to enable user service."

	echo -e "${CYAN}Restarting user service...${RESET}"
	${SUDO:-} systemctl restart user
	validateStep $? \
		"User service restarted successfully." \
		"Failed to restart user service."

	echo -e "${GREEN}User SystemD service deployed and running with latest configuration.${RESET}"
}


main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "User Service Setup Script Execution" "${TIMESTAMP}"

	echo "Script Name      : ${SCRIPT_NAME}"
	echo "Script Directory : ${SCRIPT_DIR}"
	echo "Log File         : ${LOG_FILE}"

	isItRootUser
	basicAppRequirements

	installUserApplication
	createUserSystemDService

	echo -e "${GREEN}User service setup script completed successfully.${RESET}"
}

main "$@"
