<div align="center">
  <img src="./docs/images/favicon.png" alt="ScrapeFun" width="80" />
  <h1>ScrapeFun</h1>
  <p><strong>简体中文</strong> · <a href="./README.en.md">English</a></p>
  <p>自托管媒体服务器 · 统一管理影视、漫画与远程媒体资源</p>
  <p>
    <a href="https://scrapefun.com/">产品网站</a> ·
    <a href="./docs/README.md">部署文档</a> ·
    <a href="#下载与部署">软件下载</a> ·
    <a href="./SUPPORT.md">支持与反馈</a>
  </p>
  <img src="./docs/images/library.jpg" alt="ScrapeFun 影视库：继续观看、分类筛选与海报浏览" width="960" />
</div>

> 文档更新：2026-09-28。各平台独立发布，具体版本、系统要求及安装注意事项以对应 Release 为准。

ScrapeFun 将媒体刮削、资源浏览、播放、阅读和多用户管理集中在一个自托管服务中。你可以在 Linux / NAS、Mac 或 Windows 电脑上部署 Server，再通过浏览器或专用客户端连接。

本仓库提供公开产品文档、部署模板和扩展示例。完整产品源码不在此仓库中公开；平台仓库用于发布安装包和安装说明。

## 下载与部署

先部署一个 Server，再按需要安装 Client。Server 保存媒体库、用户、配置和进度；Client 连接已有 Server。使用浏览器可直接访问 Server，无需安装客户端。

| 类型 | 平台 | 公开安装方式 | 入口 |
| --- | --- | --- | --- |
| Server | Linux / NAS | Docker，`linux/amd64` / `linux/arm64` | [Docker 部署](./DOCKER_GUIDE.md) |
| Server | macOS | Apple Silicon / arm64 DMG | [安装说明](https://github.com/HaoweiLi97/scrapefun-server-macos) · [稳定版](https://github.com/HaoweiLi97/scrapefun-server-macos/releases/latest) |
| Server | Windows | x64 安装程序 | [安装说明](https://github.com/HaoweiLi97/scrapefun-server-windows) · [稳定版](https://github.com/HaoweiLi97/scrapefun-server-windows/releases/latest) |
| Client | Linux | x64 deb / AppImage | [安装说明](https://github.com/HaoweiLi97/scrapefun-client-linux) · [稳定版](https://github.com/HaoweiLi97/scrapefun-client-linux/releases/latest) |
| Client | macOS | Apple Silicon / arm64 DMG | [安装说明](https://github.com/HaoweiLi97/scrapefun-client-macos) · [稳定版](https://github.com/HaoweiLi97/scrapefun-client-macos/releases/latest) |
| Client | Windows | x64 / ARM64 安装程序 | [安装说明](https://github.com/HaoweiLi97/scrapefun-client-windows) · [稳定版](https://github.com/HaoweiLi97/scrapefun-client-windows/releases/latest) |
| Client | Android | arm64-v8a / armeabi-v7a APK | [安装说明](https://github.com/HaoweiLi97/scrapefun-client-android) · [稳定版](https://github.com/HaoweiLi97/scrapefun-client-android/releases/latest) |

下载范围按 2026-09-28 已公开的稳定版资产核对。其他架构或包格式应先确认 Release 是否提供。

## 快速开始

Linux 主机安装 Docker 和 Docker Compose 插件后，运行：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash -s -- stable
```

按提示选择 GPU 模式。脚本默认使用 `~/scrapefun` 保存部署配置、`~/scrapefun-data` 保存业务数据，并启动 app 与独立 updater。

部署完成后，在浏览器中打开：

```text
http://服务器IP:8096
```

按页面引导完成初始化、设置管理员凭据并添加存储和媒体库。NAS 面板用户请阅读 [Compose 部署指南](./DOCKER_COMPOSE_DEPLOYMENT.md)。升级已有实例前请先完成[数据备份](./DOCKER_DATA_AND_BACKUP.md)。

## 产品能力

| 领域 | 提供的能力 |
| --- | --- |
| 媒体整理 | 电影与剧集刮削、海报和演员信息、清洗规则、自定义刮削器与组合刮削 |
| 漫画阅读 | 漫画扫描、网页与客户端阅读、阅读进度保存 |
| 远程资源 | WebDAV / AList 浏览与文件管理、远程媒体库扫描、资源连接 |
| 播放与字幕 | 网页与客户端播放、播放进度同步、字幕搜索与导入 |
| 用户管理 | 管理员与普通用户、媒体库访问权限、多设备访问 |
| 扩展能力 | Emby / Jellyfin 风格兼容接口、画面增强等 Pro 功能 |

部分高级功能需要有效的 ScrapeFun Pro 授权。具体权益与有效期以[产品权益说明](https://scrapefun.com/#/pro)、购买页面和实例内许可证页面为准；播放器兼容性同时受客户端版本、媒体编码及服务器配置影响。

## 界面预览

以下为产品实际界面，与[产品网站](https://scrapefun.com/#/product)使用同一套截图。不同平台、版本和个人设置可能影响显示效果。

<details>
  <summary>漫画库与阅读进度</summary>

按作品浏览漫画和卷册，并查看继续阅读内容。

<img src="./docs/images/comics.jpg" alt="ScrapeFun 漫画库：继续阅读、卷册封面与漫画筛选" width="960" />

</details>

<details>
  <summary>书籍库</summary>

通过封面浏览书籍，集中查看阅读中的作品。

<img src="./docs/images/books.png" alt="ScrapeFun 书籍库：继续阅读与书籍封面" width="960" />

</details>

<details>
  <summary>WebDAV 远程资源</summary>

浏览远程目录，以海报或列表查看媒体资源。

<img src="./docs/images/webdav.jpg" alt="ScrapeFun WebDAV：目录导航、文件搜索与海报视图" width="960" />

</details>

<details>
  <summary>作品详情</summary>

集中查看作品资料、简介、角色和阅读操作。

<img src="./docs/images/media-detail.jpg" alt="ScrapeFun 漫画作品详情：封面、资料、简介与角色" width="960" />

</details>

## 文档导航

| 任务 | 文档 |
| --- | --- |
| Linux 安装、更新与频道切换 | [Docker 部署与运维](./DOCKER_GUIDE.md) |
| 在 NAS 面板手动配置 | [Docker Compose 部署](./DOCKER_COMPOSE_DEPLOYMENT.md) |
| 备份、迁移与故障恢复 | [数据持久化、备份与恢复](./DOCKER_DATA_AND_BACKUP.md) |
| 查看配置字段 | [环境变量示例](./.env.example) · [配置 Schema](./server-env.schema.json) |
| 编写刮削器 | [中文开发指南](./server/SCRAPER_GUIDE.zh-CN.md) · [English guide](./server/SCRAPER_GUIDE.md) |
| 核对版本与更新规则 | [发行与兼容性说明](./RELEASE_POLICY.md) |
| 报告问题或安全漏洞 | [支持与反馈](./SUPPORT.md) · [安全说明](./SECURITY.md) |
| 查询软件授权 | [许可与协议](./legal/README.md) |

完整使用文档见[在线文档中心](https://scrapefun.com/#/docs)。

## 数据与更新

Docker 必须持久化完整数据根目录：

```yaml
volumes:
  - ./scrapefun-data:/app/data
```

更新会重启 Server，并中断正在进行的播放和后台任务。先备份，再更新，最后检查登录、媒体库、图片、播放与阅读进度。`latest` 是稳定版频道别名，`beta` 是测试版频道别名；需要固定版本时使用明确的版本标签。

macOS Server 0.3.3 仅提供 Apple Silicon 版本，使用 ad-hoc 完整性签名，未经 Apple Developer ID 签名和公证。首次启动步骤见[平台安装说明](https://github.com/HaoweiLi97/scrapefun-server-macos#安装与首次启动)。

## 联系与授权

使用问题请通过 [GitHub Issues](https://github.com/HaoweiLi97/ScrapeFun/issues) 或[产品反馈页面](https://scrapefun.com/#/contact)提交。涉及账号、付费或私密日志，请发送至 `scrapefun@outlook.com`；商业合作可联系 `lihaowei977@gmail.com`。

软件、文档和第三方组件的授权范围见[许可与协议](./legal/README.md)。
