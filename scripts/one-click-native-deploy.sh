#!/usr/bin/env bash
set -euo pipefail
# Public release archives carry the protected application; no source build is
# performed on the user's server. Only amd64 is currently published.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CHANNEL="${1:-}"
if [[ -z "$CHANNEL" && -f "${SCRAPEFUN_CONFIG_DIR:-/etc/scrapefun}/management.env" ]]; then
  CHANNEL="$(sed -n 's/^CHANNEL=//p' "${SCRAPEFUN_CONFIG_DIR:-/etc/scrapefun}/management.env" | tail -n 1)"
fi
CHANNEL="${CHANNEL:-stable}"
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
if [[ "$CHANNEL" == --help || "$CHANNEL" == -h ]]; then
  printf 'Usage: one-click-native-deploy.sh [stable|beta]\nRequires Linux amd64, systemd, Node.js 20/22/24, Python 3, curl and ffmpeg.\nDefaults: /opt/scrapefun, /var/lib/scrapefun, /etc/scrapefun.\nOffline: SCRAPEFUN_NATIVE_ARCHIVE=/path/release.tar.gz (requires adjacent .sha256).\n'
  exit 0
fi
[[ $# -le 1 && ( "$CHANNEL" == stable || "$CHANNEL" == beta ) ]] || fail 'channel must be stable or beta'
[[ $EUID -eq 0 ]] || fail 'native installation requires root; run the command with sudo bash'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'native releases currently support Linux amd64; use Docker for other architectures'
for required in curl python3 sha256sum systemctl flock ffmpeg ffprobe; do command -v "$required" >/dev/null || fail "missing required command: $required"; done
[[ -d /run/systemd/system ]] || fail 'systemd must be running (enable systemd in WSL before installing)'
node_binary="${SCRAPEFUN_NODE_BINARY:-$(command -v node || true)}"
[[ -x "$node_binary" && "$("$node_binary" -p "process.versions.node.split('.')[0]")" =~ ^(20|22|24)$ ]] || fail 'Node.js 20/22/24 is required'
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
source_base="https://raw.githubusercontent.com/${GITHUB_REPO:-HaoweiLi97/ScrapeFun}/${GITHUB_BRANCH:-main}/scripts"
mkdir -p "$stage/operations" "$stage/release"
fetch_script() {
  local relative="$1" target="$stage/$1"
  if [[ -f "$ROOT_DIR/$relative" ]]; then cp "$ROOT_DIR/$relative" "$target"; else
    curl --fail --show-error --location --retry 3 --connect-timeout 20 -o "$target" "$source_base/$relative"
  fi
}
printf '准备 Linux 原生安装工具…\n'
for file in operations/scrapefun.sh operations/linux-server-tools.py release/install-scrapefun-linux-server.sh release/start-scrapefun-linux-server.sh ensure-comic-gpu-environment.sh setup-wsl-comic-gpu.sh; do fetch_script "$file"; done
if [[ -f "$ROOT_DIR/one-click-native-deploy.sh" ]]; then cp "$ROOT_DIR/one-click-native-deploy.sh" "$stage/operations/one-click-native-deploy.sh"; else
  curl -fsSL --retry 3 "$source_base/one-click-native-deploy.sh" -o "$stage/operations/one-click-native-deploy.sh"
fi
if [[ -n "${SCRAPEFUN_NATIVE_ARCHIVE:-}" ]]; then
  archive="$(realpath "$SCRAPEFUN_NATIVE_ARCHIVE")"
  [[ -f "$archive" && -f "$archive.sha256" ]] || fail 'offline release requires archive and adjacent .sha256'
  checksum="$archive.sha256"
else
  release_api="https://api.github.com/repos/${SCRAPEFUN_NATIVE_RELEASE_REPO:-HaoweiLi97/scrapefun-server-linux}/releases"
  printf '查找 %s 发布包…\n' "$CHANNEL"
  if [[ "$CHANNEL" == stable ]]; then release_api+='/latest'; fi
  curl -fsSL --retry 3 "$release_api" -o "$stage/releases.json"
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
  curl --fail --location --progress-bar --retry 3 --connect-timeout 20 -o "$archive" "${assets[0]}"
  curl -fsSL --retry 3 -o "$stage/checksums" "${assets[1]}"
  python3 - "$stage/checksums" "${assets[2]}" > "$checksum" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
for line in lines:
    fields = line.split()
    if len(fields) >= 2 and fields[1].lstrip('*').removeprefix('./') == sys.argv[2] and re.fullmatch(r'[a-fA-F0-9]{64}', fields[0]):
        print(fields[0]); break
else:
    if len(lines) == 1 and re.fullmatch(r'[a-fA-F0-9]{64}', lines[0].strip()): print(lines[0].strip())
    else: raise SystemExit('Checksum for selected release is missing')
PY
fi
expected="$(awk 'NR==1 {print $1}' "$checksum")"
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'invalid release checksum'
# The installer verifies the archive before extraction. Keep one checksum pass
# even for large archives accessed across a Windows/WSL filesystem boundary.
export SCRAPEFUN_OPERATION_SOURCE="$stage/operations"
export SCRAPEFUN_START_SOURCE="$stage/release/start-scrapefun-linux-server.sh"
export SCRAPEFUN_NATIVE_CHANNEL="$CHANNEL"
# GPU setup happens before the installer stops or replaces the existing service.
gpu_mode="${SCRAPEFUN_GPU_MODE:-auto}"
if [[ "$gpu_mode" == auto ]]; then
  if [[ -c /dev/dxg && -r /usr/lib/wsl/lib/libd3d12.so ]]; then gpu_mode=wsl
  elif [[ -d /dev/dri ]] || { command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; }; then gpu_mode=native
  else gpu_mode=none; fi
fi
mkdir -p "$stage/gpu"
: > "$stage/gpu/vulkan.env"
bash "$stage/ensure-comic-gpu-environment.sh" "$gpu_mode" native "$stage/gpu"
export SCRAPEFUN_GPU_ENV_FILE="$stage/gpu/vulkan.env"
bash "$stage/release/install-scrapefun-linux-server.sh" "$archive"
