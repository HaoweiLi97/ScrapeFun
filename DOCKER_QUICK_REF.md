# 🐳 ScrapeFun Docker 快速参考

## 一键部署
```bash
./deploy.sh
```

## 常用命令

### 启动/停止
```bash
# 启动
docker-compose up -d

# 停止（保留数据）
docker-compose down

# 停止并删除数据（危险！）
docker-compose down -v
```

### 查看状态
```bash
# 查看运行状态
docker-compose ps

# 查看日志
docker-compose logs -f app

# 查看资源使用
docker stats scrapetab
```

### 数据管理
```bash
# 查看 volumes
docker volume ls | grep scrapetab

# 备份所有数据
docker run --rm \
  -v scrapefun_db:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/scrapetab_full_backup_$(date +%Y%m%d).tar.gz -C /data .

# 恢复数据
docker run --rm \
  -v scrapefun_db:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/scrapetab_full_backup_YYYYMMDD.tar.gz"
```

### 更新应用
```bash
# 拉取最新镜像
docker pull haoweil/scrapetab:latest

# 重启服务
docker-compose down
docker-compose up -d
```

### 故障排查
```bash
# 进入容器
docker-compose exec app sh

# 查看完整日志
docker-compose logs --tail=100 app

# 重置数据库
docker-compose exec app npx prisma migrate reset --force
```

## 数据位置

| 数据类型 | Volume 名称 | 容器内路径 |
|---------|------------|-----------|
| 数据库 | scrapefun_db | /app/data/db |
| 图片 | scrapefun_images | /app/data/images |
| 配置 | scrapefun_config | /app/data/config |
| 本地化字幕 | scrapefun_local_subtitles | /app/data/local-subtitles |

## 端口

| 服务 | 端口 | 说明 |
|-----|------|-----|
| ScrapeFun | 4000 | 主应用 |
| FlareSolverr | 8191 | Cloudflare 绕过 |
| PostgreSQL | 5432 | R18Dev 数据库（可选） |

## 环境变量

```yaml
environment:
  - NODE_ENV=production
  - PORT=4000
  - FLARESOLVERR_URL=http://flaresolverr:8191/v1
```

## 访问地址

- 🌐 Web UI: http://localhost:4000
- 🔧 FlareSolverr: http://localhost:8191

## 📚 更多文档

- 详细部署指南: [DOCKER_GUIDE.md](./DOCKER_GUIDE.md)
- 数据持久化说明: [DOCKER_PERSISTENCE_SUMMARY.md](./DOCKER_PERSISTENCE_SUMMARY.md)
- 项目文档: [README.md](./README.md)
