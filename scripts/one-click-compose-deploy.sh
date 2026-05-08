#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="deploy"
if [[ "${1:-}" == "install" || "${1:-}" == "deploy" || "${1:-}" == "update" ]]; then
  ACTION="$1"
  shift
fi

CHANNEL=""
DEPLOY_DIR="${HOME}/scrapefun"
if [[ "${1:-}" == "stable" || "${1:-}" == "beta" ]]; then
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
GITHUB_REPO="${GITHUB_REPO:-HaoweiLi97/ScrapeFun}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
COMPOSE_URL="${COMPOSE_URL:-https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/docker-compose.remote.yml}"
COMPOSE_API_URL="${COMPOSE_API_URL:-https://api.github.com/repos/${GITHUB_REPO}/contents/docker-compose.remote.yml?ref=${GITHUB_BRANCH}}"
APP_HOST_PORT="${APP_HOST_PORT:-}"
SCRAPEFUN_DATA_DIR="${SCRAPEFUN_DATA_DIR:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage:
  ./scripts/one-click-compose-deploy.sh [install|deploy|update] [stable|beta] [deploy_dir]

Examples:
  ./scripts/one-click-compose-deploy.sh
  ./scripts/one-click-compose-deploy.sh beta
  ./scripts/one-click-compose-deploy.sh stable /opt/scrapefun
  ./scripts/one-click-compose-deploy.sh update
  ./scripts/one-click-compose-deploy.sh update beta
  ./scripts/one-click-compose-deploy.sh update stable /opt/scrapefun
  ./scripts/one-click-compose-deploy.sh update /opt/scrapefun
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
resolve_channel

if [[ "${ACTION}" == "update" && ! -f "${COMPOSE_TARGET}" && ! -f "${UPDATER_ENV_FILE}" ]]; then
  echo -e "${RED}Error: no existing ScrapeFun deployment found in ${DEPLOY_DIR}.${NC}"
  echo -e "${RED}Run install first, or pass the correct deploy_dir.${NC}"
  usage
  exit 1
fi

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

write_updater_env_file() {
  local tmp_file
  tmp_file="$(create_deploy_tmp_file ".updater.env.tmp")"

  cat > "${tmp_file}" <<EOF
SCRAPETAB_IMAGE=${REPOSITORY}:${TAG}
UPDATE_CURRENT_TAG=${TAG}
APP_HOST_PORT=${APP_HOST_PORT}
SCRAPEFUN_DATA_DIR=${SCRAPEFUN_DATA_DIR}
COMPOSE_PROJECT_NAME=scrapefun
EOF

  if [[ -f "${UPDATER_ENV_FILE}" ]] && cmp -s "${tmp_file}" "${UPDATER_ENV_FILE}"; then
    rm -f "${tmp_file}"
    echo -e "${YELLOW}Keeping existing ${UPDATER_ENV_FILE}${NC}"
    return
  fi

  if ! mv "${tmp_file}" "${UPDATER_ENV_FILE}" 2>/dev/null; then
    rm -f "${tmp_file}"
    print_permission_help "${UPDATER_ENV_FILE}"
    exit 1
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

download_compose
resolve_app_host_port
resolve_data_dir

mkdir -p \
  "${SCRAPEFUN_DATA_DIR}/db" \
  "${SCRAPEFUN_DATA_DIR}/images" \
  "${SCRAPEFUN_DATA_DIR}/config" \
  "${SCRAPEFUN_DATA_DIR}/local-subtitles"

TAG="latest"
if [[ "${CHANNEL}" == "beta" ]]; then
  TAG="beta"
fi

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
UPDATE_DOCKERHUB_REPO=${REPOSITORY}
UPDATE_DEFAULT_CHANNEL=${CHANNEL}
EOF
  echo -e "${YELLOW}Created ${SERVER_ENV_FILE}${NC}"
else
  echo -e "${YELLOW}Keeping existing ${SERVER_ENV_FILE}${NC}"
  upsert_env_value "UPDATE_DOCKERHUB_REPO" "${REPOSITORY}" "${SERVER_ENV_FILE}"
  upsert_env_value "UPDATE_DEFAULT_CHANNEL" "${CHANNEL}" "${SERVER_ENV_FILE}"
fi

write_updater_env_file

echo -e "${GREEN}========================================${NC}"
if [[ "${ACTION}" == "update" ]]; then
  echo -e "${GREEN}ScrapeFun Compose Update${NC}"
else
  echo -e "${GREEN}ScrapeFun Compose Deploy${NC}"
fi
echo -e "${GREEN}========================================${NC}"
echo -e "Action: ${YELLOW}${ACTION}${NC}"
echo -e "Channel: ${YELLOW}${CHANNEL}${NC}"
echo -e "Image: ${YELLOW}${REPOSITORY}:${TAG}${NC}"
echo -e "Host port: ${YELLOW}${APP_HOST_PORT}${NC}"
echo -e "Data dir: ${YELLOW}${SCRAPEFUN_DATA_DIR}${NC}"
echo -e "Deploy dir: ${YELLOW}${DEPLOY_DIR}${NC}"
echo ""

cd "${DEPLOY_DIR}"

docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" pull
docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" up -d

echo ""
if [[ "${ACTION}" == "update" ]]; then
  echo -e "${GREEN}Update complete.${NC}"
else
  echo -e "${GREEN}Deployment complete.${NC}"
fi
echo -e "Open: ${YELLOW}http://<your-server-ip>:${APP_HOST_PORT}${NC}"
echo -e "Compose file: ${YELLOW}${COMPOSE_TARGET}${NC}"
echo -e "Server env: ${YELLOW}${SERVER_ENV_FILE}${NC}"
echo -e "Updater env: ${YELLOW}${UPDATER_ENV_FILE}${NC}"
echo ""
echo -e "Later update by running:"
echo -e "  ${YELLOW}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/one-click-compose-deploy.sh | bash -s -- update ${CHANNEL} ${DEPLOY_DIR}${NC}"
echo -e "Or use the app Settings page to switch Stable/Beta and click Update."
