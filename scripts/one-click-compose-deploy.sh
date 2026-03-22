#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHANNEL="${1:-stable}"
DEPLOY_DIR="${2:-$HOME/scrapefun}"
COMPOSE_SOURCE="${ROOT_DIR}/docker-compose.remote.yml"
COMPOSE_TARGET="${DEPLOY_DIR}/docker-compose.remote.yml"
SERVER_ENV_FILE="${DEPLOY_DIR}/server.env"
UPDATER_ENV_FILE="${DEPLOY_DIR}/.updater.env"
REPOSITORY="${REPOSITORY:-haoweil/scrapefun}"
GITHUB_REPO="${GITHUB_REPO:-HaoweiLi97/ScrapeFun}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
COMPOSE_URL="${COMPOSE_URL:-https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/docker-compose.remote.yml}"
COMPOSE_API_URL="${COMPOSE_API_URL:-https://api.github.com/repos/${GITHUB_REPO}/contents/docker-compose.remote.yml?ref=${GITHUB_BRANCH}}"
APP_HOST_PORT="${APP_HOST_PORT:-}"

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
EOF
}

if [[ "${CHANNEL}" == "-h" || "${CHANNEL}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${CHANNEL}" != "stable" && "${CHANNEL}" != "beta" ]]; then
  echo -e "${RED}Error: channel must be 'stable' or 'beta'.${NC}"
  usage
  exit 1
fi

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

download_compose() {
  if [[ -f "${COMPOSE_SOURCE}" ]]; then
    cp "${COMPOSE_SOURCE}" "${COMPOSE_TARGET}"
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "${COMPOSE_URL}" -o "${COMPOSE_TARGET}"; then
      return
    fi
    rm -f "${COMPOSE_TARGET}"
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO "${COMPOSE_TARGET}" "${COMPOSE_URL}"; then
      return
    fi
    rm -f "${COMPOSE_TARGET}"
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "${COMPOSE_API_URL}" "${COMPOSE_TARGET}" <<'PY'
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
    return
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
    existing_port="$(sed -n 's/^APP_HOST_PORT=//p' "${UPDATER_ENV_FILE}" | tail -n 1)"
    if [[ -n "${existing_port}" ]]; then
      APP_HOST_PORT="${existing_port}"
      return
    fi
  fi

  APP_HOST_PORT="4000"

  if [[ -t 1 && -r /dev/tty ]]; then
    local requested_port
    printf "Deploy to which host port? [4000]: " > /dev/tty
    IFS= read -r requested_port < /dev/tty || true
    requested_port="${requested_port//$'\r'/}"
    requested_port="${requested_port//[[:space:]]/}"
    requested_port="${requested_port:-4000}"

    if [[ ! "${requested_port}" =~ ^[0-9]+$ ]] || (( requested_port < 1 || requested_port > 65535 )); then
      echo -e "${RED}Error: port must be a number between 1 and 65535.${NC}"
      exit 1
    fi

    APP_HOST_PORT="${requested_port}"
  fi
}

download_compose
resolve_app_host_port

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
fi

cat > "${UPDATER_ENV_FILE}" <<EOF
SCRAPETAB_IMAGE=${REPOSITORY}:${TAG}
UPDATE_CURRENT_TAG=${TAG}
APP_HOST_PORT=${APP_HOST_PORT}
EOF

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ScrapeFun Compose Deploy${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Channel: ${YELLOW}${CHANNEL}${NC}"
echo -e "Image: ${YELLOW}${REPOSITORY}:${TAG}${NC}"
echo -e "Host port: ${YELLOW}${APP_HOST_PORT}${NC}"
echo -e "Deploy dir: ${YELLOW}${DEPLOY_DIR}${NC}"
echo ""

cd "${DEPLOY_DIR}"

docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" pull
docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" up -d

echo ""
echo -e "${GREEN}Deployment complete.${NC}"
echo -e "Open: ${YELLOW}http://<your-server-ip>:${APP_HOST_PORT}${NC}"
echo -e "Compose file: ${YELLOW}${COMPOSE_TARGET}${NC}"
echo -e "Server env: ${YELLOW}${SERVER_ENV_FILE}${NC}"
echo -e "Updater env: ${YELLOW}${UPDATER_ENV_FILE}${NC}"
echo ""
echo -e "Later switch channel by running:"
echo -e "  ${YELLOW}cd ${DEPLOY_DIR} && docker compose --env-file .updater.env -f docker-compose.remote.yml up -d${NC}"
echo -e "Or use the app Settings page to switch Stable/Beta and click Update."
