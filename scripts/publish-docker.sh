#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DOCKER_USERNAME="${DOCKER_USERNAME:-haoweil}"
IMAGE_NAME="${IMAGE_NAME:-scrapefun}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PROTECTION_PROFILE="${PROTECTION_PROFILE:-balance}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage:
  ./scripts/publish-docker.sh <version> [stable|beta]
  ./scripts/publish-docker.sh --current [stable|beta]

Examples:
  ./scripts/publish-docker.sh 0.1.1-beta.1 beta
  ./scripts/publish-docker.sh 0.1.1 stable
  ./scripts/publish-docker.sh --current beta

Notes:
  - When <version> is provided, both client and server package.json versions are updated.
  - "stable" pushes the "latest" tag.
  - "beta" pushes the "beta" tag and does not touch "latest".
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

VERSION_INPUT="${1:-}"
CHANNEL="${2:-}"

if [[ -z "$VERSION_INPUT" ]]; then
  usage
  exit 1
fi

if [[ "$VERSION_INPUT" == "--current" ]]; then
  VERSION="$(node -p "require('./server/package.json').version")"
else
  VERSION="$VERSION_INPUT"
  CLIENT_VERSION="$(node -p "require('./client/package.json').version")"
  SERVER_VERSION="$(node -p "require('./server/package.json').version")"

  if [[ "$CLIENT_VERSION" != "$VERSION" ]]; then
    npm version "$VERSION" --no-git-tag-version --prefix client >/dev/null
  fi

  if [[ "$SERVER_VERSION" != "$VERSION" ]]; then
    npm version "$VERSION" --no-git-tag-version --prefix server >/dev/null
  fi
fi

if [[ -z "$CHANNEL" ]]; then
  if [[ "$VERSION" == *"-beta."* ]]; then
    CHANNEL="beta"
  else
    CHANNEL="stable"
  fi
fi

if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "beta" ]]; then
  echo -e "${RED}Error: channel must be 'stable' or 'beta'.${NC}"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}Error: Docker is not running.${NC}"
  exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Publish Docker Image${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Version: ${YELLOW}${VERSION}${NC}"
echo -e "Channel: ${YELLOW}${CHANNEL}${NC}"
echo -e "Image: ${YELLOW}${DOCKER_USERNAME}/${IMAGE_NAME}${NC}"
echo -e "Platforms: ${YELLOW}${PLATFORMS}${NC}"
echo ""

docker buildx create --name multiarch-builder --use 2>/dev/null || docker buildx use multiarch-builder
docker buildx inspect --bootstrap >/dev/null

TAG_ARGS=(
  -t "${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}"
)

if [[ "$CHANNEL" == "stable" ]]; then
  TAG_ARGS+=(-t "${DOCKER_USERNAME}/${IMAGE_NAME}:latest")
else
  TAG_ARGS+=(-t "${DOCKER_USERNAME}/${IMAGE_NAME}:beta")
fi

echo -e "${YELLOW}Building and pushing image...${NC}"
docker buildx build \
  --platform "${PLATFORMS}" \
  --build-arg "PROTECTION_PROFILE=${PROTECTION_PROFILE}" \
  "${TAG_ARGS[@]}" \
  --push \
  .

echo ""
echo -e "${GREEN}Done.${NC}"
echo -e "Pushed:"
echo -e "  ${YELLOW}${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}${NC}"
if [[ "$CHANNEL" == "stable" ]]; then
  echo -e "  ${YELLOW}${DOCKER_USERNAME}/${IMAGE_NAME}:latest${NC}"
else
  echo -e "  ${YELLOW}${DOCKER_USERNAME}/${IMAGE_NAME}:beta${NC}"
fi
