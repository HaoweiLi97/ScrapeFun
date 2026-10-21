# Docker deployment and operations

[简体中文](./DOCKER_GUIDE.md) · **English**

> Updated: 2026-10-20

For Linux hosts and NAS systems. The current release pipeline defaults to `linux/amd64`; verify the selected tag’s manifest before deploying to another architecture. Choose an installation method, then complete setup. [Back up](./DOCKER_DATA_AND_BACKUP.en.md) before updating an existing instance.

| Method | Environment | Guide |
| --- | --- | --- |
| One-click deployment | Linux hosts with terminal access | This page |
| Manual Compose | NAS panels, 1Panel, CasaOS, and similar tools | [Compose deployment](./DOCKER_COMPOSE_DEPLOYMENT.en.md) |
| Configuration template | Review production services and mounts | [docker-compose.remote.yml](./docker-compose.remote.yml) |

## Prerequisites

- Install Docker Engine and the Docker Compose plugin. Confirm that the current user can run Docker.
- Prepare writable deployment and persistent-data directories.
- Check that port `8096`, or your chosen host port, is available.
- GPU hardware is detected automatically and missing dependencies are installed. The host GPU driver must already work on native Linux.

```bash
docker version
docker compose version
```

## Install stable

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable
```

The script creates these default locations:

| Location | Purpose |
| --- | --- |
| `~/scrapefun` | Compose, `server.env`, `.updater.env`, and operations tools |
| `~/scrapefun-data` | Complete persistent data root mounted at `/app/data` |

To set an explicit deployment directory:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable /opt/scrapefun
```

The current user needs write access to the destination. Existing environment settings are preserved. New installations generate a login-token secret and an updater token. Do not commit environment files to public repositories.

Open `http://SERVER_IP:8096` after installation and complete setup. Use the actual host port if you changed it.

## GPU modes

| Mode | Devices or prerequisites |
| --- | --- |
| `auto` | Default: detect GPU access; failed container checks fall back to CPU |
| `dri` | Intel / AMD / NAS integrated GPUs; maps a single render node |
| `amd` | Legacy alias for `dri`; does not map `/dev/kfd` |
| `nvidia` | NVIDIA Container Toolkit; uses `gpus: all` |
| `wsl` | WSL2 `/dev/dxg`, automatically installs isolated Vulkan |
| `none` | No GPU passthrough |

Example for a non-interactive installation:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | \
  SCRAPEFUN_GPU_MODE=nvidia bash -s -- stable
```

Device passthrough makes hardware accessible to the container. Actual decoding, transcoding, and enhancement capabilities still depend on drivers, hardware, and media formats.

Confirm the host render node exists; set `SCRAPEFUN_DRI_DEVICE=/dev/dri/renderD128` as needed. Use `all` only when the NAS requires the complete directory. NVIDIA needs `video` and `graphics` in `NVIDIA_DRIVER_CAPABILITIES`. Explicit `dri` / `nvidia` modes stop deployment if Vulkan / Waifu2x container checks fail.

## Update an existing deployment

Back up and pause scanning, scraping, and other write tasks first. Rerun the script to synchronize deployment configuration and update images. Without a channel argument, it preserves the current stable / beta channel, host port, and data directory:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

For a one-click deployment using the default directory, you can also update manually:

If `.updater.env` pins images with `@sha256` digests, `pull` keeps that fixed version. To upgrade along a channel, first set `SCRAPETAB_IMAGE` and `SCRAPETAB_UPDATER_IMAGE` to the desired `:latest` / `:beta` tags and set the matching `UPDATE_CURRENT_TAG`. Keep digests when recreating the same version.

```bash
cd ~/scrapefun
docker compose --env-file .updater.env -f docker-compose.remote.yml pull
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d --remove-orphans
```

For a custom directory, enter that directory first. Ordinary updates do not require an initial `down`; rebuilding services still interrupts playback and background tasks.

## Change channels

Install or switch to beta:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- beta
```

Explicitly return to stable:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable
```

Append your custom deployment directory after the channel argument if applicable. Keep app and updater on matching channels. `latest` / `beta` are moving aliases rather than fixed versions. Back up before switching; older versions are not guaranteed to read data written by newer versions.

## Persistence and updater permissions

Mount the complete data root at `/app/data`:

```yaml
volumes:
  - ${SCRAPEFUN_DATA_DIR:-./scrapefun-data}:/app/data
```

Migrate older per-directory mounts using the [migration guide](./DOCKER_DATA_AND_BACKUP.en.md#migrate-older-per-directory-mounts). Do not rebuild the container before preserving its data.

Updater uses the separate `haoweil/scrapefun-updater` image and mounts the Docker socket. Do not expose `4182` to the public internet. Manual updates remain available without updater. See the [Compose guide](./DOCKER_COMPOSE_DEPLOYMENT.en.md) for full configuration.

## Verify after updating

For the default directory and port:

```bash
cd ~/scrapefun
docker compose --env-file .updater.env -f docker-compose.remote.yml ps
docker compose --env-file .updater.env -f docker-compose.remote.yml logs --tail=100 app
curl -fsS http://127.0.0.1:8096/health/live
curl -fsS http://127.0.0.1:8096/health/ready
```

Also check login, libraries, artwork, playback, and reading progress. If something fails, preserve current data and logs and follow [backup and recovery](./DOCKER_DATA_AND_BACKUP.en.md). Redact logs before public reporting.

## Native systemd installation

Native releases support glibc Linux amd64. Requires running systemd, Node.js 20/22/24, Python 3, curl, FFmpeg, and FFprobe. The script downloads a release for the selected channel and verifies SHA-256 without compiling source on the host. It exits if no matching release is available.

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-native-deploy.sh | sudo bash
# Beta: replace sudo bash with sudo bash -s -- beta
```

Defaults: application `/opt/scrapefun`, data `/var/lib/scrapefun`, configuration `/etc/scrapefun/server.env`. Manage with `sudo scrapefun status`, `health`, `logs --follow`, `update`, and `backup`. Run `sudo scrapefun restart` after editing configuration. Backups contain secrets and belong outside the data directory. Restore native archives with `sudo scrapefun restore /path/to/backup.tar.gz`; they cannot be passed to the Docker restore tool.

## Related documentation

[Compose configuration](./DOCKER_COMPOSE_DEPLOYMENT.en.md) · [Backup and recovery](./DOCKER_DATA_AND_BACKUP.en.md) · [Releases](./RELEASE_POLICY.en.md) · [Support](./SUPPORT.en.md) · [Licensing](./legal/README.en.md)

## Comic enhancement: automatic GPU detection and setup

The one-click script defaults to auto: WSL2 /dev/dxg takes priority, followed by NVIDIA and Intel/AMD DRI. Missing GPU dependencies are installed automatically; an installed, validated environment is reused. Comic enhancement uses NCNN Vulkan and does not require the CUDA Toolkit.

On Ubuntu/Debian WSL2, the installer automatically builds and installs a verified isolated Dozen Vulkan driver. Native Linux installs missing Vulkan loader, tools and Mesa drivers. NVIDIA userspace Vulkan libraries must match the running driver version.

On native Linux, NVIDIA Docker mode installs the NVIDIA Container Toolkit when missing and configures the local system Docker runtime. First-time configuration restarts Docker and may briefly affect other containers. Remote, custom and rootless daemons are not reconfigured automatically.

The Windows GPU driver must already support WSL2 GPU passthrough. Dozen remains experimental; the RTX 4060 Ti has been verified. Driver installation on other devices and NAS systems depends on vendor support. Automatic dependency installation currently supports Ubuntu/Debian; other distributions need a preinstalled GPU environment.

Before Docker startup, the installer tests hardware Vulkan and the five built-in enhancement engines as the actual service user. Software renderers such as llvmpipe/lavapipe are not accepted as hardware GPUs. Native installation checks host hardware Vulkan; run the engine capability tests from Settings after installation.

WSL settings are written into the primary Compose file and native service environment and retained by one-click updates. The WSL Docker daemon must run in the same distribution with access to /dev/dxg and the driver directory.

Set SCRAPEFUN_GPU_MODE=none to disable GPU environment installation, or explicitly select wsl, nvidia or dri. Failed hardware tests in auto mode report CPU fallback; explicit GPU mode failures stop deployment. Environment installation failures stop deployment without replacing existing app containers.

Validation: the published v0.4.0 native and Docker releases passed Waifu2x Fast, Waifu2x, Real-CUGAN SE, Real-CUGAN Pro and Real-ESRGAN tests on an RTX 4060 Ti under WSL2. Images were enlarged from 512×768 to 1024×1536 in strict GPU mode without CPU fallback; observed GPU utilization peaked at 76%.

Select GPU 0 and automatic tile size (tile=0) in the reader. Real-CUGAN crashed with tile=32 in this environment; validate real pages with automatic tiling first. A successful nvidia-smi query alone does not prove Vulkan works; use the Settings capability tests and actual enhancement results.
