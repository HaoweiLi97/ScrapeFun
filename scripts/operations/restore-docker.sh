#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=docker-operations-common.sh
source "${SCRIPT_DIR}/docker-operations-common.sh"

OP_DEPLOY_DIR="$(pwd)"
OP_DATA_DIR=""
BUNDLE=""
AGE_IDENTITY=""
RESTORE_CONFIG=1

usage() {
  cat <<'EOF'
Usage: restore-docker.sh --backup FILE [options]

Options:
  --deploy-dir DIR     Existing Compose deployment directory
  --data-dir DIR       Override the configured data directory
  --age-identity FILE  Identity used to decrypt an .age backup
  --no-config          Restore data but keep current Compose/env files
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --backup) BUNDLE="$2"; shift ;;
    --deploy-dir) OP_DEPLOY_DIR="$2"; shift ;;
    --data-dir) OP_DATA_DIR="$2"; shift ;;
    --age-identity) AGE_IDENTITY="$2"; shift ;;
    --no-config) RESTORE_CONFIG=0 ;;
    -h|--help) usage; exit 0 ;;
    *) operation_fail "unknown argument: $1" ;;
  esac
  shift
done

[[ -n "$BUNDLE" && -f "$BUNDLE" ]] || operation_fail "--backup must name an existing file"
require_operation_command docker
require_operation_command tar
require_operation_command python3
resolve_operation_layout
restore_data_dir="$OP_DATA_DIR"
restore_app_port="$(read_operation_env APP_HOST_PORT "$OP_ENV_FILE")"
restore_gpu_mode="$(read_operation_env SCRAPEFUN_GPU_MODE "$OP_ENV_FILE")"
restore_project_name="$(read_operation_env COMPOSE_PROJECT_NAME "$OP_ENV_FILE")"

case "$OP_DATA_DIR" in
  /|/Users|/home|"${HOME}") operation_fail "refusing to restore into broad path: $OP_DATA_DIR" ;;
esac
[[ "$OP_DATA_DIR" != "$OP_DEPLOY_DIR" ]] || operation_fail "data directory must not equal deployment directory"

status_file="${OP_DEPLOY_DIR}/.restore-status.json"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/scrapefun-host-restore.XXXXXX")"
outer_archive="$BUNDLE"
new_data=""
rollback_data=""
failed_data=""
config_backup="${work_dir}/current-config"
config_absent="${work_dir}/config-absent.list"
data_switched=0
config_switched=0
restore_finished=0

app_container="$(operation_compose ps -q app 2>/dev/null || true)"
updater_container="$(operation_compose ps -q updater 2>/dev/null || true)"
app_was_running=false
updater_was_running=false
[[ -z "$app_container" ]] || app_was_running="$(docker inspect --format '{{.State.Running}}' "$app_container" 2>/dev/null || printf false)"
[[ -z "$updater_container" ]] || updater_was_running="$(docker inspect --format '{{.State.Running}}' "$updater_container" 2>/dev/null || printf false)"

recover_after_failure() {
  if [[ "$data_switched" -eq 1 && -n "$rollback_data" && -d "$rollback_data" ]]; then
    failed_data="${OP_DATA_DIR}.failed-restore-$(date -u +%Y%m%dT%H%M%SZ)"
    [[ ! -e "$OP_DATA_DIR" ]] || mv "$OP_DATA_DIR" "$failed_data"
    mv "$rollback_data" "$OP_DATA_DIR"
  fi
  if [[ "$config_switched" -eq 1 && -d "$config_backup" ]]; then
    while IFS= read -r -d '' backup_file; do
      relative="${backup_file#${config_backup}/}"
      cp -p "$backup_file" "${OP_DEPLOY_DIR}/${relative}"
    done < <(find "$config_backup" -type f -print0)
    if [[ -f "$config_absent" ]]; then
      while IFS= read -r relative; do
        [[ -z "$relative" ]] || rm -f "${OP_DEPLOY_DIR}/${relative}"
      done < "$config_absent"
    fi
  fi
  if [[ "$app_was_running" == true || "$updater_was_running" == true ]]; then
    operation_compose up -d >/dev/null 2>&1 || true
  fi
}

cleanup() {
  if [[ "$restore_finished" -ne 1 ]]; then
    recover_after_failure
    write_operation_status "$status_file" failed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "Host restore failed; previous data was restored when possible" "$BUNDLE" || true
  fi
  [[ -z "$new_data" || ! -d "$new_data" ]] || rm -rf "$new_data"
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

if [[ "$BUNDLE" == *.age ]]; then
  [[ -n "$AGE_IDENTITY" && -f "$AGE_IDENTITY" ]] || operation_fail "--age-identity is required for an encrypted backup"
  require_operation_command age
  outer_archive="${work_dir}/backup.tar.gz"
  age -d -i "$AGE_IDENTITY" -o "$outer_archive" "$BUNDLE"
fi

if [[ -f "${BUNDLE}.sha256" ]]; then
  expected="$(awk 'NR == 1 { print $1 }' "${BUNDLE}.sha256")"
  actual="$(sha256_file "$BUNDLE")"
  [[ "$actual" == "$expected" ]] || operation_fail "outer backup checksum mismatch"
fi

assert_safe_tar_archive "$outer_archive" gzip
tar -xzf "$outer_archive" -C "$work_dir"
grep -Fq '"format": "scrapefun-docker-host-backup-v1"' "${work_dir}/manifest.json" \
  || operation_fail "unsupported host backup manifest"

while read -r expected file; do
  [[ -n "$expected" && -n "$file" ]] || continue
  file="${file#\*}"
  file="${file# }"
  [[ -f "${work_dir}/${file}" ]] || operation_fail "backup member is missing: $file"
  [[ "$(sha256_file "${work_dir}/${file}")" == "$expected" ]] || operation_fail "backup member checksum mismatch: $file"
done < "${work_dir}/files.sha256"

assert_safe_tar_archive "${work_dir}/data.tar.gz" gzip
assert_safe_tar_archive "${work_dir}/deployment.tar.gz" gzip

data_parent="$(dirname "$OP_DATA_DIR")"
mkdir -p "$data_parent"
new_data="${data_parent}/.scrapefun-restore-new-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$new_data"

required_bytes="$(python3 - "${work_dir}/data.tar.gz" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    print(sum(member.size for member in archive.getmembers() if member.isfile()))
PY
)"
available_bytes="$(python3 - "$data_parent" <<'PY'
import shutil
import sys
print(shutil.disk_usage(sys.argv[1]).free)
PY
)"
required_with_margin=$((required_bytes + required_bytes / 5 + 64 * 1024 * 1024))
[[ "$available_bytes" -ge "$required_with_margin" ]] \
  || operation_fail "insufficient free space for restore staging: need ${required_with_margin}, have ${available_bytes} bytes"

tar -xzf "${work_dir}/data.tar.gz" -C "$new_data"
verify_sqlite_database "${new_data}/db/dev.db"

printf 'Stopping app and updater before switching restored data...\n'
operation_compose stop --timeout 60 app >/dev/null
if [[ -n "$updater_container" ]]; then
  operation_compose stop --timeout 60 updater >/dev/null
fi
if [[ -n "$app_container" ]]; then
  [[ "$(docker inspect --format '{{.State.Running}}' "$app_container" 2>/dev/null || printf true)" == false ]] \
    || operation_fail "app container is still running; restore was not started"
fi
if [[ -n "$updater_container" ]]; then
  [[ "$(docker inspect --format '{{.State.Running}}' "$updater_container" 2>/dev/null || printf true)" == false ]] \
    || operation_fail "updater container is still running; restore was not started"
fi

rollback_data="${OP_DATA_DIR}.pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"
[[ ! -e "$rollback_data" ]] || operation_fail "rollback path already exists: $rollback_data"
if [[ -e "$OP_DATA_DIR" ]]; then
  mv "$OP_DATA_DIR" "$rollback_data"
fi
mv "$new_data" "$OP_DATA_DIR"
new_data=""
data_switched=1

if [[ "$RESTORE_CONFIG" -eq 1 ]]; then
  mkdir -p "$config_backup" "${work_dir}/restored-config"
  : > "$config_absent"
  tar -xzf "${work_dir}/deployment.tar.gz" -C "${work_dir}/restored-config"
  while IFS= read -r -d '' restored_file; do
    relative="${restored_file#${work_dir}/restored-config/}"
    if [[ -f "${OP_DEPLOY_DIR}/${relative}" ]]; then
      mkdir -p "${config_backup}/$(dirname "$relative")"
      cp -p "${OP_DEPLOY_DIR}/${relative}" "${config_backup}/${relative}"
    else
      printf '%s\n' "$relative" >> "$config_absent"
    fi
  done < <(find "${work_dir}/restored-config" -type f -print0)
  config_switched=1
  while IFS= read -r -d '' restored_file; do
    relative="${restored_file#${work_dir}/restored-config/}"
    cp -p "$restored_file" "${OP_DEPLOY_DIR}/${relative}"
  done < <(find "${work_dir}/restored-config" -type f -print0)
  if [[ -f "$OP_ENV_FILE" ]]; then
    upsert_operation_env SCRAPEFUN_DATA_DIR "$restore_data_dir" "$OP_ENV_FILE"
    [[ -z "$restore_app_port" ]] || upsert_operation_env APP_HOST_PORT "$restore_app_port" "$OP_ENV_FILE"
    [[ -z "$restore_gpu_mode" ]] || upsert_operation_env SCRAPEFUN_GPU_MODE "$restore_gpu_mode" "$OP_ENV_FILE"
    [[ -z "$restore_project_name" ]] || upsert_operation_env COMPOSE_PROJECT_NAME "$restore_project_name" "$OP_ENV_FILE"
  fi
fi

resolve_operation_layout
[[ "$OP_DATA_DIR" == "$restore_data_dir" ]] || operation_fail "restored configuration attempted to change the selected data directory"
operation_compose up -d

printf 'Waiting for readiness at http://127.0.0.1:%s/health/ready ...\n' "$OP_APP_PORT"
ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${OP_APP_PORT}/health/ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
[[ "$ready" -eq 1 ]] || operation_fail "restored app did not become ready"
verify_sqlite_database "${OP_DATA_DIR}/db/dev.db"

restore_finished=1
write_operation_status "$status_file" succeeded "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "Host restore completed and passed readiness/database verification" "$BUNDLE"
printf 'Restore completed. Previous data retained at: %s\n' "$rollback_data"
