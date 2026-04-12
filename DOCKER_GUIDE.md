# ScrapeFun Docker 部署指南

## 快速开始

### 使用 Docker Compose（推荐）

```bash
# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f app

# 停止服务
docker-compose down

# 停止并删除所有数据（谨慎使用！）
docker-compose down -v
```

### 使用 Docker Hub 镜像

```bash
# 拉取最新镜像
docker pull haoweil/scrapetab:latest

# 运行容器
docker run -d \
  --name scrapetab \
  -p 4000:4000 \
  -v scrapefun_db:/app/data/db \
  -v scrapefun_images:/app/data/images \
  -v scrapefun_config:/app/data/config \
  -v scrapefun_local_subtitles:/app/data/local-subtitles \
  -e FLARESOLVERR_URL=http://your-flaresolverr:8191/v1 \
  haoweil/scrapetab:latest
```

## 数据持久化

ScrapeFun 使用 Docker volumes 来持久化以下数据：

### 1. **数据库** (`scrapefun_db`)
- **路径**: `/app/data/db`
- **包含内容**:
  - `dev.db` - SQLite 数据库文件
  - 媒体元数据（标题、年份、评分、简介等）
  - Custom Scrapers（自定义刮削器代码）
  - Cleaning Rules（清理规则）
  - Custom Scraper Configurations（刮削器配置）
  - Composite Scrapers（组合刮削器）
  - 系统设置

### 2. **图片** (`scrapefun_images`)
- **路径**: `/app/data/images`
- **包含内容**:
  - 海报图片（Posters）
  - 背景图片（Backdrops/Fanart）
  - 缩略图（Thumbnails）
  - 其他媒体图片

### 3. **配置** (`scrapefun_config`)
- **路径**: `/app/data/config`
- **包含内容**:
  - 运行时配置文件
  - 安装态相关持久数据

### 4. **本地化字幕** (`scrapefun_local_subtitles`)
- **路径**: `/app/data/local-subtitles`
- **包含内容**:
  - 通过“字幕本地化”保存的字幕文件
  - 按媒体目录散列归档的本地字幕内容

如果你用 Docker 更新镜像或重建容器，但没有持久化这个目录，本地化字幕会丢失。
也可以通过 `LOCAL_SUBTITLE_DIR` 把它改到你自己的挂载路径。

### 5. **系统刮削器** (`scrapetab_scrapers`)
- **路径**: `/app/server/src/scrapers`
- **包含内容**:
  - 内置刮削器代码（如 TMDB）
  - 刮削器基类和工具

## 数据备份与恢复

### 方法 1: 使用应用内置的备份功能

应用提供了完整的备份和恢复功能，可以导出/导入所有数据：

1. 打开 ScrapeFun 设置页面
2. 点击 "Export Data" 导出所有数据（包括数据库、图片、刮削器）
3. 保存备份文件到安全位置
4. 需要恢复时，点击 "Import Data" 并选择备份文件

### 方法 2: 手动备份 Docker Volumes

```bash
# 备份数据库
docker run --rm \
  -v scrapefun_db:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/scrapefun_db_backup.tar.gz -C /data .

# 备份图片
docker run --rm \
  -v scrapefun_images:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/scrapefun_images_backup.tar.gz -C /data .

# 备份刮削器
docker run --rm \
  -v scrapefun_local_subtitles:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/scrapefun_local_subtitles_backup.tar.gz -C /data .
```

### 恢复备份

```bash
# 恢复数据库
docker run --rm \
  -v scrapefun_db:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/scrapefun_db_backup.tar.gz"

# 恢复图片
docker run --rm \
  -v scrapefun_images:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/scrapefun_images_backup.tar.gz"

# 恢复刮削器
docker run --rm \
  -v scrapefun_local_subtitles:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/scrapefun_local_subtitles_backup.tar.gz"
```

## 数据迁移

### 从本地开发环境迁移到 Docker

```bash
# 1. 停止 Docker 容器
docker-compose down

# 2. 复制数据库
docker run --rm \
  -v scrapetab_data:/data \
  -v $(pwd)/server/prisma:/source \
  alpine cp /source/dev.db /data/dev.db

# 3. 复制图片
docker run --rm \
  -v scrapetab_images:/data \
  -v $(pwd)/server/public/images:/source \
  alpine sh -c "cp -r /source/* /data/"

# 4. 复制刮削器（如果有自定义修改）
docker run --rm \
  -v scrapetab_scrapers:/data \
  -v $(pwd)/server/src/scrapers:/source \
  alpine sh -c "cp -r /source/* /data/"

# 5. 重启容器
docker-compose up -d
```

### 从 Docker 导出到本地

```bash
# 导出数据库
docker run --rm \
  -v scrapetab_data:/data \
  -v $(pwd):/backup \
  alpine cp /data/dev.db /backup/dev.db

# 导出图片
docker run --rm \
  -v scrapetab_images:/data \
  -v $(pwd):/backup \
  alpine sh -c "cp -r /data /backup/images"
```

## 环境变量

可以通过环境变量配置应用：

```yaml
environment:
  - NODE_ENV=production
  - PORT=4000
  - FLARESOLVERR_URL=http://flaresolverr:8191/v1
  # 添加其他环境变量...
```

## 更新应用

### 使用 Docker Compose

```bash
# 拉取最新代码
git pull

# 重新构建并启动
docker-compose up -d --build
```

### 使用 Docker Hub 镜像

```bash
# 拉取最新镜像
docker pull haoweil/scrapetab:latest

# 停止并删除旧容器
docker stop scrapetab
docker rm scrapetab

# 启动新容器（数据会保留在 volumes 中）
docker run -d \
  --name scrapetab \
  -p 4000:4000 \
  -v scrapefun_db:/app/data/db \
  -v scrapefun_images:/app/data/images \
  -v scrapefun_config:/app/data/config \
  -v scrapefun_local_subtitles:/app/data/local-subtitles \
  -e FLARESOLVERR_URL=http://your-flaresolverr:8191/v1 \
  haoweil/scrapetab:latest
```

## 故障排查

### 查看日志

```bash
# Docker Compose
docker-compose logs -f app

# Docker
docker logs -f scrapetab
```

### 进入容器调试

```bash
# Docker Compose
docker-compose exec app sh

# Docker
docker exec -it scrapetab sh
```

### 检查 volumes

```bash
# 列出所有 volumes
docker volume ls

# 检查 volume 详情
docker volume inspect scrapefun_db
docker volume inspect scrapefun_images
docker volume inspect scrapefun_config
docker volume inspect scrapefun_local_subtitles
```

### 重置数据库

```bash
# 进入容器
docker-compose exec app sh

# 重置数据库
cd /app/server
npx prisma migrate reset --force
npx prisma generate
```

## 多平台支持

镜像支持以下平台：
- `linux/amd64` - x86_64 架构（Intel/AMD）
- `linux/arm64` - ARM64 架构（Apple Silicon, Raspberry Pi 4+）

Docker 会自动选择适合您系统的镜像。

## 端口说明

- `4000` - ScrapeFun 主应用
- `8191` - FlareSolverr（用于绕过 Cloudflare）
- `5432` - PostgreSQL（用于 R18Dev 数据库，可选）

## 安全建议

1. **定期备份**: 使用应用内置备份功能或手动备份 volumes
2. **访问控制**: 如果暴露到公网，建议使用反向代理（如 Nginx）并配置认证
3. **更新镜像**: 定期拉取最新镜像以获取安全更新
4. **环境变量**: 敏感信息（如数据库密码）使用 Docker secrets 或 .env 文件

## 性能优化

### 限制资源使用

```yaml
services:
  app:
    # ... 其他配置
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

### 使用本地绑定挂载（开发环境）

如果需要实时编辑代码，可以使用绑定挂载：

```yaml
volumes:
  - ./server/prisma:/app/server/prisma
  - ./server/public/images:/app/server/public/images
  - ./server/src/scrapers:/app/server/src/scrapers
```

## 支持

如有问题，请访问：
- GitHub Issues: [项目地址]
- 文档: [文档地址]
