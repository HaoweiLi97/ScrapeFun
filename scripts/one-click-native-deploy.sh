#!/usr/bin/env bash
set -euo pipefail
# Public release archives carry the protected application; no source build is
# performed on the user's server. Only amd64 is currently published.
# Do not execute a partially downloaded curl | bash script.
main() {
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage: one-click-native-deploy.sh [stable|beta] [OPTIONS]
Requires Linux amd64, systemd, Node.js 20/22/24, Python 3, curl and ffmpeg.
Defaults: /opt/scrapefun, /var/lib/scrapefun, /etc/scrapefun; port 8096.
  --port PORT             Override APP_HOST_PORT and the saved port (1-65535).
  --version VERSION       Install a specific release instead of the latest.
  --archive FILE          Offline archive, with adjacent FILE.sha256.
  --install-dir PATH      Application directory.
  --data-dir PATH         Persistent data directory.
  --config-dir PATH       Configuration directory; existing settings are reused.
  --service-name NAME     Separate systemd unit, ending in .service.
  --service-user USER     Unprivileged service user.
  --node PATH             Existing Node.js binary.
  --gpu-mode MODE         auto, none, native or wsl.
  --health-timeout SECS   Readiness timeout (default: 180 seconds).
  --install-deps          Install missing OS packages and an isolated Node 22 runtime.
  --non-interactive, -y   Use explicit/saved/default settings without prompts.
  --check, --dry-run      Check prerequisites and configuration without installing.
  --help                  Show this help.
First interactive installation asks for a port; updates keep the saved port unless overridden.
Offline: SCRAPEFUN_NATIVE_ARCHIVE=/path/release.tar.gz (requires adjacent .sha256).
EOF
}
CHANNEL=""
NON_INTERACTIVE=0 CHECK_ONLY=0 INSTALL_DEPS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --port) [[ $# -ge 2 && -n "$2" ]] || fail '--port requires a value'; export APP_HOST_PORT="$2"; shift 2 ;;
    --port=*) export APP_HOST_PORT="${1#*=}"; [[ -n "$APP_HOST_PORT" ]] || fail '--port requires a value'; shift ;;
    --non-interactive|--yes|-y) NON_INTERACTIVE=1; shift ;;
    --check|--dry-run) CHECK_ONLY=1; NON_INTERACTIVE=1; shift ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --version|--archive|--install-dir|--data-dir|--config-dir|--service-name|--service-user|--node|--gpu-mode|--health-timeout)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 requires a value"
      case "$1" in
        --version) export SCRAPEFUN_NATIVE_VERSION="${2#v}" ;;
        --archive) export SCRAPEFUN_NATIVE_ARCHIVE="$2" ;;
        --install-dir) export SCRAPEFUN_INSTALL_DIR="$2" ;;
        --data-dir) export SCRAPEFUN_DATA_DIR="$2" ;;
        --config-dir) export SCRAPEFUN_CONFIG_DIR="$2" ;;
        --service-name) export SCRAPEFUN_SERVICE_NAME="$2" ;;
        --service-user) export SCRAPEFUN_SERVICE_USER="$2" ;;
        --node) export SCRAPEFUN_NODE_BINARY="$2" ;;
        --gpu-mode) export SCRAPEFUN_GPU_MODE="$2" ;;
        --health-timeout)
          [[ "$2" =~ ^[0-9]{1,5}$ ]] && (( 10#$2 >= 1 && 10#$2 <= 86400 )) || fail 'health timeout must be between 1 and 86400 seconds'
          export SCRAPEFUN_HEALTH_TIMEOUT="$((10#$2))" ;;
      esac
      shift 2 ;;
    stable|beta) [[ -z "$CHANNEL" ]] || fail 'specify only one channel'; CHANNEL="$1"; shift ;;
    *) fail "unknown argument: $1 (use --help)" ;;
  esac
done
if [[ -n "${SCRAPEFUN_NATIVE_VERSION:-}" ]]; then
  [[ "$SCRAPEFUN_NATIVE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || fail 'invalid release version'
fi
if [[ -n "${APP_HOST_PORT+x}" ]]; then
  [[ "$APP_HOST_PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$APP_HOST_PORT >= 1 && 10#$APP_HOST_PORT <= 65535 )) \
    || fail 'port must be a number between 1 and 65535'
  export APP_HOST_PORT="$((10#$APP_HOST_PORT))"
fi
read_setting() {
  [[ -f "$2" ]] || return 0
  local value
  value="$(sed -n "s/^$1=//p" "$2" | tail -n 1)"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then value="${value:1:${#value}-2}"; fi
  printf '%s' "$value"
}
export SCRAPEFUN_CONFIG_DIR="${SCRAPEFUN_CONFIG_DIR:-/etc/scrapefun}"
state="$SCRAPEFUN_CONFIG_DIR/management.env"
CHANNEL="${CHANNEL:-$(read_setting CHANNEL "$state")}"
export SCRAPEFUN_INSTALL_DIR="${SCRAPEFUN_INSTALL_DIR:-$(read_setting INSTALL_DIR "$state")}"
export SCRAPEFUN_DATA_DIR="${SCRAPEFUN_DATA_DIR:-$(read_setting DATA_DIR "$state")}"
export SCRAPEFUN_SERVICE_NAME="${SCRAPEFUN_SERVICE_NAME:-$(read_setting SERVICE "$state")}"
export SCRAPEFUN_SERVICE_USER="${SCRAPEFUN_SERVICE_USER:-$(read_setting SERVICE_USER "$state")}"
export SCRAPEFUN_INSTALL_DIR="${SCRAPEFUN_INSTALL_DIR:-/opt/scrapefun}"
export SCRAPEFUN_DATA_DIR="${SCRAPEFUN_DATA_DIR:-/var/lib/scrapefun}"
export SCRAPEFUN_SERVICE_NAME="${SCRAPEFUN_SERVICE_NAME:-scrapefun.service}"
export SCRAPEFUN_SERVICE_USER="${SCRAPEFUN_SERVICE_USER:-scrapefun}"
[[ "$SCRAPEFUN_SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+\.service$ && "$SCRAPEFUN_SERVICE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail 'invalid service/user name'
CHANNEL="${CHANNEL:-stable}"
[[ "$CHANNEL" == stable || "$CHANNEL" == beta ]] || fail 'channel must be stable or beta'
[[ $EUID -eq 0 ]] || fail 'native installation requires root; run the command with sudo bash'
if [[ $NON_INTERACTIVE -eq 0 && -z "${APP_HOST_PORT+x}" && ! -f "$SCRAPEFUN_CONFIG_DIR/server.env" && -t 1 ]] && ( : < /dev/tty ) 2>/dev/null; then
  while true; do
    printf '服务端端口 [8096]: ' > /dev/tty
    requested_port=""
    IFS= read -r requested_port < /dev/tty || true
    requested_port="${requested_port%$'\r'}"
    APP_HOST_PORT="${requested_port:-8096}"
    if [[ "$APP_HOST_PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$APP_HOST_PORT >= 1 && 10#$APP_HOST_PORT <= 65535 )); then break; fi
    printf '端口必须是 1-65535 之间的数字。\n' > /dev/tty
  done
  export APP_HOST_PORT="$((10#$APP_HOST_PORT))"
fi
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'native releases currently support Linux amd64; use Docker for other architectures'
[[ -d /run/systemd/system ]] || fail 'systemd must be running (enable systemd in WSL before installing)'
libc="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
[[ "$libc" == 'glibc '* ]] || fail 'native releases require glibc Linux; musl/Alpine is not supported'
libc_version="${libc#glibc }"
IFS=. read -r libc_major libc_minor _ <<< "$libc_version"
(( libc_major > 2 || (libc_major == 2 && libc_minor >= 28) )) || fail 'glibc 2.28 or newer is required'
missing=()
for required in curl python3 sha256sum systemctl flock ffmpeg ffprobe tar gzip runuser useradd install; do
  command -v "$required" >/dev/null || missing+=("$required")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  if [[ $INSTALL_DEPS -eq 0 || $CHECK_ONLY -eq 1 ]]; then
    fail "missing commands: ${missing[*]}; install them or rerun with --install-deps"
  fi
  printf '安装缺失的系统依赖: %s\n' "${missing[*]}"
  # Use only the distribution's configured repositories; do not replace them
  # or perform a whole-system upgrade. Verify actual tools after installation.
  manager=''
  for candidate in apt-get dnf yum zypper pacman; do
    if command -v "$candidate" >/dev/null; then manager="$candidate"; break; fi
  done
  [[ -n "$manager" ]] || fail "no supported package manager (apt-get/dnf/yum/zypper/pacman); manually install: ${missing[*]}"
  packages=()
  for required in "${missing[@]}"; do
    case "$required" in
      sha256sum|install) packages+=(coreutils) ;; flock|runuser) packages+=(util-linux) ;;
      useradd)
        case "$manager" in apt-get) packages+=(passwd) ;; dnf|yum) packages+=(shadow-utils) ;; *) packages+=(shadow) ;; esac ;;
      python3) if [[ "$manager" == pacman ]]; then packages+=(python); else packages+=(python3); fi ;;
      ffprobe) packages+=(ffmpeg) ;; systemctl) packages+=(systemd) ;;
      *) packages+=("$required") ;;
    esac
  done
  case "$manager" in
    apt-get)
      apt-get update
      env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates "${packages[@]}" ;;
    dnf|yum) "$manager" install -y ca-certificates "${packages[@]}" ;;
    zypper) zypper --non-interactive install --no-recommends ca-certificates "${packages[@]}" ;;
    pacman) pacman -S --needed --noconfirm ca-certificates "${packages[@]}" ;;
  esac
fi
for required in curl python3 sha256sum systemctl flock ffmpeg ffprobe tar gzip runuser useradd install; do
  command -v "$required" >/dev/null || fail "missing command after dependency installation: $required (check enabled OS repositories)"
done
node_binary="${SCRAPEFUN_NODE_BINARY:-$(read_setting NODE_BIN "$state")}"
node_binary="${node_binary:-$(command -v node || true)}"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
download_file() {
  local url="$1" target="$2" timeout=120
  [[ "${3:-}" != large ]] || timeout=3600
  if ! curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time "$timeout" \
    --speed-time 60 --speed-limit 1024 -o "$target.part" "$url"; then
    rm -f -- "$target.part"
    fail "download failed: $url; check network, proxy and GitHub API rate limits, or use --archive FILE"
  fi
  mv -- "$target.part" "$target"
}
source_base="https://raw.githubusercontent.com/${GITHUB_REPO:-HaoweiLi97/ScrapeFun}/${GITHUB_BRANCH:-main}/scripts"
mkdir -p "$stage/operations" "$stage/release"
fetch_script() {
  local relative="$1" target="$stage/$1"
  if [[ -f "$ROOT_DIR/$relative" ]]; then cp "$ROOT_DIR/$relative" "$target"; else
    download_file "$source_base/$relative" "$target"
  fi
  if [[ "$relative" == *.sh ]]; then
    sed -i 's/\r$//' "$target"
    bash -n "$target" || fail "invalid or incomplete installation script: $relative"
  fi
}
printf '准备 Linux 原生安装工具…\n'
for file in operations/scrapefun.sh operations/linux-server-tools.py release/install-scrapefun-linux-server.sh release/start-scrapefun-linux-server.sh; do fetch_script "$file"; done
if [[ -f "$ROOT_DIR/one-click-native-deploy.sh" ]]; then cp "$ROOT_DIR/one-click-native-deploy.sh" "$stage/operations/one-click-native-deploy.sh"; else
  download_file "$source_base/one-click-native-deploy.sh" "$stage/operations/one-click-native-deploy.sh"
fi
python3 "$stage/operations/linux-server-tools.py" preflight --install "$SCRAPEFUN_INSTALL_DIR" --data "$SCRAPEFUN_DATA_DIR" --config "$SCRAPEFUN_CONFIG_DIR"
if [[ -z "${SCRAPEFUN_NODE_BINARY:-}" ]] && { [[ ! -x "$node_binary" ]] || ! [[ "$("$node_binary" -p "process.versions.node.split('.')[0]" 2>/dev/null)" =~ ^(20|22|24)$ ]]; }; then
  for candidate in "$SCRAPEFUN_CONFIG_DIR"/runtime/node-v22.*-linux-x64/bin/node; do
    if [[ -x "$candidate" && "$("$candidate" -p "process.versions.node.split('.')[0]" 2>/dev/null)" == 22 ]]; then node_binary="$candidate"; break; fi
  done
fi
if [[ ! -x "$node_binary" ]] || ! [[ "$("$node_binary" -p "process.versions.node.split('.')[0]" 2>/dev/null)" =~ ^(20|22|24)$ ]]; then
  [[ -z "${SCRAPEFUN_NODE_BINARY:-}" ]] || fail 'specified --node must be an executable Node.js 20/22/24 binary'
  [[ $INSTALL_DEPS -eq 1 && $CHECK_ONLY -eq 0 ]] || fail 'Node.js 20/22/24 is required; use --node PATH or --install-deps'
  printf '从 nodejs.org 安装独立 Node.js 22 运行时…\n'
  download_file https://nodejs.org/dist/index.json "$stage/node-index.json"
  node_version="$(python3 - "$stage/node-index.json" <<'PY'
import json, re, sys
for release in json.load(open(sys.argv[1])):
    if re.fullmatch(r'v22\.[0-9]+\.[0-9]+', release.get('version', '')) and 'linux-x64' in release.get('files', []):
        print(release['version']); break
else: raise SystemExit('No supported Node.js 22 runtime found')
PY
)"
  node_name="node-$node_version-linux-x64"
  download_file "https://nodejs.org/dist/$node_version/$node_name.tar.gz" "$stage/node.tar.gz" large
  download_file "https://nodejs.org/dist/$node_version/SHASUMS256.txt" "$stage/node-checksums"
  node_sum="$(awk -v name="$node_name.tar.gz" '$2 == name { print $1 }' "$stage/node-checksums")"
  [[ "$node_sum" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'Node runtime checksum missing'
  printf '%s  %s\n' "$node_sum" "$stage/node.tar.gz" | sha256sum --check --strict -
  mkdir -p "$stage/node"
  python3 - "$stage/operations/linux-server-tools.py" "$stage/node.tar.gz" "$stage/node" <<'PY'
import runpy, sys
runpy.run_path(sys.argv[1])['extract'](sys.argv[2], sys.argv[3], allow_links=True)
PY
  "$stage/node/$node_name/bin/node" --version
  # Keep Node outside the immutable application so upgrades preserve it.
  install -d -o root -g root -m 755 "$SCRAPEFUN_CONFIG_DIR" "$SCRAPEFUN_CONFIG_DIR/runtime"
  runtime="$SCRAPEFUN_CONFIG_DIR/runtime/$node_name"
  [[ ! -e "$runtime" ]] || fail "runtime already exists but is unusable: $runtime; select --node PATH"
  chown -R root:root "$stage/node/$node_name"
  chmod -R go-w "$stage/node/$node_name"
  mv -- "$stage/node/$node_name" "$runtime"
  node_binary="$runtime/bin/node"
fi
export SCRAPEFUN_NODE_BINARY="$(readlink -f -- "$node_binary")"
selected_port="${APP_HOST_PORT:-$(read_setting PORT "$SCRAPEFUN_CONFIG_DIR/server.env")}"
selected_port="${selected_port:-8096}"
[[ "$selected_port" =~ ^[0-9]{1,5}$ ]] && (( 10#$selected_port >= 1 && 10#$selected_port <= 65535 )) || fail 'invalid saved port; specify --port PORT'
selected_port="$((10#$selected_port))"
if ! systemctl is-active --quiet "$SCRAPEFUN_SERVICE_NAME" || [[ "$selected_port" != "$(read_setting PORT "$SCRAPEFUN_CONFIG_DIR/server.env")" ]]; then
  python3 "$stage/operations/linux-server-tools.py" check-port --port "$selected_port"
fi
printf 'Linux amd64 · glibc %s · Node %s\n服务: %s · 渠道: %s · 端口: %s\n程序: %s\n数据: %s\n配置: %s\n' \
  "$libc_version" "$("$SCRAPEFUN_NODE_BINARY" --version)" "$SCRAPEFUN_SERVICE_NAME" "$CHANNEL" "$selected_port" \
  "$SCRAPEFUN_INSTALL_DIR" "$SCRAPEFUN_DATA_DIR" "$SCRAPEFUN_CONFIG_DIR"
if [[ $CHECK_ONLY -eq 1 ]]; then
  if [[ -n "${SCRAPEFUN_NATIVE_ARCHIVE:-}" ]]; then
    archive="$(realpath -- "$SCRAPEFUN_NATIVE_ARCHIVE")"
    [[ -f "$archive" && -f "$archive.sha256" ]] || fail 'offline release requires archive and adjacent .sha256'
    expected="$(awk 'NR==1 {print $1}' "$archive.sha256")"
    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'invalid release checksum'
    printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --strict -
  fi
  printf '安装前检查通过；未安装或重启服务。\n'; return
fi
if [[ -n "${SCRAPEFUN_NATIVE_ARCHIVE:-}" ]]; then
  archive="$(realpath -- "$SCRAPEFUN_NATIVE_ARCHIVE")"
  [[ -f "$archive" && -f "$archive.sha256" ]] || fail 'offline release requires archive and adjacent .sha256'
  checksum="$archive.sha256"
else
  release_api="https://api.github.com/repos/${SCRAPEFUN_NATIVE_RELEASE_REPO:-HaoweiLi97/scrapefun-server-linux}/releases"
  printf '查找 %s 发布包…\n' "$CHANNEL"
  if [[ -n "${SCRAPEFUN_NATIVE_VERSION:-}" ]]; then release_api+="/tags/v$SCRAPEFUN_NATIVE_VERSION"
  elif [[ "$CHANNEL" == stable ]]; then release_api+='/latest'; fi
  download_file "$release_api" "$stage/releases.json"
  python3 - "$stage/releases.json" "$CHANNEL" > "$stage/asset.txt" <<'PY'
import json, sys
from urllib.parse import urlparse
releases = json.load(open(sys.argv[1]))
if isinstance(releases, dict): releases = [releases]
for release in releases:
    if release.get('draft') or bool(release.get('prerelease')) != (sys.argv[2] == 'beta'): continue
    assets = release.get('assets', [])
    for asset in assets:
        name = asset['name']
        if not name.startswith('scrapefun-server-linux-amd64-') or not name.endswith('-' + sys.argv[2] + '.tar.gz'): continue
        checksums = [a for a in assets if a['name'] == name + '.sha256'] or [a for a in assets if a['name'] == 'SHA256SUMS']
        if not checksums: continue
        for url in [asset['browser_download_url'], checksums[0]['browser_download_url']]:
            if urlparse(url).scheme != 'https': raise SystemExit('Invalid release URL')
            print(url)
        print(name)
        raise SystemExit(0)
raise SystemExit('No matching native release available; existing installation was not changed')
PY
  mapfile -t assets < "$stage/asset.txt"
  archive="$stage/release.tar.gz"
  checksum="$archive.sha256"
  printf '下载原生发布包（文件较大，请等待下载进度）…\n'
  download_file "${assets[0]}" "$archive" large
  download_file "${assets[1]}" "$stage/checksums"
  python3 - "$stage/checksums" "${assets[2]}" > "$checksum" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
for line in lines:
    fields = line.split()
    filename = fields[1].lstrip('*') if len(fields) >= 2 else ''
    if filename.startswith('./'): filename = filename[2:]
    if len(fields) >= 2 and filename == sys.argv[2] and re.fullmatch(r'[a-fA-F0-9]{64}', fields[0]):
        print(fields[0]); break
else:
    if len(lines) == 1 and re.fullmatch(r'[a-fA-F0-9]{64}', lines[0].strip()): print(lines[0].strip())
    else: raise SystemExit('Checksum for selected release is missing')
PY
fi
expected="$(awk 'NR==1 {print $1}' "$checksum")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'invalid release checksum'
# The installer verifies the archive before extraction. GPU setup additionally
# checks it before making any changes to the host's graphics dependencies.
export SCRAPEFUN_OPERATION_SOURCE="$stage/operations"
export SCRAPEFUN_START_SOURCE="$stage/release/start-scrapefun-linux-server.sh"
export SCRAPEFUN_NATIVE_CHANNEL="$CHANNEL"
# GPU setup happens before the installer stops or replaces the existing service.
gpu_mode="${SCRAPEFUN_GPU_MODE:-auto}"
[[ "$gpu_mode" == auto || "$gpu_mode" == none || "$gpu_mode" == native || "$gpu_mode" == wsl ]] || fail 'GPU mode must be auto, none, native or wsl'
if [[ "$gpu_mode" == auto ]]; then
  if [[ -c /dev/dxg && -r /usr/lib/wsl/lib/libd3d12.so ]]; then gpu_mode=wsl
  elif [[ -d /dev/dri ]] || { command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; }; then gpu_mode=native
  else gpu_mode=none; fi
fi
mkdir -p "$stage/gpu"
: > "$stage/gpu/vulkan.env"
if [[ -n "${SCRAPEFUN_GPU_MODE+x}" || ! -f "$SCRAPEFUN_CONFIG_DIR/gpu.env" ]]; then
  if [[ "$gpu_mode" != none ]]; then
    printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --strict -
    for file in ensure-comic-gpu-environment.sh setup-wsl-comic-gpu.sh; do fetch_script "$file"; done
    bash "$stage/ensure-comic-gpu-environment.sh" "$gpu_mode" native "$stage/gpu"
  fi
  export SCRAPEFUN_GPU_ENV_FILE="$stage/gpu/vulkan.env"
fi
bash "$stage/release/install-scrapefun-linux-server.sh" "$archive"
}
main "$@"
