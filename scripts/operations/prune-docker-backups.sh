#!/usr/bin/env bash

set -euo pipefail

DIRECTORY=""
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --directory) DIRECTORY="$2"; shift ;;
    --daily) KEEP_DAILY="$2"; shift ;;
    --weekly) KEEP_WEEKLY="$2"; shift ;;
    --monthly) KEEP_MONTHLY="$2"; shift ;;
    -h|--help)
      printf 'Usage: prune-docker-backups.sh --directory DIR [--daily 7] [--weekly 4] [--monthly 6]\n'
      exit 0
      ;;
    *) printf 'Error: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

[[ -d "$DIRECTORY" ]] || { printf 'Error: backup directory not found: %s\n' "$DIRECTORY" >&2; exit 1; }
for value in "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { printf 'Error: retention values must be non-negative integers.\n' >&2; exit 1; }
done

python3 - "$DIRECTORY" "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY" <<'PY'
from datetime import datetime
from pathlib import Path
import re
import sys

directory = Path(sys.argv[1]).resolve()
daily, weekly, monthly = map(int, sys.argv[2:])
pattern = re.compile(r"^scrapefun-docker-backup-(\d{8}T\d{6}Z)\.tar\.gz(?:\.age)?$")
entries = []
for path in directory.iterdir():
    match = pattern.match(path.name)
    if not match or not path.is_file():
        continue
    entries.append((datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ"), path))
entries.sort(reverse=True)

keep = set()
for _, path in entries[:daily]:
    keep.add(path)

seen_weeks = set()
for moment, path in entries:
    key = moment.strftime("%G-W%V")
    if key not in seen_weeks and len(seen_weeks) < weekly:
        seen_weeks.add(key)
        keep.add(path)

seen_months = set()
for moment, path in entries:
    key = moment.strftime("%Y-%m")
    if key not in seen_months and len(seen_months) < monthly:
        seen_months.add(key)
        keep.add(path)

for _, path in entries:
    if path in keep:
        continue
    checksum = Path(f"{path}.sha256")
    path.unlink()
    if checksum.exists():
        checksum.unlink()
    print(f"Pruned expired backup: {path}")
PY
