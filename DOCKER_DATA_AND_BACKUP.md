# Docker 数据持久化与备份

> 最后更新：2026 年 7 月 26 日

ScrapeFun 的应用容器可以重建，用户数据应保存在 Compose 项目目录下的 `scrapefun-data` 中。

## 持久化目录

```text
scrapefun-data/
  db/
  images/
  config/
  custom-scrapers/
  local-subtitles/
```

| 目录 | 内容 |
| --- | --- |
| `db` | SQLite 数据库、媒体元数据、用户、配置和漫画清单缓存 |
| `images` | 海报、背景图、演员图和图片缓存 |
| `config` | 实例配置与运行状态 |
| `custom-scrapers` | 用户安装或编辑的自定义刮削器 |
| `local-subtitles` | 本地化保存的字幕 |

Compose 应包含：

```yaml
volumes:
  - ./scrapefun-data/db:/app/data/db
  - ./scrapefun-data/images:/app/data/images
  - ./scrapefun-data/config:/app/data/config
  - ./scrapefun-data/custom-scrapers:/app/data/custom-scrapers
  - ./scrapefun-data/local-subtitles:/app/data/local-subtitles
```

## 备份

在 Compose 项目目录执行：

```bash
docker compose stop
tar -czf "../scrapefun-backup-$(date +%Y%m%d-%H%M%S).tar.gz" .
docker compose start
```

备份文件包含数据、环境配置和 Compose 配置。请将备份复制到另一块磁盘或其他可靠位置。

## 恢复

1. 停止当前 Compose 项目。
2. 备份当前目录，避免覆盖后无法回退。
3. 将备份中的 `scrapefun-data`、`server.env`、`.updater.env` 和 `docker-compose.yml` 恢复到项目目录。
4. 重新启动服务。

```bash
docker compose up -d
```

## 更新与重建

以下操作不会主动删除绑定目录中的数据：

```bash
docker compose pull
docker compose up -d
docker compose down
```

更新或迁移后，确认新的 Compose 仍指向同一个 `scrapefun-data` 目录。

## 避免误删

- 不要手动删除 `scrapefun-data`
- 删除 NAS Compose 项目前先确认面板是否会同时删除项目目录
- 执行清理命令前先创建备份
- 修改数据挂载路径后检查新旧目录是否一致

## 迁移到新机器

在旧机器创建备份，将整个部署目录复制到新机器，确认目录权限后运行：

```bash
docker compose pull
docker compose up -d
```

访问地址可能因新机器 IP 或端口而变化，但媒体库、用户和实例配置会从持久化目录恢复。
