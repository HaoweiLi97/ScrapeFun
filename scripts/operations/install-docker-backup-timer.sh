#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${HOME}/scrapefun"
OUTPUT_DIR="${HOME}/scrapefun-backups"
SCHEDULE="daily"
AGE_RECIPIENT=""
RCLONE_REMOTE=""
NOTIFY_WEBHOOK=""

usage() {
  cat <<'EOF'
Usage: sudo install-docker-backup-timer.sh [options]

Options:
  --deploy-dir DIR       Compose deployment directory
  --output-dir DIR       Local backup destination
  --schedule CALENDAR    systemd OnCalendar value (default: daily)
  --age-recipient KEY    Encrypt scheduled backups with age
  --rclone-remote PATH   Copy and verify scheduled backups off-host
  --notify-webhook URL   POST backup success/failure notifications
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --deploy-dir) DEPLOY_DIR="$2"; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift ;;
    --schedule) SCHEDULE="$2"; shift ;;
    --age-recipient) AGE_RECIPIENT="$2"; shift ;;
    --rclone-remote) RCLONE_REMOTE="$2"; shift ;;
    --notify-webhook) NOTIFY_WEBHOOK="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Error: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

[[ "$(id -u)" -eq 0 ]] || { printf 'Error: run this installer with sudo.\n' >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { printf 'Error: systemd is required.\n' >&2; exit 1; }
[[ -x "${SCRIPT_DIR}/backup-docker.sh" ]] || { printf 'Error: backup script is missing.\n' >&2; exit 1; }

service_file="/etc/systemd/system/scrapefun-backup.service"
timer_file="/etc/systemd/system/scrapefun-backup.timer"
environment_file="/etc/scrapefun-backup.env"
arguments=(--deploy-dir "$DEPLOY_DIR" --output-dir "$OUTPUT_DIR")
[[ -z "$AGE_RECIPIENT" ]] || arguments+=(--age-recipient "$AGE_RECIPIENT")
[[ -z "$RCLONE_REMOTE" ]] || arguments+=(--rclone-remote "$RCLONE_REMOTE")
printf -v escaped_command '%q ' "${SCRIPT_DIR}/backup-docker.sh" "${arguments[@]}"

umask 077
printf 'SCRAPEFUN_BACKUP_NOTIFY_WEBHOOK=%q\n' "$NOTIFY_WEBHOOK" > "$environment_file"
chmod 600 "$environment_file"

cat > "$service_file" <<EOF
[Unit]
Description=ScrapeFun verified Docker backup
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
EnvironmentFile=-${environment_file}
ExecStart=${escaped_command}
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat > "$timer_file" <<EOF
[Unit]
Description=Schedule ScrapeFun verified Docker backups

[Timer]
OnCalendar=${SCHEDULE}
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

chmod 644 "$service_file" "$timer_file"
systemctl daemon-reload
systemctl enable --now scrapefun-backup.timer
printf 'Installed timer. Next run:\n'
systemctl list-timers scrapefun-backup.timer --no-pager
