#!/usr/bin/env bash

# This script will install and configure Nginx as a reverse proxy
# for the RoboShop Web/Frontend service.
#
# It:
#   - Installs required utility packages (from 09_web_util_packages.txt)
#   - Installs Nginx
#   - Removes default Nginx web content
#   - Downloads and extracts web frontend content into /usr/share/nginx/html
#   - Copies reverse proxy config (10_web_nginx_roboshop.conf) into /etc/nginx/default.d/roboshop.conf
#   - Tests and restarts Nginx
#
# Logging, colors, helper functions, and directory handling are similar to mongodb.sh/catalogue.sh.

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

APP_DIR="/app"                   # Application root directory
LOGS_DIRECTORY="${APP_DIR}/logs" # Central log directory -> /app/logs

SCRIPT_NAME="$(basename "$0")"                             # e.g. 08_web_nginx.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. 08_web_nginx
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives

LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

# Optional utility package list (create if you need extra tools: curl, unzip, vim, etc.)
UTIL_PKG_FILE="${SCRIPT_DIR}/09_web_util_packages.txt"

# Nginx web root and content URL
NGINX_WEB_ROOT="/usr/share/nginx/html"
WEB_ZIP_URL="https://roboshop-builds.s3.amazonaws.com/web.zip"
WEB_ZIP_FILE="/tmp/web.zip"

# Nginx reverse proxy configuration
NGINX_CONF_SOURCE="${SCRIPT_DIR}/10_web_nginx_roboshop.conf"
NGINX_CONF_TARGET_DIR="/etc/nginx/default.d"
NGINX_CONF_TARGET="${NGINX_CONF_TARGET_DIR}/roboshop.conf"

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

# ---------- Helper: validate step ----------
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

	# 4) Ownership
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

# ---------- Utility package installer ----------
installUtilPackages() {
	echo -e "${CYAN}Checking utility package list file: ${UTIL_PKG_FILE}${RESET}"

	if [[ ! -f "${UTIL_PKG_FILE}" ]]; then
		echo -e "${YELLOW}Utility package file not found: ${UTIL_PKG_FILE}${RESET}"
		echo -e "${YELLOW}Skipping utility package installation (file is optional).${RESET}"
		return
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
		${SUDO:-} "${PKG_MGR}" install -y "${PKG}"
		validateStep $? \
			"Utility package '${PKG}' installed successfully." \
			"Failed to install utility package '${PKG}'."
	done

	echo -e "${GREEN}All requested utility packages processed successfully.${RESET}"
}

# ---------- Nginx install & basic service ----------
installNginx() {
	echo -e "${CYAN}Checking if Nginx is already installed...${RESET}"

	if rpm -q nginx >/dev/null 2>&1; then
		echo -e "${YELLOW}Nginx is already installed. Skipping installation.${RESET}"
	else
		echo -e "${CYAN}Installing Nginx using ${PKG_MGR}...${RESET}"
		${SUDO:-} "${PKG_MGR}" install -y nginx
		validateStep $? \
			"Nginx installed successfully." \
			"Failed to install Nginx."
	fi

	echo -e "${CYAN}Enabling Nginx service on boot...${RESET}"
	${SUDO:-} systemctl enable nginx
	validateStep $? \
		"Nginx service enabled successfully." \
		"Failed to enable Nginx service."

	echo -e "${YELLOW}NOTE:${RESET} Nginx will be (re)started after reverse proxy config is copied."
}

# ---------- Web content setup ----------
setupWebContent() {
	echo -e "${CYAN}Preparing Nginx web root: ${NGINX_WEB_ROOT}${RESET}"

	# Remove default Nginx content
	echo -e "${CYAN}Removing default content from ${NGINX_WEB_ROOT}...${RESET}"
	${SUDO:-} rm -rf "${NGINX_WEB_ROOT:?}/"*
	validateStep $? \
		"Default content removed from ${NGINX_WEB_ROOT}." \
		"Failed to remove default content from ${NGINX_WEB_ROOT}."

	# Download frontend zip
	echo -e "${CYAN}Downloading frontend content to ${WEB_ZIP_FILE}...${RESET}"
	${SUDO:-} curl -s -L -o "${WEB_ZIP_FILE}" "${WEB_ZIP_URL}"
	validateStep $? \
		"Frontend content downloaded successfully." \
		"Failed to download frontend content."

	# Unzip into Nginx web root
	echo -e "${CYAN}Extracting frontend content into ${NGINX_WEB_ROOT}...${RESET}"
	${SUDO:-} unzip -o "${WEB_ZIP_FILE}" -d "${NGINX_WEB_ROOT}" >/dev/null
	validateStep $? \
		"Frontend content extracted into ${NGINX_WEB_ROOT} successfully." \
		"Failed to extract frontend content into ${NGINX_WEB_ROOT}."
}

# ---------- Nginx reverse proxy config with backup ----------
createRoboshopNginxConf() {
	echo -e "${CYAN}Deploying Nginx roboshop.conf...${RESET}"
	echo "Source : ${NGINX_CONF_SOURCE}"
	echo "Target : ${NGINX_CONF_TARGET}"

	# Ensure default.d exists
	echo -e "${CYAN}Ensuring ${NGINX_CONF_TARGET_DIR} exists...${RESET}"
	${SUDO:-} mkdir -p "${NGINX_CONF_TARGET_DIR}"
	validateStep $? \
		"${NGINX_CONF_TARGET_DIR} exists / created successfully." \
		"Failed to ensure ${NGINX_CONF_TARGET_DIR}."

	# Ensure source config exists
	if [[ ! -f "${NGINX_CONF_SOURCE}" ]]; then
		echo -e "${RED}ERROR: Nginx reverse proxy config template not found: ${NGINX_CONF_SOURCE}${RESET}"
		echo -e "${YELLOW}Create 10_roboshop.conf in ${SCRIPT_DIR} with the required locations and proxy_pass entries.${RESET}"
		exit 1
	fi

	# Optional: backup existing target
	if [[ -f "${NGINX_CONF_TARGET}" ]]; then
		local BACKUP="${NGINX_CONF_TARGET}.$(date +%F-%H-%M-%S).bak"
		echo -e "${YELLOW}Existing roboshop.conf found. Taking backup as ${BACKUP}${RESET}"
		${SUDO:-} cp "${NGINX_CONF_TARGET}" "${BACKUP}"
		validateStep $? \
			"Backup of existing roboshop.conf created at ${BACKUP}." \
			"Failed to backup existing roboshop.conf."
	fi

	# Copy new config
	echo -e "${CYAN}Copying ${NGINX_CONF_SOURCE} to ${NGINX_CONF_TARGET}...${RESET}"
	${SUDO:-} cp "${NGINX_CONF_SOURCE}" "${NGINX_CONF_TARGET}"
	validateStep $? \
		"Nginx reverse proxy config copied to ${NGINX_CONF_TARGET}." \
		"Failed to copy Nginx reverse proxy config."

	echo -e "${GREEN}roboshop.conf deployed (copy + backup) successfully.${RESET}"
}

# ---------- Restart Nginx ----------
restartNginx() {
	echo -e "${CYAN}Testing Nginx configuration (nginx -t)...${RESET}"
	${SUDO:-} nginx -t
	validateStep $? \
		"Nginx configuration test succeeded." \
		"Nginx configuration test failed."

	echo -e "${CYAN}Restarting Nginx to apply configuration changes...${RESET}"
	${SUDO:-} systemctl restart nginx
	validateStep $? \
		"Nginx restarted successfully." \
		"Failed to restart Nginx."
}

# ---------- Main ----------
main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "WEB/Nginx Script Execution" "${TIMESTAMP}"
	echo "App Directory: ${APP_DIR}"
	echo "Log Directory: ${LOGS_DIRECTORY}"
	echo "Log File Location and Name: ${LOG_FILE}"
	echo "Script Name: ${SCRIPT_NAME}"
	echo "Script Base: ${SCRIPT_BASE}"
	echo "Script Directory: ${SCRIPT_DIR}"
	echo "Util package file: ${UTIL_PKG_FILE}"
	echo "Nginx web root: ${NGINX_WEB_ROOT}"
	echo "Nginx config source: ${NGINX_CONF_SOURCE}"
	echo "Nginx config target: ${NGINX_CONF_TARGET}"
	echo "Package Manager: ${PKG_MGR}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling installUtilPackages() (optional)...${RESET}"
	installUtilPackages

	echo -e "\n${CYAN}Calling installNginx()...${RESET}"
	installNginx

	echo -e "\n${CYAN}Calling setupWebContent()...${RESET}"
	setupWebContent

	echo -e "\n${CYAN}Calling createRoboshopNginxConf()...${RESET}"
	createRoboshopNginxConf

	echo -e "\n${CYAN}Calling restartNginx()...${RESET}"
	restartNginx

	echo -e "\n${GREEN}WEB/Nginx setup script completed successfully.${RESET}"
}

main "$@"
