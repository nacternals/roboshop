#!/usr/bin/env bash

set -euo pipefail

# ---------- Config ----------
timestamp=$(date +"%F-%H-%M-%S")
logs_directory="/app/logs"
script_name="$(basename "$0")"   # e.g. mongodb.sh
script_base="${script_name%.*}"  # e.g. mongodb
log_file="${logs_directory}/${script_base}-${timestamp}.log"

# ---------- Root / sudo handling ----------
isItRootUser() {
	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		if command -v sudo >/dev/null 2>&1; then
			SUDO="sudo"
		else
			echo "ERROR: Insufficient privileges. Run as root or install sudo."
			exit 1
		fi
	else
		SUDO=""
	fi
}

main() {
	# Ensure log dir exists
	mkdir -p "${logs_directory}"

	# Send everything (stdout + stderr) to log file from here on
	# exec >>"${log_file}" 2>&1

	echo "MongoDB script execution has been started @ ${timestamp}"
	echo "Log Directory: ${logs_directory}"
	echo "MongoDB Log File Name: ${log_file}"

	isItRootUser >>"${log_file}" 2>&1 

	# your MongoDB setup steps here...
}

main "$@"
