#!/usr/bin/env bash

# This script will install and configure Redis for RoboShop.
#
# It:
#   - Ensures /app, /app/logs and roboshop user exist
#   - Installs Remi repo and enables redis:remi-6.2 module
#   - Installs redis package
#   - Changes bind address from 127.0.0.1 to 0.0.0.0
#     in /etc/redis.conf and /etc/redis/redis.conf (if present)
#   - Enables and restarts Redis service
#
# Logging, colors, helper functions, and directory handling
# are consistent with mongodb.sh, catalogue.sh, and 08_web_nginx.sh.

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
APP_DIR="/app"                   						   # Application root directory
LOGS_DIRECTORY="${APP_DIR}/logs" 						   # Central log directory -> /app/logs
SCRIPT_NAME="$(basename "$0")"                             # e.g. redis.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. redis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log" # one log file per day

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

# ---------- Helper: validate step ----------
# Usage:
#   some_command
#   validateStep $? "success msg" "failure msg"
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

# ---------- Root / sudo handling ----------
# Sets SUDO="sudo" for non-root (if sudo exists), or "" for root.
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

	# 4) Ensure /app owned by roboshop
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

# ---------- Redis installation (Remi repo + module + package) ----------
installRedis() {
    echo -e "${CYAN}Installing Redis on CentOS Stream 8 (AppStream)...${RESET}"

    echo -e "${CYAN}Checking if Redis is already installed...${RESET}"
    if rpm -q redis >/dev/null 2>&1; then
        echo -e "${YELLOW}Redis is already installed. Skipping installation....${RESET}"
    else
        echo -e "${CYAN}Installing Redis from AppStream repository...${RESET}"
        ${SUDO:-} "${PKG_MGR}" install -y redis
        validateStep $? \
            "Redis installed successfully from AppStream." \
            "Failed to install Redis."
    fi

    echo -e "${CYAN}Enabling Redis service...${RESET}"
    ${SUDO:-} systemctl enable redis
    validateStep $? \
        "Redis enabled successfully." \
        "Failed to enable Redis."

    echo -e "${CYAN}Starting Redis service...${RESET}"
    ${SUDO:-} systemctl start redis
    validateStep $? \
        "Redis started successfully." \
        "Failed to start Redis."

    echo -e "${GREEN}Redis installation and setup completed.${RESET}"
}



# ---------- Redis configuration (bind 0.0.0.0) ----------
configureRedis() {
	echo -e "${CYAN}Configuring Redis to listen on 0.0.0.0...${RESET}"

	for FILE in /etc/redis.conf /etc/redis/redis.conf; do
		if [[ -f "${FILE}" ]]; then
			echo -e "${CYAN}Updating bind address in ${FILE}...${RESET}"
			# Handle both uncommented and commented bind lines
			${SUDO:-} sed -i 's/^bind .*/bind 0.0.0.0/' "${FILE}" || true
			${SUDO:-} sed -i 's/^# *bind .*/bind 0.0.0.0/' "${FILE}" || true
		fi
	done

	echo -e "${GREEN}Redis configuration updated (bind 0.0.0.0 where applicable).${RESET}"
}

# ---------- Redis service enable + start ----------
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

# ---------- Main ----------
main() {
	# Ensure log dir exists before redirecting
	mkdir -p "${LOGS_DIRECTORY}"

	# Redirect all stdout+stderr to log file
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Redis Setup Script Execution" "${TIMESTAMP}"

	# Echo all key variables for traceability
	echo "Script Name          : ${SCRIPT_NAME}"
	echo "Script Base          : ${SCRIPT_BASE}"
	echo "Script Directory     : ${SCRIPT_DIR}"
	echo "App Directory        : ${APP_DIR}"
	echo "Logs Directory       : ${LOGS_DIRECTORY}"
	echo "Log File             : ${LOG_FILE}"
	echo "Package Manager      : ${PKG_MGR}"
	echo "Execution Timestamp  : ${TIMESTAMP}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling installRedis()....${RESET}"
	installRedis

	echo -e "\n${CYAN}Calling configureRedis()....${RESET}"
	configureRedis

	echo -e "\n${CYAN}Calling startRedis()....${RESET}"
	startRedis

	echo -e "\n${GREEN}Redis setup script completed successfully.${RESET}"
}

main "$@"
