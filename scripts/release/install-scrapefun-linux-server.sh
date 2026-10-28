#!/usr/bin/env bash
set -euo pipefail
main() {
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE=""
INSTALL_DIR="${SCRAPEFUN_INSTALL_DIR:-/opt/scrapefun}"
DATA_DIR="${SCRAPEFUN_DATA_DIR:-/var/lib/scrapefun}"
CONFIG_DIR="${SCRAPEFUN_CONFIG_DIR:-/etc/scrapefun}"
SERVICE_USER="${SCRAPEFUN_SERVICE_USER:-scrapefun}"
SERVICE="${SCRAPEFUN_SERVICE_NAME:-scrapefun.service}"
NODE_BIN="${SCRAPEFUN_NODE_BINARY:-$(command -v node || true)}"
OPS_SOURCE="${SCRAPEFUN_OPERATION_SOURCE:-$SCRIPT_DIR/../operations}"
START_SOURCE="${SCRAPEFUN_START_SOURCE:-$SCRIPT_DIR/start-scrapefun-linux-server.sh}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) printf 'Usage: install-scrapefun-linux-server.sh ARCHIVE.tar.gz [--port PORT]\nPort: --port > APP_HOST_PORT > saved PORT > 8096 (1-65535).\n'; exit 0 ;;
    --port) [[ $# -ge 2 && -n "$2" ]] || fail '--port requires a value'; APP_HOST_PORT="$2"; shift 2 ;;
    --port=*) APP_HOST_PORT="${1#*=}"; [[ -n "$APP_HOST_PORT" ]] || fail '--port requires a value'; shift ;;
    -*) fail "unknown option: $1" ;;
    *) [[ -z "$ARCHIVE" ]] || fail 'specify only one release archive'; ARCHIVE="$1"; shift ;;
  esac
done
ENV_FILE="$CONFIG_DIR/server.env"
port="${APP_HOST_PORT-}"
if [[ -z "${APP_HOST_PORT+x}" ]]; then
  if [[ -f "$ENV_FILE" ]]; then port="$(sed -n 's/^PORT=//p' "$ENV_FILE" | tail -n 1)"; fi
  port="${port%$'\r'}"
  if [[ "$port" == \"*\" || "$port" == \'*\' ]]; then port="${port:1:${#port}-2}"; fi
  port="${port:-8096}"
fi
[[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) \
  || fail 'port must be a number between 1 and 65535'
port="$((10#$port))"
[[ $EUID -eq 0 ]] || fail 'native installation requires root'
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || fail 'usage: install-scrapefun-linux-server.sh ARCHIVE.tar.gz [--port PORT]'
[[ "$SERVICE" =~ ^[a-zA-Z0-9_-]+\.service$ && "$SERVICE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail 'invalid service/user name'
for required in python3 systemctl flock ffmpeg ffprobe sha256sum runuser useradd; do command -v "$required" >/dev/null || fail "missing required command: $required"; done
[[ -f "$ARCHIVE.sha256" ]] || fail 'release requires an adjacent .sha256 checksum file'
expected="$(awk 'NR==1 {print $1}' "$ARCHIVE.sha256")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'invalid release checksum'
printf '%s  %s\n' "$expected" "$ARCHIVE" | sha256sum --check --strict -
[[ -x "$NODE_BIN" ]] || fail 'Node.js 20/22/24 is required'
NODE_BIN="$(readlink -f -- "$NODE_BIN")"
[[ "$("$NODE_BIN" -p "process.versions.node.split('.')[0]")" =~ ^(20|22|24)$ ]] || fail 'Node.js 20/22/24 is required'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'native release supports Linux amd64'
[[ -d /run/systemd/system ]] || fail 'systemd must be running; enable systemd in WSL before installing'
for file in scrapefun.sh linux-server-tools.py; do [[ -f "$OPS_SOURCE/$file" ]] || fail "management script missing: $file"; done
DEPLOY_SOURCE="$OPS_SOURCE/one-click-native-deploy.sh"
[[ -f "$DEPLOY_SOURCE" ]] || DEPLOY_SOURCE="$SCRIPT_DIR/../one-click-native-deploy.sh"
[[ -f "$DEPLOY_SOURCE" ]] || fail 'native one-click script missing'
[[ -f "$START_SOURCE" ]] || fail 'native startup script missing'
# Restrict systemd paths to literal safe characters; reject broad directories,
# symlinks and nested layouts before any write, move or service interruption.
python3 "$OPS_SOURCE/linux-server-tools.py" preflight --install "$INSTALL_DIR" --data "$DATA_DIR" --config "$CONFIG_DIR"
UNIT="/etc/systemd/system/$SERVICE"
[[ ! -L "$UNIT" ]] || fail 'service unit is a symlink or masked; select another service name or resolve it before installing'
mkdir -p "$CONFIG_DIR" "$(dirname "$INSTALL_DIR")"
exec 9>"$CONFIG_DIR/.operations.lock"
flock -n 9 || fail 'another native operation is running'
stage="$(mktemp -d "$(dirname "$INSTALL_DIR")/.scrapefun-install.XXXXXX")"
old_install="" backup="" old_unit="" activated=0 succeeded=0 was_running=0 was_enabled=0 stopped=0
phase='release validation'
systemctl is-active --quiet "$SERVICE" && was_running=1
systemctl is-enabled --quiet "$SERVICE" && was_enabled=1
cleanup() {
  local code=$?
  trap '' INT TERM HUP
  set +e
  local rollback_failed=0
  recover() { "$@" || rollback_failed=1; }
  if [[ $succeeded -eq 0 ]]; then
    printf '安装失败（%s，退出码 %s）。日志: journalctl -u %s -n 50 --no-pager\n' "$phase" "$code" "$SERVICE" >&2
  fi
  if [[ $succeeded -eq 0 && $activated -eq 1 ]]; then
    printf '更新失败，正在恢复旧版本和数据…\n' >&2
    if ! systemctl stop "$SERVICE"; then
      printf '无法停止失败服务，未继续回退。请人工检查；恢复资料保留在: %s\n' "$stage" >&2
      exit "$code"
    fi
    if [[ $was_enabled -eq 0 ]]; then recover systemctl disable "$SERVICE"; fi
    if [[ -d "$INSTALL_DIR" ]]; then recover mv -- "$INSTALL_DIR" "$INSTALL_DIR.failed-$(date +%s)-$$"; fi
    if [[ -n "$old_install" && -d "$old_install" ]]; then recover mv -- "$old_install" "$INSTALL_DIR"; fi
    if [[ -n "$backup" ]]; then
      if ! python3 "$OPS_SOURCE/linux-server-tools.py" restore --archive "$backup" --data "$DATA_DIR"; then
        rollback_failed=1
        printf '自动数据回退失败；请保留并检查备份: %s\n' "$backup" >&2
      fi
    fi
    if [[ -n "$old_unit" ]]; then recover cp "$old_unit" "$UNIT"; else recover rm -f -- "$UNIT"; fi
    if [[ -f "$stage/old-server.env" ]]; then recover cp -p "$stage/old-server.env" "$ENV_FILE"; else recover rm -f -- "$ENV_FILE"; fi
    if [[ -f "$stage/old-management.env" ]]; then recover cp "$stage/old-management.env" "$CONFIG_DIR/management.env"; else recover rm -f -- "$CONFIG_DIR/management.env"; fi
    if [[ -f "$stage/old-gpu.env" ]]; then recover cp "$stage/old-gpu.env" "$CONFIG_DIR/gpu.env"; else recover rm -f "$CONFIG_DIR/gpu.env"; fi
    for item in scrapefun operations; do
      if [[ -e "$CONFIG_DIR/$item" ]]; then recover mv -- "$CONFIG_DIR/$item" "$stage/failed-$item"; fi
      if [[ -e "$stage/old-$item" ]]; then recover mv -- "$stage/old-$item" "$CONFIG_DIR/$item"; fi
    done
    recover systemctl daemon-reload
  fi
  if [[ $succeeded -eq 0 && $stopped -eq 1 && $was_running -eq 1 && $rollback_failed -eq 0 ]]; then recover systemctl start "$SERVICE"; fi
  if [[ $rollback_failed -ne 0 ]]; then
    printf '自动恢复未完成，服务未确认恢复；请人工检查。恢复资料保留在: %s\n备份: %s\n' "$stage" "$backup" >&2
    exit "$code"
  fi
  rm -rf -- "$stage"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf '验证并解压发布包…\n'
release="$(python3 "$OPS_SOURCE/linux-server-tools.py" extract-release --archive "$ARCHIVE" --destination "$stage")"
CHANNEL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["channel"])' "$release/RELEASE.json")"
[[ -z "${SCRAPEFUN_NATIVE_CHANNEL:-}" || "$CHANNEL" == "$SCRAPEFUN_NATIVE_CHANNEL" ]] || fail 'archive channel differs from requested channel'
if [[ -n "${SCRAPEFUN_NATIVE_VERSION:-}" ]]; then
  release_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version", ""))' "$release/RELEASE.json")"
  [[ "$release_version" == "$SCRAPEFUN_NATIVE_VERSION" ]] || fail 'archive version differs from requested version'
fi
install -m 755 "$START_SOURCE" "$release/start.sh"
install -d -m 755 "$release/operations"
install -m 755 "$OPS_SOURCE/linux-server-tools.py" "$release/operations/linux-server-tools.py"
# Verify the immutable server before stopping an existing service.
(cd "$release/server" && "$NODE_BIN" scripts/verify-protected.cjs)
for module in "$release/server/dist/pro-runtime/"*.node; do
  [[ -f "$module" ]] || continue
  command -v ldd >/dev/null || fail 'ldd is required to check native runtime libraries'
  libraries="$(ldd "$module" 2>&1)" || fail "incompatible native runtime libraries: $libraries"
  if grep -q 'not found' <<< "$libraries"; then fail "missing native runtime libraries: $libraries"; fi
done
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  if getent group "$SERVICE_USER" >/dev/null; then user_group=(--gid "$SERVICE_USER"); else user_group=(--user-group); fi
  useradd --system "${user_group[@]}" --home-dir "$DATA_DIR" --shell "$(command -v nologin || command -v false)" "$SERVICE_USER"
fi
SERVICE_GROUP="$(id -gn "$SERVICE_USER")"
[[ "$SERVICE_GROUP" =~ ^[a-zA-Z0-9_.-]+$ ]] || fail 'unsupported primary service group name'
runuser -u "$SERVICE_USER" -- "$NODE_BIN" --version >/dev/null || fail 'Node.js must be accessible to the service account; use a system installation'
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$DATA_DIR"
install -d -o root -g "$SERVICE_GROUP" -m 0755 "$CONFIG_DIR"
# Stage configuration so backup and failed-update rollback retain the old port
# and secret. Publish it only when the new installation is activated.
if [[ -f "$ENV_FILE" ]]; then
  cp -p "$ENV_FILE" "$stage/old-server.env"
  sed "s/^PORT=.*/PORT=$port/" "$ENV_FILE" > "$stage/server.env"
else
  printf 'HOST=0.0.0.0\n' > "$stage/server.env"
fi
# Existing hand-edited env files may lack a final newline.
[[ ! -s "$stage/server.env" || -z "$(tail -c 1 "$stage/server.env")" ]] || printf '\n' >> "$stage/server.env"
if ! grep -q '^PORT=' "$stage/server.env"; then printf 'PORT=%s\n' "$port" >> "$stage/server.env"; fi
if ! grep -q '^APP_AUTH_SECRET=.' "$stage/server.env"; then
  printf 'APP_AUTH_SECRET=%s\n' "$("$NODE_BIN" -e "process.stdout.write(require('node:crypto').randomBytes(48).toString('base64url'))")" >> "$stage/server.env"
fi
[[ ! -f "$CONFIG_DIR/management.env" ]] || cp "$CONFIG_DIR/management.env" "$stage/old-management.env"
[[ ! -f "$CONFIG_DIR/gpu.env" ]] || cp "$CONFIG_DIR/gpu.env" "$stage/old-gpu.env"
[[ ! -f "$UNIT" ]] || { cp "$UNIT" "$stage/old.service"; old_unit="$stage/old.service"; }
for item in scrapefun operations; do
  if [[ -e "$CONFIG_DIR/$item" ]]; then cp -a -- "$CONFIG_DIR/$item" "$stage/old-$item"; fi
done
phase='port and backup preflight'
existing_port="$(sed -n 's/^PORT=//p' "$ENV_FILE" 2>/dev/null | tail -n 1 || true)"
if [[ $was_running -eq 0 || "$port" != "$existing_port" ]]; then
  python3 "$OPS_SOURCE/linux-server-tools.py" check-port --port "$port"
fi
python3 "$OPS_SOURCE/linux-server-tools.py" preflight --install "$INSTALL_DIR" --data "$DATA_DIR" --config "$CONFIG_DIR"
printf '停止服务并备份现有数据…\n'
phase='stopped-service backup'
stopped=1
systemctl stop "$SERVICE" 2>/dev/null || [[ $was_running -eq 0 ]]
python3 "$OPS_SOURCE/linux-server-tools.py" check-port --port "$port"
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
phase='activation'
install -o root -g "$SERVICE_GROUP" -m 640 "$stage/server.env" "$ENV_FILE"
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
Group=$SERVICE_GROUP
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
if (( port < 1024 )); then
  sed -i '/^NoNewPrivileges=true/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' "$UNIT"
fi
systemctl daemon-reload
printf '启动服务并检查应用就绪状态…\n'
phase='service readiness'
systemctl start "$SERVICE"
bash "$CONFIG_DIR/scrapefun" wait-ready
systemctl enable "$SERVICE"
succeeded=1
if [[ "$CONFIG_DIR" == /etc/scrapefun && "$SERVICE" == scrapefun.service ]]; then
  ln -sfn "$CONFIG_DIR/scrapefun" /usr/local/bin/scrapefun
fi
printf '\nScrapeFun 原生服务已就绪。\n管理: sudo %s/scrapefun\n数据: %s\n配置: %s\n' "$CONFIG_DIR" "$DATA_DIR" "$ENV_FILE"
bash "$CONFIG_DIR/scrapefun" url
[[ -z "$old_install" ]] || printf '旧版本保留: %s\n' "$old_install"
}
main "$@"
