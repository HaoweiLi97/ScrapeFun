#!/usr/bin/env bash
# Opt-in Vulkan over D3D12 for WSL2. Never replaces the system Mesa installation.
set -euo pipefail
VERSION=26.1.4
SHA256=072705caa9adf4740f1489194b13e278ad959166863b5271fe423a86353c9ab6
PREFIX="/opt/scrapefun-wsl-vulkan/mesa-${VERSION}"
OUTPUT_DIR="$PWD/scrapefun-wsl-gpu"
ADAPTER=NVIDIA
REUSE=0
while (( $# )); do
  case "$1" in
    --prefix) PREFIX="${2:?missing prefix}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?missing output directory}"; shift 2 ;;
    --adapter) ADAPTER="${2:?missing adapter name}"; shift 2 ;;
    --reuse-prefix) REUSE=1; shift ;;
    --help)
      printf '%s\n' 'Usage: sudo bash scripts/setup-wsl-comic-gpu.sh [--prefix /absolute/path] [--output-dir /absolute/path] [--adapter NVIDIA] [--reuse-prefix]'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -c /dev/dxg && -r /usr/lib/wsl/lib/libd3d12.so ]] || { echo 'This helper requires WSL2 GPU passthrough (/dev/dxg and libd3d12.so).' >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || { echo 'This helper has been verified only on WSL2 amd64.' >&2; exit 1; }
# Paths are embedded in shell, systemd EnvironmentFile and Compose configuration.
[[ "$PREFIX" =~ ^/[a-zA-Z0-9_./-]+$ && "$OUTPUT_DIR" =~ ^/[a-zA-Z0-9_./-]+$ && "$ADAPTER" =~ ^[a-zA-Z0-9_-]+$ ]] || {
  echo 'Use absolute paths without spaces and an alphanumeric adapter substring.' >&2; exit 2;
}
if (( ! REUSE )); then
  if [[ -r "$PREFIX/share/vulkan/icd.d/dzn_icd.x86_64.json" && -r "$PREFIX/lib/x86_64-linux-gnu/libvulkan_dzn.so" ]]; then REUSE=1; fi
fi
if (( ! REUSE )); then
  [[ "$EUID" == 0 ]] || { echo 'Building the isolated driver requires sudo.' >&2; exit 1; }
  command -v apt-get >/dev/null || { echo 'Automatic build requires an apt-based Ubuntu/Debian distribution.' >&2; exit 1; }
  CACHE="${XDG_CACHE_HOME:-/root/.cache}/scrapefun-comic-gpu"
  mkdir -p "$CACHE"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential cmake git curl ca-certificates python3-venv python3-mako python3-yaml \
    libdrm-dev libzstd-dev libelf-dev pkg-config ninja-build bison flex vulkan-tools directx-headers-dev
  ARCHIVE="$CACHE/mesa-${VERSION}.tar.xz"
  if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --retry 3 "https://archive.mesa3d.org/mesa-${VERSION}.tar.xz" -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
  fi
  printf '%s  %s\n' "$SHA256" "$ARCHIVE" | sha256sum --check -
  [[ -d "$CACHE/mesa-${VERSION}" ]] || tar -xJf "$ARCHIVE" -C "$CACHE"
  [[ -d "$CACHE/venv" ]] || python3 -m venv --system-site-packages "$CACHE/venv"
  "$CACHE/venv/bin/python" -m pip install 'meson==1.12.1' 'packaging==26.3'
  MESON_ARGS=(setup "$CACHE/build" "$CACHE/mesa-${VERSION}" "--prefix=$PREFIX"
    -Dbuildtype=release '-Dplatforms=[]' '-Dgallium-drivers=[]' -Dvulkan-drivers=microsoft-experimental
    -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dglx=disabled -Degl=disabled
    -Dllvm=disabled -Dxmlconfig=disabled -Dshader-cache=disabled -Dbuild-tests=false)
  [[ ! -f "$CACHE/build/build.ninja" ]] || MESON_ARGS+=(--reconfigure)
  "$CACHE/venv/bin/meson" "${MESON_ARGS[@]}"
  ninja -C "$CACHE/build" -j "${SCRAPEFUN_GPU_BUILD_JOBS:-8}"
  ninja -C "$CACHE/build" install
fi
LIB_DIR="$PREFIX/lib/x86_64-linux-gnu"
if ! command -v vulkaninfo >/dev/null; then
  [[ "$EUID" == 0 ]] || { echo 'Install vulkan-tools with sudo before reusing this prefix.' >&2; exit 1; }
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libvulkan1 vulkan-tools
fi
ICD="$PREFIX/share/vulkan/icd.d/dzn_icd.x86_64.json"
[[ -r "$ICD" && -r "$LIB_DIR/libvulkan_dzn.so" ]] || { echo 'The isolated Dozen driver is missing.' >&2; exit 1; }
SUMMARY="$(env LD_LIBRARY_PATH="$LIB_DIR:/usr/lib/wsl/lib" VK_ICD_FILENAMES="$ICD" \
  MESA_D3D12_DEFAULT_ADAPTER_NAME="$ADAPTER" vulkaninfo --summary 2>&1)" || { printf '%s\n' "$SUMMARY" >&2; exit 1; }
printf '%s\n' "$SUMMARY"
grep -Eq 'deviceType.*(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU)' <<< "$SUMMARY" || {
  echo 'No hardware Vulkan device found; refusing a software-only configuration.' >&2; exit 1;
}
mkdir -p "$OUTPUT_DIR"
cat > "$OUTPUT_DIR/vulkan.env" <<EOF
LD_LIBRARY_PATH=$LIB_DIR:/usr/lib/wsl/lib
VK_ICD_FILENAMES=$ICD
MESA_D3D12_DEFAULT_ADAPTER_NAME=$ADAPTER
IMAGE_UPSCALE_GPU_FALLBACK_POLICY=strict
EOF
cat > "$OUTPUT_DIR/run-native.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -gt 0 ]] || { echo 'Usage: run-native.sh command [args...]' >&2; exit 2; }
set -a
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vulkan.env"
set +a
exec "$@"
EOF
chmod 755 "$OUTPUT_DIR/run-native.sh"
cat > "$OUTPUT_DIR/docker-compose.wsl-gpu.yml" <<EOF
services:
  app:
    # Use with a CPU-mode base Compose file, without NVIDIA reservations/runtime.
    gpus: !reset []
    devices:
      - /dev/dxg:/dev/dxg
    environment:
      LD_LIBRARY_PATH: $LIB_DIR:/usr/lib/wsl/lib
      VK_ICD_FILENAMES: $ICD
      MESA_D3D12_DEFAULT_ADAPTER_NAME: $ADAPTER
      IMAGE_UPSCALE_GPU_FALLBACK_POLICY: strict
    volumes:
      - type: bind
        source: /usr/lib/wsl
        target: /usr/lib/wsl
        read_only: true
        bind:
          create_host_path: false
      - type: bind
        source: $PREFIX
        target: $PREFIX
        read_only: true
        bind:
          create_host_path: false
EOF
printf '\nGenerated configuration in %s\n' "$OUTPUT_DIR"
echo 'Dozen is experimental. Validate each enhancement engine on real pages before using this WSL configuration.'
echo 'No service was restarted. See docs/linux-server-management.md for activation and persistence.'
