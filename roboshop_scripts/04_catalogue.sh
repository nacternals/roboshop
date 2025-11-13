#!/usr/bin/env bash

#Prepare this script as like as mongodb.sh like colors, functions, comments, logs, script source directory....etc
#This script will create a Catalogue Microservice
#1.
#
#

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
script_name="$(basename "$0")"                              # e.g. catalogue.sh
script_base="${script_name%.*}"                             # e.g. catalogue
log_file="${logs_directory}/${script_base}-$(date +%F).log" # one log file per day
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Directory where script lives
echo "source directory is : ${SCRIPT_DIR}"
UTIL_PKG_FILE="${SCRIPT_DIR}/05_catalogueutilpackages.txt"     # File containing utility package list (one per line)

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
# Reads package names from catalogueutilpackages.txt (one per line) and installs them.
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

installNodeJS() {
	# Step 1: Check if NodeJS is already installed
	echo -e "${CYAN}Checking if NodeJS is already installed...${RESET}"

	if command -v node >/dev/null 2>&1; then
		# Get current Node version (e.g. v18.19.0 → 18)
		local node_version
		node_version="$(node -v | sed 's/^v//')" # remove leading 'v'
		local node_major="${node_version%%.*}"   # take first part before '.'

		echo -e "${YELLOW}Found NodeJS version: ${node_version}${RESET}"

		if ((node_major >= 18)); then
			echo -e "${GREEN}NodeJS version is already >= 18. Skipping installation.${RESET}"
			return
		else
			echo -e "${YELLOW}NodeJS version is < 18. Will upgrade via YUM module.${RESET}"
		fi
	else
		echo -e "${YELLOW}NodeJS is not installed. Proceeding with fresh installation...${RESET}"
	fi

	# Step 2: List available NodeJS modules (to see what streams are present)
	echo -e "${CYAN}Checking available NodeJS module streams...${RESET}"
	${SUDO:-} yum module list nodejs
	validateStep $? \
		"Successfully listed NodeJS module streams." \
		"Failed to list NodeJS module streams."

	# Step 3: Disable existing NodeJS module (usually default is nodejs 10 on CentOS 8)
	echo -e "${CYAN}Disabling existing NodeJS module stream (if any, e.g., nodejs 10)...${RESET}"
	${SUDO:-} yum module disable -y nodejs
	validateStep $? \
		"Disabled existing NodeJS module stream successfully." \
		"Failed to disable existing NodeJS module stream."

	# Step 4: Enable NodeJS 18 module stream
	# NOTE: This assumes nodejs:18 is available in your OS module repo
	echo -e "${CYAN}Enabling NodeJS 18 module stream (nodejs:18)...${RESET}"
	${SUDO:-} yum module enable -y nodejs:18
	validateStep $? \
		"Enabled NodeJS 18 module stream (nodejs:18) successfully." \
		"Failed to enable NodeJS 18 module stream (nodejs:18)."

	# Step 5: Install NodeJS from the enabled module stream
	echo -e "${CYAN}Installing NodeJS from the enabled module stream...${RESET}"
	${SUDO:-} yum install -y nodejs
	validateStep $? \
		"NodeJS installed successfully from module stream." \
		"Failed to install NodeJS from module stream."

	# Step 6: Final verification of NodeJS version after installation
	echo -e "${CYAN}Verifying NodeJS installation and version...${RESET}"
	if command -v node >/dev/null 2>&1; then
		local final_node_version
		final_node_version="$(node -v | sed 's/^v//')"
		local final_node_major="${final_node_version%%.*}"

		echo -e "${GREEN}NodeJS is installed. Version: v${final_node_version}${RESET}"

		if ((final_node_major >= 18)); then
			echo -e "${GREEN}NodeJS final version is >= 18. Installation/upgrade successful.${RESET}"
		else
			echo -e "${YELLOW}NodeJS final version is < 18, which is unexpected after enabling nodejs:18.${RESET}"
		fi
	else
		echo -e "${RED}NodeJS command not found even after installation. Please check YUM logs / repository configuration.${RESET}"
		exit 1
	fi
}

# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${logs_directory}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${log_file}" 2>&1

	echo -e "${BLUE}Catalogue script execution has been started @ ${timestamp}${RESET}"
	echo "Log Directory: ${logs_directory}"
	echo "Log File Location and Name: ${log_file}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling installUtilPackages() to install utility packages from file...${RESET}"
	installUtilPackages

	echo -e "\n${CYAN}Calling installNodeJS()...${RESET}"
	installNodeJS

	echo -e "\n${GREEN}Catalogue setup script: Still work-in-progress....${RESET}"
}

main "$@"
