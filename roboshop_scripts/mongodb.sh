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
timestamp="$(date +"%F-%H-%M-%S")"
logs_directory="/app/logs"
script_name="$(basename "$0")"                               # e.g. mongodb.sh
script_base="${script_name%.*}"                              # e.g. mongodb
log_file="${logs_directory}/${script_base}-${timestamp}.log" # one log file per execution
# log_file="${logs_directory}/${script_base}-$(date +%F).log" # one log file per day
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives

# ---------- Helper: validate step ----------
# Usage:
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

createMongoRepo() {
	echo -e "${CYAN}Checking MongoDB repo...${RESET}"

	if [[ -f /etc/yum.repos.d/mongo.repo ]]; then
		echo -e "${YELLOW}MongoDB repo already exists, skipping.${RESET}"
		return
	fi

	echo -e "${CYAN}MongoDB repo not found. Creating MongoDB repo...${RESET}"
	echo "mongodb.repo script location: ${SCRIPT_DIR}/mongodb.repo"

	# Try copying the repo file
	${SUDO:-} cp "${SCRIPT_DIR}/mongodb.repo" /etc/yum.repos.d/mongo.repo
	validateStep $? \
		"MongoDB repo created at /etc/yum.repos.d/mongo.repo" \
		"Failed to create MongoDB repo. Copy operation failed."
}

main() {
	# Ensure log dir exists
	mkdir -p "${logs_directory}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${log_file}" 2>&1

	echo -e "${BLUE}MongoDB script execution has been started @ ${timestamp}${RESET}"
	echo "Log Directory: ${logs_directory}"
	echo "MongoDB Log File Name: ${log_file}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling createMongoRepo()...${RESET}"
	createMongoRepo

	# your MongoDB setup steps here...
}

main "$@"
