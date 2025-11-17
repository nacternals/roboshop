#!/usr/bin/env bash

# 24_load_shipping_schema.sh
#
# Purpose:
#   - Prepare /app and roboshop user (like other roboshop scripts)
#   - Download shipping.zip and unzip it into /app/shipping
#   - Install MongoDB shell client (mongodb-org-shell)
#   - Load the Shipping schema into the MongoDB server
#
# Notes:
#   - Expects shipping schema at /app/shipping/schema/shipping.sql after unzip
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
TIMESTAMP="$(date +"%F-%H-%M-%S")"                         # Full timestamp of this run
APP_DIR="/app"                                             # Application root directory
SHIPPING_APP_DIR="${APP_DIR}/shipping"                     # Catalogue app root
LOGS_DIRECTORY="${APP_DIR}/logs"                           # Central log directory -> /app/logs
SCRIPT_NAME="$(basename "$0")"                             # e.g. 07_load_catalogue_schema.sh
SCRIPT_BASE="${SCRIPT_NAME%.*}"                            # e.g. 07_load_catalogue_schema
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

# MongoDB repo file inside repo (reuse the same 02_mongodb.repo)
MONGO_REPO_FILE="${SCRIPT_DIR}/02_mongodb.repo"

# Where shipping schema is expected after unzip
SHIPPING_SCHEMA_FILE="${SHIPPING_APP_DIR}/schema/shipping.sql"

# MongoDB host
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

# ---------- Basic app requirements (/app + /app/logs + roboshop) ----------
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

	# 2) Ensure logs directory exists
	echo -e "${CYAN}Ensuring logs directory ${LOGS_DIRECTORY} exists...${RESET}"
	${SUDO:-} mkdir -p "${LOGS_DIRECTORY}"
	validateStep $? \
		"Logs directory ${LOGS_DIRECTORY} is ready." \
		"Failed to create logs directory ${LOGS_DIRECTORY}."

	# 3) Ensure application user 'roboshop' exists
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

	# 4) Ensure ownership of APP_DIR (including logs) is set to roboshop
	echo -e "${CYAN}Setting ownership of ${APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${APP_DIR}"
	validateStep $? \
		"Ownership of ${APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${APP_DIR} to roboshop."
}

downloadShippingCode() {
	echo -e "${CYAN}Setting up Shipping application code...${RESET}"

	# Ensure shipping app directory exists
	echo -e "${CYAN}Ensuring ${SHIPPING_APP_DIR} directory exists...${RESET}"
	${SUDO:-} mkdir -p "${SHIPPING_APP_DIR}"
	validateStep $? \
		"${SHIPPING_APP_DIR} directory is ready." \
		"Failed to create ${SHIPPING_APP_DIR} directory."

	# Download the shipping code
	echo -e "${CYAN}Downloading shipping application code to /tmp/shipping.zip...${RESET}"
	${SUDO:-} curl -s -L -o /tmp/shipping.zip "https://roboshop-builds.s3.amazonaws.com/shipping.zip"
	validateStep $? \
		"Shipping application zip downloaded successfully." \
		"Failed to download shipping application zip."

	# Unzip into ${SHIPPING_APP_DIR}
	echo -e "${CYAN}Unzipping shipping application into ${SHIPPING_APP_DIR}...${RESET}"
	${SUDO:-} unzip -o /tmp/shipping.zip -d "${SHIPPING_APP_DIR}" >/dev/null
	validateStep $? \
		"Shipping application unzipped into ${SHIPPING_APP_DIR} successfully." \
		"Failed to unzip shipping application into ${SHIPPING_APP_DIR}."

	# Ownership
	echo -e "${CYAN}Setting ownership of ${SHIPPING_APP_DIR} to user 'roboshop'...${RESET}"
	${SUDO:-} chown -R roboshop:roboshop "${SHIPPING_APP_DIR}"
	validateStep $? \
		"Ownership of ${SHIPPING_APP_DIR} set to roboshop successfully." \
		"Failed to set ownership of ${SHIPPING_APP_DIR} to roboshop."

	echo -e "${GREEN}Shipping application code setup completed.${RESET}"
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

# ---------- Load Shipping schema ----------
loadShippingSchema() {
	echo -e "${CYAN}Loading Shipping schema into MySQL...${RESET}"

	# Where the schema SQL is expected
	local SCHEMA_FILE="${SHIPPING_APP_DIR}/schema/shipping.sql"

	if [[ ! -f "${SCHEMA_FILE}" ]]; then
		echo -e "${RED}ERROR: Shipping schema file not found: ${SCHEMA_FILE}${RESET}"
		exit 1
	fi

	# MySQL connection details
	local MYSQL_HOST_VAR="${MYSQL_HOST:-mysql.optimusprime.sbs}"
	local MYSQL_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-RoboShop@1}"

	echo -e "${CYAN}Using MySQL host: ${MYSQL_HOST_VAR}${RESET}"
	echo -e "${CYAN}Using MySQL root user to load schema.${RESET}"

	# Load schema
	MYSQL_PWD="${MYSQL_ROOT_PASS}" mysql -h "${MYSQL_HOST_VAR}" -uroot < "${SCHEMA_FILE}"
	local rc=$?

	validateStep "${rc}" \
		"Shipping schema loaded successfully into MySQL on host ${MYSQL_HOST_VAR}." \
		"Failed to load Shipping schema into MySQL on host ${MYSQL_HOST_VAR}."

	echo -e "${GREEN}Shipping schema load completed.${RESET}"
}


# ---------- Main ----------
main() {
	# Ensure log dir exists
	mkdir -p "${LOGS_DIRECTORY}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Load Catalogue Schema Script Execution" "${TIMESTAMP}"

	echo "App Directory: ${APP_DIR}"
	echo "Shipping App Directory: ${SHIPPING_APP_DIR}"
	echo "Log Directory: ${LOGS_DIRECTORY}"
	echo "Log File Location and Name: ${LOG_FILE}"
	echo "Script Directory: ${SCRIPT_DIR}"
	echo "MongoDB Host: ${MONGODB_HOST}:${MONGODB_PORT}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
	basicAppRequirements

	echo -e "\n${CYAN}Calling downloadShippingCode() to download and unzip shipping code into ${SHIPPING_APP_DIR}...${RESET}"
	downloadShippingCode

	echo -e "\n${CYAN}Calling createMongoRepoForClient() to configure MongoDB repo...${RESET}"
	createMongoRepoForClient

	echo -e "\n${CYAN}Calling installMongoClient() to install MongoDB shell client...${RESET}"
	installMongoClient

	echo -e "\n${CYAN}Calling loadShippingSchema() to load schema into MongoDB...${RESET}"
	loadShippingSchema

	echo -e "\n${GREEN}Load Shipping Schema script completed successfully.${RESET}"
}

main "$@"
