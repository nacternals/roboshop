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
SCRIPT_NAME="$(basename "$0")"                             # e.g. mongodb.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. mongodb
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives

# Log file: one per day, per script
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

# Utility package list lives inside the git repo, next to script
UTIL_PKG_FILE="${SCRIPT_DIR}/03_mongodb_util_packages.txt"

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

# ---------- Basic app requirements (/app + roboshop) ----------
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

	# 2) Ensure application user 'roboshop' exists
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

	# 3) Ensure APP_DIR ownership is set to roboshop
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
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

# ---------- Utility package installer ----------
# Reads package names from 03_mongodbutilpackages.txt (one per line) and installs them.
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
		${SUDO:-} yum install -y "${PKG}"
		validateStep $? \
			"Utility package '${PKG}' installed successfully." \
			"Failed to install utility package '${PKG}'."
	done

	echo -e "${GREEN}All requested utility packages processed successfully.${RESET}"
}

# ---------- MongoDB repo setup ----------
createMongoRepo() {
	echo -e "${CYAN}Checking MongoDB repo...${RESET}"

	if [[ -f /etc/yum.repos.d/mongo.repo ]]; then
		echo -e "${YELLOW}MongoDB repo already exists, skipping....${RESET}"
		return
	fi

	echo -e "${CYAN}MongoDB repo not found. Creating MongoDB repo....${RESET}"
	echo "mongodb.repo script location: ${SCRIPT_DIR}/02_mongodb.repo"

	# Try copying the repo file from script directory to yum repo directory
	${SUDO:-} cp "${SCRIPT_DIR}/02_mongodb.repo" /etc/yum.repos.d/mongo.repo
	validateStep $? \
		"MongoDB repo created at /etc/yum.repos.d/mongo.repo" \
		"Failed to create MongoDB repo. Copy operation failed."
}

# ---------- MongoDB installation & configuration ----------
installMongoDB() {
	# First check whether mongodb is already installed or not
	echo -e "${CYAN}Checking if MongoDB is already installed...${RESET}"

	# Check if mongod command exists
	if command -v mongod >/dev/null 2>&1; then
		echo -e "${YELLOW}MongoDB is already installed. Skipping installation.${RESET}"
		return
	fi

	echo -e "${CYAN}MongoDB not found. Proceeding with installation...${RESET}"

	# Install MongoDB (expects repo already created)
	${SUDO:-} yum install -y mongodb-org
	validateStep $? \
		"MongoDB packages installed successfully." \
		"Failed to install MongoDB packages."

	# Enable MongoDB service
	echo -e "${CYAN}Enabling MongoDB service (mongod)...${RESET}"
	${SUDO:-} systemctl enable mongod
	validateStep $? \
		"MongoDB service enabled to start on boot." \
		"Failed to enable MongoDB service."

	# Start MongoDB service
	echo -e "${CYAN}Starting MongoDB service (mongod)...${RESET}"
	${SUDO:-} systemctl start mongod
	validateStep $? \
		"MongoDB service started successfully." \
		"Failed to start MongoDB service."

	# Update bind IP in /etc/mongod.conf from 127.0.0.1 to 0.0.0.0
	echo -e "${CYAN}Updating MongoDB bind IP in /etc/mongod.conf (127.0.0.1 → 0.0.0.0)...${RESET}"

	if [[ -f /etc/mongod.conf ]]; then
		if grep -q "127.0.0.1" /etc/mongod.conf; then
			${SUDO:-} sed -i 's/127\.0\.0\.1/0.0.0.0/g' /etc/mongod.conf
			validateStep $? \
				"Updated bind IP in /etc/mongod.conf to 0.0.0.0." \
				"Failed to update bind IP in /etc/mongod.conf."

			echo -e "${CYAN}Restarting MongoDB service after bind IP config change...${RESET}"
			${SUDO:-} systemctl restart mongod
			validateStep $? \
				"MongoDB service restarted successfully after bind IP config change." \
				"Failed to restart MongoDB service after bind IP config change."
		else
			echo -e "${YELLOW}No '127.0.0.1' entry found in /etc/mongod.conf. Skipping bind IP update.${RESET}"
		fi
	else
		echo -e "${RED}WARNING: /etc/mongod.conf not found. Skipping bind IP update.${RESET}"
	fi

	echo -e "${GREEN}MongoDB installation and basic configuration completed.${RESET}"
}

# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${LOGS_DIRECTORY}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "MongoDB Script Execution" "${TIMESTAMP}"
	echo "App Directory: ${APP_DIR}"
	echo "Log Directory: ${LOGS_DIRECTORY}"
	echo "Log File Location and Name: ${LOG_FILE}"
	echo "Script Directory: ${SCRIPT_DIR}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling installUtilPackages() to install utility packages from file...${RESET}"
	installUtilPackages

	echo -e "\n${CYAN}Calling createMongoRepo()...${RESET}"
	createMongoRepo

	echo -e "\n${CYAN}Calling installMongoDB()...${RESET}"
	installMongoDB

	echo -e "\n${GREEN}MongoDB setup script completed successfully.${RESET}"
}

main "$@"
