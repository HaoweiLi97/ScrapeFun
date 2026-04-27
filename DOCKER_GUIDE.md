# ScrapeFun Docker 部署指南

当前推荐使用 Docker Compose 部署。服务器优先使用一键命令；NAS Docker、群晖 Container Manager、绿联 Docker、飞牛 Docker、CasaOS、1Panel 等环境，可以复制 Compose 内容创建项目。

如果你只需要可复制的 Compose 文件，请看：

- [Docker Compose 部署文档](./DOCKER_COMPOSE_DEPLOYMENT.md)

## 1. 一键部署（推荐）

Linux 服务器上推荐使用一键命令部署：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

默认部署 stable 频道，应用端口为 `8096`。

部署 beta 频道：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- beta
```

指定部署目录：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable /opt/scrapefun
```

部署完成后访问：

```text
http://服务器IP:8096
```

## 2. NAS / 面板 Compose 部署

NAS 面板创建 Compose 项目时，使用 [Docker Compose 部署文档](./DOCKER_COMPOSE_DEPLOYMENT.md) 里的 YAML 内容。

创建项目时只需要粘贴 Compose 内容，然后选择一个固定项目目录即可。

推荐项目目录示例：

```text
/volume1/docker/scrapefun
```

Compose 会在项目目录下使用这些持久化目录：

```text
scrapefun-data/db
scrapefun-data/images
scrapefun-data/config
scrapefun-data/local-subtitles
```

如果 NAS 面板不会自动创建挂载目录，再手动创建上面四个目录即可。

## 3. Compose 服务说明

推荐 Compose 包含两个服务：

### `app`

主应用服务，负责：

- Web UI
- API
- 媒体库管理
- WebDAV / AList 访问
- 字幕处理
- 播放兼容接口

默认访问端口：

```text
8096
```

访问地址：

```text
http://NAS_IP:8096
```

### `updater`

内置更新服务，负责：

- 接收应用内“立即更新”请求
- 拉取 `latest` 或 `beta` 镜像
- 重建 `app` 容器
- 保留现有持久化数据

`updater` 需要挂载 Docker socket：

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

这是为了让 updater 调用宿主机 Docker 去更新 `app` 服务，不需要用户手动创建这个文件。

`updater` 还会挂载当前 Compose 项目目录：

```yaml
- ./:/workspace
```

这里的 `/workspace` 是容器内部路径，不需要用户创建。它只用来让 updater 读取当前项目的 `docker-compose.yml`。

## 4. 端口

当前版本默认端口是 `8096`。

默认 Compose：

```yaml
ports:
  - "8096:8096"
```

如果 NAS 上 `8096` 被占用，只改左边的宿主机端口：

```yaml
ports:
  - "18096:8096"
```

访问地址变为：

```text
http://NAS_IP:18096
```

历史版本说明：

- `0.1.3` 之前默认端口是 `4000`
- `0.1.3` 及之后默认端口是 `8096`

## 5. 数据持久化

推荐持久化目录：

```text
scrapefun-data/
  db/
  images/
  config/
  local-subtitles/
```

目录作用：

- `db`：SQLite 数据库、媒体元数据、用户数据、配置数据
- `images`：海报、背景图、演员图等图片缓存
- `config`：实例配置和运行状态
- `local-subtitles`：本地化字幕文件

备份时备份整个 `scrapefun-data` 目录即可。

## 6. 环境变量

常用环境变量在 Compose 的 `environment` 中配置。

常见可改项：

```yaml
environment:
  NODE_ENV: production
  PORT: 8096
  DATABASE_URL: file:/app/data/db/dev.db
  FLARESOLVERR_URL: http://host.docker.internal:8191/v1
  UPDATE_CURRENT_TAG: latest
  UPDATE_WEBHOOK_URL: http://updater:4182/update
  UPDATE_WEBHOOK_TOKEN: ""
  UPDATE_DOCKERHUB_REPO: haoweil/scrapefun
```

可选配置：

```yaml
# TMDB_API_KEY: your_tmdb_api_key
# WEBDAV_URL: https://your-webdav.example.com
# WEBDAV_USERNAME: your_username
# WEBDAV_PASSWORD: your_password
```

## 7. 更新 Token

更新 token 是可选的。

默认：

```yaml
UPDATE_WEBHOOK_TOKEN: ""
UPDATER_TOKEN: ""
```

为空表示不校验 token，部署和应用内更新都可以正常使用。

如果你想限制更新接口调用，可以设置同一个随机字符串：

```yaml
UPDATE_WEBHOOK_TOKEN: your-random-token
UPDATER_TOKEN: your-random-token
```

两个值必须一致。

## 8. FlareSolverr

推荐 Compose 默认：

```yaml
FLARESOLVERR_URL: http://host.docker.internal:8191/v1
```

这表示 ScrapeFun 会尝试访问宿主机上的 FlareSolverr。

如果 FlareSolverr 在同一个 Compose 项目里，服务名叫 `flaresolverr`，改成：

```yaml
FLARESOLVERR_URL: http://flaresolverr:8191/v1
```

如果 FlareSolverr 在另一台机器，改成：

```yaml
FLARESOLVERR_URL: http://192.168.1.50:8191/v1
```

如果暂时不使用需要 FlareSolverr 的 scraper，可以先保持默认。

## 9. 镜像频道

稳定版：

```yaml
image: haoweil/scrapefun:latest
UPDATE_CURRENT_TAG: latest
```

测试版：

```yaml
image: haoweil/scrapefun:beta
UPDATE_CURRENT_TAG: beta
```

如果切换频道，`app` 和 `updater` 两个服务的镜像标签都要一起改。

## 10. 常见问题

### 页面打不开

检查：

- NAS 防火墙是否放行端口
- Compose 项目是否正常启动
- `app` 容器日志是否有报错
- 端口映射是否仍是 `8096:8096` 或你修改后的端口

### 更新失败

检查：

- `updater` 容器是否正常运行
- 是否挂载了 `/var/run/docker.sock`
- 如果设置了 token，`UPDATE_WEBHOOK_TOKEN` 和 `UPDATER_TOKEN` 是否一致
- NAS Docker 是否允许容器访问 Docker socket

### 重建后数据丢失

通常是项目目录或挂载目录变了。

确认 Compose 仍然挂载到同一个数据目录：

```yaml
volumes:
  - ./scrapefun-data/db:/app/data/db
  - ./scrapefun-data/images:/app/data/images
  - ./scrapefun-data/config:/app/data/config
  - ./scrapefun-data/local-subtitles:/app/data/local-subtitles
```

只要 `scrapefun-data` 目录保留，重建容器不会清空数据。
