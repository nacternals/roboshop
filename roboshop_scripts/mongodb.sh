#!/usr/bin/env bash

set -euo pipefail

# ---------- Config ----------
timestamp=$(date +"%F-%H-%M-%S")
logs_directory="/app/logs"
script_name="$(basename "$0")"                               # e.g. mongodb.sh
script_base="${script_name%.*}"                              # e.g. mongodb
log_file="${logs_directory}/${script_base}-${timestamp}.log" #one log file per execution
# log_file="${logs_directory}/${script_base}-$(date +%F).log" #one log file per day
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory where script lives (if you haven't added this already)

# ---------- Root / sudo handling ----------
isItRootUser() {
		echo "Checking Root user or Not ?????????"

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		if command -v sudo >>$log_file 2>&1; then
			SUDO="sudo"
		else
			echo "ERROR: Insufficient privileges. Run as root or install sudo."
			exit 1
		fi
	else
		SUDO=""
		echo "Executing this script as a ROOT user....."
	fi
}

createMongoRepo() {
    echo "Checking MongoDB repo..."

    if [[ -f /etc/yum.repos.d/mongo.repo ]]; then
        echo "MongoDB repo already exists, skipping."
        return
    fi

    echo "MongoDB repo not found. Creating MongoDB repo..."
    echo "mongodb.repo script location: ${SCRIPT_DIR}/mongodb.repo"

    # Try copying the repo file
    if ${SUDO:-} cp "${SCRIPT_DIR}/mongodb.repo" /etc/yum.repos.d/mongo.repo; then
        echo "MongoDB repo created at /etc/yum.repos.d/mongo.repo"
    else
        echo "ERROR: Failed to create MongoDB repo. Copy operation failed."
        exit 1
    fi
}


main() {
	# Ensure log dir exists
	mkdir -p "${logs_directory}"

	# Send everything (stdout + stderr) to log file from here on
	exec >>"${log_file}" 2>&1

	echo "MongoDB script execution has been started @ ${timestamp}"
	echo "Log Directory: ${logs_directory}"
	echo "MongoDB Log File Name: ${log_file}"

	echo "Calling isItRootUser function to validate the user....."
	isItRootUser

	echo "Calling createMongoRepo functoin....."
	createMongoRepo

	# your MongoDB setup steps here...
}

main "$@"
