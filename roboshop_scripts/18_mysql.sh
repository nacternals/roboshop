#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# MySQL 5.7 Setup Script for RoboShop
# - Creates base app/logs structure
# - Configures MySQL 5.7 repo
# - Installs MySQL 5.7 server
# - Secures MySQL root user in a production-friendly way
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

# Utility packages list specific to MySQL script
# One package name per line in this file.
UTIL_PKG_FILE="${SCRIPT_DIR}/20_mysql_util_packages.txt"

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
		return 0
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
		${SUDO:-} yum install -y "${PKG}"
		validateStep $? \
			"Utility package '${PKG}' installed successfully." \
			"Failed to install utility package '${PKG}'."
	done

	echo -e "${GREEN}All requested utility packages processed successfully.${RESET}"
}

# ==========================================================
# MySQL-specific Functions
# ==========================================================

# ---------- Function: configureMySQLRepo ----------
# Purpose : Configure YUM repo for MySQL 5.7 and disable default MySQL 8 module.
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

	# 2. Always copy our custom MySQL 5.7 repo
	echo -e "${CYAN}Creating/updating MySQL 5.7 repo at /etc/yum.repos.d/mysql.repo....${RESET}"
	echo "mysql.repo script location: ${SCRIPT_DIR}/19_mysql.repo"

	${SUDO:-} cp -f "${SCRIPT_DIR}/19_mysql.repo" /etc/yum.repos.d/mysql.repo
	validateStep $? \
		"MySQL 5.7 repo created/updated at /etc/yum.repos.d/mysql.repo" \
		"Failed to create/update MySQL 5.7 repo. Copy operation failed."
}

installMySQLServer() {
	echo -e "${CYAN}Checking if MySQL Server (MySQL 5.7) is already installed...${RESET}"

	# Check if mysqld or mysql command exists
	if command -v mysqld >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
		echo -e "${YELLOW}MySQL Server already appears to be installed. Skipping installation.${RESET}"
		return
	fi

	echo -e "${CYAN}MySQL Server not found. Proceeding with installation (MySQL 5.7 Community Server)...${RESET}"

	# ---------- Handle DNF module conflicts (AppStream mysql module) ----------
	if command -v dnf >/dev/null 2>&1; then
		echo -e "${CYAN}Resetting and disabling default 'mysql' module from AppStream (if present)...${RESET}"
		${SUDO:-} dnf -y module reset mysql >/dev/null 2>&1 || true
		${SUDO:-} dnf -y module disable mysql >/dev/null 2>&1 || true
	else
		echo -e "${YELLOW}dnf command not found. Skipping module reset/disable for mysql.${RESET}"
	fi

	# ---------- Clean metadata ----------
	echo -e "${CYAN}Cleaning DNF/YUM metadata cache before MySQL installation...${RESET}"
	${SUDO:-} "${PKG_MGR}" clean all >/dev/null 2>&1 || true
	${SUDO:-} "${PKG_MGR}" makecache >/dev/null 2>&1 || true

	# ---------- Install MySQL 5.7 Community Server ----------
	local PKG_MGR_CMD="${PKG_MGR:-yum}"

	echo -e "${CYAN}Installing mysql-community-server from configured MySQL 5.7 repo...${RESET}"
	${SUDO:-} "${PKG_MGR_CMD}" install -y mysql-community-server
	local install_rc=$?

	validateStep "${install_rc}" \
		"MySQL 5.7 Community Server installed successfully." \
		"Failed to install MySQL 5.7 Community Server."

	# ---------- Enable MySQL service ----------
	echo -e "${CYAN}Enabling MySQL service (mysqld)...${RESET}"
	${SUDO:-} systemctl enable mysqld
	validateStep $? \
		"MySQL (mysqld) service enabled to start on boot." \
		"Failed to enable MySQL (mysqld) service."

	# ---------- Start MySQL service ----------
	echo -e "${CYAN}Starting MySQL service (mysqld)...${RESET}"
	${SUDO:-} systemctl start mysqld
	validateStep $? \
		"MySQL (mysqld) service started successfully." \
		"Failed to start MySQL (mysqld) service."

	# ---------- Optional: Update bind-address to allow remote connections ----------
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

# ---------- Function: setRootPassword ----------
# Purpose : Securely ensure MySQL root password is set.

setRootPassword() {
	echo -e "${CYAN}Ensuring MySQL root password is configured to '------------'...${RESET}"

	# Fixed root password (change here if needed)
	local ROOT_PASS="RoboShop@1"
	local EXIT_CODE=0

	# 1. If root already works with this password, skip
	if MYSQL_PWD="${ROOT_PASS}" mysql -uroot -e "SELECT 1" >/dev/null 2>&1; then
		echo -e "${YELLOW}MySQL root password already set to the desired value. Skipping reconfiguration.${RESET}"
		return 0
	fi

	echo -e "${CYAN}Setting MySQL root password using mysql_secure_installation (if available)...${RESET}"

	# 2. Preferred path: mysql_secure_installation --set-root-pass
	if command -v mysql_secure_installation >/devnull 2>&1; then
		${SUDO:-} mysql_secure_installation --set-root-pass "${ROOT_PASS}" >/dev/null 2>&1 || EXIT_CODE=$?
		if [[ ${EXIT_CODE} -ne 0 ]]; then
			echo -e "${YELLOW}mysql_secure_installation failed or is unsupported. Falling back to direct SQL method...${RESET}"
		fi
	else
		echo -e "${YELLOW}mysql_secure_installation not found. Using direct SQL method to set root password...${RESET}"
		EXIT_CODE=1
	fi


	validateStep ${EXIT_CODE} \
		"MySQL root password set/updated successfully to '-----------'." \
		"Failed to set/update MySQL root password."

	echo -e "${GREEN}MySQL root password configuration completed.${RESET}"
}

# ==========================================================
# Main Execution
# ==========================================================

main() {
	# Ensure logs directory exists before redirect
	mkdir -p "${LOGS_DIRECTORY}"
	# Redirect all stdout and stderr to log file
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "MySQL 5.7 Setup Script Execution" "${TIMESTAMP}"

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
	echo "MYSQL_ROOT_PASSWORD (env): ${MYSQL_ROOT_PASSWORD:-<not set>}"
	echo "CREATE_MYCNF (env): ${CREATE_MYCNF:-true}"
	echo -e "${CYAN}==============================${RESET}"

	isItRootUser

	# Now SUDO is known, echo it as well
	echo "SUDO helper       : ${SUDO:-<not set>}"

	basicAppRequirements
	installUtilPackages

	configureMySQLRepo
	installMySQLServer
	setRootPassword

	echo -e "${GREEN}MySQL setup script completed successfully.${RESET}"
}

main "$@"
