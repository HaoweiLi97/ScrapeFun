# ScrapeFun 文档中心

**简体中文** · [English](./README.en.md)

> 文档更新：2026-11-03

从部署方式开始选择文档。Server 管理数据和媒体库，Client 连接已有 Server；不同平台的安装程序和更新通道独立发布。

## 部署与运维

| 文档 | 适用任务 |
| --- | --- |
| [Docker 部署与运维](../DOCKER_GUIDE.md) | Linux 一键安装、频道切换、升级与健康检查 |
| [Ubuntu 原生安装](ubuntu-native-install.md) | 从全新 Ubuntu 安装 ScrapeFun 并检查服务 |
| [Debian 原生安装](debian-native-install.md) | 在没有 GPU 直通的 Debian 虚拟机上安装并检查服务 |
| [Docker Compose 部署](../DOCKER_COMPOSE_DEPLOYMENT.md) | NAS 或管理面板手动配置 |
| [飞牛 fnOS 图文安装教程](fnos-docker-install.md) | 从官网复制配置并在飞牛 Docker 部署 |
| [群晖 DSM 图文安装教程](synology-docker-install.md) | 从官网复制配置并在群晖 Container Manager 部署 |
| [数据持久化、备份与恢复](../DOCKER_DATA_AND_BACKUP.md) | 数据目录、旧挂载迁移、备份和恢复演练 |
| [生产 Compose 模板](../docker-compose.remote.yml) | 核对实际服务、挂载与 updater 配置 |
| [环境变量示例](../.env.example) | 查找配置项；生产密钥需自行生成 |

## 平台安装

- Server：[Linux 原生](../DOCKER_GUIDE.md#原生-systemd-安装) · [Android](https://github.com/HaoweiLi97/scrapefun-server-android) ·[macOS](https://github.com/HaoweiLi97/scrapefun-server-macos) · [Windows](https://github.com/HaoweiLi97/scrapefun-server-windows)
- Client：[Linux](https://github.com/HaoweiLi97/scrapefun-client-linux) · [macOS](https://github.com/HaoweiLi97/scrapefun-client-macos) · [Windows](https://github.com/HaoweiLi97/scrapefun-client-windows) · [Android](https://github.com/HaoweiLi97/scrapefun-client-android)

## 扩展与支持

- [常用设置指南](developers/settings.md) · [AI 接入与配置](developers/ai-settings.md)

- [API 接入参考](developers/api.md) · [OpenAPI](developers/openapi.json)
- [刮削器开发参考](developers/scrapers.md) · [测试与管理 API](developers/scraper-api.md) · [扩展示例](developers/examples/)

- [自定义刮削器开发（中文）](../server/SCRAPER_GUIDE.zh-CN.md)
- [Custom Scraper Development Guide (English)](../server/SCRAPER_GUIDE.md)
- [发行与兼容性说明](../RELEASE_POLICY.md)
- [支持与反馈](../SUPPORT.md)
- [安全说明](../SECURITY.md)
- [许可与协议](../legal/README.md)

媒体库、播放、阅读和 Pro 使用说明见[在线文档中心](https://scrapefun.com/#/docs)。
