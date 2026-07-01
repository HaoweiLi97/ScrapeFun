# Docker Compose 部署

## 推荐 Compose

```yaml
name: scrapefun

services:
  app:
    image: haoweil/scrapefun:latest
    container_name: scrapefun
    restart: unless-stopped
    ports:
      - "8096:8096"
    environment:
      NODE_ENV: production
      PORT: 8096
      DATABASE_URL: file:/app/data/db/dev.db

      # 可选：部分 scraper 绕过 Cloudflare 时使用。
      # 如果没有部署 FlareSolverr，可以先保持默认。
      FLARESOLVERR_URL: http://host.docker.internal:8191/v1

	      # 可选：TMDB 数据源。
	      # TMDB_API_KEY: your_tmdb_api_key

	      # 可选：Bangumi 漫画数据源（默认留空）。
	      # BANGUMI_API_KEY:

	      # 可选：WebDAV 默认配置，也可以部署后在网页里配置。
      # WEBDAV_URL: https://your-webdav.example.com
      # WEBDAV_USERNAME: your_username
      # WEBDAV_PASSWORD: your_password

      # 内置更新相关配置。
      UPDATE_CURRENT_TAG: latest
      UPDATE_WEBHOOK_URL: http://updater:4182/update
      # 可选：更新 webhook token。为空表示不校验。
      UPDATE_WEBHOOK_TOKEN: ""
      UPDATE_DOCKERHUB_REPO: haoweil/scrapefun
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./scrapefun-data/db:/app/data/db
      - ./scrapefun-data/images:/app/data/images
      - ./scrapefun-data/config:/app/data/config
      - ./scrapefun-data/local-subtitles:/app/data/local-subtitles

  updater:
    image: haoweil/scrapefun:latest
    container_name: scrapefun-updater
    restart: unless-stopped
    working_dir: /workspace
    command: ["node", "/app/updater/server.cjs"]
    environment:
      # 可选：更新 webhook token。为空表示不校验。
      UPDATER_TOKEN: ""
      # 如果你改了镜像仓库，这里要和 UPDATE_DOCKERHUB_REPO 保持一致。
      UPDATER_REPOSITORY: haoweil/scrapefun
    volumes:
      - ./:/workspace
      - /var/run/docker.sock:/var/run/docker.sock
```

部署完成后访问：

```text
http://NAS_IP:8096
```

## GPU 透传

如果你希望 Docker 里的图像增强使用宿主机 GPU，而不是只跑 CPU，需要额外做设备透传。

如果你是通过一键脚本部署，脚本首次运行时会提示你选择 GPU 模式，并自动把对应配置写进部署目录里的 `docker-compose.remote.yml`；后续更新会沿用这个选择。也可以通过 `SCRAPEFUN_GPU_MODE=none|dri|amd|nvidia` 直接指定。

常见 Linux / NAS 情况：

```yaml
services:
  app:
    devices:
      - /dev/dri:/dev/dri
```

部分 AMD 设备还需要：

```yaml
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
```

注意：

- 如果宿主机没有 `/dev/kfd`，不要硬加这一行
- NVIDIA 通常使用 `gpus: all`，并且还需要宿主机安装 `NVIDIA Container Toolkit`
- 不建议在这里写死 `group_add: render` / `video`，有些镜像里不存在这些组名，会直接启动失败
- 不做设备透传时，容器虽然能启动，但图像增强通常无法真正使用 GPU

## NAS 面板填写要点

- 项目名称：`scrapefun`
- Compose 内容：粘贴上面的 YAML
- 工作目录 / 项目目录：建议选择一个固定目录，例如 `/volume1/docker/scrapefun`
- 数据目录：Compose 会在项目目录下创建 `scrapefun-data`
- Web 端口：默认 `8096`

不需要手动创建 `/workspace`，也不需要给它单独准备目录。它只是 updater 容器内部路径，用来读取当前 Compose 项目的 `docker-compose.yml` 并执行更新；`./:/workspace` 会自动把 NAS 面板选择的项目目录挂载进去。

如果 NAS 面板要求手动创建挂载目录，创建这些目录：

```text
scrapefun-data/db
scrapefun-data/images
scrapefun-data/config
scrapefun-data/local-subtitles
```

## 可选：更新 Token

默认 Compose 里更新 token 为空，可以正常部署和使用。如果你希望限制网页内更新接口调用，可以设置 token。

两个位置必须填同一个值：

```yaml
UPDATE_WEBHOOK_TOKEN: scrapefun-update-2026-your-random-text
UPDATER_TOKEN: scrapefun-update-2026-your-random-text
```

如果不需要 token，保持为空：

```yaml
UPDATE_WEBHOOK_TOKEN: ""
UPDATER_TOKEN: ""
```

如果只填了其中一个，或者两个值不一致，网页内更新功能会无法调用 updater。

如果你还改了镜像仓库地址，也要确保 `UPDATE_DOCKERHUB_REPO` 和 `UPDATER_REPOSITORY` 指向同一个仓库；一键脚本会自动处理这件事，手动维护 compose 时要一起改。

## 常用可改项

### 修改访问端口

如果 `8096` 被占用，只改左边的宿主机端口：

```yaml
ports:
  - "18096:8096"
```

访问地址变为：

```text
http://NAS_IP:18096
```

### 使用 beta 镜像

把两个镜像和当前标签改成 `beta`：

```yaml
services:
  app:
    image: haoweil/scrapefun:beta
    environment:
      UPDATE_CURRENT_TAG: beta

  updater:
    image: haoweil/scrapefun:beta
```

### 图像增强说明

Docker 镜像当前只内置并开放 `waifu2x_fast`。

这意味着：

- Docker 下不会显示 `realcugan` / `realesrgan`
- `waifu2x_fast` 在 `amd64` / `arm64` 镜像里都可用
- 是否真正用上 GPU，还取决于上面的设备透传和宿主机驱动

### 配置 FlareSolverr

如果你已经在 NAS 上单独部署了 FlareSolverr，并暴露 `8191` 端口，保持默认即可：

```yaml
FLARESOLVERR_URL: http://host.docker.internal:8191/v1
```

如果 FlareSolverr 是同一个 Compose 项目里的服务，服务名叫 `flaresolverr`，改成：

```yaml
FLARESOLVERR_URL: http://flaresolverr:8191/v1
```

如果 FlareSolverr 在另一台机器，改成：

```yaml
FLARESOLVERR_URL: http://192.168.1.50:8191/v1
```

## 持久化目录说明

```text
./scrapefun-data/db              数据库
./scrapefun-data/images          海报、背景图、演员图等图片缓存
./scrapefun-data/config          实例配置
./scrapefun-data/local-subtitles 本地化字幕
```

备份时备份整个 `scrapefun-data` 目录即可。
