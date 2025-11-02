#!/usr/bin/env bash
set -euo pipefail

# ---------- Logging ----------
info()  { printf '[INFO]  %s\n' "$@"; }
warn()  { printf '[WARN]  %s\n' "$@" >&2; }
error() { printf '[ERROR] %s\n' "$@" >&2; }

# ---------- 1) Root / sudo handling ----------
isItRootUser() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      error "Insufficient privileges. Run as root or install sudo."
      exit 1
    fi
  else
    SUDO=""
  fi
}

# ---------- pkg manager detection (CentOS/RHEL families) ----------
detectPkgMgr() {
  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
  else
    error "Neither dnf nor yum found on this system."
    exit 1
  fi
}

# ---------- 2) Is package already installed? ----------
isItInstalled() {
  local pkg="$1"
  rpm -q "$pkg" >/dev/null 2>&1
}

# ---------- 3) Install required package ----------
installRequiredPackage() {
  local pkg="$1"
  info "Installing package: $pkg (via $PKG_MGR)"
  if $SUDO "$PKG_MGR" -y install "$pkg" >/dev/null; then
    info "$pkg has been installed successfully."
  else
    error "Installation of $pkg failed."
    exit 1
  fi
}

# ---------- Main ----------
main() {
  echo -e "\nThis script demonstrates how to install packages with the help of functions:"

  # Read package name from user (no default)
  local package=""
  while [[ -z "${package:-}" ]]; do
    read -rp "Enter the package to install: " package
    [[ -z "$package" ]] && warn "Package name cannot be empty."
  done

  isItRootUser
  detectPkgMgr

  info "Checking whether '$package' is already installed"
  if isItInstalled "$package"; then
    info "'$package' is already installed."
    # Show version via rpm (reliable for RPM-based systems)
    if rpm -q "$package" >/dev/null 2>&1; then
      printf '[INFO]  Version: %s\n' "$(rpm -q "$package")"
    fi
    exit 0
  else
    info "'$package' is not installed; proceeding with installation."
    installRequiredPackage "$package"
  fi
}

main "$@"
