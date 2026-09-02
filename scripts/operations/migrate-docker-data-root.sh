#!/usr/bin/env bash

set -euo pipefail

MODE="check"
CONTAINER_NAME="scrapefun"
TARGET_DATA_DIR=""
MANIFEST_FILE=""
LEAVE_STOPPED=0

usage() {
  cat <<'EOF'
Usage:
  migrate-docker-data-root.sh --check --target DATA_DIR [--container NAME]
  migrate-docker-data-root.sh --migrate --target DATA_DIR [--container NAME] [--manifest FILE] [--leave-stopped]

Exit status for --check:
  0  the container already uses TARGET_DATA_DIR as the /app/data root bind mount
  2  migration is required before switching to the new root mount
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --migrate) MODE="migrate" ;;
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
root_mount="$(printf '%s\n' "$mounts" | awk -F ' \| ' '$1 == "/app/data" { print; exit }')"

if [[ -n "$root_mount" ]]; then
  root_source="$(printf '%s\n' "$root_mount" | awk -F ' \| ' '{ print $2 }')"
  root_type="$(printf '%s\n' "$root_mount" | awk -F ' \| ' '{ print $3 }')"
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
