# Docker 数据持久化、备份与恢复

> 最后更新：2026 年 9 月 2 日

ScrapeFun 容器可以随时重建，业务数据必须保存在宿主机。当前唯一推荐的 Compose 写法是把整个数据根目录挂载到 `/app/data`：

```yaml
services:
  app:
    volumes:
      - ${SCRAPEFUN_DATA_DIR:-./scrapefun-data}:/app/data
```

不要分别挂载 `db`、`images`、`config`、`custom-scrapers` 等子目录。分目录配置只能保护当时列出的内容，新版本增加 `user-avatars`、模型、缓存或其他运行目录后，未挂载的数据会留在容器可写层，并在容器重建时丢失。

## 数据目录

默认宿主机目录是一键部署目录旁的 `~/scrapefun-data`；NAS 手动 Compose 通常使用项目目录下的 `./scrapefun-data`。实际路径以 `.updater.env` 的 `SCRAPEFUN_DATA_DIR` 或 Compose 配置为准。

主要内容包括：

| 子目录 | 内容 | 应用内备份 |
| --- | --- | --- |
| `db` | SQLite 数据库、设置、用户、媒体库、进度和任务 | 包含 |
| `images` | 海报、背景图、生成封面和阅读背景 | 包含 |
| `user-avatars` | 用户头像 | 包含 |
| `config` | 系统刮削器运行时配置 | 包含 |
| `custom-scrapers` | 旧版兼容的自定义刮削器文件 | 存在时包含 |
| `local-subtitles` | 本地字幕 | 包含 |
| `video-proxy-cache`、`transcode-cache` | 视频代理和转码缓存 | 不包含，可重建 |
| `comic-cache`、`image-cache`、`image-upscale-cache` | 漫画和图片缓存 | 不包含，可重建 |
| `media-probe-v2`、`temp`、`logs`、`cache` | 探测、临时文件和日志 | 不包含，可重建 |

## 从旧分目录挂载迁移

先检查当前容器：

```bash
docker inspect scrapefun \
  --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

如果看到多条 `/app/data/db`、`/app/data/images` 等挂载，不要直接编辑 Compose 后重建。最新版一键脚本会默认停止，并要求显式执行迁移：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh \
  | bash -s -- stable ~/scrapefun --migrate-data-root
```

迁移工具会：

1. 停止 app 的写入任务并保留一份应用内备份。
2. 停止 app，但先不要删除旧容器。
3. 将旧容器 `/app/data` 中未挂载的其他目录复制到统一宿主机数据根目录。
4. 确认数据库、图片、配置、头像、字幕和其他目录都在同一个根目录。
5. 把 Compose 改为单个根挂载，再重建 app。
6. 验证登录、媒体库、图片、刮削器和播放后，才删除旧容器或迁移副本。

无法判断哪些文件只存在于旧容器时，不要继续重建；先保留旧容器并寻求支持。

## 应用内备份（推荐）

进入 `设置 → 通用 → 备份与恢复`，点击“导出”。当前 `snapshot-v4` 备份使用 SQLite 一致性快照，并为每个文件记录大小与 SHA-256。它包含数据库、图片、头像、刮削器配置和本地字幕；可再生成的媒体缓存、临时文件和日志不会进入备份。

`snapshot-v3`、`snapshot-v2` 和 `backup.json` 仍可导入。恢复会在修改当前数据前完成路径、逐文件校验、空间和 SQLite 检查，并在中断时回滚。旧备份恢复成功后，应立即导出一份新的 `snapshot-v4`。应用备份可能包含存储连接配置，应加密保存并复制到另一台设备。

## Docker 宿主机完整备份

灾难恢复应同时备份数据目录与部署配置。一键部署会在部署目录安装经过校验的运维工具：

```bash
cd ~/scrapefun
./operations/backup-docker.sh --deploy-dir "$PWD" --output-dir /srv/backups/scrapefun
```

工具自动读取 `.updater.env`、停止并恢复 app、验证 SQLite、归档数据和配置、生成 manifest/SHA-256，并保留 7 日、4 周、6 月恢复点。缓存默认排除；添加 `--include-caches` 才会包含。符号链接或特殊文件会在归档前被拒绝，避免生成不安全或不完整的备份。

可选的加密和异机复验：

```bash
./operations/backup-docker.sh \
  --deploy-dir "$PWD" \
  --output-dir /srv/backups/scrapefun \
  --age-recipient age1你的公钥 \
  --rclone-remote minio:scrapefun/backups
```

`server.env` 和 `.updater.env` 可能包含密钥。age 私钥必须存放在数据目录和备份之外；只有远端副本重新下载并通过 SHA-256 复验，才算异机备份成功。

使用 `install-docker-backup-timer.sh` 安装 systemd 定时任务时，通知地址保存在仅 root 可读的 `/etc/scrapefun-backup.env`，不会出现在 `ExecStart` 命令行中。

## 从应用备份恢复

1. 先导出当前实例备份作为回退点。
2. 确认没有扫描、刮削、整理、转码或升级任务。
3. 在 `设置 → 通用 → 备份与恢复` 中选择“导入”。
4. 上传 ScrapeFun 导出的 ZIP，等待恢复成功并自动重启。
5. 恢复后检查登录、用户、媒体库、图片、刮削器、WebDAV/AList、播放与阅读进度。

恢复会先校验归档和 SQLite，再写入暂存位置，并在重启时统一提交；失败时会回滚。每次成功恢复还会保留恢复前数据库，默认保留最近 3 份，但这些本地副本不能代替离机备份。

## 从完整数据目录恢复

使用恢复工具，不要直接覆盖当前目录：

```bash
cd ~/scrapefun
./operations/restore-docker.sh \
  --deploy-dir "$PWD" \
  --backup /srv/backups/scrapefun/scrapefun-docker-backup-YYYYMMDDTHHMMSSZ.tar.gz
```

工具会校验内外归档、预检空间、在新目录解压、检查 SQLite、保留当前数据为 `.pre-restore-*`，并在启动后验证 readiness。加密归档需添加 `--age-identity /安全路径/identity.txt`。恢复验证完成并重新生成备份后，才删除旧目录。

定期运行隔离恢复演练：

```bash
./operations/drill-docker-backup.sh --backup /srv/backups/scrapefun/备份文件.tar.gz
```

## 恢复后检查

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml ps
docker compose --env-file .updater.env -f docker-compose.remote.yml logs --tail=200 app
curl -fsS http://127.0.0.1:8096/health/live
curl -fsS http://127.0.0.1:8096/health/ready
```

`/health/ready` 会检查启动、数据库、数据目录权限和恢复事务；仍应实际检查登录、媒体库、海报/头像、本地字幕、刮削器注册、WebDAV/AList 和一次播放。

## 避免误删

- 不要执行 `docker compose down -v`。
- 不要删除或清空 `scrapefun-data`。
- 不要把新备份直接解压覆盖正在使用的数据目录。
- 不要只备份 SQLite 数据库；数据库和文件资源必须来自同一时间点。
- NAS 删除 Compose 项目前，先确认面板不会同时删除绑定目录。
- 更新或重建后，确认仍是同一个宿主机目录挂载到 `/app/data`。
