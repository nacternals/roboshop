#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
DATE=$(date +"%F-%H-%M-%S")
LOG_DIR="/app/logs"
LOG_FILE="$LOG_DIR/$DATE.log"
PACKAGES=(git vim wget net-tools tree httpd)

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
	*) return 2 ;; # unknown package manager
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

# ---------- Setup logging to /app/logs/<DATE>.log ----------
setup_logging() {
	# Ensure the log directory exists (use sudo if needed)
	if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
		need_sudo
		$SUDO mkdir -p "$LOG_DIR"
	fi

	# Route all stdout+stderr to the log file (works even if /app owns root)
	# - If not root, write via sudo tee to avoid permission issues.
	if [[ -n "$SUDO" ]]; then
		exec > >($SUDO tee -a "$LOG_FILE" >/dev/null) 2>&1
	else
		exec > >(tee -a "$LOG_FILE" >/dev/null) 2>&1
	fi

	info "Logging to $LOG_FILE"
}

# ---------- Trap for clean error messages ----------
trap 'rc=$?; [[ $rc -ne 0 ]] && error "Script failed with exit code $rc"; exit $rc' EXIT

# ---------- Main ----------
main() {
	need_sudo
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
