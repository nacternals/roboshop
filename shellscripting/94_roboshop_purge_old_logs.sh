#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
LOG_DIR="${LOG_DIR:-/app/logs}"                     # override via env if needed
RETENTION_DAYS="${RETENTION_DAYS:-14}"              # days to keep
PATTERN="${PATTERN:-*.log}"                         # which files to target
DRY_RUN="${DRY_RUN:-false}"                         # true|false — preview only
CLEANUP_LOG="${CLEANUP_LOG:-/app/logs/cleanup.log}" # where to record runs
LOCK_FILE="${LOCK_FILE:-/var/lock/purge_old_logs.lock}"

# ---------- Binaries (use absolute paths in cron) ----------
FIND_BIN="/usr/bin/find"
DATE_BIN="/usr/bin/date"
HOSTNAME_BIN="/usr/bin/hostname"
FLOCK_BIN="/usr/bin/flock"
MKDIR_BIN="/usr/bin/mkdir"
TEE_BIN="/usr/bin/tee"

# ---------- Ensure log dir exists ----------
$MKDIR_BIN -p "$(dirname "$CLEANUP_LOG")"

# ---------- Logging helpers ----------
ts() { "$DATE_BIN" +"%F %T"; }
log_info() { printf "%s [INFO]  %s\n" "$(ts)" "$*"; }
log_warn() { printf "%s [WARN]  %s\n" "$(ts)" "$*"; }
log_error() { printf "%s [ERROR] %s\n" "$(ts)" "$*" >&2; }

# ---------- Run under a lock to avoid overlap ----------
exec {lock_fd}>"$LOCK_FILE"
$FLOCK_BIN -n "$lock_fd" || {
	log_warn "Another cleanup is running. Exiting."
	exit 0
}

# ---------- Validate inputs ----------
if [[ ! -d "$LOG_DIR" ]]; then
	log_error "Log directory not found: $LOG_DIR"
	exit 1
fi

log_info "Host: $($HOSTNAME_BIN) | Dir: $LOG_DIR | Keep: ${RETENTION_DAYS}d | Pattern: ${PATTERN} | Dry-run: ${DRY_RUN}"

# ---------- Build find command ----------
# -type f: files only
# -name "$PATTERN": only matching files
# -mtime +N: strictly older than N days
# -print: always show what we matched (goes to CLEANUP_LOG via tee)
# -delete: only if not dry-run

if [[ "$DRY_RUN" == "true" ]]; then
	$FIND_BIN "$LOG_DIR" -type f -name "$PATTERN" -mtime +"$RETENTION_DAYS" -print |
		$TEE_BIN -a "$CLEANUP_LOG"
	log_info "Dry-run complete. No files were deleted." | $TEE_BIN -a "$CLEANUP_LOG"
else
	$FIND_BIN "$LOG_DIR" -type f -name "$PATTERN" -mtime +"$RETENTION_DAYS" -print -delete |
		$TEE_BIN -a "$CLEANUP_LOG"
	log_info "Deletion complete." | $TEE_BIN -a "$CLEANUP_LOG"
fi
