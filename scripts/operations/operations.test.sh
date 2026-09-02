#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/scrapefun-operations-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

MOCK_BIN="${TEST_ROOT}/bin"
DEPLOY_DIR="${TEST_ROOT}/deploy"
DATA_DIR="${TEST_ROOT}/data"
BACKUP_DIR="${TEST_ROOT}/backups"
MOCK_CONTAINER_DATA="${TEST_ROOT}/container-data"
DOCKER_LOG="${TEST_ROOT}/docker.log"
mkdir -p "$MOCK_BIN" "$DEPLOY_DIR" "$DATA_DIR/db" "$BACKUP_DIR" "$MOCK_CONTAINER_DATA"
: > "$DOCKER_LOG"

cat > "${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ "$1" == "ps" && "$*" == *"name=^/scrapefun$"* ]]; then
  printf 'legacy-container\n'
elif [[ "$1" == "inspect" && "$*" == *"range .Mounts"* ]]; then
  printf '/app/data/db | /legacy/db | bind\n/app/data/images | /legacy/images | bind\n'
elif [[ "$1" == "inspect" && "$*" == *".State.Running"* ]]; then
  printf '%s\n' "${MOCK_CONTAINER_RUNNING:-false}"
elif [[ "$1" == "cp" ]]; then
  cp -R "${MOCK_CONTAINER_DATA}/." "$3"
elif [[ "$1" == "compose" ]]; then
  if [[ "$*" == *" ps -q app"* ]]; then
    exit 0
  fi
elif [[ "$1" == "image" && "$2" == "inspect" ]]; then
  exit 0
fi
exit 0
EOF

cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "${MOCK_BIN}/docker" "${MOCK_BIN}/curl"

printf 'old-only\n' > "${MOCK_CONTAINER_DATA}/legacy.txt"
mkdir -p "${MOCK_CONTAINER_DATA}/images"
printf 'same\n' > "${MOCK_CONTAINER_DATA}/images/same.txt"
cp "${MOCK_CONTAINER_DATA}/images/same.txt" "${DATA_DIR}/same-copy.txt"

if PATH="${MOCK_BIN}:$PATH" DOCKER_LOG="$DOCKER_LOG" MOCK_CONTAINER_DATA="$MOCK_CONTAINER_DATA" \
  "${SCRIPT_DIR}/migrate-docker-data-root.sh" --check --target "$DATA_DIR" >/dev/null 2>&1; then
  printf 'Legacy migration check unexpectedly passed.\n' >&2
  exit 1
else
  [[ "$?" -eq 2 ]]
fi

PATH="${MOCK_BIN}:$PATH" DOCKER_LOG="$DOCKER_LOG" MOCK_CONTAINER_DATA="$MOCK_CONTAINER_DATA" \
  MOCK_CONTAINER_RUNNING=true \
  "${SCRIPT_DIR}/migrate-docker-data-root.sh" --migrate --target "$DATA_DIR" \
    --manifest "${TEST_ROOT}/migration.sha256" >/dev/null
test -f "${DATA_DIR}/legacy.txt"
test -f "${DATA_DIR}/images/same.txt"
test -s "${TEST_ROOT}/migration.sha256"
grep -Fq 'stop --time 60 legacy-container' "$DOCKER_LOG"
grep -Fq 'start legacy-container' "$DOCKER_LOG"

cat > "${DEPLOY_DIR}/docker-compose.remote.yml" <<'EOF'
services:
  app:
    image: example/scrapefun:test
EOF
cat > "${DEPLOY_DIR}/.updater.env" <<EOF
SCRAPEFUN_DATA_DIR=${DATA_DIR}
APP_HOST_PORT=18096
SCRAPETAB_IMAGE=example/scrapefun:test
SCRAPETAB_UPDATER_IMAGE=example/scrapefun-updater:test
SCRAPEFUN_GPU_MODE=none
EOF
printf 'APP_AUTH_SECRET=test-secret\n' > "${DEPLOY_DIR}/server.env"
python3 - "${DATA_DIR}/db/dev.db" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
connection.execute("CREATE TABLE marker(value TEXT)")
connection.execute("INSERT INTO marker VALUES ('before-backup')")
connection.commit()
connection.close()
PY

ln -s "${DEPLOY_DIR}/server.env" "${DATA_DIR}/unsafe-link"
if PATH="${MOCK_BIN}:$PATH" DOCKER_LOG="$DOCKER_LOG" \
  "${SCRIPT_DIR}/backup-docker.sh" --deploy-dir "$DEPLOY_DIR" --output-dir "$BACKUP_DIR" >/dev/null 2>&1; then
  printf 'Backup unexpectedly accepted a symbolic link.\n' >&2
  exit 1
fi
rm -f "${DATA_DIR}/unsafe-link"

PATH="${MOCK_BIN}:$PATH" DOCKER_LOG="$DOCKER_LOG" \
  "${SCRIPT_DIR}/backup-docker.sh" --deploy-dir "$DEPLOY_DIR" --output-dir "$BACKUP_DIR" >/dev/null
bundle="$(find "$BACKUP_DIR" -name 'scrapefun-docker-backup-*.tar.gz' -type f | head -n 1)"
test -n "$bundle"
test -s "${bundle}.sha256"

python3 - "${DATA_DIR}/db/dev.db" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
connection.execute("UPDATE marker SET value = 'after-backup'")
connection.commit()
connection.close()
PY
printf 'changed\n' > "${DATA_DIR}/changed-after-backup.txt"

PATH="${MOCK_BIN}:$PATH" DOCKER_LOG="$DOCKER_LOG" \
  "${SCRIPT_DIR}/restore-docker.sh" --deploy-dir "$DEPLOY_DIR" --backup "$bundle" >/dev/null
restored="$(python3 - "${DATA_DIR}/db/dev.db" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
print(connection.execute("SELECT value FROM marker").fetchone()[0])
connection.close()
PY
)"
test "$restored" = before-backup
test ! -e "${DATA_DIR}/changed-after-backup.txt"
find "$TEST_ROOT" -maxdepth 1 -type d -name 'data.pre-restore-*' | grep -q .
grep -Fq '"status": "succeeded"' "${DEPLOY_DIR}/.backup-status.json"
grep -Fq '"status": "succeeded"' "${DEPLOY_DIR}/.restore-status.json"

printf 'Docker operations tests passed.\n'
