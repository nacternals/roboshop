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

configureMySQLRepo() {
	echo -e "${CYAN}Configuring MySQL YUM repo (MySQL 5.7)...${RESET}"

	# 1. Disable default MySQL 8 module from CentOS 8 AppStream (if enabled)
	echo -e "${CYAN}Checking default MySQL 8 module status...${RESET}"

	if ${SUDO:-} dnf -q module list mysql 2>/dev/null | grep -qE '^\s*mysql\s+.*\senabled'; then
		echo -e "${YELLOW}Default MySQL 8 module is enabled. Disabling it now...${RESET}"
		${SUDO:-} dnf -y module disable mysql >/dev/null 2>&1

		validateStep $? \
			"Disabled default MySQL 8 module from AppStream." \
			"Failed to disable default MySQL 8 module from AppStream."
	else
		echo -e "${YELLOW}Default MySQL module is not enabled or already disabled. Skipping module disable step....${RESET}"
	fi

	# 2. Copy 19_mysql.repo to /etc/yum.repos.d/mysql.repo
	echo -e "${CYAN}Checking custom MySQL 5.7 repo file...${RESET}"

	if [[ -f /etc/yum.repos.d/mysql.repo ]]; then
		echo -e "${YELLOW}MySQL repo already exists at /etc/yum.repos.d/mysql.repo, skipping copy....${RESET}"
		return
	fi

	echo -e "${CYAN}MySQL repo not found. Creating MySQL 5.7 repo....${RESET}"
	echo "mysql.repo script location: ${SCRIPT_DIR}/19_mysql.repo"

	${SUDO:-} cp "${SCRIPT_DIR}/19_mysql.repo" /etc/yum.repos.d/mysql.repo
	validateStep $? \
		"MySQL 5.7 repo created at /etc/yum.repos.d/mysql.repo" \
		"Failed to create MySQL 5.7 repo. Copy operation failed."
}


installMySQLServer() {
	# Install MySQL 5.7 community server
	echo -e "${CYAN}Checking if MySQL Server (MySQL 5.7) is already installed...${RESET}"

	# Check if mysqld or mysql command exists
	if command -v mysqld >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
		echo -e "${YELLOW}MySQL Server already appears to be installed. Skipping installation.${RESET}"
		return
	fi

	echo -e "${CYAN}MySQL Server not found. Proceeding with installation (MySQL 5.7 Community Server)...${RESET}"

	# Use package manager (expects repo already configured via configureMySQLRepo)
	local PKG_MGR_CMD="${PKG_MGR:-yum}"

	${SUDO:-} "${PKG_MGR_CMD}" install -y mysql-community-server
	validateStep $? \
		"MySQL 5.7 Community Server installed successfully." \
		"Failed to install MySQL 5.7 Community Server."

	# Enable MySQL service
	echo -e "${CYAN}Enabling MySQL service (mysqld)...${RESET}"
	${SUDO:-} systemctl enable mysqld
	validateStep $? \
		"MySQL (mysqld) service enabled to start on boot." \
		"Failed to enable MySQL (mysqld) service."

	# Start MySQL service
	echo -e "${CYAN}Starting MySQL service (mysqld)...${RESET}"
	${SUDO:-} systemctl start mysqld
	validateStep $? \
		"MySQL (mysqld) service started successfully." \
		"Failed to start MySQL (mysqld) service."

	# Optional: Update bind-address to allow remote connections (0.0.0.0)
	echo -e "${CYAN}Checking MySQL bind-address configuration to allow remote connections...${RESET}"

	local MYSQL_CNF_FILE=""
	if [[ -f /etc/my.cnf.d/mysql-server.cnf ]]; then
		MYSQL_CNF_FILE="/etc/my.cnf.d/mysql-server.cnf"
	elif [[ -f /etc/my.cnf ]]; then
		MYSQL_CNF_FILE="/etc/my.cnf"
	fi

	if [[ -n "${MYSQL_CNF_FILE}" ]]; then
		if grep -q "bind-address" "${MYSQL_CNF_FILE}"; then
			${SUDO:-} sed -i 's/^\s*bind-address\s*=.*/bind-address = 0.0.0.0/' "${MYSQL_CNF_FILE}"
			validateStep $? \
				"Updated MySQL bind-address in ${MYSQL_CNF_FILE} to 0.0.0.0." \
				"Failed to update MySQL bind-address in ${MYSQL_CNF_FILE}."
		else
			echo -e "${YELLOW}No 'bind-address' directive found in ${MYSQL_CNF_FILE}. Skipping bind-address update.${RESET}"
		fi

		echo -e "${CYAN}Restarting MySQL service after configuration change...${RESET}"
		${SUDO:-} systemctl restart mysqld
		validateStep $? \
			"MySQL (mysqld) service restarted successfully after configuration change." \
			"Failed to restart MySQL (mysqld) service after configuration change."
	else
		echo -e "${YELLOW}MySQL configuration file not found. Skipping bind-address update.${RESET}"
	fi

	echo -e "${GREEN}MySQL 5.7 Community Server installation and basic configuration completed.${RESET}"
}


setRootPassword() {
	local ROOT_PASS="RoboShop@1"
	echo -e "${CYAN}Setting MySQL root password (if not already set)...${RESET}"

	if mysql -uroot -p"${ROOT_PASS}" -e "SELECT 1" >/dev/null 2>&1; then
		echo -e "${YELLOW}Root password already set and working. Skipping mysql_secure_installation.${RESET}"
		return
	fi

	${SUDO:-} mysql_secure_installation --set-root-pass "${ROOT_PASS}"
	validateStep $? \
		"MySQL root password set successfully." \
		"Failed to set MySQL root password."
}

main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "MySQL 5.7 Setup Script Execution" "${TIMESTAMP}"

	echo "Script Name      : ${SCRIPT_NAME}"
	echo "Script Directory : ${SCRIPT_DIR}"
	echo "Log File         : ${LOG_FILE}"

	isItRootUser
	basicAppRequirements

	configureMySQLRepo
	installMySQLServer
	setRootPassword

	echo -e "${GREEN}MySQL setup script completed successfully.${RESET}"
}

main "$@"
