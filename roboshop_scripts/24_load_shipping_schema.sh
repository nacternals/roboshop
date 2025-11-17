#!/usr/bin/env bash

# 24_load_shipping_schema.sh
#
# Purpose:
#   - Prepare /app and roboshop user (like other roboshop scripts)
#   - Download shipping.zip and unzip it into /app/shipping
#   - Ensure MySQL client is installed on bastion
#   - Load the Shipping schema into the MySQL server
#
# Notes:
#   - Expects shipping schema somewhere under /app/shipping/db (shipping.sql or schema.sql)
#   - MySQL server must be reachable on port 3306
#   - MYSQL_HOST and MYSQL_ROOT_PASSWORD can be overridden via environment variables

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
SHIPPING_APP_DIR="${APP_DIR}/shipping"
LOGS_DIRECTORY="${APP_DIR}/logs"

SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

# Default MySQL connection details (overridable via env)
MYSQL_HOST="${MYSQL_HOST:-mysql.optimusprime.sbs}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-RoboShop@1}"

# ==========================================================
# Helper Functions
# ==========================================================

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
    echo -e "${CYAN}Ensuring basic application requirements (${APP_DIR} dir and roboshop user)...${RESET}"

    # /app dir
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

    # /app/logs
    echo -e "${CYAN}Ensuring logs directory ${LOGS_DIRECTORY} exists...${RESET}"
    ${SUDO:-} mkdir -p "${LOGS_DIRECTORY}"
    validateStep $? \
        "Logs directory ${LOGS_DIRECTORY} is ready." \
        "Failed to create logs directory ${LOGS_DIRECTORY}."

    # roboshop user
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

    # Ownership
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

ensureMySQLClient() {
    echo -e "${CYAN}Checking if 'mysql' client is available...${RESET}"

    if command -v mysql >/dev/null 2>&1; then
        echo -e "${YELLOW}mysql client already installed. Skipping installation....${RESET}"
        return
    fi

    echo -e "${CYAN}Installing MySQL client package...${RESET}"
    if command -v dnf >/dev/null 2>&1; then
        ${SUDO:-} dnf install -y mysql
    else
        ${SUDO:-} yum install -y mysql
    fi

    validateStep $? \
        "MySQL client installed successfully." \
        "Failed to install MySQL client."
}

loadShippingSchema() {
    echo -e "${CYAN}Loading Shipping schema into MySQL...${RESET}"

    local DB_DIR="${SHIPPING_APP_DIR}/db"
    local SCHEMA_FILE=""

    # Prefer shipping.sql; fall back to schema.sql
    if [[ -f "${DB_DIR}/shipping.sql" ]]; then
        SCHEMA_FILE="${DB_DIR}/shipping.sql"
    elif [[ -f "${DB_DIR}/schema.sql" ]]; then
        SCHEMA_FILE="${DB_DIR}/schema.sql"
    else
        echo -e "${RED}ERROR: Shipping schema file not found in ${DB_DIR} (tried shipping.sql and schema.sql).${RESET}"
        exit 1
    fi

    echo -e "${CYAN}Using MySQL host: ${MYSQL_HOST}:${MYSQL_PORT}${RESET}"
    echo -e "${CYAN}Using MySQL root user to load schema from: ${SCHEMA_FILE}${RESET}"

    MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" \
        mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -uroot < "${SCHEMA_FILE}"
    local rc=$?

    validateStep "${rc}" \
        "Shipping schema loaded successfully into MySQL on host ${MYSQL_HOST}." \
        "Failed to load Shipping schema into MySQL on host ${MYSQL_HOST}."

    echo -e "${GREEN}Shipping schema load completed.${RESET}"
}

# ==========================================================
# Main
# ==========================================================
main() {
    mkdir -p "${LOGS_DIRECTORY}"
    exec >>"${LOG_FILE}" 2>&1

    printBoxHeader "Load Shipping Schema Script Execution" "${TIMESTAMP}"

    echo "App Directory: ${APP_DIR}"
    echo "Shipping App Directory: ${SHIPPING_APP_DIR}"
    echo "Log Directory: ${LOGS_DIRECTORY}"
    echo "Log File Location and Name: ${LOG_FILE}"
    echo "Script Directory: ${SCRIPT_DIR}"
    echo "MySQL Host: ${MYSQL_HOST}:${MYSQL_PORT}"

    echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
    isItRootUser

    echo -e "\n${CYAN}Calling basicAppRequirements()....${RESET}"
    basicAppRequirements

    echo -e "\n${CYAN}Calling ensureMySQLClient() to ensure mysql CLI is present...${RESET}"
    ensureMySQLClient

    echo -e "\n${CYAN}Calling downloadShippingCode() to download and unzip shipping code into ${SHIPPING_APP_DIR}...${RESET}"
    downloadShippingCode

    echo -e "\n${CYAN}Calling loadShippingSchema() to load schema into MySQL...${RESET}"
    loadShippingSchema

    echo -e "\n${GREEN}Load Shipping Schema script completed successfully.${RESET}"
}

main "$@"
