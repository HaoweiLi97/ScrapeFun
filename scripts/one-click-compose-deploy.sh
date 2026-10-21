#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ACTION="deploy"
MIGRATE_LEGACY_DATA=0

POSITIONAL_ARGS=()
for argument in "$@"; do
  case "$argument" in
    --migrate-data-root) MIGRATE_LEGACY_DATA=1 ;;
    *) POSITIONAL_ARGS+=("$argument") ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  ACTION="$1"
fi

CHANNEL=""
DEPLOY_DIR="${HOME}/scrapefun"
if [[ "${ACTION}" == "-h" || "${ACTION}" == "--help" ]]; then
  :
elif [[ "${1:-}" == "stable" || "${1:-}" == "beta" ]]; then
  CHANNEL="$1"
  DEPLOY_DIR="${2:-${DEPLOY_DIR}}"
elif [[ -n "${1:-}" ]]; then
  DEPLOY_DIR="$1"
fi

COMPOSE_SOURCE="${ROOT_DIR}/docker-compose.remote.yml"
if [[ "$(basename "$SCRIPT_DIR")" == operations && -f "$SCRIPT_DIR/docker-compose.template.yml" ]]; then
  COMPOSE_SOURCE="$SCRIPT_DIR/docker-compose.template.yml"
fi
COMPOSE_TARGET="${DEPLOY_DIR}/docker-compose.remote.yml"
SERVER_ENV_FILE="${DEPLOY_DIR}/server.env"
UPDATER_ENV_FILE="${DEPLOY_DIR}/.updater.env"
LEGACY_ENV_FILE="${DEPLOY_DIR}/.env"
DEFAULT_DATA_DIR="${HOME}/scrapefun-data"
REPOSITORY="${REPOSITORY:-haoweil/scrapefun}"
IMAGE_REPOSITORIES="${IMAGE_REPOSITORIES:-$REPOSITORY}"
IMAGE_BUNDLE_REPOSITORY="${IMAGE_BUNDLE_REPOSITORY:-$REPOSITORY}"
IMAGE_BUNDLE_BASE_URL="${IMAGE_BUNDLE_BASE_URL:-https://github.com/HaoweiLi97/scrapefun-desktop-macos/releases/latest/download}"
IMAGE_BUNDLE_URL="${IMAGE_BUNDLE_URL:-}"
SCRAPEFUN_SKIP_IMAGE_BUNDLE="${SCRAPEFUN_SKIP_IMAGE_BUNDLE:-0}"
GITHUB_REPO="${GITHUB_REPO:-HaoweiLi97/ScrapeFun}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
COMPOSE_URL="${COMPOSE_URL:-https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/docker-compose.remote.yml}"
COMPOSE_API_URL="${COMPOSE_API_URL:-https://api.github.com/repos/${GITHUB_REPO}/contents/docker-compose.remote.yml?ref=${GITHUB_BRANCH}}"
OPERATIONS_DIR="${DEPLOY_DIR}/operations"
APP_HOST_PORT="${APP_HOST_PORT:-}"
SCRAPEFUN_DATA_DIR="${SCRAPEFUN_DATA_DIR:-}"
NVIDIA_VISIBLE_DEVICES_WAS_SET="${NVIDIA_VISIBLE_DEVICES+x}"
NVIDIA_DRIVER_CAPABILITIES_WAS_SET="${NVIDIA_DRIVER_CAPABILITIES+x}"
SCRAPEFUN_DRI_DEVICE_WAS_SET="${SCRAPEFUN_DRI_DEVICE+x}"
SCRAPEFUN_GPU_MODE="${SCRAPEFUN_GPU_MODE:-}"
SCRAPEFUN_GPU_MODE_REQUESTED="${SCRAPEFUN_GPU_MODE_REQUESTED:-}"
SCRAPEFUN_DRI_DEVICE="${SCRAPEFUN_DRI_DEVICE:-}"
NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES:-all}"
NVIDIA_DRIVER_CAPABILITIES="${NVIDIA_DRIVER_CAPABILITIES:-compute,utility,video,graphics}"
SCRAPEFUN_WSL_VULKAN_PREFIX="${SCRAPEFUN_WSL_VULKAN_PREFIX:-}"
SCRAPEFUN_WSL_GPU_ADAPTER="${SCRAPEFUN_WSL_GPU_ADAPTER:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage:
  ./scripts/one-click-compose-deploy.sh [stable|beta] [deploy_dir]

Examples:
  ./scripts/one-click-compose-deploy.sh
  ./scripts/one-click-compose-deploy.sh beta
  ./scripts/one-click-compose-deploy.sh stable /opt/scrapefun

Environment variables:
  IMAGE_REPOSITORIES       Space or comma separated image repositories to try.
                           Example: "haoweil/scrapefun registry.example.com/scrapefun"
  IMAGE_BUNDLE_BASE_URL    Base URL for GitHub Release docker load bundles.
  IMAGE_BUNDLE_URL         Exact docker load bundle URL. Overrides IMAGE_BUNDLE_BASE_URL.
  SCRAPEFUN_SKIP_IMAGE_BUNDLE=1
                           Disable offline bundle fallback.
  SCRAPEFUN_GPU_MODE       GPU passthrough mode for video decode/transcode and image processing.
                           Options:
                             auto    detect NVIDIA or one DRI render node; otherwise use CPU
                             none    no GPU passthrough
                             dri     Intel / AMD / most NAS via one DRI render node
                             amd     deprecated alias for dri (does not expose /dev/kfd)
                             nvidia  gpus: all for NVIDIA Container Toolkit
                             wsl     WSL2 /dev/dxg with automatically installed isolated Vulkan
  SCRAPEFUN_DRI_DEVICE     DRI render node, for example /dev/dri/renderD128.
                           Use 'all' only when a NAS requires the complete /dev/dri directory.
  NVIDIA_VISIBLE_DEVICES   NVIDIA device index/UUID list (default: all).
  NVIDIA_DRIVER_CAPABILITIES
                           Must include video and graphics (default: compute,utility,video,graphics).
  --migrate-data-root      After a legacy mount is detected, stop the old app,
                           copy its complete /app/data view, verify conflicts,
                           and then switch to the root bind mount.

Notes:
  - default port is 8096
  - new deployments auto-detect GPU passthrough; set SCRAPEFUN_GPU_MODE=none to disable it
  - script preserves existing channel, host port, data dir, and GPU selection on updates
  - if docker pull fails, the script will try an arch-matched offline image bundle
EOF
}

if [[ "${ACTION}" == "-h" || "${ACTION}" == "--help" || "${CHANNEL}" == "-h" || "${CHANNEL}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${CHANNEL}" && "${CHANNEL}" != "stable" && "${CHANNEL}" != "beta" ]]; then
  echo -e "${RED}Error: channel must be 'stable' or 'beta'.${NC}"
  usage
  exit 1
fi

read_env_value() {
  local key="$1"
  local file="$2"

  if [[ ! -f "${file}" ]]; then
    return
  fi

  sed -n "s/^${key}=//p" "${file}" | tail -n 1
}

print_permission_help() {
  local path="$1"
  local chown_paths="${DEPLOY_DIR}"

  if [[ -n "${SCRAPEFUN_DATA_DIR:-}" ]]; then
    chown_paths="${chown_paths} ${SCRAPEFUN_DATA_DIR}"
  fi

  echo -e "${RED}Error: cannot write ${path}.${NC}"
  echo -e "${RED}The deployment directory may be owned by root from an earlier sudo run.${NC}"
  echo -e "Fix permissions, then run this script again:"
  echo -e "  ${YELLOW}sudo chown -R $(id -u):$(id -g) ${chown_paths}${NC}"
}

upsert_env_value() {
  local key="$1"
  local value="$2"
  local file="$3"
  local current_value
  current_value="$(read_env_value "${key}" "${file}")"

  if [[ "${current_value}" == "${value}" ]]; then
    return
  fi

  if [[ ! -w "${file}" ]]; then
    print_permission_help "${file}"
    exit 1
  fi

  if grep -q "^${key}=" "${file}"; then
    local escaped_value
    escaped_value="$(printf '%s' "${value}" | sed 's/[&/\]/\\&/g')"
    sed -i.bak "s/^${key}=.*/${key}=${escaped_value}/" "${file}"
    rm -f "${file}.bak"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

resolve_channel() {
  if [[ -n "${CHANNEL}" ]]; then
    return
  fi

  if [[ -f "${UPDATER_ENV_FILE}" ]]; then
    local existing_tag
    existing_tag="$(read_env_value "UPDATE_CURRENT_TAG" "${UPDATER_ENV_FILE}")"
    if [[ "${existing_tag}" == "beta" ]]; then
      CHANNEL="beta"
      return
    fi
  fi

  CHANNEL="stable"
}

replace_file_if_changed() {
  local tmp_file="$1"
  local target_file="$2"

  if [[ -f "${target_file}" ]] && cmp -s "${tmp_file}" "${target_file}"; then
    rm -f "${tmp_file}"
    return
  fi

  if ! mv "${tmp_file}" "${target_file}" 2>/dev/null; then
    rm -f "${tmp_file}"
    print_permission_help "${target_file}"
    exit 1
  fi
}

create_deploy_tmp_file() {
  local prefix="$1"
  local tmp_file

  tmp_file="$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX")" || {
    echo -e "${RED}Error: failed to create a temporary file.${NC}"
    exit 1
  }

  printf '%s\n' "${tmp_file}"
}

download_file() {
  local url="$1"
  local target="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL "${url}" -o "${target}"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "${target}" "${url}"
    return
  fi

  echo -e "${RED}Error: curl or wget is required to download ${url}.${NC}"
  exit 1
}

if ! command -v docker >/dev/null 2>&1; then
  echo -e "${RED}Error: docker is not installed.${NC}"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}Error: docker is not running.${NC}"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo -e "${RED}Error: docker compose is not available.${NC}"
  exit 1
fi

mkdir -p "${DEPLOY_DIR}"
if [[ -f "${COMPOSE_TARGET}" || -f "${UPDATER_ENV_FILE}" ]]; then
  ACTION="update"
fi
resolve_channel

download_compose() {
  local tmp_file
  tmp_file="$(create_deploy_tmp_file ".docker-compose.remote.yml.tmp")"

  if [[ -f "${COMPOSE_SOURCE}" ]]; then
    cp "${COMPOSE_SOURCE}" "${tmp_file}" || {
      rm -f "${tmp_file}"
      print_permission_help "${DEPLOY_DIR}"
      exit 1
    }
    replace_file_if_changed "${tmp_file}" "${COMPOSE_TARGET}"
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "${COMPOSE_URL}" -o "${tmp_file}"; then
      replace_file_if_changed "${tmp_file}" "${COMPOSE_TARGET}"
      return
    fi
    rm -f "${tmp_file}"
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO "${tmp_file}" "${COMPOSE_URL}"; then
      replace_file_if_changed "${tmp_file}" "${COMPOSE_TARGET}"
      return
    fi
    rm -f "${tmp_file}"
  fi

  if command -v python3 >/dev/null 2>&1; then
    if python3 - "${COMPOSE_API_URL}" "${tmp_file}" <<'PY'
import base64
import json
import sys
import urllib.request

url = sys.argv[1]
target = sys.argv[2]

with urllib.request.urlopen(url) as response:
    payload = json.load(response)

content = base64.b64decode(payload["content"])
with open(target, "wb") as file:
    file.write(content)
PY
    then
      replace_file_if_changed "${tmp_file}" "${COMPOSE_TARGET}"
      return
    fi
    rm -f "${tmp_file}"
  fi

  echo -e "${RED}Error: failed to download docker-compose.remote.yml from GitHub.${NC}"
  echo -e "${RED}Tried raw URL: ${COMPOSE_URL}${NC}"
  echo -e "${RED}Tried API URL: ${COMPOSE_API_URL}${NC}"
  echo -e "${RED}Install curl, wget, or python3 and try again.${NC}"
  exit 1
}

install_operation_scripts() {
  local operation_file
  mkdir -p "${OPERATIONS_DIR}"
  # Keep a pristine template for installed updates. The deployment's rendered
  # Compose file no longer contains the GPU marker and cannot be reused as input.
  cp "${COMPOSE_TARGET}" "${OPERATIONS_DIR}/docker-compose.template.yml"
  for operation_file in \
    docker-operations-common.sh \
    migrate-docker-data-root.sh \
    backup-docker.sh \
    restore-docker.sh \
    prune-docker-backups.sh \
    drill-docker-backup.sh \
    install-docker-backup-timer.sh \
    scrapefun.sh; do
    local tmp_file
    tmp_file="$(create_deploy_tmp_file ".${operation_file}.tmp")"
    if [[ -f "${ROOT_DIR}/scripts/operations/${operation_file}" ]]; then
      cp "${ROOT_DIR}/scripts/operations/${operation_file}" "${tmp_file}"
    else
      download_file \
        "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/operations/${operation_file}" \
        "${tmp_file}"
    fi
    chmod 755 "${tmp_file}"
    replace_file_if_changed "${tmp_file}" "${OPERATIONS_DIR}/${operation_file}"
    chmod 755 "${OPERATIONS_DIR}/${operation_file}"
  done
  cp "${OPERATIONS_DIR}/scrapefun.sh" "${DEPLOY_DIR}/scrapefun"
  chmod 755 "${DEPLOY_DIR}/scrapefun"
  local deploy_script_tmp
  deploy_script_tmp="$(create_deploy_tmp_file '.one-click-compose-deploy.sh.tmp')"
  if [[ -f "${ROOT_DIR}/scripts/one-click-compose-deploy.sh" ]]; then
    cp "${ROOT_DIR}/scripts/one-click-compose-deploy.sh" "$deploy_script_tmp"
  else
    download_file "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/one-click-compose-deploy.sh" "$deploy_script_tmp"
  fi
  replace_file_if_changed "$deploy_script_tmp" "${OPERATIONS_DIR}/one-click-compose-deploy.sh"
  chmod 755 "${OPERATIONS_DIR}/one-click-compose-deploy.sh"
  for operation_file in ensure-comic-gpu-environment.sh setup-wsl-comic-gpu.sh; do
    if [[ -f "${SCRIPT_DIR}/${operation_file}" ]]; then
      cp "${SCRIPT_DIR}/${operation_file}" "${OPERATIONS_DIR}/${operation_file}"
    else
      download_file "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/${operation_file}" "${OPERATIONS_DIR}/${operation_file}"
    fi
    chmod 755 "${OPERATIONS_DIR}/${operation_file}"
  done
}

render_compose_with_gpu_mode() {
  local tmp_file
  local marker_found=0
  local wsl_markers=0
  tmp_file="$(create_deploy_tmp_file ".docker-compose.remote.rendered.yml.tmp")"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    if [[ "${line}" == "    # __APP_GPU_BLOCK__" ]]; then
      marker_found=1
      case "${SCRAPEFUN_GPU_MODE}" in
        none)
          printf '%s\n' "    # GPU passthrough disabled" >> "${tmp_file}"
          ;;
        dri)
          if [[ "${SCRAPEFUN_DRI_DEVICE}" == "all" ]]; then
            cat >> "${tmp_file}" <<'EOF'
    devices:
      - /dev/dri:/dev/dri
EOF
          else
            cat >> "${tmp_file}" <<EOF
    devices:
      - ${SCRAPEFUN_DRI_DEVICE}:${SCRAPEFUN_DRI_DEVICE}
EOF
          fi
          ;;
        nvidia)
          printf '%s\n' "    gpus: all" >> "${tmp_file}"
          ;;
        wsl)
          printf '%s\n' '    devices:' '      - /dev/dxg:/dev/dxg' >> "${tmp_file}"
          ;;
      esac
      continue
    fi
    if [[ "$line" == '      # __APP_GPU_ENV__' && "$SCRAPEFUN_GPU_MODE" == wsl ]]; then
      wsl_markers=$((wsl_markers + 1))
      cat >> "$tmp_file" <<EOF
      - LD_LIBRARY_PATH=${SCRAPEFUN_WSL_VULKAN_PREFIX}/lib/x86_64-linux-gnu:/usr/lib/wsl/lib
      - VK_ICD_FILENAMES=${SCRAPEFUN_WSL_VULKAN_PREFIX}/share/vulkan/icd.d/dzn_icd.x86_64.json
      - MESA_D3D12_DEFAULT_ADAPTER_NAME=${SCRAPEFUN_WSL_GPU_ADAPTER}
      - IMAGE_UPSCALE_GPU_FALLBACK_POLICY=strict
EOF
      continue
    fi
    if [[ "$line" == '      # __APP_GPU_VOLUMES__' && "$SCRAPEFUN_GPU_MODE" == wsl ]]; then
      wsl_markers=$((wsl_markers + 1))
      printf '      - /usr/lib/wsl:/usr/lib/wsl:ro\n      - %s:%s:ro\n' "$SCRAPEFUN_WSL_VULKAN_PREFIX" "$SCRAPEFUN_WSL_VULKAN_PREFIX" >> "$tmp_file"
      continue
    fi
    printf '%s\n' "${line}" >> "${tmp_file}"
  done < "${COMPOSE_TARGET}"

  if [[ "${marker_found}" -ne 1 || ( "$SCRAPEFUN_GPU_MODE" == wsl && "$wsl_markers" -ne 2 ) ]]; then
    rm -f "${tmp_file}"
    echo -e "${RED}Error: compose template GPU marker not found.${NC}"
    exit 1
  fi

  replace_file_if_changed "${tmp_file}" "${COMPOSE_TARGET}"
}

resolve_app_host_port() {
  if [[ -n "${APP_HOST_PORT}" ]]; then
    return
  fi

  if [[ -f "${UPDATER_ENV_FILE}" ]]; then
    local existing_port
    existing_port="$(read_env_value "APP_HOST_PORT" "${UPDATER_ENV_FILE}")"
    if [[ -n "${existing_port}" ]]; then
      APP_HOST_PORT="${existing_port}"
      return
    fi
  fi

  APP_HOST_PORT="8096"

  if [[ -t 1 && -r /dev/tty ]]; then
    local requested_port
    printf "Deploy to which host port? [8096]: " > /dev/tty
    IFS= read -r requested_port < /dev/tty || true
    requested_port="${requested_port//$'\r'/}"
    requested_port="${requested_port//[[:space:]]/}"
    requested_port="${requested_port:-8096}"

    if [[ ! "${requested_port}" =~ ^[0-9]+$ ]] || (( requested_port < 1 || requested_port > 65535 )); then
      echo -e "${RED}Error: port must be a number between 1 and 65535.${NC}"
      exit 1
    fi

    APP_HOST_PORT="${requested_port}"
  fi
}

resolve_data_dir() {
  if [[ -n "${SCRAPEFUN_DATA_DIR}" ]]; then
    return
  fi

  if [[ -f "${UPDATER_ENV_FILE}" ]]; then
    local existing_data_dir
    existing_data_dir="$(read_env_value "SCRAPEFUN_DATA_DIR" "${UPDATER_ENV_FILE}")"
    if [[ -n "${existing_data_dir}" ]]; then
      SCRAPEFUN_DATA_DIR="${existing_data_dir}"
      return
    fi
  fi

  if [[ -f "${LEGACY_ENV_FILE}" ]]; then
    local legacy_data_dir
    legacy_data_dir="$(read_env_value "SCRAPEFUN_DATA_DIR" "${LEGACY_ENV_FILE}")"
    if [[ -n "${legacy_data_dir}" ]]; then
      SCRAPEFUN_DATA_DIR="${legacy_data_dir}"
      return
    fi
  fi

  SCRAPEFUN_DATA_DIR="${DEFAULT_DATA_DIR}"
}

normalize_gpu_mode() {
  local raw
  raw="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${raw}" in
    auto)
      echo "auto"
      ;;
    none|off|cpu)
      echo "none"
      ;;
    dri|intel|igpu|intel-amd|intel_amd)
      echo "dri"
      ;;
    amd|rocm|kfd)
      echo "dri"
      ;;
    nvidia|cuda)
      echo "nvidia"
      ;;
    wsl|dxg) echo wsl ;;
    *)
      echo -e "${RED}Error: unsupported GPU mode: ${1}${NC}" >&2
      echo -e "${RED}Supported values: auto, none, dri, amd, nvidia, wsl${NC}" >&2
      exit 1
      ;;
  esac
}

find_first_dri_render_node() {
  local candidate
  for candidate in /dev/dri/renderD*; do
    if [[ -c "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

host_has_nvidia_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    return 0
  fi
  if [[ -d /proc/driver/nvidia/gpus ]] && find /proc/driver/nvidia/gpus -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

host_has_wsl_gpu() {
  [[ -c /dev/dxg && -r /usr/lib/wsl/lib/libd3d12.so ]]
}

resolve_auto_gpu_mode() {
  local detected_dri_device=""

  if host_has_wsl_gpu; then
    SCRAPEFUN_GPU_MODE=wsl
    echo 'Auto-detected WSL2 GPU; checking the comic Vulkan environment.'
    return
  fi

  if host_has_nvidia_gpu; then
    SCRAPEFUN_GPU_MODE="nvidia"
    echo -e "${GREEN}Auto-detected NVIDIA GPU support.${NC}"
    return
  fi

  detected_dri_device="$(find_first_dri_render_node || true)"
  if [[ -n "${detected_dri_device}" ]]; then
    SCRAPEFUN_GPU_MODE="dri"
    if [[ -z "${SCRAPEFUN_DRI_DEVICE_WAS_SET}" ]]; then
      SCRAPEFUN_DRI_DEVICE="${detected_dri_device}"
    else
      SCRAPEFUN_DRI_DEVICE="${SCRAPEFUN_DRI_DEVICE:-${detected_dri_device}}"
    fi
    echo -e "${GREEN}Auto-detected DRI render node: ${SCRAPEFUN_DRI_DEVICE}.${NC}"
    return
  fi

  SCRAPEFUN_GPU_MODE="none"
  SCRAPEFUN_DRI_DEVICE=""
  echo -e "${YELLOW}No supported GPU passthrough was detected; using CPU mode.${NC}"
}

resolve_dri_device() {
  if [[ "${SCRAPEFUN_GPU_MODE}" != "dri" ]]; then
    SCRAPEFUN_DRI_DEVICE=""
    return
  fi

  if [[ -z "${SCRAPEFUN_DRI_DEVICE}" ]]; then
    SCRAPEFUN_DRI_DEVICE="$(find_first_dri_render_node || true)"
  fi

  if [[ "${SCRAPEFUN_DRI_DEVICE}" == "all" ]]; then
    if [[ ! -d /dev/dri ]]; then
      echo -e "${RED}Error: SCRAPEFUN_DRI_DEVICE=all was requested, but /dev/dri does not exist.${NC}"
      exit 1
    fi
    return
  fi

  if [[ ! "${SCRAPEFUN_DRI_DEVICE}" =~ ^/dev/dri/renderD[0-9]+$ ]]; then
    echo -e "${RED}Error: SCRAPEFUN_DRI_DEVICE must be /dev/dri/renderD<number> or 'all'.${NC}"
    exit 1
  fi
  if [[ ! -c "${SCRAPEFUN_DRI_DEVICE}" ]]; then
    echo -e "${RED}Error: DRI render node does not exist or is not a character device: ${SCRAPEFUN_DRI_DEVICE}.${NC}"
    echo -e "${RED}Available nodes: $(find /dev/dri -maxdepth 1 -name 'renderD*' -print 2>/dev/null | tr '\n' ' ')${NC}"
    exit 1
  fi
}

validate_nvidia_settings() {
  [[ "${SCRAPEFUN_GPU_MODE}" == "nvidia" ]] || return 0

  if [[ ! "${NVIDIA_VISIBLE_DEVICES}" =~ ^[A-Za-z0-9_,.-]+$ ]]; then
    echo -e "${RED}Error: NVIDIA_VISIBLE_DEVICES must be 'all' or a comma-separated list of GPU indices/UUIDs.${NC}"
    exit 1
  fi

  local compact_capabilities
  compact_capabilities="$(printf '%s' "${NVIDIA_DRIVER_CAPABILITIES}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  if [[ ! ",${compact_capabilities}," =~ ,video, ]] || [[ ! ",${compact_capabilities}," =~ ,graphics, ]]; then
    echo -e "${RED}Error: NVIDIA_DRIVER_CAPABILITIES must include both 'video' and 'graphics'.${NC}"
    echo -e "${RED}'video' is required for transcoding; 'graphics' is required for Vulkan/NCNN image enhancement.${NC}"
    exit 1
  fi
  NVIDIA_DRIVER_CAPABILITIES="${compact_capabilities}"
}

load_saved_gpu_settings() {
  [[ -f "${UPDATER_ENV_FILE}" ]] || return 0
  SCRAPEFUN_WSL_VULKAN_PREFIX="${SCRAPEFUN_WSL_VULKAN_PREFIX:-$(read_env_value SCRAPEFUN_WSL_VULKAN_PREFIX "$UPDATER_ENV_FILE")}"
  SCRAPEFUN_WSL_GPU_ADAPTER="${SCRAPEFUN_WSL_GPU_ADAPTER:-$(read_env_value SCRAPEFUN_WSL_GPU_ADAPTER "$UPDATER_ENV_FILE")}"

  if [[ -z "${SCRAPEFUN_DRI_DEVICE}" ]]; then
    SCRAPEFUN_DRI_DEVICE="$(read_env_value "SCRAPEFUN_DRI_DEVICE" "${UPDATER_ENV_FILE}")"
  fi
  if [[ -z "${NVIDIA_VISIBLE_DEVICES_WAS_SET}" ]]; then
    NVIDIA_VISIBLE_DEVICES="$(read_env_value "NVIDIA_VISIBLE_DEVICES" "${UPDATER_ENV_FILE}")"
    NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES:-all}"
  fi
  if [[ -z "${NVIDIA_DRIVER_CAPABILITIES_WAS_SET}" ]]; then
    NVIDIA_DRIVER_CAPABILITIES="$(read_env_value "NVIDIA_DRIVER_CAPABILITIES" "${UPDATER_ENV_FILE}")"
    NVIDIA_DRIVER_CAPABILITIES="${NVIDIA_DRIVER_CAPABILITIES:-compute,utility,video,graphics}"
  fi
}

resolve_gpu_mode() {
  local requested_raw=""
  load_saved_gpu_settings

  if [[ -n "${SCRAPEFUN_GPU_MODE}" ]]; then
    requested_raw="${SCRAPEFUN_GPU_MODE}"
  elif [[ -n "${SCRAPEFUN_GPU_MODE_REQUESTED}" ]]; then
    requested_raw="${SCRAPEFUN_GPU_MODE_REQUESTED}"
  elif [[ -f "${UPDATER_ENV_FILE}" ]]; then
    requested_raw="$(read_env_value "SCRAPEFUN_GPU_MODE_REQUESTED" "${UPDATER_ENV_FILE}")"
    if [[ -z "${requested_raw}" ]]; then
      requested_raw="$(read_env_value "SCRAPEFUN_GPU_MODE" "${UPDATER_ENV_FILE}")"
    fi
  fi

  if [[ -n "${requested_raw}" ]]; then
    SCRAPEFUN_GPU_MODE_REQUESTED="$(normalize_gpu_mode "${requested_raw}")"
    if [[ "$(printf '%s' "${requested_raw}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" =~ ^(amd|rocm|kfd)$ ]]; then
      echo -e "${YELLOW}Warning: GPU mode 'amd' is deprecated; using DRI without /dev/kfd.${NC}"
    fi
    if [[ "${SCRAPEFUN_GPU_MODE_REQUESTED}" == "auto" ]]; then
      resolve_auto_gpu_mode
    else
      SCRAPEFUN_GPU_MODE="${SCRAPEFUN_GPU_MODE_REQUESTED}"
    fi
    resolve_dri_device
    validate_nvidia_settings
    return
  fi

  SCRAPEFUN_GPU_MODE_REQUESTED="auto"

  if [[ -t 1 && -r /dev/tty ]]; then
    local selected
    echo "Choose GPU passthrough mode for hardware video decode/transcode and image processing:" > /dev/tty
    echo "  1) auto   - detect NVIDIA or one DRI render node (recommended)" > /dev/tty
    echo "  2) none   - no GPU passthrough" > /dev/tty
    echo "  3) dri    - Intel / AMD / most NAS via one DRI render node" > /dev/tty
    echo "  4) nvidia - NVIDIA Container Toolkit; limit devices with NVIDIA_VISIBLE_DEVICES" > /dev/tty
    printf "Select GPU mode [1]: " > /dev/tty
    IFS= read -r selected < /dev/tty || true
    selected="${selected//$'\r'/}"
    selected="${selected//[[:space:]]/}"
    case "${selected:-1}" in
      1) SCRAPEFUN_GPU_MODE_REQUESTED="auto" ;;
      2) SCRAPEFUN_GPU_MODE_REQUESTED="none" ;;
      3) SCRAPEFUN_GPU_MODE_REQUESTED="dri" ;;
      4) SCRAPEFUN_GPU_MODE_REQUESTED="nvidia" ;;
      *)
        echo -e "${RED}Error: invalid GPU mode selection.${NC}"
        exit 1
        ;;
    esac
  fi

  if [[ "${SCRAPEFUN_GPU_MODE_REQUESTED}" == "auto" ]]; then
    resolve_auto_gpu_mode
  else
    SCRAPEFUN_GPU_MODE="${SCRAPEFUN_GPU_MODE_REQUESTED}"
  fi
  resolve_dri_device
  validate_nvidia_settings
}

normalize_repository_list() {
  printf '%s\n' "${IMAGE_REPOSITORIES//,/ }"
}

write_server_env_file() {
  local repository="$1"

  if [[ ! -f "${SERVER_ENV_FILE}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      UPDATER_TOKEN="$(openssl rand -hex 24)"
      APP_AUTH_SECRET="$(openssl rand -hex 32)"
    else
      UPDATER_TOKEN="$(date +%s | sha256sum | cut -d' ' -f1 | cut -c1-48)"
      APP_AUTH_SECRET="$(date +%s%N | sha256sum | cut -d' ' -f1)"
    fi

    cat > "${SERVER_ENV_FILE}" <<EOF
NODE_ENV=production
DATABASE_URL=file:/app/data/db/dev.db
SCRAPETAB_UPDATER_TOKEN=${UPDATER_TOKEN}
APP_AUTH_SECRET=${APP_AUTH_SECRET}
UPDATE_REPOSITORY=${repository}
UPDATE_DOCKERHUB_REPO=${repository}
UPDATE_DEFAULT_CHANNEL=${CHANNEL}
EOF
    echo -e "${YELLOW}Created ${SERVER_ENV_FILE}${NC}"
  else
    echo -e "${YELLOW}Keeping existing ${SERVER_ENV_FILE}${NC}"
    if [[ -z "$(read_env_value "APP_AUTH_SECRET" "${SERVER_ENV_FILE}")" && -z "$(read_env_value "JWT_SECRET" "${SERVER_ENV_FILE}")" ]]; then
      if command -v openssl >/dev/null 2>&1; then
        APP_AUTH_SECRET="$(openssl rand -hex 32)"
      else
        APP_AUTH_SECRET="$(date +%s%N | sha256sum | cut -d' ' -f1)"
      fi
      upsert_env_value "APP_AUTH_SECRET" "${APP_AUTH_SECRET}" "${SERVER_ENV_FILE}"
    fi
    upsert_env_value "UPDATE_REPOSITORY" "${repository}" "${SERVER_ENV_FILE}"
    upsert_env_value "UPDATE_DOCKERHUB_REPO" "${repository}" "${SERVER_ENV_FILE}"
    upsert_env_value "UPDATE_DEFAULT_CHANNEL" "${CHANNEL}" "${SERVER_ENV_FILE}"
  fi

  chmod 600 "${SERVER_ENV_FILE}" 2>/dev/null || echo -e "${YELLOW}Warning: could not restrict permissions on ${SERVER_ENV_FILE}.${NC}"
}

write_updater_env_file() {
  local repository="$1"
  local tmp_file
  tmp_file="$(create_deploy_tmp_file ".updater.env.tmp")"

  cat > "${tmp_file}" <<EOF
SCRAPETAB_IMAGE=${repository}:${TAG}
SCRAPETAB_UPDATER_IMAGE=${repository}-updater:${TAG}
UPDATE_CURRENT_TAG=${TAG}
UPDATE_DEFAULT_CHANNEL=${CHANNEL}
UPDATE_REPOSITORY=${repository}
UPDATE_DOCKERHUB_REPO=${repository}
APP_HOST_PORT=${APP_HOST_PORT}
SCRAPEFUN_DATA_DIR=${SCRAPEFUN_DATA_DIR}
SCRAPEFUN_GPU_MODE=${SCRAPEFUN_GPU_MODE}
SCRAPEFUN_GPU_MODE_REQUESTED=${SCRAPEFUN_GPU_MODE_REQUESTED}
SCRAPEFUN_DRI_DEVICE=${SCRAPEFUN_DRI_DEVICE}
NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}
NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES}
SCRAPEFUN_WSL_VULKAN_PREFIX=${SCRAPEFUN_WSL_VULKAN_PREFIX}
SCRAPEFUN_WSL_GPU_ADAPTER=${SCRAPEFUN_WSL_GPU_ADAPTER}
COMPOSE_PROJECT_NAME=scrapefun
EOF

  if [[ -f "${UPDATER_ENV_FILE}" ]] && cmp -s "${tmp_file}" "${UPDATER_ENV_FILE}"; then
    rm -f "${tmp_file}"
    chmod 600 "${UPDATER_ENV_FILE}" 2>/dev/null || echo -e "${YELLOW}Warning: could not restrict permissions on ${UPDATER_ENV_FILE}.${NC}"
    return
  fi

  if ! mv "${tmp_file}" "${UPDATER_ENV_FILE}" 2>/dev/null; then
    rm -f "${tmp_file}"
    print_permission_help "${UPDATER_ENV_FILE}"
    exit 1
  fi
  chmod 600 "${UPDATER_ENV_FILE}" 2>/dev/null || echo -e "${YELLOW}Warning: could not restrict permissions on ${UPDATER_ENV_FILE}.${NC}"
}

remove_legacy_container_if_needed() {
  local container_name="$1"
  local container_id
  container_id="$(docker ps -aq --filter "name=^/${container_name}$" | head -n 1)"

  if [[ -z "${container_id}" ]]; then
    return
  fi

  local project_label
  project_label="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "${container_id}" 2>/dev/null || true)"
  if [[ "${project_label}" == "scrapefun" ]]; then
    return
  fi

  echo -e "${YELLOW}Removing legacy container ${container_name} (${container_id}) before starting Compose services.${NC}"
  docker rm -f "${container_id}" >/dev/null
}

ensure_legacy_data_is_safe() {
  local migration_script="${OPERATIONS_DIR}/migrate-docker-data-root.sh"
  local container_id
  container_id="$(docker ps -aq --filter 'name=^/scrapefun$' | head -n 1)"
  [[ -n "${container_id}" ]] || return 0

  if [[ ! -x "${migration_script}" ]]; then
    echo -e "${RED}Error: Docker data migration helper is missing: ${migration_script}${NC}"
    exit 1
  fi

  local check_status=0
  "${migration_script}" --check --container scrapefun --target "${SCRAPEFUN_DATA_DIR}" || check_status=$?
  if [[ "${check_status}" -eq 0 ]]; then
    return 0
  fi
  if [[ "${check_status}" -ne 2 ]]; then
    echo -e "${RED}Error: unable to verify the existing Docker data layout.${NC}"
    exit 1
  fi

  if [[ "${MIGRATE_LEGACY_DATA}" -ne 1 ]]; then
    echo -e "${RED}Error: the existing container does not use the configured /app/data root mount.${NC}"
    echo -e "${RED}Re-run with --migrate-data-root to copy and verify legacy container data before replacement.${NC}"
    exit 1
  fi

  "${migration_script}" \
    --migrate \
    --container scrapefun \
    --target "${SCRAPEFUN_DATA_DIR}" \
    --manifest "${DEPLOY_DIR}/data-migration-$(date -u +%Y%m%dT%H%M%SZ).sha256" \
    --leave-stopped
}

try_pull_images() {
  local repository
  local pull_failed=1

  for repository in $(normalize_repository_list); do
    [[ -n "${repository}" ]] || continue
    echo -e "${YELLOW}Trying image source: ${repository}:${TAG}${NC}"
    write_updater_env_file "${repository}"

    if docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" pull; then
      SELECTED_REPOSITORY="${repository}"
      return 0
    fi

    pull_failed=1
    echo -e "${YELLOW}Image source failed: ${repository}:${TAG}${NC}"
  done

  return "${pull_failed}"
}

detect_bundle_arch() {
  local machine
  machine="$(uname -m)"

  case "${machine}" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo -e "${RED}Error: unsupported architecture for offline bundle: ${machine}.${NC}" >&2
      return 1
      ;;
  esac
}

resolve_bundle_url() {
  if [[ -n "${IMAGE_BUNDLE_URL}" ]]; then
    printf '%s\n' "${IMAGE_BUNDLE_URL}"
    return
  fi

  local arch
  arch="$(detect_bundle_arch)"
  printf '%s/scrapefun-image-linux-%s-%s.tar.gz\n' "${IMAGE_BUNDLE_BASE_URL%/}" "${arch}" "${CHANNEL}"
}

load_image_bundle() {
  if [[ "${SCRAPEFUN_SKIP_IMAGE_BUNDLE}" == "1" ]]; then
    return 1
  fi

  local bundle_url
  bundle_url="$(resolve_bundle_url)" || return 1

  local bundle_file
  bundle_file="$(create_deploy_tmp_file ".scrapefun-image.tar.gz")"

  echo -e "${YELLOW}Trying offline image bundle: ${bundle_url}${NC}"
  if ! download_file "${bundle_url}" "${bundle_file}"; then
    rm -f "${bundle_file}"
    return 1
  fi

  if ! gzip -dc "${bundle_file}" | docker load; then
    rm -f "${bundle_file}"
    return 1
  fi
  rm -f "${bundle_file}"

  SELECTED_REPOSITORY="${IMAGE_BUNDLE_REPOSITORY}"
  write_updater_env_file "${SELECTED_REPOSITORY}"
  if ! docker image inspect "${SELECTED_REPOSITORY}:${TAG}" >/dev/null 2>&1 \
    || ! docker image inspect "${SELECTED_REPOSITORY}-updater:${TAG}" >/dev/null 2>&1; then
    echo -e "${YELLOW}Offline bundle does not contain both app and updater images for ${TAG}.${NC}"
    return 1
  fi
  return 0
}

validate_compose_configuration() {
  if ! docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" config --quiet; then
    echo -e "${RED}Error: generated Docker Compose configuration is invalid.${NC}"
    if [[ "${SCRAPEFUN_GPU_MODE}" == "nvidia" ]]; then
      echo -e "${RED}Confirm that Docker Compose supports the 'gpus' service field and NVIDIA Container Toolkit is installed.${NC}"
    fi
    exit 1
  fi
}

gpu_preflight_container_script() {
  cat <<'EOF'
set -eu

if [ "$(id -u)" != "1000" ]; then
  echo "entrypoint did not drop privileges to UID 1000" >&2
  exit 10
fi

if [ "${SCRAPEFUN_PREFLIGHT_DRI_DEVICE:-}" = "all" ]; then
  render_node="$(find /dev/dri -maxdepth 1 -name 'renderD*' -print -quit 2>/dev/null || true)"
  [ -n "$render_node" ] || { echo "no DRI render node is visible" >&2; exit 11; }
elif [ -n "${SCRAPEFUN_PREFLIGHT_DRI_DEVICE:-}" ]; then
  render_node="$SCRAPEFUN_PREFLIGHT_DRI_DEVICE"
  [ -c "$render_node" ] || { echo "selected DRI render node is not visible: $render_node" >&2; exit 12; }
  [ -r "$render_node" ] && [ -w "$render_node" ] || { echo "UID 1000 cannot read/write $render_node" >&2; exit 13; }
fi

export XDG_RUNTIME_DIR=/tmp/scrapefun-vulkan-runtime
mkdir -p "$XDG_RUNTIME_DIR"
vulkaninfo --summary > /tmp/scrapefun-vulkan-summary.txt 2>&1 || {
  cat /tmp/scrapefun-vulkan-summary.txt >&2
  echo "vulkaninfo failed" >&2
  exit 14
}
cat /tmp/scrapefun-vulkan-summary.txt

if ! grep -Eiq 'deviceType.*(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU)' /tmp/scrapefun-vulkan-summary.txt; then
  echo "no hardware Vulkan device was found (software Vulkan is not accepted)" >&2
  exit 15
fi

if [ "${SCRAPEFUN_PREFLIGHT_NVIDIA:-0}" = "1" ]; then
  nvidia-smi -L || { echo "nvidia-smi could not enumerate the selected NVIDIA device" >&2; exit 16; }
  grep -Eiq 'deviceName.*NVIDIA' /tmp/scrapefun-vulkan-summary.txt || {
    echo "Vulkan did not enumerate an NVIDIA hardware device; ensure NVIDIA_DRIVER_CAPABILITIES includes graphics" >&2
    exit 17
  }
fi

waifu_bin=/app/server/vendor/linux/waifu2x-ncnn-vulkan-20250915-linux/waifu2x-ncnn-vulkan
waifu_models=/app/server/models/models-upconv_7_anime_style_art_rgb
waifu_input=/app/public/comic-backgrounds/woodBG1-thumb.webp
[ -x "$waifu_bin" ] || { echo "waifu2x NCNN binary is missing" >&2; exit 18; }
[ -d "$waifu_models" ] || { echo "waifu2x model directory is missing" >&2; exit 19; }
[ -f "$waifu_input" ] || { echo "waifu2x smoke-test image is missing" >&2; exit 20; }

if command -v timeout >/dev/null 2>&1; then
  timeout 60 "$waifu_bin" -i "$waifu_input" -o /tmp/scrapefun-waifu2x-output.webp \
    -s 2 -n -1 -m "$waifu_models" -t 64 -j 1:1:1 -g 0
else
  "$waifu_bin" -i "$waifu_input" -o /tmp/scrapefun-waifu2x-output.webp \
    -s 2 -n -1 -m "$waifu_models" -t 64 -j 1:1:1 -g 0
fi
[ -s /tmp/scrapefun-waifu2x-output.webp ] || { echo "waifu2x NCNN smoke test produced no output" >&2; exit 21; }
# Exercise the same five engine capability tests as the app settings page.
node <<'JS'
const { imageUpscaleService } = require('/app/server/dist/services/image-upscale.service.js');
imageUpscaleService.getRuntimeReport(true, 0).then(report => {
  const failed = report.engines.filter(engine => engine.available && !engine.test?.passed);
  console.log(JSON.stringify({ hardwareAvailable: report.hardwareAvailable, device: report.selectedDevice,
    engines: report.engines.map(engine => ({ id: engine.id, available: engine.available, passed: engine.test?.passed })) }));
  process.exit(report.hardwareAvailable && report.supported && !failed.length ? 0 : 22);
}).catch(error => { console.error(error); process.exit(22); });
JS
EOF
}

run_gpu_preflight() {
  [[ "${SCRAPEFUN_GPU_MODE}" != "none" ]] || return 0

  local image_ref="${SELECTED_REPOSITORY}:${TAG}"
  local output_file
  local status=0
  local -a docker_args=(run --rm --init --security-opt no-new-privileges:true)
  output_file="$(create_deploy_tmp_file ".gpu-preflight.log")"

  case "${SCRAPEFUN_GPU_MODE}" in
    dri)
      if [[ "${SCRAPEFUN_DRI_DEVICE}" == "all" ]]; then
        docker_args+=(--device /dev/dri:/dev/dri -e SCRAPEFUN_PREFLIGHT_DRI_DEVICE=all)
      else
        docker_args+=(--device "${SCRAPEFUN_DRI_DEVICE}:${SCRAPEFUN_DRI_DEVICE}" -e "SCRAPEFUN_PREFLIGHT_DRI_DEVICE=${SCRAPEFUN_DRI_DEVICE}")
      fi
      ;;
    nvidia)
      docker_args+=(
        --gpus all
        -e "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}"
        -e "NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES}"
        -e SCRAPEFUN_PREFLIGHT_NVIDIA=1
      )
      ;;
    wsl)
      docker_args+=(--device /dev/dxg:/dev/dxg
        --mount type=bind,src=/usr/lib/wsl,dst=/usr/lib/wsl,readonly
        --mount "type=bind,src=$SCRAPEFUN_WSL_VULKAN_PREFIX,dst=$SCRAPEFUN_WSL_VULKAN_PREFIX,readonly"
        -e "LD_LIBRARY_PATH=$SCRAPEFUN_WSL_VULKAN_PREFIX/lib/x86_64-linux-gnu:/usr/lib/wsl/lib"
        -e "VK_ICD_FILENAMES=$SCRAPEFUN_WSL_VULKAN_PREFIX/share/vulkan/icd.d/dzn_icd.x86_64.json"
        -e "MESA_D3D12_DEFAULT_ADAPTER_NAME=$SCRAPEFUN_WSL_GPU_ADAPTER")
      ;;
  esac

  echo -e "${YELLOW}Running container GPU preflight (Vulkan + Waifu2x NCNN)...${NC}"
  docker_args+=("${image_ref}" /bin/sh -c "$(gpu_preflight_container_script)")
  if command -v timeout >/dev/null 2>&1; then
    timeout 240 docker "${docker_args[@]}" > "${output_file}" 2>&1 || status=$?
  else
    docker "${docker_args[@]}" > "${output_file}" 2>&1 || status=$?
  fi

  if [[ "${status}" -eq 0 ]]; then
    rm -f "${output_file}"
    echo -e "${GREEN}GPU preflight passed for ${SCRAPEFUN_GPU_MODE}.${NC}"
    return 0
  fi

  echo -e "${RED}GPU preflight failed for ${SCRAPEFUN_GPU_MODE} (exit ${status}).${NC}"
  sed -n '1,160p' "${output_file}" >&2
  rm -f "${output_file}"
  return 1
}

handle_gpu_preflight_failure() {
  if [[ "${SCRAPEFUN_GPU_MODE_REQUESTED}" == "auto" ]]; then
    echo -e "${YELLOW}Automatic GPU setup was not usable; continuing in CPU mode.${NC}"
    SCRAPEFUN_GPU_MODE="none"
    SCRAPEFUN_DRI_DEVICE=""
    download_compose
    render_compose_with_gpu_mode
    write_updater_env_file "${SELECTED_REPOSITORY}"
    validate_compose_configuration
    return 0
  fi

  echo -e "${RED}Error: explicit GPU configuration failed validation; deployment was not started.${NC}"
  echo -e "${RED}Fix the device/runtime settings, use SCRAPEFUN_GPU_MODE=auto, or explicitly select none.${NC}"
  exit 1
}

resolve_app_host_port
resolve_data_dir
resolve_gpu_mode
download_compose
install_operation_scripts
if [[ "$SCRAPEFUN_GPU_MODE" != none ]]; then
  SCRAPEFUN_WSL_VULKAN_PREFIX="${SCRAPEFUN_WSL_VULKAN_PREFIX:-/opt/scrapefun-wsl-vulkan/mesa-26.1.4}"
  SCRAPEFUN_WSL_GPU_ADAPTER="${SCRAPEFUN_WSL_GPU_ADAPTER:-NVIDIA}"
  export SCRAPEFUN_WSL_VULKAN_PREFIX SCRAPEFUN_WSL_GPU_ADAPTER
  if ! bash "$OPERATIONS_DIR/ensure-comic-gpu-environment.sh" "$SCRAPEFUN_GPU_MODE" docker "$DEPLOY_DIR/wsl-gpu"; then
    echo 'GPU environment setup failed; deployment stopped before starting or replacing app containers.' >&2
    exit 1
  fi
fi
render_compose_with_gpu_mode

mkdir -p \
  "${SCRAPEFUN_DATA_DIR}/db" \
  "${SCRAPEFUN_DATA_DIR}/images" \
  "${SCRAPEFUN_DATA_DIR}/user-avatars" \
  "${SCRAPEFUN_DATA_DIR}/config" \
  "${SCRAPEFUN_DATA_DIR}/custom-scrapers" \
  "${SCRAPEFUN_DATA_DIR}/local-subtitles" \
  "${SCRAPEFUN_DATA_DIR}/book-cache" \
  "${SCRAPEFUN_DATA_DIR}/book-tts-cache" \
  "${SCRAPEFUN_DATA_DIR}/comic-cache" \
  "${SCRAPEFUN_DATA_DIR}/image-cache" \
  "${SCRAPEFUN_DATA_DIR}/video-proxy-cache" \
  "${SCRAPEFUN_DATA_DIR}/transcode-cache" \
  "${SCRAPEFUN_DATA_DIR}/image-upscale-cache" \
  "${SCRAPEFUN_DATA_DIR}/models" \
  "${SCRAPEFUN_DATA_DIR}/logs" \
  "${SCRAPEFUN_DATA_DIR}/cache" \
  "${SCRAPEFUN_DATA_DIR}/temp"

TAG="latest"
if [[ "${CHANNEL}" == "beta" ]]; then
  TAG="beta"
fi

SELECTED_REPOSITORY="${REPOSITORY}"
write_server_env_file "${SELECTED_REPOSITORY}"
write_updater_env_file "${SELECTED_REPOSITORY}"
validate_compose_configuration

echo -e "${GREEN}========================================${NC}"
if [[ "${ACTION}" == "update" ]]; then
  echo -e "${GREEN}ScrapeFun Compose Update${NC}"
else
  echo -e "${GREEN}ScrapeFun Compose Deploy${NC}"
fi
echo -e "${GREEN}========================================${NC}"
echo -e "Action: ${YELLOW}${ACTION}${NC}"
echo -e "Channel: ${YELLOW}${CHANNEL}${NC}"
echo -e "Image sources: ${YELLOW}${IMAGE_REPOSITORIES}${NC}"
echo -e "Host port: ${YELLOW}${APP_HOST_PORT}${NC}"
echo -e "Data dir: ${YELLOW}${SCRAPEFUN_DATA_DIR}${NC}"
echo -e "GPU request: ${YELLOW}${SCRAPEFUN_GPU_MODE_REQUESTED}${NC}"
echo -e "GPU effective mode: ${YELLOW}${SCRAPEFUN_GPU_MODE}${NC}"
if [[ "${SCRAPEFUN_GPU_MODE}" == "dri" ]]; then
  echo -e "DRI device: ${YELLOW}${SCRAPEFUN_DRI_DEVICE}${NC}"
elif [[ "${SCRAPEFUN_GPU_MODE}" == "nvidia" ]]; then
  echo -e "NVIDIA devices: ${YELLOW}${NVIDIA_VISIBLE_DEVICES}${NC}"
fi
echo -e "Deploy dir: ${YELLOW}${DEPLOY_DIR}${NC}"
echo ""

cd "${DEPLOY_DIR}"

if ! try_pull_images; then
  echo -e "${YELLOW}All image sources failed. Falling back to downloadable image bundle...${NC}"
  load_image_bundle || {
    echo -e "${RED}Error: failed to pull Docker image and failed to load offline bundle.${NC}"
    exit 1
  }
fi

write_server_env_file "${SELECTED_REPOSITORY}"
write_updater_env_file "${SELECTED_REPOSITORY}"

if ! run_gpu_preflight; then
  handle_gpu_preflight_failure
fi

ensure_legacy_data_is_safe
remove_legacy_container_if_needed "scrapefun"
remove_legacy_container_if_needed "scrapefun-updater"
if [[ "${ACTION}" == "update" ]]; then
  echo -e "${YELLOW}Recreating changed Compose services without stopping the project...${NC}"
  docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" up -d --remove-orphans
else
  docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" up -d
fi

bash "${DEPLOY_DIR}/scrapefun" wait-ready

echo ""
if [[ "${ACTION}" == "update" ]]; then
  echo -e "${GREEN}Update complete.${NC}"
else
  echo -e "${GREEN}Deployment complete.${NC}"
fi
echo -e "Image: ${YELLOW}${SELECTED_REPOSITORY}:${TAG}${NC}"
echo -e "Open: ${YELLOW}http://<your-server-ip>:${APP_HOST_PORT}${NC}"
echo -e "Compose file: ${YELLOW}${COMPOSE_TARGET}${NC}"
echo -e "Server env: ${YELLOW}${SERVER_ENV_FILE}${NC}"
echo -e "Updater env: ${YELLOW}${UPDATER_ENV_FILE}${NC}"
echo -e "Operations: ${YELLOW}${OPERATIONS_DIR}${NC}"
echo -e "Manage: ${YELLOW}${DEPLOY_DIR}/scrapefun${NC}"
echo -e "Status: ${YELLOW}${DEPLOY_DIR}/scrapefun status${NC}"
bash "${DEPLOY_DIR}/scrapefun" url
echo ""
echo -e "Later update by running the same one-click command again:"
echo -e "  ${YELLOW}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/one-click-compose-deploy.sh | bash -s -- ${CHANNEL} ${DEPLOY_DIR}${NC}"
echo -e "Or use the app Settings page to switch Stable/Beta and click Update."
