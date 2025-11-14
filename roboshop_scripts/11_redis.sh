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

installRedis() {
	echo -e "${CYAN}Installing Redis repositories and packages...${RESET}"

	echo -e "${CYAN}Installing Remi repository RPM...${RESET}"
	${SUDO:-} "${PKG_MGR}" install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm
	validateStep $? \
		"Remi repository RPM installed successfully." \
		"Failed to install Remi repository RPM."

	echo -e "${CYAN}Enabling redis:remi-6.2 module stream...${RESET}"
	${SUDO:-} "${PKG_MGR}" module enable -y redis:remi-6.2
	validateStep $? \
		"redis:remi-6.2 module enabled successfully." \
		"Failed to enable redis:remi-6.2 module."

	echo -e "${CYAN}Installing Redis server...${RESET}"
	${SUDO:-} "${PKG_MGR}" install -y redis
	validateStep $? \
		"Redis server installed successfully." \
		"Failed to install Redis server."
}

configureRedis() {
	echo -e "${CYAN}Configuring Redis to listen on 0.0.0.0...${RESET}"

	for FILE in /etc/redis.conf /etc/redis/redis.conf; do
		if [[ -f "${FILE}" ]]; then
			echo -e "${CYAN}Updating bind address in ${FILE}...${RESET}"
			${SUDO:-} sed -i 's/^bind .*/bind 0.0.0.0/' "${FILE}" || true
			${SUDO:-} sed -i 's/^# *bind .*/bind 0.0.0.0/' "${FILE}" || true
		fi
	done
}

startRedis() {
	echo -e "${CYAN}Enabling and starting Redis service...${RESET}"
	${SUDO:-} systemctl enable redis
	validateStep $? \
		"Redis service enabled successfully." \
		"Failed to enable Redis service."

	${SUDO:-} systemctl restart redis
	validateStep $? \
		"Redis service started/restarted successfully." \
		"Failed to start/restart Redis service."
}

main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Redis Setup Script Execution" "${TIMESTAMP}"

	echo "Script Name      : ${SCRIPT_NAME}"
	echo "Script Directory : ${SCRIPT_DIR}"
	echo "Log File         : ${LOG_FILE}"

	isItRootUser
	basicAppRequirements

	installRedis
	configureRedis
	startRedis

	echo -e "${GREEN}Redis setup script completed successfully.${RESET}"
}

main "$@"
