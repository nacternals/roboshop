#!/usr/bin/env bash

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
timestamp="$(date +"%F-%H-%M-%S")" # Full timestamp of this run
logs_directory="/app/logs"         # Central log directory
script_name="$(basename "$0")"     # e.g. mongodb.sh
script_base="${script_name%.*}"    # e.g. mongodb
# log_file="${logs_directory}/${script_base}-${timestamp}.log"    # one log file per execution
log_file="${logs_directory}/${script_base}-$(date +%F).log" # one log file per day
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Directory where script lives
UTIL_PKG_FILE="${SCRIPT_DIR}/mongodbutilpackages.txt" # File containing utility package list (one per line)

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
			echo -e "${YELLOW}Not root. Using 'sudo' for privileged operations.${RESET}"
		else
			echo -e "${RED}ERROR: Insufficient privileges. Run as root or install sudo.${RESET}"
			exit 1
		fi
	else
		SUDO=""
		echo -e "${GREEN}Executing this script as ROOT user.${RESET}"
	fi
}

# ---------- Utility package installer ----------
# Reads package names from mongodbutilpackages.txt (one per line) and installs them.
# Example mongodbutilpackages.txt content:
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

# ---------- MongoDB repo setup ----------
createMongoRepo() {
	echo -e "${CYAN}Checking MongoDB repo...${RESET}"

	if [[ -f /etc/yum.repos.d/mongo.repo ]]; then
		echo -e "${YELLOW}MongoDB repo already exists, skipping....${RESET}"
		return
	fi

	echo -e "${CYAN}MongoDB repo not found. Creating MongoDB repo....${RESET}"
	echo "mongodb.repo script location: ${SCRIPT_DIR}/mongodb.repo"

	# Try copying the repo file from script directory to yum repo directory
	${SUDO:-} cp "${SCRIPT_DIR}/mongodb.repo" /etc/yum.repos.d/mongo.repo
	validateStep $? \
		"MongoDB repo created at /etc/yum.repos.d/mongo.repo" \
		"Failed to create MongoDB repo. Copy operation failed."
}

# ---------- MongoDB installation & configuration ----------
installMongoDB() {
	# First check whether mongodb is already installed or not
	echo -e "${CYAN}Checking if MongoDB is already installed...${RESET}"

	# Check if mongod command exists
	if command -v mongod >/dev/null 2>&1; then
		echo -e "${YELLOW}MongoDB is already installed. Skipping installation.${RESET}"
		return
	fi

	echo -e "${CYAN}MongoDB not found. Proceeding with installation...${RESET}"

	# Install MongoDB (expects repo already created)
	${SUDO:-} yum install -y mongodb-org
	validateStep $? \
		"MongoDB packages installed successfully." \
		"Failed to install MongoDB packages."

	# Enable MongoDB service
	echo -e "${CYAN}Enabling MongoDB service (mongod)...${RESET}"
	${SUDO:-} systemctl enable mongod
	validateStep $? \
		"MongoDB service enabled to start on boot." \
		"Failed to enable MongoDB service."

	# Start MongoDB service
	echo -e "${CYAN}Starting MongoDB service (mongod)...${RESET}"
	${SUDO:-} systemctl start mongod
	validateStep $? \
		"MongoDB service started successfully." \
		"Failed to start MongoDB service."

	# Update bind IP in /etc/mongod.conf from 127.0.0.1 to 0.0.0.0
	echo -e "${CYAN}Updating MongoDB bind IP in /etc/mongod.conf (127.0.0.1 → 0.0.0.0)...${RESET}"

	if [[ -f /etc/mongod.conf ]]; then
		if grep -q "127.0.0.1" /etc/mongod.conf; then
			${SUDO:-} sed -i 's/127\.0\.0\.1/0.0.0.0/g' /etc/mongod.conf
			validateStep $? \
				"Updated bind IP in /etc/mongod.conf to 0.0.0.0." \
				"Failed to update bind IP in /etc/mongod.conf."

			echo -e "${CYAN}Restarting MongoDB service after bind IP config change...${RESET}"
			${SUDO:-} systemctl restart mongod
			validateStep $? \
				"MongoDB service restarted successfully after bind IP config change." \
				"Failed to restart MongoDB service after bind IP config change."
		else
			echo -e "${YELLOW}No '127.0.0.1' entry found in /etc/mongod.conf. Skipping bind IP update.${RESET}"
		fi
	else
		echo -e "${RED}WARNING: /etc/mongod.conf not found. Skipping bind IP update.${RESET}"
	fi

	echo -e "${GREEN}MongoDB installation and basic configuration completed.${RESET}"
}

# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${logs_directory}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${log_file}" 2>&1

	echo -e "${BLUE}MongoDB script execution has been started @ ${timestamp}${RESET}"
	echo "Log Directory: ${logs_directory}"
	echo "Log File Location and Name: ${log_file}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling installUtilPackages() to install utility packages from file...${RESET}"
	installUtilPackages

	echo -e "\n${CYAN}Calling createMongoRepo()...${RESET}"
	createMongoRepo

	echo -e "\n${CYAN}Calling installMongoDB()...${RESET}"
	installMongoDB

	echo -e "\n${GREEN}MongoDB setup script completed successfully.${RESET}"
}

main "$@"
