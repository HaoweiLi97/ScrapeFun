# Docker 部署入口

> 最后更新：2026 年 9 月 2 日

为避免多份 Compose 示例和备份命令长期分叉，Docker 文档按用途拆分：

- [NAS / 手动 Docker Compose 部署](./DOCKER_COMPOSE_DEPLOYMENT.md)
- [Docker 数据持久化、备份与恢复](./DOCKER_DATA_AND_BACKUP.md)
- [仓库提供的生产 Compose 模板](./docker-compose.remote.yml)

Linux 主机推荐运行一键部署脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

无论使用脚本还是 NAS 面板，业务数据都应通过一个根挂载保存：

```yaml
volumes:
  - ${SCRAPEFUN_DATA_DIR:-./scrapefun-data}:/app/data
```

不要使用只挂载 `db`、`images`、`config` 等已知子目录的旧写法。新版本可能增加新的数据目录；根挂载才能保证容器更新或重建后它们仍然存在。

> 不要执行 `docker compose down -v`，不要删除 `scrapefun-data`。恢复前请先保留当前目录作为回退点。
