#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="${SCRAPEFUN_INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DATA_DIR="${SCRAPEFUN_DATA_DIR:-/var/lib/scrapefun}"
NODE_BIN="${SCRAPEFUN_NODE_BINARY:-$(command -v node)}"
[[ -d "$APP_ROOT/server" && -d "$APP_ROOT/client/dist" ]] || { printf 'Invalid release layout\n' >&2; exit 1; }
mkdir -p "$DATA_DIR"/{db,images,user-avatars,config,custom-scrapers,local-subtitles,logs,cache,temp}
export NODE_ENV=production
export APP_DATA_DIR="$DATA_DIR" APP_DB_DIR="$DATA_DIR/db" APP_CONFIG_DIR="$DATA_DIR/config"
export IMAGE_STORAGE_DIR="$DATA_DIR/images" USER_AVATAR_DIR="$DATA_DIR/user-avatars"
export APP_CLIENT_DIST_DIR="$APP_ROOT/client/dist" DATABASE_URL="file:$DATA_DIR/db/dev.db"
export SCRAPER_SEED_DIRS="$APP_ROOT/server/scraper-seeds,$APP_ROOT/server/scraper-seeds/generated"
export ENABLE_DIST_INTEGRITY_CHECK=true
export IMAGE_UPSCALE_SUPPORTED="${IMAGE_UPSCALE_SUPPORTED:-true}"
export FFMPEG_PATH="${FFMPEG_PATH:-$(command -v ffmpeg)}"
export FFPROBE_PATH="${FFPROBE_PATH:-$(command -v ffprobe)}"
cd "$APP_ROOT/server"
# Uses the same transactional migrations and integrity checks as Windows and
# Docker. The release is immutable: never regenerate Prisma in /opt at startup.
if [[ -f dist/scripts/prepare-storage.js ]]; then
  "$NODE_BIN" dist/scripts/prepare-storage.js
else
  # Published 0.3.3 archives predate prepare-storage. The compatibility helper
  # prepares and verifies a private SQLite copy; incompatible changes never
  # overwrite the original database.
  printf '旧版发布包：检查数据库并执行保守的 schema 同步…\n'
  python3 "$APP_ROOT/operations/linux-server-tools.py" prepare-legacy --data "$DATA_DIR" \
    --schema "$APP_ROOT/server/prisma/schema.prisma" --node "$NODE_BIN"
fi
exec "$NODE_BIN" dist/index.js
