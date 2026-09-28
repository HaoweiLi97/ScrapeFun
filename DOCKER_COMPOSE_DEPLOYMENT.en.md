# NAS Docker Compose deployment

[简体中文](./DOCKER_COMPOSE_DEPLOYMENT.md) · **English**

> Updated: 2026-09-28

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

## Create docker-compose.yml

```yaml
name: scrapefun

services:
  app:
    image: haoweil/scrapefun:latest
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
      UPDATE_CURRENT_TAG: latest
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
    image: haoweil/scrapefun-updater:latest
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
      - /dev/dri:/dev/dri
```

Some AMD hosts also require `/dev/kfd`:

```yaml
services:
  app:
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
```

NVIDIA:

```yaml
services:
  app:
    gpus: all
```

Install NVIDIA Container Toolkit on the host first. Omit GPU configuration when you deliberately do not want hardware acceleration.

## Start

```bash
docker compose up -d
```

Check `docker compose ps`, then open:

```text
http://NAS_IP:8096
```

## Change the access port

If `8096` is occupied, change only the host-side port on the left:

```yaml
ports:
  - "18096:8096"
```

The address becomes `http://NAS_IP:18096`.

## Use beta

Change both image tags and the current channel:

```yaml
services:
  app:
    image: haoweil/scrapefun:beta
    environment:
      UPDATE_CURRENT_TAG: beta

  updater:
    image: haoweil/scrapefun-updater:beta
```

To return to stable, change both image tags and `UPDATE_CURRENT_TAG` to `latest`.

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

```bash
docker compose pull
docker compose up -d --remove-orphans
```

An ordinary update does not require an initial `docker compose down`. Running `down` stops both app and updater and unnecessarily increases downtime. Consider it only when changing networks, the project name, or removing the whole project.

See [persistent data and backups](./DOCKER_DATA_AND_BACKUP.en.md) for full backup and migration instructions.

[Documentation](./docs/README.en.md) · [Releases](./RELEASE_POLICY.en.md) · [Support](./SUPPORT.en.md) · [Licensing](./legal/README.en.md)
