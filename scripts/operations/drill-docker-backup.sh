#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=docker-operations-common.sh
source "${SCRIPT_DIR}/docker-operations-common.sh"

BUNDLE=""
AGE_IDENTITY=""
IMAGE=""
TIMEOUT=180

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --backup) BUNDLE="$2"; shift ;;
    --age-identity) AGE_IDENTITY="$2"; shift ;;
    --image) IMAGE="$2"; shift ;;
    --timeout) TIMEOUT="$2"; shift ;;
    -h|--help)
      printf 'Usage: drill-docker-backup.sh --backup FILE [--age-identity FILE] [--image IMAGE] [--timeout SECONDS]\n'
      exit 0
      ;;
    *) operation_fail "unknown argument: $1" ;;
  esac
  shift
done

[[ -n "$BUNDLE" && -f "$BUNDLE" ]] || operation_fail "--backup must name an existing file"
require_operation_command docker
require_operation_command tar
require_operation_command curl
require_operation_command python3

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/scrapefun-restore-drill.XXXXXX")"
container_name="scrapefun-restore-drill-$$"
outer_archive="$BUNDLE"
started_at="$(date +%s)"

cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

if [[ "$BUNDLE" == *.age ]]; then
  [[ -n "$AGE_IDENTITY" && -f "$AGE_IDENTITY" ]] || operation_fail "--age-identity is required for an encrypted backup"
  require_operation_command age
  outer_archive="${work_dir}/backup.tar.gz"
  age -d -i "$AGE_IDENTITY" -o "$outer_archive" "$BUNDLE"
fi

assert_safe_tar_archive "$outer_archive" gzip
tar -xzf "$outer_archive" -C "$work_dir"
while read -r expected file; do
  [[ -n "$expected" && -n "$file" ]] || continue
  file="${file#\*}"
  file="${file# }"
  [[ "$(sha256_file "${work_dir}/${file}")" == "$expected" ]] || operation_fail "backup member checksum mismatch: $file"
done < "${work_dir}/files.sha256"

mkdir -p "${work_dir}/data"
assert_safe_tar_archive "${work_dir}/data.tar.gz" gzip
tar -xzf "${work_dir}/data.tar.gz" -C "${work_dir}/data"
verify_sqlite_database "${work_dir}/data/db/dev.db"

if [[ -z "$IMAGE" ]]; then
  IMAGE="$(sed -n 's/^[[:space:]]*"appImage": "\([^"]*\)",*$/\1/p' "${work_dir}/manifest.json" | head -n 1)"
fi
[[ -n "$IMAGE" ]] || operation_fail "backup manifest has no app image; provide --image"
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"

chmod -R u+rwX "${work_dir}/data"
docker run -d --rm \
  --name "$container_name" \
  -p 127.0.0.1::8096 \
  -e NODE_ENV=production \
  -e DATABASE_URL=file:/app/data/db/dev.db \
  -e APP_AUTH_SECRET="restore-drill-$RANDOM-$RANDOM" \
  -v "${work_dir}/data:/app/data" \
  "$IMAGE" >/dev/null

port=""
for _ in $(seq 1 20); do
  port="$(docker port "$container_name" 8096/tcp 2>/dev/null | sed -n 's/.*://p' | tail -n 1)"
  [[ -z "$port" ]] || break
  sleep 1
done
[[ -n "$port" ]] || operation_fail "unable to resolve isolated drill port"

elapsed=0
while [[ "$elapsed" -lt "$TIMEOUT" ]]; do
  if curl -fsS "http://127.0.0.1:${port}/health/ready" >/dev/null 2>&1; then
    table_count="$(python3 - "${work_dir}/data/db/dev.db" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
try:
    print(connection.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0])
finally:
    connection.close()
PY
)"
    printf 'Restore drill passed: image=%s tables=%s RTO=%ss\n' "$IMAGE" "$table_count" "$(( $(date +%s) - started_at ))"
    exit 0
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

docker logs "$container_name" >&2 || true
operation_fail "isolated restore drill did not become ready within ${TIMEOUT}s"
