\
    #!/usr/bin/env bash
    set -euo pipefail

    RED="\e[31m"
    GREEN="\e[32m"
    YELLOW="\e[33m"
    CYAN="\e[36m"
    RESET="\e[0m"

    TIMESTAMP="$(date +"%F-%H-%M-%S")"
    APP_DIR="/app"
    LOGS_DIRECTORY="${APP_DIR}/logs"
    SCRIPT_NAME="$(basename "$0")"
    SCRIPT_BASE="${SCRIPT_NAME%.*}"
    LOG_FILE="${LOGS_DIRECTORY}/${SCRIPT_BASE}-$(date +%F).log"

    MONGO_HOST="mongodb.optimusprime.sbs"
    SCHEMA_DIR="${APP_DIR}/user"
    SCHEMA_FILE="${SCHEMA_DIR}/schema/user.js"

    printBoxHeader() {
        local TITLE="$1"
        local TIME="$2"
        echo -e "${CYAN}===========================================${RESET}"
        printf "${CYAN}%20s${RESET}\n" "$TITLE"
        printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
        echo -e "${CYAN}===========================================${RESET}"
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

    main() {
        mkdir -p "${LOGS_DIRECTORY}"
        exec >>"${LOG_FILE}" 2>&1

        printBoxHeader "Load USER schema from bastion" "${TIMESTAMP}"

        echo -e "${CYAN}Ensuring schema directory ${SCHEMA_DIR} exists...${RESET}"
        mkdir -p "${SCHEMA_DIR}"

        echo -e "${CYAN}Downloading user.zip to bastion...${RESET}"
        curl -s -L -o /tmp/user.zip "https://roboshop-builds.s3.amazonaws.com/user.zip"
        validateStep $? "user.zip downloaded successfully." "Failed to download user.zip"

        echo -e "${CYAN}Unzipping user.zip into ${SCHEMA_DIR}...${RESET}"
        unzip -o /tmp/user.zip -d "${SCHEMA_DIR}" >/dev/null
        validateStep $? "user.zip extracted successfully." "Failed to extract user.zip"

        if [[ ! -f "${SCHEMA_FILE}" ]]; then
            echo -e "${RED}Schema file not found at ${SCHEMA_FILE}${RESET}"
            exit 1
        fi

        echo -e "${CYAN}Loading USER schema into MongoDB at ${MONGO_HOST}...${RESET}"
        mongo --host "${MONGO_HOST}" < "${SCHEMA_FILE}"
        validateStep $? "USER schema loaded successfully." "Failed to load USER schema."

        echo -e "${GREEN}USER schema load script completed successfully.${RESET}"
    }

    main "$@"
