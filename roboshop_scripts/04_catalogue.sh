#!/usr/bin/env bash

# This script will create and configure the Catalogue microservice.
# It:
#   - Installs required utility packages
#   - Ensures NodeJS (>= 18) is installed
#   - Creates roboshop application user and /app directory
#   - Downloads and sets up the catalogue application code
#   - Creates and starts the catalogue SystemD service
#
# Logging, colors, helper functions, and directory handling are similar to mongodb.sh.

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
timestamp="$(date +"%F-%H-%M-%S")"                          # Full timestamp of this run
logs_directory="/app/logs"                                  # Central log directory
script_name="$(basename "$0")"                              # e.g. 04_catalogue.sh
script_base="${script_name%.*}"                             # e.g. 04_catalogue
log_file="${logs_directory}/${script_base}-$(date +%F).log" # one log file per day
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Directory where script lives
UTIL_PKG_FILE="${SCRIPT_DIR}/05_catalogueutilpackages.txt"  # File containing utility package list (one per line)
CATALOGUE_SERVICE_FILE="${SCRIPT_DIR}/06_catalogue.service" # SystemD service template

# ---------- Helper: validate step ----------
# Usage pattern:
#   some_command
#   validateStep $? "success message" "failure message"
validateStep() {
	local status="$1"
	local success_msg="$2"
	local failure_msg="$3"

	if [[ "$status" -eq 0 ]]; then
		echo -e "${GREEN}[SUCCESS]${RESET} ${success_msg}"
	else
		echo -e "${RED}[FAILURE]${RESET} ${failure_msg} (exit code: ${status})"
		exit "$status"
	fi
}

# ---------- Root / sudo handling ----------
# Sets SUDO variable as "sudo" for non-root users (if sudo is available),
# or empty string if script is already running as root.
isItRootUser() {
	echo -e "${CYAN}Checking whether script is running as root...${RESET}"

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		if command -v sudo >/dev/null 2>&1; then
			SUDO="sudo"
			echo -e "${YELLOW}Not a ROOT user. Using 'sudo' for privileged operations.${RESET}"
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
# Reads package names from 05_catalogueutilpackages.txt (one per line) and installs them.
installUtilPackages() {
	echo -e "${CYAN}Checking utility package list file: ${UTIL_PKG_FILE}${RESET}"

	# Ensure the util package file exists
	if [[ ! -f "${UTIL_PKG_FILE}" ]]; then
		echo -e "${RED}ERROR: Utility package file not found: ${UTIL_PKG_FILE}${RESET}"
		echo -e "${YELLOW}Create the file and add one package name per line, then rerun the script.${RESET}"
		exit 1
	fi

	# Read packages into an array (skip empty lines)
	local packages=()
	while IFS= read -r pkg; do
		# Trim simple whitespace and skip blank lines
		[[ -z "${pkg}" ]] && continue
		packages+=("${pkg}")
	done <"${UTIL_PKG_FILE}"

	if [[ "${#packages[@]}" -eq 0 ]]; then
		echo -e "${YELLOW}No packages found in ${UTIL_PKG_FILE}. Skipping utility installation.${RESET}"
		return
	fi

	echo -e "${CYAN}Utility packages to install: ${packages[*]}${RESET}"

	# Install each package individually to track success/failure per package
	for pkg in "${packages[@]}"; do
		echo -e "${CYAN}Installing utility package: ${pkg}${RESET}"
		${SUDO:-} yum install -y "${pkg}"
		validateStep $? \
			"Utility package '${pkg}' installed successfully." \
			"Failed to install utility package '${pkg}'."
	done

	echo -e "${GREEN}All requested utility packages processed successfully.${RESET}"
}

# ---------- NodeJS installation (handles module and non-module OSes) ----------
installNodeJS() {
	echo -e "${CYAN}Checking if NodeJS is already installed...${RESET}"

	# Step 1: Check if NodeJS is already installed
	if command -v node >/dev/null 2>&1; then
		local node_version
		node_version="$(node -v | sed 's/^v//')" # remove leading 'v', e.g. v18.19.0 -> 18.19.0
		local node_major="${node_version%%.*}"   # take part before first dot, e.g. 18

		echo -e "${YELLOW}Found NodeJS version: ${node_version}${RESET}"

		if ((node_major >= 18)); then
			echo -e "${GREEN}NodeJS version is already >= 18. Skipping installation.${RESET}"
			return
		else
			echo -e "${YELLOW}NodeJS version is < 18. Will try to upgrade.${RESET}"
		fi
	else
		echo -e "${YELLOW}NodeJS is not installed. Proceeding with fresh installation...${RESET}"
	fi

	# Step 2: Try module-based flow (CentOS/RHEL style)
	echo -e "${CYAN}Checking if 'nodejs' module streams are available...${RESET}"
	if ${SUDO:-} yum module list nodejs >/dev/null 2>&1; then
		echo -e "${CYAN}NodeJS module stream detected. Using module-based installation...${RESET}"

		echo -e "${CYAN}Disabling existing NodeJS module stream (if any)...${RESET}"
		${SUDO:-} yum module disable -y nodejs
		validateStep $? \
			"Disabled existing NodeJS module stream successfully." \
			"Failed to disable existing NodeJS module stream."

		echo -e "${CYAN}Enabling NodeJS 18 module stream (nodejs:18)...${RESET}"
		${SUDO:-} yum module enable -y nodejs:18
		validateStep $? \
			"Enabled NodeJS 18 module stream (nodejs:18) successfully." \
			"Failed to enable NodeJS 18 module stream (nodejs:18)."

		echo -e "${CYAN}Installing NodeJS from the enabled module stream...${RESET}"
		${SUDO:-} yum install -y nodejs
		validateStep $? \
			"NodeJS installed successfully from module stream." \
			"Failed to install NodeJS from module stream."
	else
		# Step 3: Fallback path (Amazon Linux 2023, etc. without modules)
		echo -e "${YELLOW}No 'nodejs' module streams found. Falling back to plain package installation.${RESET}"

		# Try candidate package names in order
		local candidates=(nodejs18 nodejs nodejs16)
		local installed=false

		for pkg in "${candidates[@]}"; do
			echo -e "${CYAN}Checking availability of package: ${pkg}${RESET}"
			if ${SUDO:-} yum list available "${pkg}" >/dev/null 2>&1; then
				echo -e "${CYAN}Installing NodeJS package: ${pkg}${RESET}"
				${SUDO:-} yum install -y "${pkg}"
				validateStep $? \
					"NodeJS installed successfully via package '${pkg}'." \
					"Failed to install NodeJS package '${pkg}'."
				installed=true
				break
			fi
		done

		if [[ "${installed}" == false ]]; then
			echo -e "${RED}ERROR: Could not find a suitable NodeJS package (tried: ${candidates[*]}).${RESET}"
			exit 1
		fi
	fi

	# Step 4: Final verification of NodeJS installation and version
	echo -e "${CYAN}Verifying NodeJS installation and version...${RESET}"
	if command -v node >/dev/null 2>&1; then
		local final_node_version
		final_node_version="$(node -v | sed 's/^v//')"
		local final_node_major="${final_node_version%%.*}"

		echo -e "${GREEN}NodeJS is installed. Version: v${final_node_version}${RESET}"

		if ((final_node_major >= 18)); then
			echo -e "${GREEN}NodeJS final version is >= 18. Installation/upgrade successful.${RESET}"
		else
			echo -e "${YELLOW}NodeJS final version is < 18. Installation succeeded, but version is lower than expected.${RESET}"
		fi
	else
		echo -e "${RED}NodeJS command not found even after installation. Please check YUM/DNF logs and repository configuration.${RESET}"
		exit 1
	fi
}

# ---------- Catalogue application setup ----------
installCatalogue() {
	echo -e "${CYAN}Setting up Catalogue application...${RESET}"

	# 1) Ensure roboshop user exists
	echo -e "${CYAN}Checking if 'roboshop' user exists...${RESET}"
	if id roboshop >/dev/null 2>&1; then
		echo -e "${YELLOW}User 'roboshop' already exists. Skipping user creation.${RESET}"
	else
		echo -e "${CYAN}Creating application user 'roboshop'...${RESET}"
		${SUDO:-} useradd roboshop
		validateStep $? \
			"Application user 'roboshop' created successfully." \
			"Failed to create application user 'roboshop'."
	fi

	# 2) Ensure /app directory exists
	echo -e "${CYAN}Checking /app directory...${RESET}"
	if [[ -d /app ]]; then
		echo -e "${YELLOW}/app directory already exists.${RESET}"
	else
		echo -e "${CYAN}/app directory not found. Creating /app...${RESET}"
		${SUDO:-} mkdir -p /app
		validateStep $? \
			"/app directory created successfully." \
			"Failed to create /app directory."
	fi

	# 3) Download the catalogue code
	echo -e "${CYAN}Downloading catalogue application code to /tmp/catalogue.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/catalogue.zip "https://roboshop-builds.s3.amazonaws.com/catalogue.zip"
	validateStep $? \
		"Catalogue application zip downloaded successfully." \
		"Failed to download catalogue application zip."

	# 4) Clean existing app content (optional but common in Roboshop flows)
	# echo -e "${CYAN}Cleaning existing contents under /app...${RESET}"
	# ${SUDO:-} rm -rf /app/*
	# validateStep $? \
	# 	"Existing contents under /app cleaned successfully." \
	# 	"Failed to clean existing contents under /app."

	# 5) Unzip into /app
	echo -e "${CYAN}Unzipping catalogue application into /app...${RESET}"
	${SUDO:-} unzip -o /tmp/catalogue.zip -d /app >/dev/null
	validateStep $? \
		"Catalogue application unzipped into /app successfully." \
		"Failed to unzip catalogue application into /app."

	# 6) Set ownership to roboshop user
	echo -e "${CYAN}Setting ownership of /app to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop /app
	validateStep $? \
		"Ownership of /app set to roboshop successfully." \
		"Failed to set ownership of /app to roboshop."

	# 7) Install NodeJS dependencies as roboshop user
	echo -e "${CYAN}Installing NodeJS dependencies (npm install) as 'roboshop' user...${RESET}"
	${SUDO:-} su - roboshop -s /bin/bash -c "cd /app && npm install" >/dev/null
	validateStep $? \
		"NodeJS dependencies installed successfully (npm install)." \
		"Failed to install NodeJS dependencies (npm install)."

	echo -e "${GREEN}Catalogue application setup completed.${RESET}"
}

# ---------- SystemD service setup for Catalogue ----------
createCatalogueSystemDService() {
	echo -e "${CYAN}Checking Catalogue SystemD service...${RESET}"

	if [[ -f /etc/systemd/system/catalogue.service ]]; then
		echo -e "${YELLOW}Catalogue SystemD service already exists, skipping creation....${RESET}"
		return
	fi

	echo -e "${CYAN}Catalogue SystemD service not found. Creating Catalogue SystemD service....${RESET}"
	echo "Catalogue service file location: ${CATALOGUE_SERVICE_FILE}"

	# Copy the service unit file
	${SUDO:-} cp "${CATALOGUE_SERVICE_FILE}" /etc/systemd/system/catalogue.service
	validateStep $? \
		"Catalogue SystemD service file has been created at /etc/systemd/system/catalogue.service." \
		"Failed to create Catalogue SystemD service file. Copy operation failed."

	# Reload systemd daemon
	echo -e "${CYAN}Reloading SystemD daemon...${RESET}"
	${SUDO:-} systemctl daemon-reload
	validateStep $? \
		"SystemD daemon reloaded successfully." \
		"Failed to reload SystemD daemon."

	# Enable catalogue service
	echo -e "${CYAN}Enabling catalogue service to start on boot...${RESET}"
	${SUDO:-} systemctl enable catalogue
	validateStep $? \
		"Catalogue service enabled to start on boot." \
		"Failed to enable catalogue service."

	# Start catalogue service
	echo -e "${CYAN}Starting catalogue service...${RESET}"
	${SUDO:-} systemctl start catalogue
	validateStep $? \
		"Catalogue service started successfully." \
		"Failed to start catalogue service."

	echo -e "${GREEN}Catalogue SystemD service created and started successfully.${RESET}"
}

# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${logs_directory}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${log_file}" 2>&1

	echo -e "\n${BLUE}Catalogue script execution has been started @ ${timestamp}${RESET}"
	echo "Log Directory: ${logs_directory}"
	echo "Log File Location and Name: ${log_file}"
	echo "Script source directory: ${SCRIPT_DIR}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling installUtilPackages() to install utility packages from file...${RESET}"
	installUtilPackages

	echo -e "\n${CYAN}Calling installNodeJS()...${RESET}"
	installNodeJS

	echo -e "\n${CYAN}Calling installCatalogue()...${RESET}"
	installCatalogue

	echo -e "\n${CYAN}Calling createCatalogueSystemDService()...${RESET}"
	createCatalogueSystemDService

	echo -e "\n${GREEN}Catalogue setup script completed.${RESET}"
}

main "$@"
