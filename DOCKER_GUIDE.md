# Docker 部署与运维

**简体中文** · [English](./DOCKER_GUIDE.en.md)

> 文档更新：2026-10-20

适用于 Linux 主机和 NAS，当前发布流程默认构建 `linux/amd64`；其他架构先核对所选标签的镜像清单。先选择部署方式，再进行初始化；更新已有实例前先[备份](./DOCKER_DATA_AND_BACKUP.md)。

| 方式 | 适用环境 | 入口 |
| --- | --- | --- |
| 一键部署 | 可使用终端的 Linux 主机 | 本文 |
| 手动 Compose | NAS 面板、1Panel、CasaOS 等 | [Compose 部署指南](./DOCKER_COMPOSE_DEPLOYMENT.md) |
| 配置模板 | 核对生产服务与挂载 | [docker-compose.remote.yml](./docker-compose.remote.yml) |

## 安装前准备

- 安装 Docker Engine 与 Docker Compose 插件，确认当前用户可运行 `docker`。
- 准备可写的部署目录和持久化数据目录。
- 确认 `8096` 或计划使用的宿主机端口可用。
- 默认自动检测显卡并补装缺失环境；普通 Linux 主机显卡驱动应已可用。

```bash
docker version
docker compose version
```

## 稳定版安装

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable
```

脚本默认创建以下位置：

| 位置 | 用途 |
| --- | --- |
| `~/scrapefun` | Compose、`server.env`、`.updater.env` 和运维工具 |
| `~/scrapefun-data` | 挂载到 `/app/data` 的完整业务数据根 |

可显式指定部署目录：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable /opt/scrapefun
```

当前用户需要对目标目录有写权限。脚本会保留已有环境设置；全新安装会生成登录令牌密钥和 updater Token。不要把环境文件提交到公开仓库。

安装后打开 `http://服务器IP:8096`，按网页提示完成初始化。自定义宿主机端口时使用实际端口。

## GPU 模式

| 模式 | 设备或前置条件 |
| --- | --- |
| `auto` | 默认：检测 GPU 并执行容器预检；失败时回退 CPU |
| `dri` | Intel / AMD / NAS 集显，默认映射单个渲染节点 |
| `amd` | 旧参数别名，按 `dri` 处理，不映射 `/dev/kfd` |
| `nvidia` | NVIDIA Container Toolkit，使用 `gpus: all` |
| `wsl` | WSL2 `/dev/dxg`，自动安装独立 Vulkan 驱动 |
| `none` | 不透传 GPU |

非交互安装示例：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | \
  SCRAPEFUN_GPU_MODE=nvidia bash -s -- stable
```

设备透传只代表容器可访问硬件。实际解码、转码或增强能力仍取决于驱动、设备和媒体格式。

确认主机存在对应渲染节点，可设置 `SCRAPEFUN_DRI_DEVICE=/dev/dri/renderD128`；仅 NAS 确实需要整个目录时才设为 `all`。NVIDIA 的 `NVIDIA_DRIVER_CAPABILITIES` 必须包含 `video` 和 `graphics`。显式选择 `dri` / `nvidia` 时，容器 Vulkan / Waifu2x 预检失败会中止部署。

## 更新已有部署

先备份并暂停扫描、刮削及其他写入任务。重新运行脚本可同步部署配置并更新镜像；不指定频道时保留已有 stable / beta 频道、宿主机端口和数据目录：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

默认目录的一键部署也可手动执行：

若 `.updater.env` 中已保存 `@sha256` 摘要，`pull` 会保留固定版本。要跟随渠道升级，先将 `SCRAPETAB_IMAGE`、`SCRAPETAB_UPDATER_IMAGE` 改为目标渠道的 `:latest` / `:beta` 标签，并设置匹配的 `UPDATE_CURRENT_TAG`；只重建原版本时保留摘要。

```bash
cd ~/scrapefun
docker compose --env-file .updater.env -f docker-compose.remote.yml pull
docker compose --env-file .updater.env -f docker-compose.remote.yml up -d --remove-orphans
```

使用自定义目录时，先进入实际目录。普通更新无需提前 `down`；服务重建仍会中断播放和后台任务。

## 频道切换

安装或切到 beta：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- beta
```

明确回到 stable：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable
```

自定义部署目录需在频道参数后追加该目录。app 和 updater 应使用配套频道；`latest` / `beta` 是会随发布变化的别名，不是固定版本。切换前保存备份，旧版本不保证能读取较新版本写入的数据。

## 数据持久化与更新权限

必须把完整数据根目录挂载到 `/app/data`：

```yaml
volumes:
  - ${SCRAPEFUN_DATA_DIR:-./scrapefun-data}:/app/data
```

旧的分目录挂载应按[迁移指南](./DOCKER_DATA_AND_BACKUP.md#从旧分目录挂载迁移)处理，不能先重建再补数据。

updater 使用独立镜像 `haoweil/scrapefun-updater`，挂载 Docker socket；不要将 `4182` 暴露到公网。没有 updater 的环境仍可手动更新。完整配置见 [Compose 指南](./DOCKER_COMPOSE_DEPLOYMENT.md)。

## 更新后验证

以下命令适用于默认目录和端口：

```bash
cd ~/scrapefun
docker compose --env-file .updater.env -f docker-compose.remote.yml ps
docker compose --env-file .updater.env -f docker-compose.remote.yml logs --tail=100 app
curl -fsS http://127.0.0.1:8096/health/live
curl -fsS http://127.0.0.1:8096/health/ready
```

随后实际检查登录、媒体库、海报、播放与阅读进度。失败时先保留当前数据和日志，参照[备份与恢复](./DOCKER_DATA_AND_BACKUP.md)处理；公开反馈前脱敏。

## 原生 systemd 安装

已有安装请先通过下方命令或 `sudo scrapefun update` 升级一次到 Linux 原生 Server 0.4.4，安装网页手动更新所需组件。自定义实例请沿用已有 `--config-dir`。

原生包支持 glibc Linux amd64，要求运行中的 systemd、Node.js 20/22/24、Python 3、curl、FFmpeg 和 FFprobe。脚本下载对应渠道的发布包并校验 SHA-256，不在主机编译源码；没有匹配发布包时退出。

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-native-deploy.sh | sudo bash
# Beta：将 sudo bash 换成 sudo bash -s -- beta
```

首次终端安装会询问端口，默认 8096。指定端口、补齐基础依赖并无人值守安装：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-native-deploy.sh \
  | sudo bash -s -- stable --port 18096 --install-deps --non-interactive
```

仅检查使用 `--check` 或 `--dry-run`，不会安装依赖或重启服务；指定版本使用 `--version 0.4.2`，本地包使用 `--archive /path/release.tar.gz`（旁边须有 `.sha256`）。端口优先级为 `--port` > `APP_HOST_PORT` > 已保存端口 > 8096，更新时不指定则保留原端口。Docker 一键入口也支持 `--port 18096`。环境变量应放在运行安装器的命令前，不能仅放在管道左侧的 curl 前。

`--install-deps` 使用现有 apt-get/dnf/yum/zypper/pacman 软件源安装缺失基础包；FFmpeg 不在当前软件源时会明确报错。缺少兼容 Node 时从 nodejs.org 下载并校验独立 Node 22，保存在配置目录中，不替换全局 Node。原生包只支持 glibc Linux amd64 和运行中的 systemd；其他架构、Alpine/musl 或未启用 systemd 的 WSL 会提前退出。

自定义路径使用 `--install-dir`、`--data-dir`、`--config-dir`；多实例另设 `--service-name` 和 `--service-user`。后续只指定 `--config-dir` 即可复用该实例的已有路径与服务设置。安装会检查目标端口、路径、运行库、磁盘空间和包完整性，通过应用就绪检查后才显示完成；失败或中断会恢复旧程序、配置、管理工具和更新前数据。完整参数与使用边界见 [Linux 服务端安装与管理](./docs/linux-server-management.md)。

默认程序 `/opt/scrapefun`、数据 `/var/lib/scrapefun`、配置 `/etc/scrapefun/server.env`。使用 `sudo scrapefun status`、`health`、`logs --follow`、`update`、`backup` 管理；修改配置后运行 `sudo scrapefun restart`。备份含密钥，应存放在数据目录之外。原生归档使用 `sudo scrapefun restore /path/to/backup.tar.gz`，不能直接用于 Docker 恢复工具。

## 后续阅读

[Compose 配置](./DOCKER_COMPOSE_DEPLOYMENT.md) · [备份与恢复](./DOCKER_DATA_AND_BACKUP.md) · [发行说明](./RELEASE_POLICY.md) · [支持](./SUPPORT.md) · [许可与协议](./legal/README.md)

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
