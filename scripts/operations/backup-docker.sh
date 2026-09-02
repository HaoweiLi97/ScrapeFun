#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=docker-operations-common.sh
source "${SCRIPT_DIR}/docker-operations-common.sh"

OP_DEPLOY_DIR="$(pwd)"
OP_DATA_DIR=""
OUTPUT_DIR=""
INCLUDE_CACHES=0
AGE_RECIPIENT=""
RCLONE_REMOTE=""
NOTIFY_WEBHOOK="${SCRAPEFUN_BACKUP_NOTIFY_WEBHOOK:-}"
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=6

usage() {
  cat <<'EOF'
Usage: backup-docker.sh [options]

Options:
  --deploy-dir DIR       Compose deployment directory (default: current directory)
  --data-dir DIR         Override SCRAPEFUN_DATA_DIR
  --output-dir DIR       Backup destination (default: DEPLOY_DIR/backups)
  --include-caches       Include reproducible cache directories
  --age-recipient KEY    Encrypt the final bundle with an age recipient
  --rclone-remote PATH   Copy the completed bundle and checksum to remote storage
  --notify-webhook URL   POST a small JSON result on success or failure
  --daily N              Keep N newest daily recovery points (default: 7)
  --weekly N             Keep N additional weekly recovery points (default: 4)
  --monthly N            Keep N additional monthly recovery points (default: 6)
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --deploy-dir) OP_DEPLOY_DIR="$2"; shift ;;
    --data-dir) OP_DATA_DIR="$2"; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift ;;
    --include-caches) INCLUDE_CACHES=1 ;;
    --age-recipient) AGE_RECIPIENT="$2"; shift ;;
    --rclone-remote) RCLONE_REMOTE="$2"; shift ;;
    --notify-webhook) NOTIFY_WEBHOOK="$2"; shift ;;
    --daily) RETENTION_DAILY="$2"; shift ;;
    --weekly) RETENTION_WEEKLY="$2"; shift ;;
    --monthly) RETENTION_MONTHLY="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) operation_fail "unknown argument: $1" ;;
  esac
  shift
done

require_operation_command docker
require_operation_command tar
resolve_operation_layout

[[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="${OP_DEPLOY_DIR}/backups"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(absolute_existing_dir "$OUTPUT_DIR")"
if path_is_within "$OUTPUT_DIR" "$OP_DATA_DIR"; then
  operation_fail "backup destination must not be inside the data directory"
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
status_file="${OP_DEPLOY_DIR}/.backup-status.json"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/scrapefun-host-backup.XXXXXX")"
app_container="$(operation_compose ps -q app 2>/dev/null || true)"
app_was_running="false"
backup_finished=0

notify_result() {
  local status="$1"
  local message="$2"
  [[ -n "$NOTIFY_WEBHOOK" ]] || return 0
  curl -fsS --max-time 15 \
    -H 'Content-Type: application/json' \
    -d "{\"event\":\"scrapefun-docker-backup\",\"status\":\"$(json_escape "$status")\",\"message\":\"$(json_escape "$message")\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    "$NOTIFY_WEBHOOK" >/dev/null || printf 'Warning: backup notification failed.\n' >&2
}

if [[ -n "$app_container" ]]; then
  app_was_running="$(docker inspect --format '{{.State.Running}}' "$app_container" 2>/dev/null || printf 'false')"
fi

cleanup() {
  rm -rf "$stage_dir"
  if [[ "$app_was_running" == "true" ]]; then
    operation_compose start app >/dev/null 2>&1 || true
  fi
  if [[ "$backup_finished" -ne 1 ]]; then
    write_operation_status "$status_file" failed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "Host backup did not complete" "" || true
    notify_result failed "Host backup did not complete" || true
  fi
}
trap cleanup EXIT HUP INT TERM

if [[ "$app_was_running" == "true" ]]; then
  printf 'Stopping app for a consistent host backup...\n'
  operation_compose stop --timeout 60 app
fi

unsupported_node="$(find "$OP_DATA_DIR" ! -type d ! -type f -print -quit)"
[[ -z "$unsupported_node" ]] \
  || operation_fail "data directory contains a symbolic link or special file that cannot be safely backed up: $unsupported_node"

verify_sqlite_database "${OP_DATA_DIR}/db/dev.db"

data_tar="${stage_dir}/data.tar.gz"
tar_args=(-czf "$data_tar" -C "$OP_DATA_DIR")
if [[ "$INCLUDE_CACHES" -ne 1 ]]; then
  for cache_dir in book-cache book-tts-cache comic-cache image-cache video-proxy-cache transcode-cache image-upscale-cache cache temp logs; do
    tar_args+=(--exclude="./${cache_dir}")
  done
fi
tar_args+=(.)
tar "${tar_args[@]}"

deployment_files=()
for file in docker-compose.remote.yml .updater.env server.env .server-env.schema.json docker-compose.gpu.yml docker-compose.gpu-amd.yml docker-compose.gpu-nvidia.yml; do
  [[ -f "${OP_DEPLOY_DIR}/${file}" ]] && deployment_files+=("$file")
done
[[ "${#deployment_files[@]}" -gt 0 ]] || operation_fail "no deployment files were found"
tar -czf "${stage_dir}/deployment.tar.gz" -C "$OP_DEPLOY_DIR" "${deployment_files[@]}"

app_image="$(read_operation_env SCRAPETAB_IMAGE "$OP_ENV_FILE")"
updater_image="$(read_operation_env SCRAPETAB_UPDATER_IMAGE "$OP_ENV_FILE")"
app_digest=""
updater_digest=""
[[ -z "$app_image" ]] || app_digest="$(docker image inspect --format '{{join .RepoDigests ","}}' "$app_image" 2>/dev/null || true)"
[[ -z "$updater_image" ]] || updater_digest="$(docker image inspect --format '{{join .RepoDigests ","}}' "$updater_image" 2>/dev/null || true)"
compose_sha="$(sha256_file "$OP_COMPOSE_FILE")"
gpu_mode="$(read_operation_env SCRAPEFUN_GPU_MODE "$OP_ENV_FILE")"

cat > "${stage_dir}/manifest.json" <<EOF
{
  "format": "scrapefun-docker-host-backup-v1",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "toolVersion": 1,
  "dataDirectoryHint": "$(json_escape "$OP_DATA_DIR")",
  "includeCaches": $([[ "$INCLUDE_CACHES" -eq 1 ]] && printf true || printf false),
  "appImage": "$(json_escape "$app_image")",
  "appDigest": "$(json_escape "$app_digest")",
  "updaterImage": "$(json_escape "$updater_image")",
  "updaterDigest": "$(json_escape "$updater_digest")",
  "composeSha256": "$compose_sha",
  "gpuMode": "$(json_escape "${gpu_mode:-none}")"
}
EOF

for file in data.tar.gz deployment.tar.gz manifest.json; do
  printf '%s  %s\n' "$(sha256_file "${stage_dir}/${file}")" "$file"
done > "${stage_dir}/files.sha256"

bundle_name="scrapefun-docker-backup-${timestamp}.tar.gz"
bundle_path="${OUTPUT_DIR}/${bundle_name}"
tar -czf "$bundle_path" -C "$stage_dir" manifest.json files.sha256 data.tar.gz deployment.tar.gz
final_path="$bundle_path"

if [[ -n "$AGE_RECIPIENT" ]]; then
  require_operation_command age
  age -r "$AGE_RECIPIENT" -o "${bundle_path}.age" "$bundle_path"
  rm -f "$bundle_path"
  final_path="${bundle_path}.age"
fi

printf '%s  %s\n' "$(sha256_file "$final_path")" "$(basename "$final_path")" > "${final_path}.sha256"

if [[ -n "$RCLONE_REMOTE" ]]; then
  require_operation_command rclone
  remote_dir="${RCLONE_REMOTE%/}"
  rclone copyto "$final_path" "${remote_dir}/$(basename "$final_path")"
  rclone copyto "${final_path}.sha256" "${remote_dir}/$(basename "$final_path").sha256"
  verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/scrapefun-rclone-verify.XXXXXX")"
  rclone copyto "${remote_dir}/$(basename "$final_path")" "${verify_dir}/$(basename "$final_path")"
  [[ "$(sha256_file "${verify_dir}/$(basename "$final_path")")" == "$(sha256_file "$final_path")" ]] \
    || operation_fail "remote backup checksum verification failed"
  rm -rf "$verify_dir"
fi

"${SCRIPT_DIR}/prune-docker-backups.sh" \
  --directory "$OUTPUT_DIR" \
  --daily "$RETENTION_DAILY" \
  --weekly "$RETENTION_WEEKLY" \
  --monthly "$RETENTION_MONTHLY"

backup_finished=1
write_operation_status "$status_file" succeeded "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "Host backup completed and verified" "$final_path"
notify_result succeeded "Host backup completed and verified: $(basename "$final_path")"
printf 'Backup completed: %s (%s bytes)\n' "$final_path" "$(file_size_bytes "$final_path")"
