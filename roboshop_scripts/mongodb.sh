#!/usr/bin/env bash

set -euo pipefail

# ---------- Config ----------
timestamp=$(date +"%F-%H-%M-%S")
logs_directory="/app/logs"
script_name="$(basename "$0")"                               # e.g. mongodb.sh
script_base="${script_name%.*}"                              # e.g. mongodb
log_file="${logs_directory}/${script_base}-${timestamp}.log" #one log file per execution
# log_file="${logs_directory}/${script_base}-$(date +%F).log" #one log file per day

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
	echo "Creating MongoDB Repo"
	cp roboshop_scripts\mongodb.repo /etc/yum.repos.d/mongo.repo
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
