# NAS Docker Compose deployment

[简体中文](./DOCKER_COMPOSE_DEPLOYMENT.md) · **English**

> Updated: 2026-10-20

For Synology Container Manager, QNAP Container Station, 1Panel, CasaOS, and other environments supporting Docker Compose.

This example uses `docker-compose.yml`, `server.env`, and `.env`. App reads `server.env` through `env_file`; Compose reads `.env` for variable substitution. The one-click installer instead uses `docker-compose.remote.yml` / `.updater.env`. Choose operations commands for the files in your actual deployment.

## Create a project directory

Choose a fixed directory, for example:

```text
/volume1/docker/scrapefun
```

Create the data root inside it. The container creates the remaining subdirectories:

```text
scrapefun-data
```

## Create server.env

Generate a random 32-byte secret:

```bash
openssl rand -hex 32
```

Create `server.env` in the project directory:

```dotenv
NODE_ENV=production
DATABASE_URL=file:/app/data/db/dev.db
APP_AUTH_SECRET=REPLACE_WITH_THE_RANDOM_SECRET_GENERATED_ABOVE
```

Replace the placeholder with the generated value. `APP_AUTH_SECRET` is required in production; keep it secure.

## Create an updater token

Generate a separate random value:

```bash
openssl rand -hex 24
```

Create `.env` in the project directory and insert that value:

```dotenv
SCRAPEFUN_UPDATER_TOKEN=REPLACE_WITH_THE_RANDOM_TOKEN_GENERATED_ABOVE
```

Both files contain sensitive configuration. Restrict access and include them in secure backups.

Create an empty `.updater.env` next to `.env` to store image and channel state. Load both files for subsequent commands so manual recreation keeps the version chosen by web updates. NAS panels must load both files or provide equivalent variables.

## Create docker-compose.yml

```yaml
name: scrapefun

services:
  app:
    image: ${SCRAPETAB_IMAGE:-haoweil/scrapefun:latest}
    container_name: scrapefun
    restart: unless-stopped
    ports:
      - "8096:8096"
    env_file:
      - ./server.env
    environment:
      NODE_ENV: production
      PORT: 8096
      DATABASE_URL: file:/app/data/db/dev.db
      FLARESOLVERR_URL: http://host.docker.internal:8191/v1
      UPDATE_CURRENT_TAG: ${UPDATE_CURRENT_TAG:-latest}
      UPDATE_WEBHOOK_URL: http://updater:4182/update
      UPDATE_WEBHOOK_TOKEN: ${SCRAPEFUN_UPDATER_TOKEN:?Set the updater token in .env}
      UPDATE_DOCKERHUB_REPO: haoweil/scrapefun
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./scrapefun-data:/app/data
    init: true
    security_opt:
      - no-new-privileges:true
    stop_grace_period: 60s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  updater:
    image: ${SCRAPETAB_UPDATER_IMAGE:-haoweil/scrapefun-updater:latest}
    container_name: scrapefun-updater
    restart: unless-stopped
    working_dir: /workspace
    environment:
      UPDATER_PROJECT_DIR: /workspace
      UPDATER_COMPOSE_FILE: /workspace/docker-compose.yml
      UPDATER_SERVICE_NAME: app
      UPDATER_HEALTHCHECK_URL: http://app:8096/health/ready
      UPDATER_STATE_ENV_FILE: /workspace/.updater.env
      UPDATER_SERVER_ENV_FILE: /workspace/server.env
      UPDATER_SERVER_ENV_SCHEMA_URL: https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/server-env.schema.json
      UPDATER_SERVER_ENV_SCHEMA_CACHE: /workspace/.server-env.schema.json
      UPDATER_STATUS_FILE: /workspace/.updater-status.json
      UPDATER_UPDATE_METADATA_FILE: /workspace/.updater-image-state.json
      UPDATER_TOKEN: ${SCRAPEFUN_UPDATER_TOKEN:?Set the updater token in .env}
      UPDATER_REPOSITORY: haoweil/scrapefun
    volumes:
      - ./:/workspace
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "127.0.0.1:4182:4182"
    init: true
    security_opt:
      - no-new-privileges:true
    stop_grace_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## Updater image

Updater uses the separate `haoweil/scrapefun-updater:latest` image; beta uses `haoweil/scrapefun-updater:beta`. New app images do not contain updater runtime. Do not change updater's image to `haoweil/scrapefun`.

Updater is optional. If your environment cannot pull the separate image, remove its service and app's `UPDATE_WEBHOOK_URL`, then use the manual update commands below. This does not change business data in `/app/data`.

Updater mounts the Docker socket and has host-level container-management privileges. Do not expose `4182` to the public internet. Keep its token secure. For multi-tenant or untrusted networks, consider manual updates without updater.

## Configure GPU access

Select the appropriate configuration for your NAS or Server hardware and add it to the `app` service.

Intel, most AMD, and most NAS integrated GPUs:

```yaml
services:
  app:
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
```

NVIDIA:

```yaml
services:
  app:
    gpus: all
    environment:
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: compute,utility,video,graphics
```

Install NVIDIA Container Toolkit on the host first. Omit GPU configuration when you deliberately do not want hardware acceleration.

Merge snippets into the existing app service and preserve its environment entries. Confirm the render node exists. Map the whole `/dev/dri` only if required by the NAS. VAAPI / Vulkan do not require `/dev/kfd`; NVIDIA Vulkan requires the `graphics` capability.

## Start

```bash
docker compose --env-file .env --env-file .updater.env config -q
docker compose --env-file .env --env-file .updater.env up -d
```

Check `docker compose --env-file .env --env-file .updater.env ps`, then open:

```text
http://NAS_IP:8096
```

Check readiness using your actual host port:

```bash
curl -fsS http://127.0.0.1:8096/health/ready
```

## Change the access port

If `8096` is occupied, change only the host-side port on the left:

```yaml
ports:
  - "18096:8096"
```

The address becomes `http://NAS_IP:18096`.

## Use beta

Set these entries in `.updater.env`, then run the manual update commands. To return to Stable, change all three `beta` values to `latest`.

```dotenv
SCRAPETAB_IMAGE=haoweil/scrapefun:beta
SCRAPETAB_UPDATER_IMAGE=haoweil/scrapefun-updater:beta
UPDATE_CURRENT_TAG=beta
```

## Keep updater tokens consistent

The `.env` example provides the same `SCRAPEFUN_UPDATER_TOKEN` to both services: app uses `UPDATE_WEBHOOK_TOKEN` and updater uses `UPDATER_TOKEN`. Recreate both services after rotating the token. If your NAS panel does not load the project `.env`, supply this variable through its environment settings or replace both fields with the same random value.

## FlareSolverr

If FlareSolverr runs on the host and exposes port `8191`:

```yaml
FLARESOLVERR_URL: http://host.docker.internal:8191/v1
```

If it runs in the same Compose project with service name `flaresolverr`:

```yaml
FLARESOLVERR_URL: http://flaresolverr:8191/v1
```

If it runs on another machine:

```yaml
FLARESOLVERR_URL: http://192.168.1.50:8191/v1
```

## Updates and backups

Manual update:

If `.updater.env` pins images with `@sha256` digests, `pull` keeps that fixed version. To upgrade along a channel, first set `SCRAPETAB_IMAGE` and `SCRAPETAB_UPDATER_IMAGE` to the desired `:latest` / `:beta` tags and set the matching `UPDATE_CURRENT_TAG`. Keep digests when recreating the same version.

```bash
docker compose --env-file .env --env-file .updater.env pull
docker compose --env-file .env --env-file .updater.env up -d
```

An ordinary update does not require an initial `docker compose down`. Running `down` stops both app and updater and unnecessarily increases downtime. Consider it only when changing networks, the project name, or removing the whole project.

See [persistent data and backups](./DOCKER_DATA_AND_BACKUP.en.md) for full backup and migration instructions.

[Documentation](./docs/README.en.md) · [Releases](./RELEASE_POLICY.en.md) · [Support](./SUPPORT.en.md) · [Licensing](./legal/README.en.md)

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
