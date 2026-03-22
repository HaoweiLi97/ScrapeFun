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
cp "${COMPOSE_SOURCE}" "${COMPOSE_TARGET}"

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
EOF

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ScrapeFun Compose Deploy${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Channel: ${YELLOW}${CHANNEL}${NC}"
echo -e "Image: ${YELLOW}${REPOSITORY}:${TAG}${NC}"
echo -e "Deploy dir: ${YELLOW}${DEPLOY_DIR}${NC}"
echo ""

cd "${DEPLOY_DIR}"

docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" pull
docker compose --env-file "${UPDATER_ENV_FILE}" -f "${COMPOSE_TARGET}" up -d

echo ""
echo -e "${GREEN}Deployment complete.${NC}"
echo -e "Open: ${YELLOW}http://<your-server-ip>:4000${NC}"
echo -e "Compose file: ${YELLOW}${COMPOSE_TARGET}${NC}"
echo -e "Server env: ${YELLOW}${SERVER_ENV_FILE}${NC}"
echo -e "Updater env: ${YELLOW}${UPDATER_ENV_FILE}${NC}"
echo ""
echo -e "Later switch channel by running:"
echo -e "  ${YELLOW}cd ${DEPLOY_DIR} && docker compose --env-file .updater.env -f docker-compose.remote.yml up -d${NC}"
echo -e "Or use the app Settings page to switch Stable/Beta and click Update."
