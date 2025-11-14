#!/usr/bin/env bash

# 07_loadcatalogueschema.sh
#
# Purpose:
#   - Prepare /app and roboshop user (like other roboshop scripts)
#   - Download catalogue.zip and unzip it into /app
#   - Install MongoDB shell client (mongodb-org-shell)
#   - Load the Catalogue schema into the MongoDB server
#
# Notes:
#   - Expects catalogue schema at /app/schema/catalogue.js after unzip
#   - MongoDB server must be reachable on port 27017
#   - MONGODB_HOST can be overridden via environment variable when running

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

SCRIPT_NAME="$(basename "$0")"                             # e.g. 07_loadcatalogueschema.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. 07_loadcatalogueschema
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives

LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

# MongoDB repo file inside repo (reuse the same 02_mongodb.repo)
MONGO_REPO_FILE="${SCRIPT_DIR}/02_mongodb.repo"

# Where catalogue schema is expected after unzip
CATALOGUE_SCHEMA_FILE="${APP_DIR}/schema/catalogue.js"

# MongoDB host (can override when running: MONGODB_HOST=my-mongo bash 07_loadcatalogueschema.sh)
MONGODB_HOST="${MONGODB_HOST:-mongodb.optimusprime.sbs}"
MONGODB_PORT="${MONGODB_PORT:-27017}"

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

# ---------- Basic app requirements (/app + roboshop) ----------
basicAppRequirements() {
	echo -e "${CYAN}Ensuring basic application requirements (${APP_DIR} dir and roboshop user)...${RESET}"

	# 1) Ensure APP_DIR directory exists
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

	# 2) Ensure application user 'roboshop' exists
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

	# 3) Ensure APP_DIR ownership is set to roboshop
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

# ---------- Download and unzip catalogue code (for schema) ----------
downloadCatalogueCode() {
	echo -e "${CYAN}Preparing catalogue code under ${APP_DIR} for schema load...${RESET}"

	# Download catalogue.zip
	echo -e "${CYAN}Downloading catalogue application code to /tmp/catalogue.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/catalogue.zip "https://roboshop-builds.s3.amazonaws.com/catalogue.zip"
	validateStep $? \
		"Catalogue application zip downloaded successfully." \
		"Failed to download catalogue application zip."

	# Clean existing contents (optional but keeps /app tidy on bastion)
	echo -e "${CYAN}Cleaning existing contents under ${APP_DIR}...${RESET}"
	${SUDO:-} rm -rf "${APP_DIR}"/*
	validateStep $? \
		"Existing contents under ${APP_DIR} cleaned successfully." \
		"Failed to clean existing contents under ${APP_DIR}."

	# Unzip into APP_DIR
	echo -e "${CYAN}Unzipping catalogue application into ${APP_DIR}...${RESET}"
	${SUDO:-} unzip -o /tmp/catalogue.zip -d "${APP_DIR}" >/dev/null
	validateStep $? \
		"Catalogue application unzipped into ${APP_DIR} successfully." \
		"Failed to unzip catalogue application into ${APP_DIR}."

	# Ensure ownership to roboshop
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop' after unzip...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."

	# Check schema file exists
	if [[ ! -f "${CATALOGUE_SCHEMA_FILE}" ]]; then
		echo -e "${RED}ERROR: Expected schema file not found: ${CATALOGUE_SCHEMA_FILE}${RESET}"
		exit 1
	fi

	echo -e "${GREEN}Catalogue code prepared and schema file found at ${CATALOGUE_SCHEMA_FILE}.${RESET}"
}

# ---------- MongoDB repo for client ----------
createMongoRepoForClient() {
	echo -e "${CYAN}Checking MongoDB repo for client tools...${RESET}"

	if [[ -f /etc/yum.repos.d/mongo.repo ]]; then
		echo -e "${YELLOW}MongoDB repo already exists, skipping....${RESET}"
		return
	fi

	if [[ ! -f "${MONGO_REPO_FILE}" ]]; then
		echo -e "${RED}ERROR: MongoDB repo template file not found: ${MONGO_REPO_FILE}${RESET}"
		exit 1
	fi

	echo -e "${CYAN}MongoDB repo not found. Creating MongoDB repo for client....${RESET}"
	echo "mongo.repo template location: ${MONGO_REPO_FILE}"

	${SUDO:-} cp "${MONGO_REPO_FILE}" /etc/yum.repos.d/mongo.repo
	validateStep $? \
		"MongoDB repo created at /etc/yum.repos.d/mongo.repo" \
		"Failed to create MongoDB repo. Copy operation failed."
}

# ---------- Install MongoDB shell client ----------
installMongoClient() {
	echo -e "${CYAN}Checking if MongoDB shell (mongodb-org-shell) is installed...${RESET}"

	if rpm -q mongodb-org-shell >/dev/null 2>&1; then
		echo -e "${YELLOW}mongodb-org-shell is already installed. Skipping installation.${RESET}"
		return
	fi

	echo -e "${CYAN}Installing MongoDB shell client (mongodb-org-shell)...${RESET}"
	${SUDO:-} yum install -y mongodb-org-shell
	validateStep $? \
		"MongoDB shell client (mongodb-org-shell) installed successfully." \
		"Failed to install MongoDB shell client (mongodb-org-shell)."
}

# ---------- Load Catalogue schema ----------
loadCatalogueSchema() {
	echo -e "${CYAN}Loading Catalogue schema into MongoDB...${RESET}"

	if [[ ! -f "${CATALOGUE_SCHEMA_FILE}" ]]; then
		echo -e "${RED}ERROR: Catalogue schema file not found: ${CATALOGUE_SCHEMA_FILE}${RESET}"
		echo -e "${YELLOW}Ensure catalogue application code is deployed under ${APP_DIR} with schema/catalogue.js${RESET}"
		exit 1
	fi

	echo -e "${CYAN}Using MongoDB host: ${MONGODB_HOST}:${MONGODB_PORT}${RESET}"
	echo -e "${CYAN}Running: mongo --host ${MONGODB_HOST} --port ${MONGODB_PORT} < ${CATALOGUE_SCHEMA_FILE}${RESET}"

	mongo --host "${MONGODB_HOST}" --port "${MONGODB_PORT}" <"${CATALOGUE_SCHEMA_FILE}"
	validateStep $? \
		"Catalogue schema loaded successfully into MongoDB." \
		"Failed to load catalogue schema into MongoDB."
}

# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${LOGS_DIRECTORY}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Load Catalogue Schema Script Execution" "${TIMESTAMP}"
	echo "App Directory: ${APP_DIR}"
	echo "Log Directory: ${LOGS_DIRECTORY}"
	echo "Log File Location and Name: ${LOG_FILE}"
	echo "Script Directory: ${SCRIPT_DIR}"
	echo "MongoDB Host: ${MONGODB_HOST}:${MONGODB_PORT}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling downloadCatalogueCode() to download and unzip catalogue code...${RESET}"
	downloadCatalogueCode

	echo -e "\n${CYAN}Calling createMongoRepoForClient() to configure MongoDB repo...${RESET}"
	createMongoRepoForClient

	echo -e "\n${CYAN}Calling installMongoClient() to install MongoDB shell client...${RESET}"
	installMongoClient

	echo -e "\n${CYAN}Calling loadCatalogueSchema() to load schema into MongoDB...${RESET}"
	loadCatalogueSchema

	echo -e "\n${GREEN}Load Catalogue Schema script completed successfully.${RESET}"
}

main "$@"
