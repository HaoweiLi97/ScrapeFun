#!/usr/bin/env bash
# Called by both installers. The output directory contains no credentials.
set -euo pipefail
MODE="${1:?GPU mode required}" TARGET="${2:?native or docker required}" OUTPUT="${3:?output directory required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_root() {
  if [[ "$EUID" == 0 ]]; then "$@"; else sudo "$@"; fi
}
apt_install() {
  command -v apt-get >/dev/null || { echo 'Automatic GPU dependencies require Ubuntu/Debian; install the Vulkan environment for this distribution first.' >&2; return 1; }
  run_root apt-get update
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}
case "$MODE" in
  none) exit 0 ;;
  wsl)
    PREFIX="${SCRAPEFUN_WSL_VULKAN_PREFIX:-/opt/scrapefun-wsl-vulkan/mesa-26.1.4}"
    ADAPTER="${SCRAPEFUN_WSL_GPU_ADAPTER:-NVIDIA}"
    # The helper reuses an already installed driver and validates real hardware.
    run_root bash "$SCRIPT_DIR/setup-wsl-comic-gpu.sh" --prefix "$PREFIX" --adapter "$ADAPTER" --output-dir "$OUTPUT"
    exit 0 ;;
  native|dri|nvidia) ;;
  *) echo "Unsupported GPU environment mode: $MODE" >&2; exit 2 ;;
esac
if [[ "$TARGET" == native ]]; then
  if ! command -v vulkaninfo >/dev/null || ! vulkaninfo --summary 2>/dev/null | grep -Eq 'deviceType.*(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU)'; then
    apt_install libvulkan1 vulkan-tools mesa-vulkan-drivers
    if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
      # Install only the userspace Vulkan/GL package matching the running driver.
      DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)"
      MAJOR="${DRIVER%%.*}"
      [[ "$MAJOR" =~ ^[0-9]+$ ]] || { echo 'Cannot identify the NVIDIA driver version.' >&2; exit 1; }
      if ! vulkaninfo --summary 2>/dev/null | grep -Eiq 'deviceName.*NVIDIA'; then
        PACKAGE="libnvidia-gl-${MAJOR}"
        MATCH="$(apt-cache madison "$PACKAGE" | awk -v driver="$DRIVER" '$3 ~ "^" driver "-" { print $3; exit }')"
        [[ -n "$MATCH" ]] || { echo "No $PACKAGE matching running driver $DRIVER; refusing a mismatched driver upgrade." >&2; exit 1; }
        apt_install "$PACKAGE=$MATCH"
      fi
    fi
  fi
  vulkaninfo --summary 2>/dev/null | grep -Eq 'deviceType.*(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU)' || {
    echo 'No hardware Vulkan device after dependency installation. Check the host GPU driver.' >&2; exit 1;
  }
fi
if [[ "$TARGET" == docker && "$MODE" == nvidia ]]; then
  if docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"'; then exit 0; fi
  # Never modify another machine's or a custom daemon's configuration.
  ENDPOINT="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
  [[ "$ENDPOINT" == unix:///var/run/docker.sock && -d /run/systemd/system ]] || {
    echo 'Automatic NVIDIA Toolkit configuration requires the local system Docker daemon.' >&2; exit 1;
  }
  if ! command -v nvidia-ctk >/dev/null; then
    apt_install ca-certificates curl gnupg2
    TEMP="$(mktemp -d)"; trap 'rm -rf -- "$TEMP"' EXIT
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey -o "$TEMP/key"
    gpg --batch --dearmor --output "$TEMP/keyring.gpg" "$TEMP/key"
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list -o "$TEMP/repo"
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' "$TEMP/repo" > "$TEMP/signed-repo"
    run_root install -m 644 "$TEMP/keyring.gpg" /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    run_root install -m 644 "$TEMP/signed-repo" /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt_install nvidia-container-toolkit
  fi
  echo 'Configuring NVIDIA Container Toolkit; restarting the local Docker service to activate it.'
  run_root nvidia-ctk runtime configure --runtime=docker
  run_root systemctl restart docker
fi
