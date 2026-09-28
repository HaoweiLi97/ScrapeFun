# Docker deployment and operations

[简体中文](./DOCKER_GUIDE.md) · **English**

> Updated: 2026-09-28

For Linux hosts and NAS systems. Images are available for `linux/amd64` and `linux/arm64`. Choose an installation method, then complete setup. [Back up](./DOCKER_DATA_AND_BACKUP.en.md) before updating an existing instance.

| Method | Environment | Guide |
| --- | --- | --- |
| One-click deployment | Linux hosts with terminal access | This page |
| Manual Compose | NAS panels, 1Panel, CasaOS, and similar tools | [Compose deployment](./DOCKER_COMPOSE_DEPLOYMENT.en.md) |
| Configuration template | Review production services and mounts | [docker-compose.remote.yml](./docker-compose.remote.yml) |

## Prerequisites

- Install Docker Engine and the Docker Compose plugin. Confirm that the current user can run Docker.
- Prepare writable deployment and persistent-data directories.
- Check that port `8096`, or your chosen host port, is available.
- Select a GPU mode for your hardware. Install NVIDIA Container Toolkit first on NVIDIA hosts.

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
| `dri` | Intel / most AMD / NAS integrated GPUs; maps `/dev/dri` |
| `amd` | AMD hosts requiring both `/dev/dri` and `/dev/kfd` |
| `nvidia` | NVIDIA Container Toolkit; uses `gpus: all` |
| `none` | No GPU passthrough |

Example for a non-interactive installation:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | \
  SCRAPEFUN_GPU_MODE=nvidia bash -s -- stable
```

Device passthrough makes hardware accessible to the container. Actual decoding, transcoding, and enhancement capabilities still depend on drivers, hardware, and media formats.

## Update an existing deployment

Back up and pause scanning, scraping, and other write tasks first. Rerun the script to synchronize deployment configuration and update images. Without a channel argument, it preserves the current stable / beta channel, host port, and data directory:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

For a one-click deployment using the default directory, you can also update manually:

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

## Related documentation

[Compose configuration](./DOCKER_COMPOSE_DEPLOYMENT.en.md) · [Backup and recovery](./DOCKER_DATA_AND_BACKUP.en.md) · [Releases](./RELEASE_POLICY.en.md) · [Support](./SUPPORT.en.md) · [Licensing](./legal/README.en.md)
