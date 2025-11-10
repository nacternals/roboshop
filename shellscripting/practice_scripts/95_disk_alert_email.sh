#!/usr/bin/env bash
set -euo pipefail

# ---------- Config (hard-coded) ----------
MOUNT_POINT="/"                   # filesystem to monitor
THRESHOLD="10"                    # trigger when used% >= THRESHOLD
TO_EMAIL="srinivas.jtm@gmail.com" # recipient
FROM_NAME="Roboshop"              # friendly sender name

# Gmail (use an App Password; remove spaces if Google shows them with spaces)
GMAIL_USER="srinivas.jtm@gmail.com"
GMAIL_APP_PASS="testing" # <-- 16-char Gmail App Password

# ---------- Sanity checks ----------
if ! command -v df >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
	echo "ERROR: Requires coreutils (df) and awk." >&2
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "ERROR: python3 is required (sudo dnf install -y python3)." >&2
	exit 1
fi

if [[ -z "$GMAIL_USER" || -z "$GMAIL_APP_PASS" ]]; then
	echo "ERROR: Gmail user/password not set." >&2
	exit 1
fi

# ---------- Measure usage ----------
# POSIX df format, grab used% (strip % sign)
USAGE_PCT="$(df -P "$MOUNT_POINT" | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
if [[ -z "${USAGE_PCT:-}" || ! "$USAGE_PCT" =~ ^[0-9]+$ ]]; then
	echo "ERROR: Could not determine disk usage for $MOUNT_POINT" >&2
	exit 1
fi

# Exit quietly if under threshold
if ((USAGE_PCT < THRESHOLD)); then
	exit 0
fi

# ---------- Build email ----------
HOST="$(hostname -f 2>/dev/null || hostname)"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

DF_TABLE="$(df -hP "$MOUNT_POINT")"

# Top 10 heavy directories under the mount point (non-cross-filesystem)
# If the mount is '/', this may be a little heavy the first time—still safe.
TOP_DIRS="$(du -xhd1 "$MOUNT_POINT" 2>/dev/null | sort -hr | head -n 10 || true)"

SUBJECT="[ALERT] ${HOST}: ${MOUNT_POINT} at ${USAGE_PCT}% used (threshold ${THRESHOLD}%)"
read -r -d '' BODY <<EOF || true
Disk space alert on ${HOST}

Time: ${NOW}
Mount: ${MOUNT_POINT}
Usage: ${USAGE_PCT}% (threshold ${THRESHOLD}%)

Filesystem usage:
${DF_TABLE}

Top 10 space consumers under ${MOUNT_POINT}:
${TOP_DIRS}

Suggested next steps:
- Purge old logs/caches/temp files
- Archive/compress cold data
- Resize or add storage
EOF

# ---------- Send email via Python (smtplib + STARTTLS) ----------
# Export for the heredoc Python to read
export GMAIL_USER GMAIL_APP_PASS TO_EMAIL FROM_NAME SUBJECT BODY

python3 - <<'PYCODE'
import os, sys, ssl, smtplib
from email.mime.text import MIMEText
from email.utils import formataddr

gmail_user = os.environ["GMAIL_USER"]
gmail_pass = os.environ["GMAIL_APP_PASS"]
to_email   = os.environ["TO_EMAIL"]
from_name  = os.environ.get("FROM_NAME", "Disk Monitor")
subject    = os.environ.get("SUBJECT", "Disk alert")
body       = os.environ.get("BODY", "")

msg = MIMEText(body, _charset="utf-8")
msg["Subject"] = subject
msg["From"]    = formataddr((from_name, gmail_user))
msg["To"]      = to_email

try:
    with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as s:
        s.ehlo()
        s.starttls(context=ssl.create_default_context())
        s.ehlo()
        s.login(gmail_user, gmail_pass)
        s.sendmail(gmail_user, [to_email], msg.as_string())
except Exception as e:
    sys.stderr.write(f"ERROR: Failed to send email via Gmail SMTP: {e}\n")
    sys.exit(1)
PYCODE

# If we got here, mail sent successfully.
exit 0
