#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="deploy"

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
COMPOSE_TARGET="${DEPLOY_DIR}/docker-compose.remote.yml"
SERVER_ENV_FILE="${DEPLOY_DIR}/server.env"
UPDATER_ENV_FILE="${DEPLOY_DIR}/.updater.env"
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
APP_HOST_PORT="${APP_HOST_PORT:-}"
SCRAPEFUN_DATA_DIR="${SCRAPEFUN_DATA_DIR:-}"
SCRAPEFUN_GPU_MODE="${SCRAPEFUN_GPU_MODE:-}"

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
  SCRAPEFUN_GPU_MODE       GPU mode to use without prompting.
                           Options: none, dri, amd, nvidia

Notes:
  - default port is 8096
  - script preserves existing channel, host port, and data dir on updates
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

render_compose_with_gpu_mode() {
  local tmp_file
  local marker_found=0
  tmp_file="$(create_deploy_tmp_file ".docker-compose.remote.rendered.yml.tmp")"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "    # __APP_GPU_BLOCK__" ]]; then
      marker_found=1
      case "${SCRAPEFUN_GPU_MODE}" in
        none)
          printf '%s\n' "    # GPU passthrough disabled" >> "${tmp_file}"
          ;;
        dri)
          cat >> "${tmp_file}" <<'EOF'
    devices:
      - /dev/dri:/dev/dri
    group_add:
      - render
      - video
EOF
          ;;
        amd)
          cat >> "${tmp_file}" <<'EOF'
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
    device_cgroup_rules:
      - 'c 226:* rmw'
      - 'c 235:* rmw'
    group_add:
      - render
      - video
EOF
          ;;
        nvidia)
          printf '%s\n' "    gpus: all" >> "${tmp_file}"
          ;;
      esac
      continue
    fi
    printf '%s\n' "${line}" >> "${tmp_file}"
  done < "${COMPOSE_TARGET}"

  if [[ "${marker_found}" -ne 1 ]]; then
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

  SCRAPEFUN_DATA_DIR="${DEFAULT_DATA_DIR}"
}

normalize_gpu_mode() {
  local raw
  raw="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${raw}" in
    ""|none|off|cpu)
      echo "none"
      ;;
    dri|intel|igpu|intel-amd|intel_amd)
      echo "dri"
      ;;
    amd|rocm|kfd)
      echo "amd"
      ;;
    nvidia|cuda)
      echo "nvidia"
      ;;
    *)
      echo -e "${RED}Error: unsupported GPU mode: ${1}${NC}" >&2
      echo -e "${RED}Supported values: none, dri, amd, nvidia${NC}" >&2
      exit 1
      ;;
  esac
}

resolve_gpu_mode() {
  if [[ -n "${SCRAPEFUN_GPU_MODE}" ]]; then
    SCRAPEFUN_GPU_MODE="$(normalize_gpu_mode "${SCRAPEFUN_GPU_MODE}")"
    return
  fi

  if [[ -f "${UPDATER_ENV_FILE}" ]]; then
    local existing_gpu_mode
    existing_gpu_mode="$(read_env_value "SCRAPEFUN_GPU_MODE" "${UPDATER_ENV_FILE}")"
    if [[ -n "${existing_gpu_mode}" ]]; then
      SCRAPEFUN_GPU_MODE="$(normalize_gpu_mode "${existing_gpu_mode}")"
      return
    fi
  fi

  SCRAPEFUN_GPU_MODE="none"

  if [[ -t 1 && -r /dev/tty ]]; then
    local selected
    echo "Choose GPU passthrough mode:" > /dev/tty
    echo "  1) none   - no GPU passthrough (recommended if unsure)" > /dev/tty
    echo "  2) dri    - Intel / AMD / most NAS iGPU via /dev/dri" > /dev/tty
    echo "  3) amd    - /dev/dri + /dev/kfd for some AMD systems" > /dev/tty
    echo "  4) nvidia - enable 'gpus: all' for NVIDIA Container Toolkit" > /dev/tty
    printf "Select GPU mode [1]: " > /dev/tty
    IFS= read -r selected < /dev/tty || true
    selected="${selected//$'\r'/}"
    selected="${selected//[[:space:]]/}"
    case "${selected:-1}" in
      1) SCRAPEFUN_GPU_MODE="none" ;;
      2) SCRAPEFUN_GPU_MODE="dri" ;;
      3) SCRAPEFUN_GPU_MODE="amd" ;;
      4) SCRAPEFUN_GPU_MODE="nvidia" ;;
      *)
        echo -e "${RED}Error: invalid GPU mode selection.${NC}"
        exit 1
        ;;
    esac
  fi
}

normalize_repository_list() {
  printf '%s\n' "${IMAGE_REPOSITORIES//,/ }"
}

write_server_env_file() {
  local repository="$1"

  if [[ ! -f "${SERVER_ENV_FILE}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      UPDATER_TOKEN="$(openssl rand -hex 24)"
    else
      UPDATER_TOKEN="$(date +%s | sha256sum | cut -d' ' -f1 | cut -c1-48)"
    fi

    cat > "${SERVER_ENV_FILE}" <<EOF
NODE_ENV=production
DATABASE_URL=file:/app/data/db/dev.db
SCRAPETAB_UPDATER_TOKEN=${UPDATER_TOKEN}
UPDATE_REPOSITORY=${repository}
UPDATE_DOCKERHUB_REPO=${repository}
UPDATE_DEFAULT_CHANNEL=${CHANNEL}
EOF
    echo -e "${YELLOW}Created ${SERVER_ENV_FILE}${NC}"
  else
    echo -e "${YELLOW}Keeping existing ${SERVER_ENV_FILE}${NC}"
    upsert_env_value "UPDATE_REPOSITORY" "${repository}" "${SERVER_ENV_FILE}"
    upsert_env_value "UPDATE_DOCKERHUB_REPO" "${repository}" "${SERVER_ENV_FILE}"
    upsert_env_value "UPDATE_DEFAULT_CHANNEL" "${CHANNEL}" "${SERVER_ENV_FILE}"
  fi
}

write_updater_env_file() {
  local repository="$1"
  local tmp_file
  tmp_file="$(create_deploy_tmp_file ".updater.env.tmp")"

  cat > "${tmp_file}" <<EOF
SCRAPETAB_IMAGE=${repository}:${TAG}
UPDATE_CURRENT_TAG=${TAG}
UPDATE_REPOSITORY=${repository}
UPDATE_DOCKERHUB_REPO=${repository}
APP_HOST_PORT=${APP_HOST_PORT}
SCRAPEFUN_DATA_DIR=${SCRAPEFUN_DATA_DIR}
SCRAPEFUN_GPU_MODE=${SCRAPEFUN_GPU_MODE}
COMPOSE_PROJECT_NAME=scrapefun
EOF

  if [[ -f "${UPDATER_ENV_FILE}" ]] && cmp -s "${tmp_file}" "${UPDATER_ENV_FILE}"; then
    rm -f "${tmp_file}"
    return
  fi

  if ! mv "${tmp_file}" "${UPDATER_ENV_FILE}" 2>/dev/null; then
    rm -f "${tmp_file}"
    print_permission_help "${UPDATER_ENV_FILE}"
    exit 1
  fi
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
  return 0
}

resolve_app_host_port
resolve_data_dir
resolve_gpu_mode
download_compose
render_compose_with_gpu_mode

mkdir -p \
  "${SCRAPEFUN_DATA_DIR}/db" \
  "${SCRAPEFUN_DATA_DIR}/images" \
  "${SCRAPEFUN_DATA_DIR}/config" \
  "${SCRAPEFUN_DATA_DIR}/local-subtitles"

TAG="latest"
if [[ "${CHANNEL}" == "beta" ]]; then
  TAG="beta"
fi

SELECTED_REPOSITORY="${REPOSITORY}"
write_server_env_file "${SELECTED_REPOSITORY}"

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
echo -e "GPU mode: ${YELLOW}${SCRAPEFUN_GPU_MODE}${NC}"
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

if [[ "${ACTION}" == "update" ]]; then
  echo -e "${YELLOW}Stopping existing Compose services before update...${NC}"
  docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" down
fi

remove_legacy_container_if_needed "scrapefun"
remove_legacy_container_if_needed "scrapefun-updater"
docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" up -d

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
echo ""
echo -e "Later update by running the same one-click command again:"
echo -e "  ${YELLOW}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/one-click-compose-deploy.sh | bash -s -- ${CHANNEL} ${DEPLOY_DIR}${NC}"
echo -e "Or use the app Settings page to switch Stable/Beta and click Update."
