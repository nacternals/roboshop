#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
DATE=$(date +"%F-%H-%M-%S")
LOG_DIR="/app/logs"
LOG_FILE="$LOG_DIR/$DATE.log"
PACKAGES_FILE="${1:-/app/packages.txt}" # read from file (default path)
declare -a PACKAGES=()                  # will be filled from the file

# ---------- Logging helpers ----------
info() { printf '[INFO]  %s\n' "$@"; }
warn() { printf '[WARN]  %s\n' "$@" >&2; }
error() { printf '[ERROR] %s\n' "$@" >&2; }

# ---------- Root / sudo handling ----------
SUDO=""
need_sudo() {
	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		if command -v sudo >/dev/null 2>&1; then
			SUDO="sudo"
		else
			error "Please run as root or install sudo."
			exit 1
		fi
	fi
}

# ---------- Package manager detection ----------
PKG_MGR=""
detect_pkg_mgr() {
	if command -v dnf >/dev/null 2>&1; then
		PKG_MGR="dnf"
	elif command -v yum >/dev/null 2>&1; then
		PKG_MGR="yum"
	elif command -v apt-get >/dev/null 2>&1; then
		PKG_MGR="apt-get"
	elif command -v zypper >/dev/null 2>&1; then
		PKG_MGR="zypper"
	elif command -v pacman >/dev/null 2>&1; then
		PKG_MGR="pacman"
	elif command -v apk >/dev/null 2>&1; then
		PKG_MGR="apk"
	else
		error "Unsupported system: no known package manager found."
		exit 1
	fi
}

# ---------- Install check (per distro) ----------
is_installed() {
	local pkg="$1"
	case "$PKG_MGR" in
	dnf | yum | zypper) rpm -q "$pkg" >/dev/null 2>&1 ;;
	apt-get) dpkg -s "$pkg" >/dev/null 2>&1 ;;
	pacman) pacman -Qi "$pkg" >/dev/null 2>&1 ;;
	apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
	*) return 2 ;;
	esac
}

# ---------- Install action (per distro) ----------
install_pkg() {
	local pkg="$1"
	info "Installing: $pkg"
	case "$PKG_MGR" in
	dnf | yum) $SUDO "$PKG_MGR" -y install "$pkg" ;;
	apt-get) $SUDO apt-get update -y && $SUDO apt-get install -y "$pkg" ;;
	zypper) $SUDO zypper -n install "$pkg" ;;
	pacman) $SUDO pacman -Sy --noconfirm "$pkg" ;;
	apk) $SUDO apk add --no-cache "$pkg" ;;
	esac
	info "Installed: $pkg"
}

# ---------- Read packages from file ----------
load_packages() {
	if [[ ! -f "$PACKAGES_FILE" ]]; then
		error "Packages file not found: $PACKAGES_FILE"
		exit 1
	fi

	# Read file, ignore blanks and comments, trim whitespace
	while IFS= read -r line; do
		# strip leading/trailing whitespace
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" || "$line" == \#* ]] && continue
		PACKAGES+=("$line")
	done <"$PACKAGES_FILE"

	# De-duplicate while preserving order
	if ((${#PACKAGES[@]})); then
		declare -A seen=()
		local unique=()
		for p in "${PACKAGES[@]}"; do
			if [[ -z "${seen[$p]:-}" ]]; then
				unique+=("$p")
				seen[$p]=1
			fi
		done
		PACKAGES=("${unique[@]}")
	else
		error "No packages found in $PACKAGES_FILE (after filtering)."
		exit 1
	fi
}

# ---------- Setup logging to /app/logs/<DATE>.log ----------
setup_logging() {
	if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
		need_sudo
		$SUDO mkdir -p "$LOG_DIR"
	fi

	# Route all stdout+stderr to the log file
	if [[ -n "$SUDO" ]]; then
		exec > >($SUDO tee -a "$LOG_FILE" >/dev/null) 2>&1
	else
		exec > >(tee -a "$LOG_FILE" >/dev/null) 2>&1
	fi

	info "Logging to $LOG_FILE"
	info "Packages source file: $PACKAGES_FILE"
}

# ---------- Trap for clean error messages ----------
trap 'rc=$?; [[ $rc -ne 0 ]] && error "Script failed with exit code $rc"; exit $rc' EXIT

# ---------- Main ----------
main() {
	need_sudo
	load_packages
	setup_logging
	detect_pkg_mgr

	info "Using package manager: $PKG_MGR"
	info "Packages to process: ${PACKAGES[*]}"

	for pkg in "${PACKAGES[@]}"; do
		if is_installed "$pkg"; then
			info "Already installed: $pkg"
		else
			install_pkg "$pkg"
		fi
	done

	info "All done."
}

main "$@"
