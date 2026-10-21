#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="${1:-}"
INSTALL_DIR="${SCRAPEFUN_INSTALL_DIR:-/opt/scrapefun}"
DATA_DIR="${SCRAPEFUN_DATA_DIR:-/var/lib/scrapefun}"
CONFIG_DIR="${SCRAPEFUN_CONFIG_DIR:-/etc/scrapefun}"
SERVICE_USER="${SCRAPEFUN_SERVICE_USER:-scrapefun}"
SERVICE="${SCRAPEFUN_SERVICE_NAME:-scrapefun.service}"
NODE_BIN="${SCRAPEFUN_NODE_BINARY:-$(command -v node || true)}"
OPS_SOURCE="${SCRAPEFUN_OPERATION_SOURCE:-$SCRIPT_DIR/../operations}"
START_SOURCE="${SCRAPEFUN_START_SOURCE:-$SCRIPT_DIR/start-scrapefun-linux-server.sh}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail 'native installation requires root'
[[ $# -eq 1 && -f "$ARCHIVE" ]] || fail 'usage: install-scrapefun-linux-server.sh ARCHIVE.tar.gz'
[[ "$SERVICE" =~ ^[a-zA-Z0-9_-]+\.service$ && "$SERVICE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail 'invalid service/user name'
for required in python3 systemctl flock ffmpeg ffprobe; do command -v "$required" >/dev/null || fail "missing required command: $required"; done
[[ -f "$ARCHIVE.sha256" ]] || fail 'release requires an adjacent .sha256 checksum file'
expected="$(awk 'NR==1 {print $1}' "$ARCHIVE.sha256")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'invalid release checksum'
printf '%s  %s\n' "$expected" "$ARCHIVE" | sha256sum --check --strict -
[[ -x "$NODE_BIN" ]] || fail 'Node.js 20/22/24 is required'
NODE_BIN="$(readlink -f "$NODE_BIN")"
[[ "$("$NODE_BIN" -p "process.versions.node.split('.')[0]")" =~ ^(20|22|24)$ ]] || fail 'Node.js 20/22/24 is required'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'native release supports Linux amd64'
for file in scrapefun.sh linux-server-tools.py; do [[ -f "$OPS_SOURCE/$file" ]] || fail "management script missing: $file"; done
DEPLOY_SOURCE="$OPS_SOURCE/one-click-native-deploy.sh"
[[ -f "$DEPLOY_SOURCE" ]] || DEPLOY_SOURCE="$SCRIPT_DIR/../one-click-native-deploy.sh"
[[ -f "$DEPLOY_SOURCE" ]] || fail 'native one-click script missing'
[[ -f "$START_SOURCE" ]] || fail 'native startup script missing'
# Restrict systemd paths to literal safe characters; reject broad directories,
# symlinks and nested layouts before any write, move or service interruption.
python3 - "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" <<'PY'
from pathlib import Path
import re, sys
paths = []
for value in sys.argv[1:]:
    p = Path(value)
    broad = {'/', '/var/lib', '/usr/local', '/home', '/etc', '/usr', '/opt', '/var', '/root', '/tmp'}
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', value) or '..' in p.parts or len(p.parts) < 3 or value in broad or p.is_symlink() or p.resolve() != p:
        raise SystemExit('Unsafe systemd deployment path: ' + value)
    paths.append(p)
for i, a in enumerate(paths):
    for b in paths[i + 1:]:
        if a == b or a in b.parents or b in a.parents: raise SystemExit('Install, data and configuration directories must be separate')
PY
mkdir -p "$CONFIG_DIR" "$(dirname "$INSTALL_DIR")"
exec 9>"$CONFIG_DIR/.operations.lock"
flock -n 9 || fail 'another native operation is running'
stage="$(mktemp -d "$(dirname "$INSTALL_DIR")/.scrapefun-install.XXXXXX")"
old_install="" backup="" old_unit="" activated=0 succeeded=0 was_running=0
UNIT="/etc/systemd/system/$SERVICE"
systemctl is-active --quiet "$SERVICE" && was_running=1
cleanup() {
  local code=$?
  if [[ $succeeded -eq 0 && $activated -eq 1 ]]; then
    printf '更新失败，正在恢复旧版本和数据…\n' >&2
    systemctl stop "$SERVICE" || true
    if [[ -d "$INSTALL_DIR" ]]; then mv -- "$INSTALL_DIR" "$INSTALL_DIR.failed-$(date +%s)"; fi
    if [[ -n "$old_install" && -d "$old_install" ]]; then mv -- "$old_install" "$INSTALL_DIR"; fi
    if [[ -n "$backup" ]]; then
      python3 "$OPS_SOURCE/linux-server-tools.py" restore --archive "$backup" --data "$DATA_DIR" \
        || printf '自动数据回退失败；请保留并检查备份: %s\n' "$backup" >&2
    fi
    if [[ -n "$old_unit" ]]; then cp "$old_unit" "$UNIT"; else rm -f -- "$UNIT"; fi
    if [[ -f "$stage/old-management.env" ]]; then cp "$stage/old-management.env" "$CONFIG_DIR/management.env"; fi
    if [[ -f "$stage/old-gpu.env" ]]; then cp "$stage/old-gpu.env" "$CONFIG_DIR/gpu.env"; else rm -f "$CONFIG_DIR/gpu.env"; fi
    systemctl daemon-reload
  fi
  if [[ $succeeded -eq 0 && $was_running -eq 1 ]]; then systemctl start "$SERVICE" || true; fi
  rm -rf -- "$stage"
  exit "$code"
}
trap cleanup EXIT
printf '验证并解压发布包…\n'
release="$(python3 "$OPS_SOURCE/linux-server-tools.py" extract-release --archive "$ARCHIVE" --destination "$stage")"
CHANNEL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["channel"])' "$release/RELEASE.json")"
[[ -z "${SCRAPEFUN_NATIVE_CHANNEL:-}" || "$CHANNEL" == "$SCRAPEFUN_NATIVE_CHANNEL" ]] || fail 'archive channel differs from requested channel'
install -m 755 "$START_SOURCE" "$release/start.sh"
install -d -m 755 "$release/operations"
install -m 755 "$OPS_SOURCE/linux-server-tools.py" "$release/operations/linux-server-tools.py"
# Verify the immutable server before stopping an existing service.
(cd "$release/server" && "$NODE_BIN" scripts/verify-protected.cjs)
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"; fi
runuser -u "$SERVICE_USER" -- "$NODE_BIN" --version >/dev/null || fail 'Node.js must be accessible to the service account; use a system installation'
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "$DATA_DIR"
install -d -o root -g "$SERVICE_USER" -m 0755 "$CONFIG_DIR"
ENV_FILE="$CONFIG_DIR/server.env"
if [[ ! -f "$ENV_FILE" ]]; then
  port="${APP_HOST_PORT:-8096}"
  [[ "$port" =~ ^[0-9]+$ && "$port" -gt 0 && "$port" -le 65535 ]] || fail 'invalid APP_HOST_PORT'
  printf 'PORT=%s\nHOST=0.0.0.0\n' "$port" > "$ENV_FILE"
fi
if ! grep -q '^APP_AUTH_SECRET=.' "$ENV_FILE"; then
  printf 'APP_AUTH_SECRET=%s\n' "$("$NODE_BIN" -e "process.stdout.write(require('node:crypto').randomBytes(48).toString('base64url'))")" >> "$ENV_FILE"
fi
chmod 640 "$ENV_FILE"; chown root:"$SERVICE_USER" "$ENV_FILE"
[[ ! -f "$CONFIG_DIR/management.env" ]] || cp "$CONFIG_DIR/management.env" "$stage/old-management.env"
[[ ! -f "$CONFIG_DIR/gpu.env" ]] || cp "$CONFIG_DIR/gpu.env" "$stage/old-gpu.env"
[[ ! -f "$UNIT" ]] || { cp "$UNIT" "$stage/old.service"; old_unit="$stage/old.service"; }
printf '停止服务并备份现有数据…\n'
systemctl stop "$SERVICE" 2>/dev/null || [[ $was_running -eq 0 ]]
if [[ -d "$INSTALL_DIR" || -f "$DATA_DIR/db/dev.db" ]]; then
  backup="$(python3 "$OPS_SOURCE/linux-server-tools.py" backup --data "$DATA_DIR" --config "$ENV_FILE" --output "$CONFIG_DIR/backups")"
  printf '更新前备份: %s\n' "$backup"
fi
chown -R root:root "$release"
# Native builds emit owner-only artifacts. Root owns the immutable install,
# but the unprivileged service must be able to read and load the ELF modules.
find "$release/server/dist/pro-runtime" -type f -name '*.node' -exec chmod 555 {} +
if [[ -d "$INSTALL_DIR" ]]; then
  old_install="$INSTALL_DIR.previous-$(date +%s)-$$"
  mv -- "$INSTALL_DIR" "$old_install"
fi
activated=1
if [[ -n "${SCRAPEFUN_GPU_ENV_FILE:-}" ]]; then
  install -m 644 "$SCRAPEFUN_GPU_ENV_FILE" "$CONFIG_DIR/gpu.env"
fi
mv -- "$release" "$INSTALL_DIR"
install -d -m 755 "$CONFIG_DIR/operations"
for file in scrapefun.sh linux-server-tools.py; do install -m 755 "$OPS_SOURCE/$file" "$CONFIG_DIR/operations/$file"; done
install -m 755 "$DEPLOY_SOURCE" "$CONFIG_DIR/operations/one-click-native-deploy.sh"
for gpu_helper in ensure-comic-gpu-environment.sh setup-wsl-comic-gpu.sh; do
  if [[ -f "$SCRIPT_DIR/../$gpu_helper" ]]; then
    install -m 755 "$SCRIPT_DIR/../$gpu_helper" "$CONFIG_DIR/operations/$gpu_helper"
  fi
done
install -m 755 "$OPS_SOURCE/scrapefun.sh" "$CONFIG_DIR/scrapefun"
# Keep source-local/offline updates functional after the download staging dir
# is removed. The one-click entry finds these under its own operations directory.
install -d -m 755 "$CONFIG_DIR/operations/operations" "$CONFIG_DIR/operations/release"
for file in scrapefun.sh linux-server-tools.py; do install -m 755 "$OPS_SOURCE/$file" "$CONFIG_DIR/operations/operations/$file"; done
install -m 755 "$SCRIPT_DIR/install-scrapefun-linux-server.sh" "$CONFIG_DIR/operations/release/install-scrapefun-linux-server.sh"
install -m 755 "$START_SOURCE" "$CONFIG_DIR/operations/release/start-scrapefun-linux-server.sh"
cat > "$CONFIG_DIR/management.env" <<EOF
MODE=native
INSTALL_DIR=$INSTALL_DIR
DATA_DIR=$DATA_DIR
ENV_FILE=$ENV_FILE
PORT=$(sed -n 's/^PORT=//p' "$ENV_FILE" | tail -n 1)
SERVICE=$SERVICE
SERVICE_USER=$SERVICE_USER
NODE_BIN=$NODE_BIN
CHANNEL=$CHANNEL
EOF
chmod 644 "$CONFIG_DIR/management.env"
cat > "$UNIT" <<EOF
[Unit]
Description=ScrapeFun Server
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
Environment=SCRAPEFUN_INSTALL_DIR=$INSTALL_DIR
Environment=SCRAPEFUN_DATA_DIR=$DATA_DIR
Environment=SCRAPEFUN_NODE_BINARY=$NODE_BIN
EnvironmentFile=$ENV_FILE
EnvironmentFile=-$CONFIG_DIR/gpu.env
WorkingDirectory=$INSTALL_DIR/server
ExecStart=$INSTALL_DIR/start.sh
Restart=on-failure
RestartSec=5
TimeoutStopSec=60
KillMode=control-group
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
UMask=0027
[Install]
WantedBy=multi-user.target
EOF
# Enable actual GPU access under the unprivileged service account.
for group in video render; do if getent group "$group" >/dev/null; then usermod -a -G "$group" "$SERVICE_USER"; fi; done
systemctl daemon-reload
printf '启动服务并检查应用就绪状态…\n'
systemctl enable "$SERVICE"
systemctl start "$SERVICE"
bash "$CONFIG_DIR/scrapefun" wait-ready
succeeded=1
if [[ "$CONFIG_DIR" == /etc/scrapefun && "$SERVICE" == scrapefun.service ]]; then
  ln -sfn "$CONFIG_DIR/scrapefun" /usr/local/bin/scrapefun
fi
printf '\nScrapeFun 原生服务已就绪。\n管理: sudo %s/scrapefun\n数据: %s\n配置: %s\n' "$CONFIG_DIR" "$DATA_DIR" "$ENV_FILE"
bash "$CONFIG_DIR/scrapefun" url
[[ -z "$old_install" ]] || printf '旧版本保留: %s\n' "$old_install"
