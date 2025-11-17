#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# RabbitMQ Setup Script for RoboShop
# - Creates base /app and logs structure
# - Ensures roboshop user
# - Installs utility packages
# - Configures Erlang & RabbitMQ repos
# - Installs and starts rabbitmq-server
# - Creates RabbitMQ user 'roboshop' with permissions
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

# Utility package list lives inside the git repo, next to script
UTIL_PKG_FILE="${SCRIPT_DIR}/26_rabbitmq_util_packages.txt"

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

# ==========================================================
# RabbitMQ-specific Functions
# ==========================================================

# ---------- Function: configureRabbitMQRepos ----------
# Purpose : Configure Erlang and RabbitMQ YUM repositories.
configureRabbitMQRepos() {
	echo -e "${CYAN}Configuring Erlang and RabbitMQ YUM repositories...${RESET}"

	# Configure Erlang repository
	${SUDO:-} bash -c "curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | bash"
	validateStep $? \
		"Erlang repository configured successfully." \
		"Failed to configure Erlang repository."

	# Configure RabbitMQ repository
	${SUDO:-} bash -c "curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash"
	validateStep $? \
		"RabbitMQ repository configured successfully." \
		"Failed to configure RabbitMQ repository."
}

# ---------- Function: installRabbitMQ ----------
# Purpose : Install and start rabbitmq-server.
installRabbitMQ() {
	echo -e "${CYAN}Checking if rabbitmq-server is already installed...${RESET}"

	# Simple check whether RabbitMQ is already installed
	if rpm -q rabbitmq-server >/dev/null 2>&1; then
		echo -e "${YELLOW}rabbitmq-server is already installed. Skipping installation.${RESET}"
	else
		echo -e "${CYAN}Installing rabbitmq-server...${RESET}"
		${SUDO:-} "${PKG_MGR}" install -y rabbitmq-server
		validateStep $? \
			"rabbitmq-server installed successfully." \
			"Failed to install rabbitmq-server."
	fi

	echo -e "${CYAN}Enabling and starting rabbitmq-server service...${RESET}"
	${SUDO:-} systemctl enable rabbitmq-server
	${SUDO:-} systemctl start rabbitmq-server
	validateStep $? \
		"rabbitmq-server service enabled and started successfully." \
		"Failed to enable/start rabbitmq-server service."
}

# ---------- Function: configureRabbitMQUser ----------
# Purpose : Create RabbitMQ user 'roboshop' (if needed) and grant permissions.
# Note    : Password is set to 'roboshop123' to match RoboShop reference.
configureRabbitMQUser() {
	echo -e "${CYAN}Configuring RabbitMQ user 'roboshop'...${RESET}"

	if rabbitmqctl list_users 2>/dev/null | grep -q '^roboshop'; then
		echo -e "${YELLOW}RabbitMQ user 'roboshop' already exists. Skipping creation....${RESET}"
	else
		${SUDO:-} rabbitmqctl add_user roboshop roboshop123
		validateStep $? \
			"RabbitMQ user 'roboshop' created successfully." \
			"Failed to create RabbitMQ user 'roboshop'."
	fi

	${SUDO:-} rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"
	validateStep $? \
		"Permissions set for RabbitMQ user 'roboshop'." \
		"Failed to set permissions for RabbitMQ user 'roboshop'."
}

# ==========================================================
# Main Execution
# ==========================================================

main() {
	# Ensure logs directory exists before redirect
	mkdir -p "${LOGS_DIRECTORY}"
	# Redirect all stdout and stderr to log file
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "RabbitMQ Setup Script Execution" "${TIMESTAMP}"

	# Echo all key variables for debugging / audit
	echo -e "${CYAN}==== Script Configuration ====${RESET}"
	echo "Script Name       : ${SCRIPT_NAME}"
	echo "Script Base       : ${SCRIPT_BASE}"
	echo "Script Directory  : ${SCRIPT_DIR}"
	echo "Timestamp         : ${TIMESTAMP}"
	echo "App Directory     : ${APP_DIR}"
	echo "Logs Directory    : ${LOGS_DIRECTORY}"
	echo "Log File          : ${LOG_FILE}"
	echo "Package Manager   : ${PKG_MGR}"
	echo "Utility Pkg File  : ${UTIL_PKG_FILE}"
	echo -e "${CYAN}==============================${RESET}"

	isItRootUser

	# Now SUDO is known, echo it as well
	echo "SUDO helper       : ${SUDO:-<not set>}"

	basicAppRequirements

	echo -e "\n${CYAN}Calling installUtilPackages() to install utility packages from file...${RESET}"
	installUtilPackages

	configureRabbitMQRepos
	installRabbitMQ
	configureRabbitMQUser

	echo -e "${GREEN}RabbitMQ setup script completed successfully.${RESET}"
}

main "$@"
