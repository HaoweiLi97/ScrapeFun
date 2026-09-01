# ScrapeFun Docker 部署与更新

> 最后更新：2026 年 9 月 1 日

普通 Linux 服务器推荐使用一键脚本；群晖、威联通和其他 NAS 请使用 [Docker Compose 指南](./DOCKER_COMPOSE_DEPLOYMENT.md)。

## Linux 一键部署

先安装 Docker，然后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

脚本会完成：

- 创建部署目录和 Compose 配置
- 创建 `server.env` 与 `.updater.env`
- 初始化持久化数据目录
- 生成生产环境需要的 `APP_AUTH_SECRET`
- 选择并保存 GPU 模式
- 分别解析 app 与 updater 镜像，并兼容旧的组合镜像
- 启动 ScrapeFun 与 updater

完成后访问：

```text
http://服务器IP:8096
```

## Stable 与 Beta

Stable：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable
```

Beta：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- beta
```

从 beta 回到 stable 时，重新运行 stable 命令。已有部署目录、数据目录、端口和 GPU 选择会继续使用。

## 自定义部署目录

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable /opt/scrapefun
```

更新自定义目录中的实例时，继续传入同一路径。

## GPU 模式

部署时请根据硬件选择正确模式：

| 模式 | 适用硬件 | 配置 |
| --- | --- | --- |
| `dri` | Intel、大多数 AMD、大多数 NAS 集显 | 透传 `/dev/dri` |
| `amd` | 需要计算设备的 AMD 主机 | 透传 `/dev/dri` 与 `/dev/kfd` |
| `nvidia` | 已安装 NVIDIA Container Toolkit 的主机 | 启用 `gpus: all` |
| `none` | 明确不使用硬件加速 | 不透传 GPU |

直接指定模式：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | \
  SCRAPEFUN_GPU_MODE=dri bash
```

容器能否使用 GPU 还取决于宿主机驱动和设备权限。NVIDIA 主机必须先安装 NVIDIA Container Toolkit。

## 更新

一键部署用户可以重复运行原安装命令。脚本会拉取目标镜像并使用 `docker compose up -d --remove-orphans` 重建发生变化的服务，不会先停止整个 Compose 项目，也不会更换持久化目录。

安装新版 updater 后，也可以在 ScrapeFun 设置页检查更新。新版 updater 会读取公开配置规则，只向本地 `server.env` 补齐缺失变量，已有非空配置不会被覆盖，修改前会创建 `server.env.bak`。

### 独立 updater 镜像兼容迁移

app 直接处理网页、媒体和 scraper 请求；updater 挂载 Docker socket，权限明显更高。新版部署会优先把 updater 放进独立的 `haoweil/scrapefun-updater` 镜像，避免 app 镜像携带 Docker CLI。

一键脚本按下面顺序选择镜像：

1. 拉取当前渠道的 app 镜像，例如 `haoweil/scrapefun:latest`；
2. 尝试拉取同渠道的独立 updater，例如 `haoweil/scrapefun-updater:latest`；
3. 独立 updater tag 已存在时使用新镜像；尚未发布时暂时回退到仍包含 updater runtime 的旧 app 镜像；
4. 把最终选择分别写入 `.updater.env` 的 `SCRAPETAB_IMAGE` 和 `SCRAPETAB_UPDATER_IMAGE`。

兼容回退不会修改数据库和数据目录。等独立 updater tag 发布后，重新运行原来的一键命令，脚本就会自动切换，不需要手工编辑 Compose。迁移期间请保留公开 `docker-compose.remote.yml` 中显式的 updater `command`；旧组合镜像依赖它启动 updater，新独立镜像也兼容该命令。

可在部署目录确认当前选择：

```bash
grep -E '^SCRAPETAB_(IMAGE|UPDATER_IMAGE)=' .updater.env
```

正常情况下可能看到以下任意一种状态：

```dotenv
# 独立 updater 已可用
SCRAPETAB_IMAGE=haoweil/scrapefun:latest
SCRAPETAB_UPDATER_IMAGE=haoweil/scrapefun-updater:latest
```

```dotenv
# 迁移期兼容回退
SCRAPETAB_IMAGE=haoweil/scrapefun:latest
SCRAPETAB_UPDATER_IMAGE=haoweil/scrapefun:latest
```

## Docker Hub 拉取失败

一键脚本在 Docker Hub 拉取失败时，会尝试下载对应架构的离线镜像 bundle 并执行 `docker load`。新版 bundle 可以同时携带 app/updater 两个镜像；迁移期仍兼容只含历史组合镜像的旧 bundle。

如需关闭这项回退：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | \
  SCRAPEFUN_SKIP_IMAGE_BUNDLE=1 bash
```

## NAS 与手动 Compose

NAS 面板、1Panel、CasaOS 及其他 Compose 环境请阅读：

- [NAS Docker Compose](./DOCKER_COMPOSE_DEPLOYMENT.md)
- [数据持久化与备份](./DOCKER_DATA_AND_BACKUP.md)

## 常见问题

### 页面打不开

- 检查 `app` 容器是否正在运行
- 检查防火墙是否放行访问端口
- 检查端口映射是否为 `8096:8096` 或你设置的端口
- 查看 `app` 容器日志

### APP_AUTH_SECRET 报错

旧部署出现 `APP_AUTH_SECRET is required in production` 时，重新运行一键部署命令。手动 Compose 用户请按照 Compose 指南创建 `server.env`。

### 设置页更新失败

- 检查 `updater` 容器是否运行
- 检查是否挂载 `/var/run/docker.sock`
- 如果设置了更新 token，确认应用与 updater 两侧一致
- 旧部署先重新运行一次最新版一键脚本

### 重建后数据不见了

确认 Compose 仍挂载原来的 `scrapefun-data` 目录。不要在未备份时删除该目录。
