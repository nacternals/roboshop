#!/usr/bin/env bash

set -euo pipefail

# ---------- Colors ----------
# These are used for colored output (also visible when you 'cat' the log in a terminal)
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---------- Config ----------
TIMESTAMP="$(date +"%F-%H-%M-%S")" # Full timestamp of this run

# Application root and logs directory (runtime paths)
APP_DIR="/app"                   # Application root directory
LOGS_DIRECTORY="${APP_DIR}/logs" # Central log directory -> /app/logs

# Script / repo location (where git pull happens)
SCRIPT_NAME="$(basename "$0")"                             # e.g. roboshop_infra.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. roboshop_infra
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives

# Log file: one per day, per script
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

printBoxHeader() {
	local TITLE="$1"
	local TIME="$2"

	echo -e "${BLUE}===========================================${RESET}"
	printf "${CYAN}%20s${RESET}\n" "$TITLE"
	printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
	echo -e "${BLUE}===========================================${RESET}"
}

# ---------- Helper: validate step ----------
# Usage pattern:
#   some_command
#   validateStep $? "success message" "failure message"
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

# ---------- Basic app requirements (/app) ----------
basicAppRequirements() {
	echo -e "${CYAN}Ensuring basic application requirements (${APP_DIR} dir and roboshop user)...${RESET}"

	# 1) Ensure APP_DIR directory exists
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


	# 2) Ensure APP_DIR ownership is set to ansadmin
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'ansadmin'...${RESET}"
	${SUDO:-} chown -R ansadmin:ansadmin "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to ansadmin successfully." \
		"Failed to set ownership of ${APP_DIR} to ansadmin."
}

# ---------- Root / sudo handling ----------
# Sets SUDO variable as "sudo" for non-root users (if sudo is available),
# or empty string if script is already running as root.
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


# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${LOGS_DIRECTORY}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Roboshop Infra Script Execution" "${TIMESTAMP}"
	echo "App Directory: ${APP_DIR}"
	echo "Log Directory: ${LOGS_DIRECTORY}"
	echo "Log File Location and Name: ${LOG_FILE}"
	echo "Script Directory: ${SCRIPT_DIR}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements


	echo -e "\n${GREEN}Roboshop Infra setup script completed successfully.${RESET}"
}

main "$@"
