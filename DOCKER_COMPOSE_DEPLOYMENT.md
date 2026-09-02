# NAS Docker Compose 部署

> 最后更新：2026 年 9 月 2 日

适用于群晖 Container Manager、威联通 Container Station、1Panel、CasaOS 及其他支持 Docker Compose 的环境。

## 创建项目目录

选择一个固定目录，例如：

```text
/volume1/docker/scrapefun
```

在其中创建数据根目录；其余子目录由容器自动建立：

```text
scrapefun-data
```

## 创建 server.env

生成 32 字节随机密钥：

```bash
openssl rand -hex 32
```

在项目目录创建 `server.env`：

```dotenv
NODE_ENV=production
DATABASE_URL=file:/app/data/db/dev.db
APP_AUTH_SECRET=替换为上一步生成的随机密钥
```

`APP_AUTH_SECRET` 是生产环境必填项，请妥善保管。

## 创建 docker-compose.yml

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
      UPDATE_WEBHOOK_TOKEN: ""
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
      UPDATER_TOKEN: ""
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

## updater 镜像

updater 使用独立镜像 `haoweil/scrapefun-updater:latest`；beta 使用 `haoweil/scrapefun-updater:beta`。新版 app 镜像不包含 updater runtime，不能把 updater 的镜像改成 `haoweil/scrapefun`。

updater 是可选服务。如果当前环境无法拉取独立 updater，可暂时移除 updater 服务以及 app 中的 `UPDATE_WEBHOOK_URL`，改用本页末尾的手动更新命令；这不会影响 `/app/data` 中的业务数据。

updater 挂载 Docker socket，具备主机级容器管理权限。不要把 `4182` 暴露到公网，并妥善保存 updater token；多租户或不可信网络建议移除 updater，改为人工更新。

## 配置 GPU

GPU 是部署配置的重要部分。请根据 NAS 或服务器硬件，将对应片段加入 `app` 服务。

Intel、大多数 AMD 和大多数 NAS 集显：

```yaml
services:
  app:
    devices:
      - /dev/dri:/dev/dri
```

部分 AMD 主机还需要 `/dev/kfd`：

```yaml
services:
  app:
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
```

NVIDIA：

```yaml
services:
  app:
    gpus: all
```

NVIDIA 主机需要先安装 NVIDIA Container Toolkit。只有明确不使用硬件加速时，才不添加 GPU 配置。

## 启动

```bash
docker compose up -d
```

浏览器访问：

```text
http://NAS_IP:8096
```

## 修改访问端口

如果 `8096` 已被占用，只修改左侧宿主机端口：

```yaml
ports:
  - "18096:8096"
```

访问地址变为 `http://NAS_IP:18096`。

## 使用 Beta

同时修改 `app` 与 `updater` 的镜像标签，并设置当前频道：

```yaml
services:
  app:
    image: haoweil/scrapefun:beta
    environment:
      UPDATE_CURRENT_TAG: beta

  updater:
    image: haoweil/scrapefun-updater:beta
```

切回 stable 时，将两个镜像标签和 `UPDATE_CURRENT_TAG` 改回 `latest`。

## 可选更新 Token

如果希望限制更新接口调用，在两个服务中设置同一个随机值：

```yaml
UPDATE_WEBHOOK_TOKEN: your-random-token
UPDATER_TOKEN: your-random-token
```

不需要 token 时，两项都保持空字符串。

## FlareSolverr

FlareSolverr 在宿主机并开放 `8191` 端口：

```yaml
FLARESOLVERR_URL: http://host.docker.internal:8191/v1
```

FlareSolverr 位于同一 Compose 项目且服务名为 `flaresolverr`：

```yaml
FLARESOLVERR_URL: http://flaresolverr:8191/v1
```

FlareSolverr 位于其他机器：

```yaml
FLARESOLVERR_URL: http://192.168.1.50:8191/v1
```

## 更新与备份

手动更新：

```bash
docker compose pull
docker compose up -d --remove-orphans
```

普通更新不需要先执行 `docker compose down`。先 `down` 会同时停止 app 和 updater，扩大不必要的停机窗口；只有修改网络、项目名或需要完整移除项目时才考虑使用它。

完整备份与迁移方法见 [Docker 数据持久化与备份](./DOCKER_DATA_AND_BACKUP.md)。
