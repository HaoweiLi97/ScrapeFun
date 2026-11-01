#!/usr/bin/env bash

set -euo pipefail

MODE="check"
CONTAINER_NAME="scrapefun"
TARGET_DATA_DIR=""
MANIFEST_FILE=""
LEAVE_STOPPED=0
ALLOW_RELOCATION=1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  migrate-docker-data-root.sh --check --target DATA_DIR [--container NAME]
  migrate-docker-data-root.sh --migrate --target DATA_DIR [--container NAME] [--manifest FILE] [--leave-stopped]
  migrate-docker-data-root.sh --upgrade --target DATA_DIR [--container NAME] [--leave-stopped]

--upgrade reuses existing same-root bind mounts and migrates only unmounted
entries. A change of data location still requires explicit --migrate.

Exit status for --check:
  0  the container already uses TARGET_DATA_DIR as the /app/data root bind mount
  2  migration is required before switching to the new root mount
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --migrate) MODE="migrate" ;;
    --upgrade) MODE="migrate"; ALLOW_RELOCATION=0 ;;
    --container)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 1; }
      CONTAINER_NAME="$2"
      shift
      ;;
    --target)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 1; }
      TARGET_DATA_DIR="$2"
      shift
      ;;
    --manifest)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 1; }
      MANIFEST_FILE="$2"
      shift
      ;;
    --leave-stopped) LEAVE_STOPPED=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[[ -n "$TARGET_DATA_DIR" ]] || { printf 'Error: --target is required.\n' >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { printf 'Error: docker is required.\n' >&2; exit 1; }

container_id="$(docker ps -aq --filter "name=^/${CONTAINER_NAME}$" | head -n 1)"
if [[ -z "$container_id" ]]; then
  printf 'No existing %s container was found; no migration is required.\n' "$CONTAINER_NAME"
  exit 0
fi

mkdir -p "$TARGET_DATA_DIR"
target_real="$(cd "$TARGET_DATA_DIR" && pwd -P)"
mounts="$(docker inspect --format '{{range .Mounts}}{{println .Destination "|" .Source "|" .Type}}{{end}}' "$container_id")"
root_mount="$(printf '%s\n' "$mounts" | awk -F ' [|] ' '$1 == "/app/data" { print; exit }')"

if [[ -n "$root_mount" ]]; then
  root_source="$(printf '%s\n' "$root_mount" | awk -F ' [|] ' '{ print $2 }')"
  root_type="$(printf '%s\n' "$root_mount" | awk -F ' [|] ' '{ print $3 }')"
  if [[ "$root_type" == "bind" && -d "$root_source" ]]; then
    source_real="$(cd "$root_source" && pwd -P)"
    if [[ "$source_real" == "$target_real" ]]; then
      printf '%s already binds %s to /app/data.\n' "$CONTAINER_NAME" "$target_real"
      exit 0
    fi
  fi
fi

printf 'Legacy Docker data layout detected for %s.\n' "$CONTAINER_NAME" >&2
printf 'Current /app/data mounts:\n%s\n' "${mounts:-  (none)}" >&2
printf 'Target root: %s\n' "$target_real" >&2

if [[ "$MODE" == "check" ]]; then
  exit 2
fi

# The official old layout already persists its large child directories in the
# chosen root. Reuse those mounts instead of copying/hashing them a second time.
reuse_mounts=1
[[ -z "$root_mount" ]] || reuse_mounts=0
database_mount=0
while IFS= read -r mount; do
  destination="$(printf '%s\n' "$mount" | awk -F ' [|] ' '{print $1}')"
  case "$destination" in /app/data/*) ;; *) continue ;; esac
  relative="${destination#/app/data/}"
  source="$(printf '%s\n' "$mount" | awk -F ' [|] ' '{print $2}')"
  kind="$(printf '%s\n' "$mount" | awk -F ' [|] ' '{print $3}')"
  [[ "$relative" != */* && "$kind" == bind && -d "$source" ]] || { reuse_mounts=0; continue; }
  actual="$(cd "$source" && pwd -P)"
  expected="$(cd "$target_real/$relative" 2>/dev/null && pwd -P || true)"
  [[ "$actual" == "$expected" ]] || reuse_mounts=0
  [[ "$relative" != db ]] || database_mount=1
done <<< "$mounts"
[[ $database_mount -eq 1 ]] || reuse_mounts=0
if [[ $ALLOW_RELOCATION -eq 0 && $reuse_mounts -ne 1 ]]; then
  printf 'Error: this layout changes data locations; use --migrate-data-root explicitly after checking the source and target paths.\n' >&2
  exit 1
fi

if [[ $reuse_mounts -eq 1 ]]; then
  merger="$SCRIPT_DIR/migrate-data-root.cjs"
  [[ -f "$merger" ]] || merger="$SCRIPT_DIR/../updater/migrate-data-root.cjs"
  [[ -f "$merger" ]] || { printf 'Error: persistent-data merger is missing.\n' >&2; exit 1; }
  was_running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
  inspection_image=""
  migration_receipt="$(mktemp "${TMPDIR:-/tmp}/scrapefun-migration-receipt.XXXXXX")"
  migration_complete=0
  cleanup_fast() {
    rm -f "$migration_receipt"
    [[ -z "$inspection_image" ]] || docker image rm "$inspection_image" >/dev/null 2>&1 || true
    if [[ $migration_complete -ne 1 && "$was_running" == true ]]; then docker start "$container_id" >/dev/null 2>&1 || true; fi
  }
  trap cleanup_fast EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  [[ "$was_running" != true ]] || docker stop --time 60 "$container_id" >/dev/null
  inspection_image="$(docker commit "$container_id")"
  mounts_json="$(docker inspect --format '{{json .Mounts}}' "$container_id")"
  merge_code="$(cat "$merger")
const skipped = new Set(JSON.parse(process.argv[3]).filter(m => m.Destination.startsWith('/app/data/')).map(m => m.Destination.slice(10)));
const receipt = [];
mergeDataRoot(process.argv[1], process.argv[2], skipped, receipt);
console.log('# Verified unmounted entries only; existing persistent mounts were reused.');
for (const file of receipt) console.log(file.sha256 + '  ' + file.path);"
  docker run --rm --network none --read-only --user 0 --entrypoint node \
    --volume "$target_real:/upgrade-target" "$inspection_image" \
    -e "$merge_code" /app/data /upgrade-target "$mounts_json" > "$migration_receipt"
  MANIFEST_FILE="${MANIFEST_FILE:-$(dirname "$target_real")/scrapefun-data-migration-$(date -u +%Y%m%dT%H%M%SZ).sha256}"
  mkdir -p "$(dirname "$MANIFEST_FILE")"
  cp "$migration_receipt" "$MANIFEST_FILE"
  chmod 600 "$MANIFEST_FILE"
  migration_complete=1
  if [[ "$was_running" == true && $LEAVE_STOPPED -ne 1 ]]; then docker start "$container_id" >/dev/null; fi
  printf 'Migration completed; existing mounted databases/images were reused without copying.\n'
  printf 'Verification manifest (migrated entries only): %s\n' "$MANIFEST_FILE"
  exit 0
fi

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/scrapefun-data-migration.XXXXXX")"
was_running="$(docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null || printf 'false')"
migration_complete=0

cleanup() {
  rm -rf "$staging_dir"
  if [[ "$migration_complete" -ne 1 && "$was_running" == "true" ]]; then
    docker start "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT HUP INT TERM

if [[ "$was_running" == "true" ]]; then
  printf 'Stopping %s to take a consistent data copy...\n' "$CONTAINER_NAME"
  docker stop --time 60 "$container_id" >/dev/null
fi

printf 'Copying the complete container /app/data view to staging...\n'
docker cp "${container_id}:/app/data/." "$staging_dir"

unsupported_node="$(find "$staging_dir" ! -type d ! -type f -print -quit)"
if [[ -n "$unsupported_node" ]]; then
  printf 'Error: migration source contains a symbolic link or special file that cannot be copied safely: %s\n' "$unsupported_node" >&2
  exit 1
fi

conflict_count=0
while IFS= read -r -d '' source_file; do
  relative_path="${source_file#${staging_dir}/}"
  target_file="${target_real}/${relative_path}"
  if [[ -f "$target_file" ]] && ! cmp -s "$source_file" "$target_file"; then
    printf 'Conflict: %s differs between the container and target root.\n' "$relative_path" >&2
    conflict_count=$((conflict_count + 1))
  elif [[ -e "$target_file" && ! -f "$target_file" ]]; then
    printf 'Conflict: %s has a different file type in the target root.\n' "$relative_path" >&2
    conflict_count=$((conflict_count + 1))
  fi
done < <(find "$staging_dir" -type f -print0)

if [[ "$conflict_count" -gt 0 ]]; then
  printf 'Error: migration stopped before changing the target because %s conflict(s) require review.\n' "$conflict_count" >&2
  exit 1
fi

while IFS= read -r -d '' source_dir; do
  relative_path="${source_dir#${staging_dir}/}"
  [[ "$source_dir" == "$staging_dir" ]] && relative_path=""
  mkdir -p "${target_real}${relative_path:+/${relative_path}}"
done < <(find "$staging_dir" -type d -print0)

copied_count=0
while IFS= read -r -d '' source_file; do
  relative_path="${source_file#${staging_dir}/}"
  target_file="${target_real}/${relative_path}"
  if [[ ! -e "$target_file" ]]; then
    mkdir -p "$(dirname "$target_file")"
    cp -p "$source_file" "$target_file"
    copied_count=$((copied_count + 1))
  fi
done < <(find "$staging_dir" -type f -print0)

if [[ -z "$MANIFEST_FILE" ]]; then
  MANIFEST_FILE="$(dirname "$target_real")/scrapefun-data-migration-$(date -u +%Y%m%dT%H%M%SZ).sha256"
fi
mkdir -p "$(dirname "$MANIFEST_FILE")"
: > "$MANIFEST_FILE"
while IFS= read -r -d '' migrated_file; do
  relative_path="${migrated_file#${target_real}/}"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$migrated_file" | awk '{print $1}')"
  else
    digest="$(shasum -a 256 "$migrated_file" | awk '{print $1}')"
  fi
  printf '%s  %s\n' "$digest" "$relative_path" >> "$MANIFEST_FILE"
done < <(find "$target_real" -type f -print0)

migration_complete=1
if [[ "$was_running" == "true" && "$LEAVE_STOPPED" -ne 1 ]]; then
  docker start "$container_id" >/dev/null
fi

printf 'Migration completed: %s new file(s) copied.\n' "$copied_count"
printf 'Verification manifest: %s\n' "$MANIFEST_FILE"
