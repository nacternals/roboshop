#!/usr/bin/env bash
# CPU / Memory alert -> send email via Gmail (Python smtplib)
# Works on Amazon Linux with only python3 + coreutils.
# Author: Srinivas Ganta

set -euo pipefail

# ---------- Config (hard-coded) ----------
CPU_THRESHOLD="10" # Trigger when total CPU usage % >= this
MEM_THRESHOLD="10" # Trigger when memory usage % >= this
SAMPLE_SECS="2"    # CPU sample window (seconds)

TO_EMAIL="sriniva.jtm@gmail.com"      # Recipient
FROM_NAME="Roboshop Resource Monitor" # Friendly sender name

# Gmail (use an App Password; remove spaces if Google shows them with spaces)
GMAIL_USER="srinivas.jtm@gmail.com"
GMAIL_APP_PASS="lapjocuionjmdqgi" # <-- 16-char Gmail App Password

# ---------- Sanity checks ----------
for bin in awk grep sed head ps free; do
	command -v "$bin" >/dev/null 2>&1 || {
		echo "ERROR: $bin is required"
		exit 1
	}
done
command -v python3 >/dev/null 2>&1 || {
	echo "ERROR: python3 is required (sudo dnf install -y python3)"
	exit 1
}

# ---------- CPU measurement (overall %) ----------
# Method: sample /proc/stat twice and compute usage = 100 * (1 - idle_delta/total_delta)
read cpu user nice system idle iowait irq softirq steal guest guest_n </proc/stat
total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle1=$idle
sleep "$SAMPLE_SECS"
read cpu user nice system idle iowait irq softirq steal guest guest_n </proc/stat
total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle2=$idle

total_delta=$((total2 - total1))
idle_delta=$((idle2 - idle1))
CPU_USED_PCT=0
if ((total_delta > 0)); then
	CPU_USED_PCT=$(((100 * (total_delta - idle_delta)) / total_delta))
fi

# ---------- Memory measurement (overall %) ----------
# Use MemAvailable for realistic "free" memory
mem_total_kb=$(grep -i '^MemTotal:' /proc/meminfo | awk '{print $2}')
mem_avail_kb=$(grep -i '^MemAvailable:' /proc/meminfo | awk '{print $2}')
MEM_USED_PCT=0
if [[ -n "${mem_total_kb}" && -n "${mem_avail_kb}" && "${mem_total_kb}" -gt 0 ]]; then
	MEM_USED_PCT=$(((100 * (mem_total_kb - mem_avail_kb)) / mem_total_kb))
fi

# ---------- Decide ----------
ALERT_REASONS=()
((CPU_USED_PCT >= CPU_THRESHOLD)) && ALERT_REASONS+=("CPU ${CPU_USED_PCT}% >= ${CPU_THRESHOLD}%")
((MEM_USED_PCT >= MEM_THRESHOLD)) && ALERT_REASONS+=("MEM ${MEM_USED_PCT}% >= ${MEM_THRESHOLD}%")

# Exit quietly if nothing breached
if ((${#ALERT_REASONS[@]} == 0)); then
	exit 0
fi

# ---------- Build diagnostics ----------
HOST="$(hostname -f 2>/dev/null || hostname)"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# Top processes by CPU and MEM
TOP_CPU="$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11 | sed '1s/^/PID   COMMAND         %CPU  %MEM\n/')" || TOP_CPU="(unavailable)"
TOP_MEM="$(ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 11 | sed '1s/^/PID   COMMAND         %MEM  %CPU\n/')" || TOP_MEM="(unavailable)"

# Quick summary from `free -h`
FREE_H="$(free -h)"

SUBJECT="[ALERT] ${HOST}: $(
	IFS='; '
	echo "${ALERT_REASONS[*]}"
)"
read -r -d '' BODY <<EOF || true
Resource alert on ${HOST}

Time: ${NOW}

Thresholds:
- CPU threshold: ${CPU_THRESHOLD}%
- Memory threshold: ${MEM_THRESHOLD}%

Current:
- CPU used: ${CPU_USED_PCT}%
- Memory used: ${MEM_USED_PCT}%

free -h:
${FREE_H}

Top processes by CPU:
${TOP_CPU}

Top processes by MEM:
${TOP_MEM}

Suggested next steps:
- Investigate top offenders (apps/services).
- Check cron jobs, runaway processes, memory leaks.
- Consider scaling resources or tuning services.
EOF

# ---------- Send email via Python (smtplib + STARTTLS) ----------
export GMAIL_USER GMAIL_APP_PASS TO_EMAIL FROM_NAME SUBJECT BODY

python3 - <<'PYCODE'
import os, sys, ssl, smtplib
from email.mime.text import MIMEText
from email.utils import formataddr

gmail_user = os.environ["GMAIL_USER"]
gmail_pass = os.environ["GMAIL_APP_PASS"]
to_email   = os.environ["TO_EMAIL"]
from_name  = os.environ.get("FROM_NAME", "Roboshop Resource Monitor")
subject    = os.environ.get("SUBJECT", "Resource alert")
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
