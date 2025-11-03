#!/usr/bin/env bash

# Send a Gmail alert if disk usage on a mount exceeds a threshold.
# Requires: curl, awk, df, du, hostname, date
# Auth: Use a Gmail "App Password" (2-step verification required).

set -euo pipefail

# ---- Config (env vars with safe defaults) ----
MOUNT_POINT="${MOUNT_POINT:-/}"                      # Which filesystem to watch (default /)
THRESHOLD="${THRESHOLD:-10}"                         # Percentage used that triggers alert
TO_EMAIL="${TO_EMAIL:-srinivas.jtm@gmail.com}"       # Recipient
FROM_NAME="${FROM_NAME:-Disk Monitor}"               # Friendly name for From:
GMAIL_USER="${GMAIL_USER:-srinivas.jtm@gmail.com}"   # Your Gmail address
GMAIL_APP_PASS="${GMAIL_APP_PASS:-lapjocuionjmdqgi}" # 16-char App Password

# ---- Sanity checks ----
if ! command -v curl >/dev/null 2>&1; then
	echo "ERROR: curl is required." >&2
	exit 1
fi

if [[ -z "$GMAIL_APP_PASS" ]]; then
	echo "ERROR: GMAIL_APP_PASS is empty. Create a Gmail App Password and export it." >&2
	exit 1
fi

# ---- Measure usage ----
# Use POSIX df format (-P) and parse the used% column (strip the % sign)
USAGE_PCT="$(df -P "$MOUNT_POINT" | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"

# ---- Decide ----
if [[ -z "$USAGE_PCT" ]]; then
	echo "ERROR: Could not determine disk usage for $MOUNT_POINT" >&2
	exit 1
fi

if ((USAGE_PCT < THRESHOLD)); then
	# Optional: exit quietly when under threshold
	exit 0
fi

# ---- Build email ----
HOST="$(hostname -f 2>/dev/null || hostname)"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# Include a quick df table and top space hogs (largest 10 dirs under the mount root)
DF_TABLE="$(df -hP "$MOUNT_POINT")"
TOP_DIRS="$(du -xhd1 "$MOUNT_POINT" 2>/dev/null | sort -hr | head -n 10)"

SUBJECT="[ALERT] $HOST: $MOUNT_POINT at ${USAGE_PCT}% used (threshold ${THRESHOLD}%)"
BODY=$(
	cat <<EOF
Disk space alert on $HOST

Time: $NOW
Mount: $MOUNT_POINT
Usage: ${USAGE_PCT}% (threshold ${THRESHOLD}%)

Filesystem usage:
$DF_TABLE

Top 10 space consumers under $MOUNT_POINT:
$TOP_DIRS

Suggested next steps:
- Clean old logs, caches, temp files.
- Archive/compress large cold data.
- Expand the volume or add storage.
EOF
)

# ---- Send via Gmail SMTP with curl ----
# Option A: Implicit TLS 465
SMTP_URL="smtp://smtp.gmail.com:587"
# Option B (uncomment to use STARTTLS 587 instead):
# SMTP_URL="smtp://smtp.gmail.com:587"
# and add: --ssl-reqd

# SMTP requires CRLF line endings. We'll build the MIME message accordingly.
# If you want HTML, set Content-Type: text/html; charset=UTF-8 and adjust BODY.
# MAIL_TMP="$(mktemp)"
# {
# 	printf 'From: %s <%s>\r\n' "$FROM_NAME" "$GMAIL_USER"
# 	printf 'To: <%s>\r\n' "$TO_EMAIL"
# 	printf 'Subject: %s\r\n' "$SUBJECT"
# 	printf 'Content-Type: text/plain; charset=UTF-8\r\n'
# 	printf '\r\n'
# 	# Convert LF to CRLF on the fly:
# 	# shellcheck disable=SC2001
# 	printf '%s' "$BODY" | sed 's/$/\r/'
# } >"$MAIL_TMP"

# set +e
# curl --silent --show-error --fail \
# 	--url "$SMTP_URL" \
# 	--mail-from "$GMAIL_USER" \
# 	--mail-rcpt "$TO_EMAIL" \
# 	--user "$GMAIL_USER:$GMAIL_APP_PASS" \
# 	--upload-file "$MAIL_TMP"
# CURL_RC=$?
# set -e
# rm -f "$MAIL_TMP"

# if ((CURL_RC != 0)); then
# 	echo "ERROR: Failed to send alert email via Gmail (curl exit $CURL_RC)" >&2
# 	exit $CURL_RC
# fi

MAIL_TMP="$(mktemp)"
{
	printf 'From: %s <%s>\r\n' "$FROM_NAME" "$GMAIL_USER"
	printf 'To: <%s>\r\n' "$TO_EMAIL"
	printf 'Subject: %s\r\n' "$SUBJECT"
	printf 'Content-Type: text/plain; charset=UTF-8\r\n'
	printf '\r\n'
	printf '%s' "$BODY" | sed 's/$/\r/'
} >"$MAIL_TMP"

set +e
curl --silent --show-error --fail \
	--url "$SMTP_URL" \
	--mail-from "$GMAIL_USER" \
	--mail-rcpt "$TO_EMAIL" \
	--user "$GMAIL_USER:$GMAIL_APP_PASS" \
	--ssl-reqd \
	--upload-file "$MAIL_TMP"
CURL_RC=$?
set -e
rm -f "$MAIL_TMP"

if ((CURL_RC != 0)); then
	echo "ERROR: Failed to send alert email via Gmail (curl exit $CURL_RC)" >&2
	exit $CURL_RC
fi
