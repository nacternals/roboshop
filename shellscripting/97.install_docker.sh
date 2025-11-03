#!/usr/bin/env bash

#Cross-distro Docker Engine installer with repo setup, service enablement, and user group config.

#Fail fast on errors, unset vars, and pipeline failures.
set -euo pipefail

#Pretty-print info messages to the console.
log() { printf "\033[1;32m==>\033[0m %s\n" "$*"; }

#Pretty-print warnings to the console.
warn() { printf "\033[1;33m!! \033[0m %s\n" "$*"; }

#Pretty-print errors to stderr.
err() { printf "\033[1;31mEE \033[0m %s\n" "$*" >&2; }

#Run a command as root (use sudo if not already root).
as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

#Detect OS metadata from /etc/os-release (ID/ID_LIKE/VERSION_ID).
if [ -r /etc/os-release ]; then
	. /etc/os-release
else
	err "No /etc/os-release"
	exit 1
fi

#Normalize OS identifiers to lowercase for robust matching.
ID_LOWER="$(printf %s "$ID" | tr 'A-Z' 'a-z')"
ID_LIKE_LOWER="$(printf %s "${ID_LIKE:-$ID}" | tr 'A-Z' 'a-z')"
VERSION_ID_MAJOR="${VERSION_ID%%.*}"

#Package installer wrapper to abstract apt/yum/dnf differences.
install_pkg() {
	case "$1" in
	dnf) as_root dnf install -y "${@:2}" ;;
	yum) as_root yum install -y "${@:2}" ;;
	apt)
		as_root apt-get update -y
		as_root apt-get install -y "${@:2}"
		;;
	*)
		err "Unknown pkg mgr: $1"
		exit 2
		;;
	esac
}

#Post-install common steps (enable/start service, add user to group, print version).
post_install() {
	#Ensure docker daemon starts now and on boot.
	log "Enable + start docker"
	as_root systemctl enable docker
	as_root systemctl restart docker || as_root systemctl start docker || true

	#Add current user to 'docker' group for rootless CLI usage.
	if getent group docker >/dev/null 2>&1; then
		if ! id -nG "$USER" | grep -qw docker; then
			log "Adding $USER to docker group"
			as_root usermod -aG docker "$USER" || warn "Could not add user to docker group"
			warn "Re-login or run: newgrp docker"
		fi
	else
		#Create 'docker' group if missing and add the user.
		as_root groupadd -f docker
		as_root usermod -aG docker "$USER" || true
		warn "Re-login required to apply group membership."
	fi

	#Print Docker CLI version as a smoke test.
	log "Docker version:"
	docker --version || as_root docker --version || true
	log "Done."
}

#Choose installer path based on detected distro ID (fall back to ID_LIKE).
case "$ID_LOWER" in
amzn | amazon)
	#Amazon Linux path (AL2 via amazon-linux-extras; AL2023 via dnf).
	log "Amazon Linux detected: $PRETTY_NAME"
	if [ "$VERSION_ID_MAJOR" = "2" ]; then
		#Enable Docker channel and install on Amazon Linux 2.
		install_pkg yum amazon-linux-extras || true
		as_root amazon-linux-extras enable docker || true
		as_root yum clean metadata || true
		install_pkg yum docker
	else
		#Install docker package directly on Amazon Linux 2023.
		install_pkg dnf docker
	fi
	post_install
	;;

rhel | centos | rocky | almalinux)
	#RHEL-like path (add Docker CE repo and install Engine/CLI/Compose).
	log "RHEL-like detected: $PRETTY_NAME"
	PKM=dnf
	command -v dnf >/dev/null 2>&1 || PKM=yum

	#Remove legacy/conflicting Docker packages to avoid dependency issues.
	as_root $PKM remove -y docker{,-client,-client-latest,-common,-latest,-latest-logrotate,-logrotate,-engine} || true

	#Install repo management and TLS prerequisites.
	install_pkg $PKM dnf-plugins-core curl ca-certificates

	#Add Docker CE official repository for RHEL/CentOS family.
	as_root $PKM config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

	#Install Docker Engine, CLI, containerd, Buildx, and Compose plugin.
	install_pkg $PKM docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	post_install
	;;

fedora)
	#   Fedora path (add Docker CE repo and install Engine/CLI/Compose).
	log "Fedora detected: $PRETTY_NAME"
	install_pkg dnf dnf-plugins-core curl ca-certificates
	as_root dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
	install_pkg dnf docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	post_install
	;;

ubuntu | debian)
	#   Debian/Ubuntu path (add Docker APT repo via keyring and install).
	log "Debian/Ubuntu detected: $PRETTY_NAME"

	#   Install APT dependencies for HTTPS repos and signing.
	install_pkg apt ca-certificates curl gnupg lsb-release

	#   Create keyring directory for Docker’s GPG key.
	as_root install -m 0755 -d /etc/apt/keyrings

	#   Fetch and install Docker’s official GPG key (once).
	if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
		curl -fsSL "https://download.docker.com/linux/$ID_LOWER/gpg" | as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
		as_root chmod a+r /etc/apt/keyrings/docker.gpg
	fi

	#   Compute architecture and codename for the APT repo entry.
	arch="$(dpkg --print-architecture)"
	codename="${VERSION_CODENAME:-$(lsb_release -cs)}"

	#   Add Docker stable repository pointing to official servers.
	echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID_LOWER $codename stable" |
		as_root tee /etc/apt/sources.list.d/docker.list >/dev/null

	#   Update APT metadata and install Docker Engine stack.
	as_root apt-get update -y
	install_pkg apt docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	post_install
	;;

*)
	#   Unknown ID -> try ID_LIKE families (RHEL-like or Debian-like) as a fallback.
	if echo "$ID_LIKE_LOWER" | grep -Eq 'rhel|centos|fedora'; then
		#   Treat as RHEL-like if ID_LIKE indicates Red Hat family.
		ID_LOWER="centos"
		PRETTY_NAME="${PRETTY_NAME:-RHEL-like}"
		log "Treating as RHEL-like: $PRETTY_NAME"
		PKM=dnf
		command -v dnf >/dev/null 2>&1 || PKM=yum
		as_root $PKM remove -y docker{,-client,-client-latest,-common,-latest,-latest-logrotate,-logrotate,-engine} || true
		install_pkg $PKM dnf-plugins-core curl ca-certificates
		as_root $PKM config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
		install_pkg $PKM docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
		post_install
	elif echo "$ID_LIKE_LOWER" | grep -Eq 'debian|ubuntu'; then
		#   Treat as Debian-like if ID_LIKE indicates Debian/Ubuntu family.
		ID_LOWER="debian"
		PRETTY_NAME="${PRETTY_NAME:-Debian-like}"
		log "Treating as Debian-like: $PRETTY_NAME"
		install_pkg apt ca-certificates curl gnupg lsb-release
		as_root install -m 0755 -d /etc/apt/keyrings
		if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
			curl -fsSL "https://download.docker.com/linux/$ID_LOWER/gpg" | as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
			as_root chmod a+r /etc/apt/keyrings/docker.gpg
		fi
		arch="$(dpkg --print-architecture)"
		codename="${VERSION_CODENAME:-$(lsb_release -cs)}"
		echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID_LOWER $codename stable" |
			as_root tee /etc/apt/sources.list.d/docker.list >/dev/null
		as_root apt-get update -y
		install_pkg apt docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
		post_install
	else
		#   Abort on unsupported/unknown distro with a clear message.
		err "Unsupported distro: $PRETTY_NAME ($ID)"
		exit 2
	fi
	;;
esac
