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
installGo() {
	echo -e "${CYAN}Installing GoLang...${RESET}"
	${SUDO:-} "${PKG_MGR}" install -y golang
	validateStep $? \
		"GoLang installed successfully." \
		"Failed to install GoLang."
}

installDispatchService() {
	echo -e "${CYAN}Setting up Dispatch microservice...${RESET}"

	installGo

	echo -e "${CYAN}Downloading dispatch application code...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/dispatch.zip "https://roboshop-builds.s3.amazonaws.com/dispatch.zip"
	validateStep $? \
		"Dispatch application zip downloaded successfully." \
		"Failed to download dispatch application zip."

	echo -e "${CYAN}Extracting dispatch application into /app...${RESET}"
	${SUDO:-} unzip -o /tmp/dispatch.zip -d /app >/dev/null
	validateStep $? \
		"Dispatch application extracted into /app successfully." \
		"Failed to extract dispatch application into /app."

	echo -e "${CYAN}Initializing Go module and building dispatch binary...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd /app && go mod init dispatch || true && go get && go build" >/dev/null
	validateStep $? \
		"Dispatch application built successfully." \
		"Failed to build dispatch application."
}

createDispatchSystemDService() {
	echo -e "${CYAN}Creating / updating systemd service for dispatch...${RESET}"

	local SERVICE_FILE="/etc/systemd/system/dispatch.service"

	${SUDO:-} bash -c "cat > ${SERVICE_FILE}" <<'EOF'
[Unit]
Description=Dispatch Service

[Service]
User=roboshop
Environment=AMQP_HOST=rabbitmq.optimusprime.sbs
Environment=AMQP_USER=roboshop
Environment=AMQP_PASS=roboshop123
ExecStart=/app/dispatch
SyslogIdentifier=dispatch
Restart=always

[Install]
WantedBy=multi-user.target
EOF
	validateStep $? \
		"dispatch.service systemd unit created/updated." \
		"Failed to create/update dispatch.service."

	echo -e "${CYAN}Reloading systemd daemon and starting dispatch service...${RESET}"
	${SUDO:-} systemctl daemon-reload
	${SUDO:-} systemctl enable dispatch
	${SUDO:-} systemctl restart dispatch
	validateStep $? \
		"Dispatch service enabled and started successfully." \
		"Failed to enable/start dispatch service."
}

main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Dispatch Service Setup Script Execution" "${TIMESTAMP}"

	echo "Script Name      : ${SCRIPT_NAME}"
	echo "Script Directory : ${SCRIPT_DIR}"
	echo "Log File         : ${LOG_FILE}"

	isItRootUser
	basicAppRequirements

	installDispatchService
	createDispatchSystemDService

	echo -e "${GREEN}Dispatch service setup script completed successfully.${RESET}"
}

main "$@"
