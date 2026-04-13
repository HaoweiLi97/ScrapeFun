# ScrapeFun Docker 部署指南

这份文档对应当前公开仓库中的 Docker Compose 部署方式。

当前推荐方案：

- 使用 `docker compose`
- 使用 `docker-compose.remote.yml`
- 使用 Docker Hub 镜像 `haoweil/scrapefun`
- 通过 `latest` / `beta` 频道更新
- 持久化到宿主机目录 `scrapefun-data`

## 1. 运行前提

部署前请先确认：

- 已安装 Docker
- 已安装 Docker Compose Plugin
- `docker info` 可以正常执行
- 如果要启用部分站点刮削，宿主机或局域网中有可访问的 FlareSolverr

建议环境：

- Linux 服务器
- 2 GB 以上可用内存
- 足够的磁盘空间用于数据库、图片缓存和字幕持久化

## 2. 推荐部署方式

### 方式一：一键部署

默认部署 `stable` 频道：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

部署 `beta` 频道：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- beta
```

默认部署目录是：

```text
~/scrapefun
```

默认持久化目录是：

```text
~/scrapefun-data
```

脚本会自动完成这些事情：

- 下载 `docker-compose.remote.yml`
- 创建部署目录
- 创建数据目录
- 生成 `server.env`
- 生成 `.updater.env`
- 拉取镜像并启动 `app` 与 `updater`

### 方式二：手动部署

先准备目录：

```bash
mkdir -p ~/scrapefun
cd ~/scrapefun
```

下载 compose 文件：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/docker-compose.remote.yml -o docker-compose.remote.yml
```

创建 `server.env`：

```env
NODE_ENV=production
DATABASE_URL=file:/app/data/db/dev.db
FLARESOLVERR_URL=http://host.docker.internal:8191/v1
SCRAPETAB_UPDATER_TOKEN=replace_with_a_random_token
UPDATE_DOCKERHUB_REPO=haoweil/scrapefun
UPDATE_DEFAULT_CHANNEL=stable
```

创建 `.updater.env`：

```env
SCRAPETAB_IMAGE=haoweil/scrapefun:latest
UPDATE_CURRENT_TAG=latest
APP_HOST_PORT=8096
SCRAPEFUN_DATA_DIR=./scrapefun-data
COMPOSE_PROJECT_NAME=scrapefun
```

创建持久化目录：

```bash
mkdir -p ./scrapefun-data/db
mkdir -p ./scrapefun-data/images
mkdir -p ./scrapefun-data/config
mkdir -p ./scrapefun-data/local-subtitles
```

启动服务：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml pull
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d
```

启动后默认访问：

```text
http://<server-ip>:8096
```

## 3. 当前 Compose 结构

当前 `docker-compose.remote.yml` 包含两个服务：

### `app`

主应用服务，负责：

- Web UI
- API
- 媒体库管理
- WebDAV / AList 访问
- 字幕处理
- 播放兼容接口

### `updater`

内置 sidecar 更新服务，负责：

- 接收应用内“立即更新”请求
- 根据 `latest` 或 `beta` 拉取目标镜像
- 重建 `app` 服务
- 保留现有持久化数据

## 4. 数据持久化

当前默认持久化目录结构：

```text
scrapefun-data/
  db/
  images/
  config/
  local-subtitles/
```

各目录作用如下：

### `db`

路径：

```text
/app/data/db
```

包含：

- SQLite 数据库
- 媒体元数据
- 用户数据
- 配置数据

### `images`

路径：

```text
/app/data/images
```

包含：

- 海报
- 背景图
- 缩略图
- 其他媒体图片缓存

### `config`

路径：

```text
/app/data/config
```

包含：

- 安装态配置
- 实例级持久状态
- 更新器相关运行状态

### `local-subtitles`

路径：

```text
/app/data/local-subtitles
```

包含：

- 本地化字幕文件
- 通过字幕本地化功能保存的持久内容

如果不持久化这个目录，重建容器后字幕本地化结果会丢失。

## 5. 端口与网络

默认映射：

```text
8096 -> 8096
```

也就是：

- 容器内应用端口：`8096`
- 宿主机默认访问端口：`8096`

如果你想改宿主机端口，可以在 `.updater.env` 中修改：

```env
APP_HOST_PORT=8096
```

例如改成 `8080`：

```env
APP_HOST_PORT=8080
```

然后重新启动：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d
```

## 6. FlareSolverr 配置

当前 compose 默认值：

```env
FLARESOLVERR_URL=http://host.docker.internal:8191/v1
```

这表示容器会尝试访问宿主机上的 FlareSolverr。

如果你的 FlareSolverr 不在宿主机，而是在局域网另一台机器，请把 `server.env` 改成：

```env
FLARESOLVERR_URL=http://<your-flaresolverr-ip>:8191/v1
```

修改后重启：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d
```

## 7. 更新与频道切换

### 更新 `stable`

如果你当前使用稳定版，通常 `latest` 就是稳定版镜像。

手动更新：

```bash
cd ~/scrapefun
docker compose --env-file .updater.env -f docker-compose.remote.yml pull
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d
```

### 切换到 `beta`

把 `.updater.env` 改成：

```env
SCRAPETAB_IMAGE=haoweil/scrapefun:beta
UPDATE_CURRENT_TAG=beta
APP_HOST_PORT=8096
SCRAPEFUN_DATA_DIR=./scrapefun-data
COMPOSE_PROJECT_NAME=scrapefun
```

并把 `server.env` 改成：

```env
UPDATE_DEFAULT_CHANNEL=beta
```

然后执行：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml pull
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d
```

### 切回 `stable`

把 `.updater.env` 改回：

```env
SCRAPETAB_IMAGE=haoweil/scrapefun:latest
UPDATE_CURRENT_TAG=latest
```

并把 `server.env` 改回：

```env
UPDATE_DEFAULT_CHANNEL=stable
```

再执行：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d
```

### 在应用内更新

如果 `updater` 服务正常运行，你也可以直接在应用的设置页中：

- 切换 `Stable / Beta`
- 点击“立即更新”

## 8. 常用命令

查看容器状态：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml ps
```

查看主应用日志：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml logs -f app
```

查看更新器日志：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml logs -f updater
```

重启服务：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml restart
```

停止服务：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml down
```

进入主应用容器：

```bash
docker exec -it scrapefun sh
```

## 9. 备份建议

最简单的做法是定期备份整个数据目录：

```bash
tar czf scrapefun-data-backup.tar.gz ./scrapefun-data
```

恢复时解压回原目录即可。

建议重点保留：

- `db`
- `images`
- `config`
- `local-subtitles`

## 10. 故障排查

### 页面打不开

先看容器状态：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml ps
```

再看日志：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml logs -f app
```

### 更新失败

先看 updater 日志：

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml logs -f updater
```

再确认：

- `server.env` 中的 `SCRAPETAB_UPDATER_TOKEN` 已设置
- `server.env` 中的 `UPDATE_DOCKERHUB_REPO` 正确
- `.updater.env` 中的 `SCRAPETAB_IMAGE` 与 `UPDATE_CURRENT_TAG` 匹配
- 宿主机 Docker daemon 正常

### 刮削相关站点无法访问

优先检查：

- `FLARESOLVERR_URL` 是否正确
- FlareSolverr 服务是否真的可访问
- 宿主机防火墙是否拦截

### 重建后数据丢失

这通常说明你没有正确持久化 `scrapefun-data` 目录，或部署时修改了 `SCRAPEFUN_DATA_DIR`。

建议检查：

```bash
cat .updater.env
```

确认其中的：

```env
SCRAPEFUN_DATA_DIR=./scrapefun-data
```
