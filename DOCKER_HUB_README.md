# ScrapeFun 媒体资产管理与元数据索引平台

ScrapeFun 是一款专为 WebDAV 环境及高阶影音爱好者设计的综合性媒体资产管理解决方案。本平台集成先进的元数据刮削技术、可扩展的脚本引擎以及全双工实时同步机制，旨在提供卓越的媒体库自动化管理体验。

## 核心功能概览

自动化元数据索引：系统具备智能识别算法，可精确匹配影视作品元数据，并自动提取高解析度海报、剧照等视觉资产。

原生 WebDAV 协议支持：深度适配 WebDAV 存储架构，支持对远程存储媒介进行无缝索引、逻辑关联与流媒体传输。

可扩展脚本引擎：内置 JavaScript 运行时环境，允许开发者通过编写自定义脚本扩展刮削逻辑，以满足特定的资源索引需求。

实时状态同步 (Live Sync)：基于 WebSocket 协议构建全双工通信层，确保多终端（平板及电视端）间的播放进度、用户评分及收藏状态实现毫秒级的一致性。

架构性能优化：底层采用 SQLite Write-Ahead Logging (WAL) 并发模式，结合深度优化的索引机制，显著提升了海量数据环境下的查询响应速度。

多平台客户端覆盖：提供经过针对性优化的 Android Pad 及 Android TV 原生应用程序，确保跨设备的交互体验一致性。

## 部署流程

1. 基于 Docker Compose 的标准化部署

建议使用 Docker Compose 进行环境编排。请创建并配置 docker-compose.yml 文件如下：

```yaml
version: '3.8'

services:
  scrapetab:
    image: haoweil/scrapetab:latest
    container_name: scrapetab
    ports:
      - "4000:4000"
    environment:
      - NODE_ENV=production
      - FLARESOLVERR_URL=http://flaresolverr:8191/v1
    volumes:
      - scrapefun_db:/app/data/db
      - scrapefun_images:/app/data/images
      - scrapefun_config:/app/data/config
      - scrapefun_local_subtitles:/app/data/local-subtitles
    restart: unless-stopped
    depends_on:
      - flaresolverr

  flaresolverr:
    image: flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    restart: unless-stopped
    environment:
      - TZ=Asia/Shanghai

volumes:
  scrapefun_db:
  scrapefun_images:
  scrapefun_config:
  scrapefun_local_subtitles:
```

2. 数据库 Schema 初始化

在初次部署或执行版本更迭后，必须通过以下指令完成数据库架构的同步与初始化：

```bash
docker exec scrapetab npx prisma db push
```

## 客户端资产获取

本平台提供针对 Android Pad 与 Android TV 优化的原生客户端：

分发渠道

访问路径

认证码/备注

Quark Cloud

访问下载页面：https://pan.quark.cn/s/4d8397fc88ea?pwd=BSBk

提取码: BSBk

Google Drive

访问官方镜像：https://drive.google.com/drive/folders/1BTQi7WCSHcRNmsrlY6wRW3J8HKe0JNE1?usp=drive_link

官方维护镜像

## 配置规范 (环境变量)

参数名称

功能描述

缺省值

PORT

核心服务侦听端口

4000

FLARESOLVERR_URL

FlareSolverr 服务终结点（用于反爬虫策略规避）

-

TMDB_API_KEY

TMDB 平台 API 凭证（用于元数据检索）

-

WEBDAV_URL

目标 WebDAV 存储服务终结点

-

## 运维与数据安全

运行维护指令

实时日志审计：docker logs -f scrapetab

环境重置：docker exec -it scrapetab npx prisma migrate reset --force

版本升级规程：

```bash
docker pull haoweil/scrapetab:latest
docker-compose up -d
docker exec scrapetab npx prisma db push
```

资产持久化路径说明

scrapefun_db: 承载核心数据库文件 (dev.db)。

scrapefun_images: 存储经刮削获取的媒体海报及关联视觉素材。

scrapefun_config: 存储运行时配置和安装态持久数据。

scrapefun_local_subtitles: 存储“字幕本地化”保存的字幕文件；如果不挂载这个 volume，更新或重建容器后本地化字幕会丢失。

## 联络与合规性

开发团队: lihaowei977@gmail.com

架构兼容性: 支持 linux/amd64 与 linux/arm64 (包括 Apple Silicon 及 Raspberry Pi 等硬件平台)

授权协议: MIT License | Copyright © 2024-2026 ScrapeFun Team
