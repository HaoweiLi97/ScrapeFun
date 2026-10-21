#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
BASE="$(dirname "$SELF")"
[[ "$(basename "$BASE")" != operations ]] || BASE="$(dirname "$BASE")"
DEPLOY_DIR="$BASE"
MODE=""
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
value() {
  [[ -f "$2" ]] || return 0
  local content
  content="$(sed -n "s/^$1=//p" "$2" | tail -n 1)"
  content="${content%$'\r'}"
  if [[ "$content" == \"*\" || "$content" == \'*\' ]]; then content="${content:1:${#content}-2}"; fi
  printf '%s\n' "$content"
}
usage() {
  cat <<'EOF'
ScrapeFun Linux 服务管理
Usage: scrapefun [--deploy-dir PATH] [--mode docker|native] COMMAND [OPTIONS]
  menu                 交互管理菜单（仅终端）
  status               服务、数据位置和访问地址
  start|stop|restart   启动、停止、重启
  logs [--follow]      最近日志；--follow 持续跟踪
  health               检查应用就绪状态
  wait-ready           等待应用就绪（默认 180 秒）
  url                  显示访问地址
  update [stable|beta] 更新；省略渠道时沿用当前渠道
  backup [OPTIONS]     Docker 沿用现有备份选项；原生支持 --output-dir PATH
  restore FILE         验证备份后恢复数据（原生配置保留当前值）
  doctor               检查依赖、配置、端口和数据目录
  help                 显示帮助
两种部署使用相同 Web 管理界面。安装、更新和恢复会输出进度。
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-dir) [[ $# -ge 2 ]] || fail 'missing --deploy-dir value'; DEPLOY_DIR="$2"; shift 2 ;;
    --mode) [[ $# -ge 2 ]] || fail 'missing --mode value'; MODE="$2"; shift 2 ;;
    *) break ;;
  esac
done
COMMAND="${1:-menu}"
[[ $# -eq 0 ]] || shift
if [[ "$COMMAND" == help || "$COMMAND" == --help || "$COMMAND" == -h ]]; then usage; exit 0; fi
[[ -d "$DEPLOY_DIR" ]] || fail "deployment directory missing: $DEPLOY_DIR"
DEPLOY_DIR="$(cd "$DEPLOY_DIR" && pwd -P)"
STATE="$DEPLOY_DIR/management.env"
if [[ -z "$MODE" ]]; then
  MODE="$(value MODE "$STATE")"
  if [[ -z "$MODE" && -f "$DEPLOY_DIR/docker-compose.remote.yml" ]]; then MODE=docker; fi
fi
[[ "$MODE" == docker || "$MODE" == native ]] || fail 'deployment not found; use --deploy-dir PATH --mode docker|native'
OPS="$DEPLOY_DIR/operations"
if [[ "$MODE" == docker ]]; then
  ENV_FILE="$DEPLOY_DIR/.updater.env"
  [[ -f "$ENV_FILE" && -f "$DEPLOY_DIR/docker-compose.remote.yml" ]] || fail 'Compose deployment is incomplete'
  PORT="$(value APP_HOST_PORT "$ENV_FILE")"
  DATA_DIR="$(value SCRAPEFUN_DATA_DIR "$ENV_FILE")"
  DATA_DIR="${DATA_DIR:-$DEPLOY_DIR/scrapefun-data}"
  [[ "$DATA_DIR" == /* ]] || DATA_DIR="$DEPLOY_DIR/${DATA_DIR#./}"
  CHANNEL="$(value UPDATE_CURRENT_TAG "$ENV_FILE")"
  [[ "$CHANNEL" == beta ]] || CHANNEL=stable
else
  INSTALL_DIR="$(value INSTALL_DIR "$STATE")"
  DATA_DIR="$(value DATA_DIR "$STATE")"
  ENV_FILE="$(value ENV_FILE "$STATE")"
  SERVICE="$(value SERVICE "$STATE")"
  NODE_BIN="$(value NODE_BIN "$STATE")"
  SERVICE_USER="$(value SERVICE_USER "$STATE")"
  [[ -n "$INSTALL_DIR" && -n "$DATA_DIR" && -f "$ENV_FILE" ]] || fail 'native management.env is incomplete'
  [[ "$SERVICE" =~ ^[a-zA-Z0-9_-]+\.service$ ]] || fail 'invalid systemd service name'
  PORT="$(value PORT "$STATE")"
  if [[ -r "$ENV_FILE" ]]; then PORT="$(value PORT "$ENV_FILE")"; fi
  CHANNEL="$(value CHANNEL "$STATE")"
fi
PORT="${PORT:-8096}"
[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -gt 0 && "$PORT" -le 65535 ]] || fail 'invalid configured port'
root_exec() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo -- "$@"; fi; }
compose() { docker compose --env-file "$ENV_FILE" -f "$DEPLOY_DIR/docker-compose.remote.yml" "$@"; }
service_action() {
  printf '%s: %s …\n' "$MODE" "$1"
  if [[ "$MODE" == docker ]]; then
    case "$1" in start) compose up -d ;; stop) compose stop ;; restart) compose restart app updater ;; esac
  else root_exec systemctl "$1" "$SERVICE"; fi
}
url() {
  printf '本机: http://127.0.0.1:%s\n' "$PORT"
  local address
  for address in $(hostname -I 2>/dev/null || true); do
    [[ "$address" == *:* ]] || printf '局域网: http://%s:%s\n' "$address" "$PORT"
  done
}
health() { curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:$PORT/health/ready"; printf '\n'; }
wait_ready() {
  local timeout="${SCRAPEFUN_HEALTH_TIMEOUT:-180}" deadline
  [[ "$timeout" =~ ^[0-9]+$ ]] || fail 'invalid health timeout'
  deadline=$((SECONDS + timeout))
  printf '等待服务就绪（最多 %s 秒）…\n' "$timeout"
  while (( SECONDS < deadline )); do
    if curl --fail --silent --max-time 5 "http://127.0.0.1:$PORT/health/ready" >/dev/null; then printf '服务已就绪。\n'; return; fi
    sleep 2
  done
  printf '服务未就绪。请运行 %s logs 和 %s doctor。\n' "$SELF" "$SELF" >&2
  return 1
}
status() {
  printf 'ScrapeFun · %s · %s\n数据: %s\n部署: %s\n' "$MODE" "$CHANNEL" "$DATA_DIR" "$DEPLOY_DIR"
  if [[ "$MODE" == docker ]]; then compose ps; else systemctl --no-pager --full status "$SERVICE" || true; fi
  url
  health || return 1
}
native_backup() {
  local output="$DEPLOY_DIR/backups"
  if [[ $# -gt 0 ]]; then
    [[ $# -eq 2 && "$1" == --output-dir ]] || fail 'native backup supports --output-dir PATH'
    output="$2"
  fi
  local running=0
  systemctl is-active --quiet "$SERVICE" && running=1
  # Always restart a previously running service, including failed backups.
  trap 'if [[ $running -eq 1 ]]; then root_exec systemctl start "$SERVICE"; fi' EXIT
  root_exec systemctl stop "$SERVICE"
  root_exec python3 "$OPS/linux-server-tools.py" backup --data "$DATA_DIR" --config "$ENV_FILE" --output "$output"
  if [[ $running -eq 1 ]]; then root_exec systemctl start "$SERVICE"; wait_ready; fi
  trap - EXIT
}
native_restore() {
  [[ $# -eq 1 && -f "$1" ]] || fail 'restore requires one backup file'
  root_exec python3 "$OPS/linux-server-tools.py" verify-backup --archive "$1"
  local running=0 previous
  systemctl is-active --quiet "$SERVICE" && running=1
  trap 'if [[ $running -eq 1 ]]; then root_exec systemctl start "$SERVICE"; fi' EXIT
  root_exec systemctl stop "$SERVICE"
  previous="$(root_exec python3 "$OPS/linux-server-tools.py" restore --archive "$1" --data "$DATA_DIR")"
  printf '恢复完成，原数据保留在: %s\n' "$previous"
  if [[ $running -eq 1 ]]; then
    root_exec systemctl start "$SERVICE"
    if ! wait_ready; then
      root_exec systemctl stop "$SERVICE"
      root_exec mv -- "$DATA_DIR" "$DATA_DIR.failed-restore-$(date +%s)"
      root_exec mv -- "$previous" "$DATA_DIR"
      root_exec systemctl start "$SERVICE"
      fail 'restored service failed readiness; original data restored'
    fi
  fi
  trap - EXIT
}
update() {
  [[ $# -le 1 ]] || fail 'update takes at most one channel'
  local channel="${1:-$CHANNEL}"
  [[ "$channel" == stable || "$channel" == beta ]] || fail 'channel must be stable or beta'
  if [[ "$MODE" == docker ]]; then bash "$OPS/one-click-compose-deploy.sh" "$channel" "$DEPLOY_DIR"; else
    root_exec env SCRAPEFUN_INSTALL_DIR="$INSTALL_DIR" SCRAPEFUN_DATA_DIR="$DATA_DIR" \
      SCRAPEFUN_CONFIG_DIR="$DEPLOY_DIR" SCRAPEFUN_SERVICE_NAME="$SERVICE" \
      SCRAPEFUN_SERVICE_USER="$SERVICE_USER" SCRAPEFUN_NODE_BINARY="$NODE_BIN" \
      bash "$OPS/one-click-native-deploy.sh" "$channel"
  fi
}
doctor() {
  local missing=0 dependency
  for dependency in curl python3 "$([[ "$MODE" == docker ]] && printf docker || printf systemctl)"; do
    if command -v "$dependency" >/dev/null; then printf 'OK %s\n' "$dependency"; else printf '缺少 %s\n' "$dependency"; missing=1; fi
  done
  if [[ "$MODE" == docker ]]; then compose config --quiet || missing=1; else
    "$NODE_BIN" --version || missing=1
    for dependency in ffmpeg ffprobe; do command -v "$dependency" || printf '缺少 %s（媒体播放需要）\n' "$dependency"; done
    [[ -x "$INSTALL_DIR/start.sh" ]] || missing=1
  fi
  printf '配置: %s\n数据: %s\n' "$ENV_FILE" "$DATA_DIR"
  [[ -d "$DATA_DIR" ]] || missing=1
  df -h "$DATA_DIR" || missing=1
  health || missing=1
  return "$missing"
}
case "$COMMAND" in
  status) status ;; url) url ;; health) health ;; wait-ready) wait_ready ;; doctor) doctor ;;
  start|restart) service_action "$COMMAND"; wait_ready; url ;; stop) service_action stop ;;
  logs)
    [[ $# -eq 0 || ( $# -eq 1 && "$1" == --follow ) ]] || fail 'logs supports --follow'
    follow=(); [[ $# -eq 0 ]] || follow=(-f)
    if [[ "$MODE" == docker ]]; then compose logs --tail 100 "${follow[@]}" app updater; else root_exec journalctl --no-pager -n 100 -u "$SERVICE" "${follow[@]}"; fi ;;
  update) update "$@" ;;
  backup|restore)
    if [[ "$MODE" == docker ]]; then
      if [[ "$COMMAND" == backup ]]; then bash "$OPS/backup-docker.sh" --deploy-dir "$DEPLOY_DIR" "$@"; else
        [[ $# -eq 1 ]] || fail 'restore requires one backup file'; bash "$OPS/restore-docker.sh" --deploy-dir "$DEPLOY_DIR" --backup "$1"
      fi
    else
      # Native backups/restores must not race an installer or another snapshot.
      if [[ $EUID -ne 0 ]]; then exec sudo -- "$SELF" --deploy-dir "$DEPLOY_DIR" --mode native "$COMMAND" "$@"; fi
      exec 9>"$DEPLOY_DIR/.operations.lock"; flock -n 9 || fail 'another native operation is running'
      "native_$COMMAND" "$@"
    fi ;;
  menu)
    [[ -t 0 && -t 1 ]] || { usage; exit 0; }
    while true; do
      printf '\nScrapeFun · %s\n1 状态  2 启动  3 停止  4 重启  5 日志  6 更新  7 备份  8 诊断  9 恢复  0 退出\n' "$MODE"
      read -r -p '请选择: ' selection || break
      case "$selection" in
        9)
          read -r -p '请输入备份文件路径: ' archive || break
          "$SELF" --deploy-dir "$DEPLOY_DIR" --mode "$MODE" restore "$archive" || true
          continue ;;
        0) break ;; 1) next=status ;; 2) next=start ;; 3) next=stop ;; 4) next=restart ;;
        5) next=logs ;; 6) next=update ;; 7) next=backup ;; 8) next=doctor ;; *) continue ;;
      esac
      "$SELF" --deploy-dir "$DEPLOY_DIR" --mode "$MODE" "$next" || true
    done ;;
  *) usage; fail "unknown command: $COMMAND" ;;
esac
