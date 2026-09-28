# Docker 部署与运维

**简体中文** · [English](./DOCKER_GUIDE.en.md)

> 文档更新：2026-09-28

适用于 Linux 主机和 NAS，镜像提供 `linux/amd64` 与 `linux/arm64`。先选择部署方式，再进行初始化；更新已有实例前先[备份](./DOCKER_DATA_AND_BACKUP.md)。

| 方式 | 适用环境 | 入口 |
| --- | --- | --- |
| 一键部署 | 可使用终端的 Linux 主机 | 本文 |
| 手动 Compose | NAS 面板、1Panel、CasaOS 等 | [Compose 部署指南](./DOCKER_COMPOSE_DEPLOYMENT.md) |
| 配置模板 | 核对生产服务与挂载 | [docker-compose.remote.yml](./docker-compose.remote.yml) |

## 安装前准备

- 安装 Docker Engine 与 Docker Compose 插件，确认当前用户可运行 `docker`。
- 准备可写的部署目录和持久化数据目录。
- 确认 `8096` 或计划使用的宿主机端口可用。
- 按硬件选择 GPU 模式；NVIDIA 主机先安装 NVIDIA Container Toolkit。

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
| `dri` | Intel / 多数 AMD / NAS 集显，映射 `/dev/dri` |
| `amd` | 同时需要 `/dev/dri` 与 `/dev/kfd` 的 AMD 主机 |
| `nvidia` | NVIDIA Container Toolkit，使用 `gpus: all` |
| `none` | 不透传 GPU |

非交互安装示例：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | \
  SCRAPEFUN_GPU_MODE=nvidia bash -s -- stable
```

设备透传只代表容器可访问硬件。实际解码、转码或增强能力仍取决于驱动、设备和媒体格式。

## 更新已有部署

先备份并暂停扫描、刮削及其他写入任务。重新运行脚本可同步部署配置并更新镜像；不指定频道时保留已有 stable / beta 频道、宿主机端口和数据目录：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

默认目录的一键部署也可手动执行：

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

## 后续阅读

[Compose 配置](./DOCKER_COMPOSE_DEPLOYMENT.md) · [备份与恢复](./DOCKER_DATA_AND_BACKUP.md) · [发行说明](./RELEASE_POLICY.md) · [支持](./SUPPORT.md) · [许可与协议](./legal/README.md)
