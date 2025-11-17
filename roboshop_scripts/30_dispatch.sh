#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Dispatch Service Setup Script for RoboShop
#
# Responsibilities:
#   - Ensure /app and /app/logs exist and are owned by 'roboshop'
#   - Install utility packages from 31_dispatch_util_packages.txt
#   - Install/verify Go (Golang) runtime (>= 1.18)
#   - Download and build Dispatch Go microservice in /app/dispatch
#   - Configure and enable dispatch.service (SystemD unit)
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
DISPATCH_APP_DIR="/app/dispatch"

SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

# Utility package list lives inside the git repo, next to script
UTIL_PKG_FILE="${SCRIPT_DIR}/31_dispatch_util_packages.txt"
DISPATCH_SERVICE_FILE="${SCRIPT_DIR}/32_dispatch.service"

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

# ---------- Function: installGo ----------
# Purpose : Ensure Golang (>= 1.18) is installed using module streams or packages.
installGo() {
	echo -e "${CYAN}Checking if Go (Golang) is already installed...${RESET}"

	if command -v go >/dev/null 2>&1; then
		local go_version_raw
		local go_version
		local go_major
		local go_minor

		# go version output example: "go version go1.20.3 linux/amd64"
		go_version_raw="$(go version | awk '{print $3}')" # go1.20.3
		go_version="${go_version_raw#go}"                 # 1.20.3
		go_major="${go_version%%.*}"                      # 1
		local tmp="${go_version#*.}"                      # 20.3
		go_minor="${tmp%%.*}"                             # 20

		echo -e "${YELLOW}Found Go version: ${go_version_raw} (${go_version})${RESET}"

		# Require at least Go 1.18 (adjust if you want newer)
		if ((go_major > 1)) || ((go_major == 1 && go_minor >= 18)); then
			echo -e "${GREEN}Go version is already >= 1.18. Skipping installation.${RESET}"
			return
		else
			echo -e "${YELLOW}Go version is < 1.18. Will try to upgrade.${RESET}"
		fi
	else
		echo -e "${YELLOW}Go is not installed. Proceeding with fresh installation...${RESET}"
	fi

	echo -e "${CYAN}Checking if 'golang' module streams are available...${RESET}"
	if ${SUDO:-} yum module list golang >/dev/null 2>&1; then
		echo -e "${CYAN}Golang module stream detected. Using module-based installation...${RESET}"

		echo -e "${CYAN}Disabling existing Golang module stream (if any)...${RESET}"
		${SUDO:-} yum module disable -y golang
		validateStep $? \
			"Disabled existing Golang module stream successfully." \
			"Failed to disable existing Golang module stream."

		# Adjust version here if you want a specific stream (e.g., golang:1.20)
		echo -e "${CYAN}Enabling Golang 1.20 module stream (golang:1.20)...${RESET}"
		${SUDO:-} yum module enable -y golang:1.20
		validateStep $? \
			"Enabled Golang 1.20 module stream (golang:1.20) successfully." \
			"Failed to enable Golang 1.20 module stream (golang:1.20)."

		echo -e "${CYAN}Installing Golang from the enabled module stream...${RESET}"
		${SUDO:-} yum install -y golang
		validateStep $? \
			"Golang installed successfully from module stream." \
			"Failed to install Golang from module stream."
	else
		echo -e "${YELLOW}No 'golang' module streams found. Falling back to plain package installation.${RESET}"

		local candidates=(golang go golang18 golang20)
		local installed=false

		for pkg in "${candidates[@]}"; do
			echo -e "${CYAN}Checking availability of package: ${pkg}${RESET}"
			if ${SUDO:-} yum list available "${pkg}" >/dev/null 2>&1; then
				echo -e "${CYAN}Installing Golang package: ${pkg}${RESET}"
				${SUDO:-} yum install -y "${pkg}"
				validateStep $? \
					"Golang installed successfully via package '${pkg}'." \
					"Failed to install Golang package '${pkg}'."
				installed=true
				break
			fi
		done

		if [[ "${installed}" == false ]]; then
			echo -e "${RED}ERROR: Could not find a suitable Golang package (tried: ${candidates[*]}).${RESET}"
			exit 1
		fi
	fi

	echo -e "${CYAN}Verifying Golang installation and version...${RESET}"
	if command -v go >/dev/null 2>&1; then
		local final_go_version_raw
		local final_go_version
		local final_go_major
		local final_go_minor

		final_go_version_raw="$(go version | awk '{print $3}')" # go1.20.3
		final_go_version="${final_go_version_raw#go}"           # 1.20.3
		final_go_major="${final_go_version%%.*}"                # 1
		local final_tmp="${final_go_version#*.}"                # 20.3
		final_go_minor="${final_tmp%%.*}"                       # 20

		echo -e "${GREEN}Golang is installed. Version: ${final_go_version_raw}${RESET}"

		if ((final_go_major > 1)) || ((final_go_major == 1 && final_go_minor >= 18)); then
			echo -e "${GREEN}Golang final version is >= 1.18. Installation/upgrade successful.${RESET}"
		else
			echo -e "${YELLOW}Golang final version is < 1.18. Installation succeeded, but version is lower than expected.${RESET}"
		fi
	else
		echo -e "${RED}Go command not found even after installation. Please check YUM/DNF logs and repository configuration.${RESET}"
		exit 1
	fi
}

# ---------- Function: installDispatchApplication ----------
# Purpose : Download, extract, and build the Dispatch Go microservice.
installDispatchApplication() {
	echo -e "${CYAN}Setting up Dispatch application...${RESET}"

	# Ensure dispatch app directory exists
	echo -e "${CYAN}Ensuring ${DISPATCH_APP_DIR} directory exists...${RESET}"
	${SUDO:-} mkdir -p "${DISPATCH_APP_DIR}"
	validateStep $? \
		"${DISPATCH_APP_DIR} directory is ready." \
		"Failed to create ${DISPATCH_APP_DIR} directory."

	# Download the dispatch code
	echo -e "${CYAN}Downloading dispatch application code to /tmp/dispatch.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/dispatch.zip "https://roboshop-builds.s3.amazonaws.com/dispatch.zip"
	validateStep $? \
		"Dispatch application zip downloaded successfully." \
		"Failed to download dispatch application zip."

	# Unzip into ${DISPATCH_APP_DIR}
	echo -e "${CYAN}Unzipping dispatch application into ${DISPATCH_APP_DIR}...${RESET}"
	${SUDO:-} unzip -o /tmp/dispatch.zip -d "${DISPATCH_APP_DIR}" >/dev/null
	validateStep $? \
		"Dispatch application unzipped into ${DISPATCH_APP_DIR} successfully." \
		"Failed to unzip dispatch application into ${DISPATCH_APP_DIR}."

	# Ownership
	echo -e "${CYAN}Setting ownership of ${DISPATCH_APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${DISPATCH_APP_DIR}"
	validateStep $? \
		"Ownership of ${DISPATCH_APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${DISPATCH_APP_DIR} to roboshop."

	# Build Go binary as roboshop user
	echo -e "${CYAN}Initializing Go module (if needed) and building dispatch binary as 'roboshop' user...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd ${DISPATCH_APP_DIR} && { [ -f go.mod ] || go mod init dispatch; } && go get && go build -o dispatch" >/dev/null
	validateStep $? \
		"Dispatch application built successfully." \
		"Failed to build dispatch application."

	echo -e "${GREEN}Dispatch application setup completed.${RESET}"
}

# ---------- Function: createDispatchSystemDService ----------
# Purpose : Create, enable, and start dispatch.service SystemD unit.
createDispatchSystemDService() {
	echo -e "${CYAN}Checking Dispatch SystemD service...${RESET}"

	if [[ -f /etc/systemd/system/dispatch.service ]]; then
		echo -e "${YELLOW}Dispatch SystemD service already exists, skipping creation....${RESET}"
		return
	fi

	echo -e "${CYAN}Dispatch SystemD service not found. Creating Dispatch SystemD service....${RESET}"
	echo "Dispatch service file location: ${DISPATCH_SERVICE_FILE}"

	${SUDO:-} cp "${DISPATCH_SERVICE_FILE}" /etc/systemd/system/dispatch.service
	validateStep $? \
		"Dispatch SystemD service file has been created at /etc/systemd/system/dispatch.service." \
		"Failed to create Dispatch SystemD service file. Copy operation failed."

	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	echo -e "${CYAN}Enabling dispatch service to start on boot...${RESET}"
	${SUDO:-} systemctl enable dispatch
	validateStep $? \
		"Dispatch service enabled to start on boot." \
		"Failed to enable dispatch service."

	echo -e "${CYAN}Starting dispatch service...${RESET}"
	${SUDO:-} systemctl start dispatch
	validateStep $? \
		"Dispatch service started successfully." \
		"Failed to start dispatch service."

	echo -e "${GREEN}Dispatch SystemD service created and started successfully.${RESET}"
}

# ==========================================================
# Main Execution
# ==========================================================

main() {
	mkdir -p "${LOGS_DIRECTORY}"
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Dispatch Service Setup Script Execution" "${TIMESTAMP}"

	# Echo all key variables for debugging / audit
	echo -e "${CYAN}==== Script Configuration ====${RESET}"
	echo "Script Name          : ${SCRIPT_NAME}"
	echo "Script Base          : ${SCRIPT_BASE}"
	echo "Script Directory     : ${SCRIPT_DIR}"
	echo "Timestamp            : ${TIMESTAMP}"
	echo "App Directory        : ${APP_DIR}"
	echo "Logs Directory       : ${LOGS_DIRECTORY}"
	echo "Log File             : ${LOG_FILE}"
	echo "Package Manager      : ${PKG_MGR}"
	echo "Utility Pkg File     : ${UTIL_PKG_FILE}"
	echo "Dispatch App Dir     : ${DISPATCH_APP_DIR}"
	echo "Dispatch ServiceFile : ${DISPATCH_SERVICE_FILE}"
	echo -e "${CYAN}==============================${RESET}"

	isItRootUser
	echo "SUDO helper          : ${SUDO:-<not set>}"

	basicAppRequirements
	installUtilPackages
	installGo
	installDispatchApplication
	createDispatchSystemDService

	echo -e "${GREEN}Dispatch service setup script completed successfully.${RESET}"
}

main "$@"
