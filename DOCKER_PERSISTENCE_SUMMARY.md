# Docker 数据持久化配置总结

## ✅ 已完成的配置

### 1. Docker Compose 配置更新

在 `docker-compose.yml` 中添加了三个 volumes：

```yaml
volumes:
  # 数据库 - 存储所有元数据、自定义刮削器、清理规则和配置
  - scrapetab_data:/app/server/prisma
  
  # 图片 - 存储下载的海报、背景图和其他媒体图片
  - scrapetab_images:/app/server/public/images
  
  # 系统刮削器 - 存储内置刮削器代码
  - scrapetab_scrapers:/app/server/src/scrapers
```

### 2. 数据持久化覆盖范围

#### ✅ 数据库 (scrapetab_data)
存储在 SQLite 数据库中的所有数据：
- ✅ 媒体元数据（Metadata）
- ✅ 自定义刮削器（CustomScraper）
- ✅ 清理规则（CleaningScript）
- ✅ 自定义刮削器配置（通过 CustomScraper 表）
- ✅ 组合刮削器（CompositeScraper）
- ✅ 剧集信息（Episode）
- ✅ 媒体文件关联（MediaFile）
- ✅ 图片元数据（Image - 仅元数据，实际文件在 scrapetab_images）
- ✅ 系统设置（Setting）

#### ✅ 图片文件 (scrapetab_images)
- ✅ 海报图片（Posters）
- ✅ 背景图片（Backdrops/Fanart）
- ✅ 缩略图（Thumbnails）
- ✅ 所有下载的媒体图片

#### ✅ 系统刮削器 (scrapetab_scrapers)
- ✅ TMDB 刮削器
- ✅ 其他内置刮削器
- ✅ 刮削器基类和工具

### 3. 启动脚本增强

更新了 `server/start.sh`：
- ✅ 自动创建必要的目录
- ✅ 恢复 schema.prisma（如果被 volume 覆盖）
- ✅ 自动同步数据库结构

### 4. .dockerignore 优化

添加了更多排除规则：
- ✅ 排除开发数据库（使用 volume 代替）
- ✅ 排除本地图片（使用 volume 代替）
- ✅ 排除临时文件和缓存
- ✅ 减小 Docker 镜像大小

### 5. 文档

创建了完整的文档：
- ✅ `DOCKER_GUIDE.md` - 详细的 Docker 部署和数据管理指南
- ✅ `README.md` - 项目主文档，包含 Docker 部署说明
- ✅ `.env.example` - 环境变量配置模板
- ✅ `deploy.sh` - 一键部署脚本

## 📊 数据存储架构

```
Docker Volumes
├── scrapetab_data (数据库)
│   ├── dev.db                    # SQLite 数据库
│   ├── dev.db-journal            # 数据库日志
│   ├── schema.prisma             # 数据库 schema
│   └── migrations/               # 数据库迁移
│
├── scrapetab_images (图片)
│   └── [各种媒体图片文件]
│
└── scrapetab_scrapers (刮削器)
    ├── TMDB_TV.scraper.ts
    ├── base.scraper.ts
    ├── composite.scraper.ts
    ├── manager.ts
    ├── scripted.scraper.ts
    └── types.ts
```

## 🔄 数据流程

### 写入流程
1. 用户刮削媒体 → 
2. 元数据写入数据库 (`scrapetab_data/dev.db`) → 
3. 图片下载到 `scrapetab_images/` → 
4. 图片路径记录在数据库中

### 读取流程
1. 应用启动 → 
2. 从 `scrapetab_data/dev.db` 读取元数据 → 
3. 从 `scrapetab_images/` 提供图片服务 → 
4. 从 `scrapetab_scrapers/` 加载刮削器

## 🚀 使用方法

### 启动服务
```bash
docker-compose up -d
```

### 查看数据
```bash
# 查看所有 volumes
docker volume ls | grep scrapetab

# 检查数据库大小
docker run --rm -v scrapetab_data:/data alpine du -sh /data

# 检查图片数量
docker run --rm -v scrapetab_images:/data alpine find /data -type f | wc -l
```

### 备份数据
```bash
# 使用应用内置功能（推荐）
# 访问 Settings > Backup & Restore > Export Data

# 或手动备份
docker run --rm \
  -v scrapetab_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/scrapetab_backup.tar.gz -C /data .
```

### 恢复数据
```bash
# 使用应用内置功能（推荐）
# 访问 Settings > Backup & Restore > Import Data

# 或手动恢复
docker run --rm \
  -v scrapetab_data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/scrapetab_backup.tar.gz"
```

## 🔒 数据安全

### 自动持久化
- ✅ 容器重启 - 数据保留
- ✅ 容器删除 - 数据保留
- ✅ 镜像更新 - 数据保留

### 数据丢失场景
- ⚠️ 执行 `docker-compose down -v` - 会删除所有 volumes
- ⚠️ 手动删除 volumes - `docker volume rm scrapetab_data`

### 建议
1. ✅ 定期使用应用内置备份功能
2. ✅ 重要操作前先备份
3. ✅ 使用 `docker-compose down`（不带 -v）停止服务
4. ✅ 考虑使用外部备份工具定期备份 volumes

## 📈 未来改进

可选的增强功能：
- [ ] 支持外部数据库（PostgreSQL/MySQL）
- [ ] 支持 S3/对象存储作为图片存储
- [ ] 自动备份到云存储
- [ ] 数据加密
- [ ] 多节点部署支持

## ✅ 验证清单

在部署后验证数据持久化：

1. ✅ 启动容器并刮削一些媒体
2. ✅ 检查数据库中是否有数据
3. ✅ 检查图片是否下载
4. ✅ 重启容器 `docker-compose restart`
5. ✅ 验证数据是否还在
6. ✅ 删除并重新创建容器
   ```bash
   docker-compose down
   docker-compose up -d
   ```
7. ✅ 再次验证数据是否还在

## 🎯 总结

现在 Docker 部署已经完全支持数据持久化，涵盖：
- ✅ 刮削的媒体元数据
- ✅ 下载的图片
- ✅ Custom Scrapers（自定义刮削器）
- ✅ System Scrapers（系统刮削器）
- ✅ Cleaning Rules（清理规则）
- ✅ Custom Scraper Configurations（自定义刮削器配置）
- ✅ 所有系统设置

所有数据都会在容器重启、更新或重新部署时保留！
