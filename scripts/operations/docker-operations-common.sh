#!/usr/bin/env bash

set -euo pipefail

operation_fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_operation_command() {
  command -v "$1" >/dev/null 2>&1 || operation_fail "missing required command: $1"
}

read_operation_env() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

upsert_operation_env() {
  local key="$1"
  local value="$2"
  local file="$3"
  local temporary="${file}.tmp.$$"
  awk -v key="$key" -v value="$value" '
    BEGIN { replaced = 0 }
    index($0, key "=") == 1 {
      if (!replaced) print key "=" value
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) print key "=" value }
  ' "$file" > "$temporary"
  chmod --reference="$file" "$temporary" 2>/dev/null || chmod 600 "$temporary" 2>/dev/null || true
  mv "$temporary" "$file"
}

absolute_existing_dir() {
  local directory="$1"
  [[ -d "$directory" ]] || operation_fail "directory does not exist: $directory"
  (cd "$directory" && pwd -P)
}

absolute_parent_path() {
  local target="$1"
  local parent
  parent="$(dirname "$target")"
  mkdir -p "$parent"
  printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$(basename "$target")"
}

path_is_within() {
  local candidate="$1"
  local root="$2"
  [[ "$candidate" == "$root" || "$candidate" == "$root/"* ]]
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

file_size_bytes() {
  local file="$1"
  if stat -c '%s' "$file" >/dev/null 2>&1; then
    stat -c '%s' "$file"
  else
    stat -f '%z' "$file"
  fi
}

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { ORS = "" }
    {
      if (NR > 1) printf "\\n"
      gsub(/\\/, "\\\\")
      gsub(/\"/, "\\\"")
      gsub(/\r/, "\\r")
      gsub(/\t/, "\\t")
      printf "%s", $0
    }
  '
}

write_operation_status() {
  local target="$1"
  local status="$2"
  local timestamp="$3"
  local message="$4"
  local artifact="${5:-}"
  local temporary="${target}.tmp.$$"
  mkdir -p "$(dirname "$target")"
  printf '{\n  "status": "%s",\n  "timestamp": "%s",\n  "message": "%s",\n  "artifact": "%s"\n}\n' \
    "$(json_escape "$status")" \
    "$(json_escape "$timestamp")" \
    "$(json_escape "$message")" \
    "$(json_escape "$artifact")" > "$temporary"
  chmod 600 "$temporary" 2>/dev/null || true
  mv "$temporary" "$target"
}

assert_safe_tar_archive() {
  local archive="$1"
  local compression="${2:-gzip}"
  local list_command=(tar -tf "$archive")
  [[ "$compression" != "gzip" ]] || list_command=(tar -tzf "$archive")
  local unsafe
  unsafe="$("${list_command[@]}" | awk '
    BEGIN { unsafe = 0 }
    /^\// { print; unsafe = 1; next }
    /(^|\/)\.\.($|\/)/ { print; unsafe = 1 }
    END { if (unsafe) exit 1 }
  ' || true)"
  [[ -z "$unsafe" ]] || operation_fail "archive contains unsafe paths: $unsafe"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$archive" "$compression" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

archive_path, compression = sys.argv[1:]
mode = "r:gz" if compression == "gzip" else "r:"
with tarfile.open(archive_path, mode) as archive:
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive path: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsupported archive member type: {member.name}")
PY
  fi
}

resolve_operation_layout() {
  OP_DEPLOY_DIR="$(absolute_existing_dir "$OP_DEPLOY_DIR")"
  OP_ENV_FILE="${OP_DEPLOY_DIR}/.updater.env"
  OP_COMPOSE_FILE="${OP_DEPLOY_DIR}/docker-compose.remote.yml"
  [[ -f "$OP_ENV_FILE" ]] || operation_fail "updater env file not found: $OP_ENV_FILE"
  [[ -f "$OP_COMPOSE_FILE" ]] || operation_fail "Compose file not found: $OP_COMPOSE_FILE"

  if [[ -z "${OP_DATA_DIR:-}" ]]; then
    OP_DATA_DIR="$(read_operation_env SCRAPEFUN_DATA_DIR "$OP_ENV_FILE")"
  fi
  [[ -n "$OP_DATA_DIR" ]] || OP_DATA_DIR="${OP_DEPLOY_DIR}/scrapefun-data"
  if [[ "$OP_DATA_DIR" != /* ]]; then
    OP_DATA_DIR="${OP_DEPLOY_DIR}/${OP_DATA_DIR#./}"
  fi
  mkdir -p "$OP_DATA_DIR"
  OP_DATA_DIR="$(absolute_existing_dir "$OP_DATA_DIR")"
  OP_APP_PORT="$(read_operation_env APP_HOST_PORT "$OP_ENV_FILE")"
  OP_APP_PORT="${OP_APP_PORT:-8096}"
}

operation_compose() {
  docker compose --env-file "$OP_ENV_FILE" -f "$OP_COMPOSE_FILE" "$@"
}

verify_sqlite_database() {
  local database="$1"
  [[ -f "$database" ]] || operation_fail "SQLite database is missing: $database"
  if command -v sqlite3 >/dev/null 2>&1; then
    local result
    result="$(sqlite3 "$database" 'PRAGMA quick_check; PRAGMA integrity_check;')"
    [[ "$result" == $'ok\nok' ]] || operation_fail "SQLite integrity check failed: $result"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$database" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
try:
    for pragma in ("quick_check", "integrity_check"):
        rows = connection.execute(f"PRAGMA {pragma}").fetchall()
        values = [str(row[0]).lower() for row in rows]
        if values != ["ok"]:
            raise SystemExit(f"SQLite {pragma} failed: {values}")
finally:
    connection.close()
PY
    return
  fi
  operation_fail "sqlite3 or python3 is required for database verification"
}
