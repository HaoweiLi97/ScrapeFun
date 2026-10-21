# NAS Docker Compose 部署

**简体中文** · [English](./DOCKER_COMPOSE_DEPLOYMENT.en.md)

> 文档更新：2026-10-20

适用于群晖 Container Manager、威联通 Container Station、1Panel、CasaOS 及其他支持 Docker Compose 的环境。

本文示例使用 `docker-compose.yml`、`server.env` 和 `.env`。`server.env` 由 app 的 `env_file` 消费；`.env` 用于 Compose 的变量替换。它们与一键脚本的 `docker-compose.remote.yml` / `.updater.env` 文件组合不同，运维命令应按实际部署方式选择。

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

## 创建更新 Token

再次生成一个独立随机值：

```bash
openssl rand -hex 24
```

在项目目录创建 `.env`，将生成值填入：

```dotenv
SCRAPEFUN_UPDATER_TOKEN=替换为上一步生成的随机值
```

`server.env` 与 `.env` 均包含敏感配置，应限制访问并纳入安全备份。

在 `.env` 同目录创建空的 `.updater.env`，保存网页更新产生的镜像与渠道状态。后续命令同时加载两个文件，避免手动重建时回退到默认版本；NAS 面板须加载两个文件或提供等效变量。

## 创建 docker-compose.yml

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
      UPDATE_WEBHOOK_TOKEN: ${SCRAPEFUN_UPDATER_TOKEN:?请在 .env 中设置更新 Token}
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
      UPDATER_TOKEN: ${SCRAPEFUN_UPDATER_TOKEN:?请在 .env 中设置更新 Token}
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
      - /dev/dri/renderD128:/dev/dri/renderD128
```

NVIDIA：

```yaml
services:
  app:
    gpus: all
    environment:
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: compute,utility,video,graphics
```

NVIDIA 主机需要先安装 NVIDIA Container Toolkit。只有明确不使用硬件加速时，才不添加 GPU 配置。

将片段合并到现有 app 服务并保留原有 environment 字段。确认渲染节点实际存在；只有 NAS 需要时才映射完整 `/dev/dri`。VAAPI / Vulkan 不需要 `/dev/kfd`；NVIDIA Vulkan 必须包含 `graphics` 能力。

## 启动

```bash
docker compose --env-file .env --env-file .updater.env config -q
docker compose --env-file .env --env-file .updater.env up -d
```

启动后检查 `docker compose --env-file .env --env-file .updater.env ps`，然后在浏览器访问：

```text
http://NAS_IP:8096
```

使用实际宿主机端口检查就绪状态：

```bash
curl -fsS http://127.0.0.1:8096/health/ready
```

## 修改访问端口

如果 `8096` 已被占用，只修改左侧宿主机端口：

```yaml
ports:
  - "18096:8096"
```

访问地址变为 `http://NAS_IP:18096`。

## 使用 beta

在 `.updater.env` 设置以下三项，然后执行手动更新命令；切回稳定版时三处 `beta` 均改为 `latest`。

```dotenv
SCRAPETAB_IMAGE=haoweil/scrapefun:beta
SCRAPETAB_UPDATER_IMAGE=haoweil/scrapefun-updater:beta
UPDATE_CURRENT_TAG=beta
```

## 更新 Token 的一致性

本文的 `.env` 为两个服务提供同一个 `SCRAPEFUN_UPDATER_TOKEN`：app 使用 `UPDATE_WEBHOOK_TOKEN`，updater 使用 `UPDATER_TOKEN`。更换 Token 后重建两个服务。NAS 面板若不读取项目 `.env`，应在其环境变量设置中提供该值，或将两个字段替换为相同的随机值。

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

若 `.updater.env` 中已保存 `@sha256` 摘要，`pull` 会保留固定版本。要跟随渠道升级，先将 `SCRAPETAB_IMAGE`、`SCRAPETAB_UPDATER_IMAGE` 改为目标渠道的 `:latest` / `:beta` 标签，并设置匹配的 `UPDATE_CURRENT_TAG`；只重建原版本时保留摘要。

```bash
docker compose --env-file .env --env-file .updater.env pull
docker compose --env-file .env --env-file .updater.env up -d
```

普通更新不需要先执行 `docker compose down`。先 `down` 会同时停止 app 和 updater，扩大不必要的停机窗口；只有修改网络、项目名或需要完整移除项目时才考虑使用它。

完整备份与迁移方法见 [Docker 数据持久化与备份](./DOCKER_DATA_AND_BACKUP.md)。

[文档中心](./docs/README.md) · [发行说明](./RELEASE_POLICY.md) · [支持](./SUPPORT.md) · [许可与协议](./legal/README.md)

## 漫画增强：自动检测与安装显卡环境

一键脚本默认使用 auto：优先识别 WSL2 /dev/dxg，其次 NVIDIA 和 Intel/AMD DRI。缺少所需 GPU 环境时自动安装；已安装且验证通过的环境会直接复用。无需另外安装 CUDA Toolkit，漫画增强使用 NCNN Vulkan。

Ubuntu/Debian 的 WSL2 会自动构建并安装经过校验的独立 Dozen Vulkan 驱动；普通 Linux 原生版会补装 Vulkan loader、工具及 Mesa 驱动。NVIDIA 用户态 Vulkan 库仅安装与当前驱动匹配的版本。

普通 Linux 的 NVIDIA Docker 模式会在缺失时安装 NVIDIA Container Toolkit，并为本机系统 Docker 配置运行时；首次配置需要重启 Docker，可能短暂影响其他容器。远程、自定义或 rootless 守护进程不会被自动改写。

WSL2 的 Windows 显卡驱动需已支持 GPU 透传。Dozen 仍为实验性驱动；当前已验证 RTX 4060 Ti，其他设备与 NAS 的驱动安装仍以厂商支持为准。自动补装目前支持 Ubuntu/Debian；其他发行版需要预装 GPU 环境。

Docker 安装前会以实际服务用户运行硬件 Vulkan 和五种内置增强引擎测试；软件渲染器 llvmpipe/lavapipe 不会被当作硬件显卡。原生安装会检查主机硬件 Vulkan，安装后可在设置页运行相同的引擎能力测试。

WSL 配置直接写入主 Compose 文件和原生服务环境，后续一键更新继续沿用。WSL Docker 守护进程必须位于可访问 /dev/dxg 和驱动目录的同一发行版内。

可用 SCRAPEFUN_GPU_MODE=none 禁用显卡环境安装，也可指定 wsl、nvidia 或 dri。自动模式的硬件测试失败时会明确提示 CPU 回退；显式指定 GPU 模式失败则停止部署。环境安装失败会停止部署，不会替换现有应用容器。

验收结果：当前发布的 v0.4.0 原生版和 Docker 版均在 WSL2 的 RTX 4060 Ti 上通过 Waifu2x Fast、Waifu2x、Real-CUGAN SE、Real-CUGAN Pro 和 Real-ESRGAN 测试，512×768 图像放大为 1024×1536，严格 GPU 模式无 CPU 回退，观测到显卡利用率最高 76%。

阅读器选择 GPU 0，分块大小选择自动（tile=0）。Real-CUGAN 在本环境的 tile=32 分块测试发生崩溃，实际页面请先使用自动分块验证。nvidia-smi 正常不等于 Vulkan 已可用，应以设置页能力测试和实际增强结果为准。
