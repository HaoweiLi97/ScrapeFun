# 发行与兼容性说明

**简体中文** · [English](./RELEASE_POLICY.en.md)

> 文档更新：2026-09-28。版本表为核对当日的公开发布快照；最新状态请打开对应 Release。

## 已发布稳定版

| 产品 | 稳定版 | 下载资产 | 发行页 |
| --- | --- | --- | --- |
| macOS Server | 0.3.3 | arm64 DMG | [v0.3.3](https://github.com/HaoweiLi97/scrapefun-server-macos/releases/tag/v0.3.3) |
| Windows Server | 0.3.3 | x64 Setup.exe | [v0.3.3](https://github.com/HaoweiLi97/scrapefun-server-windows/releases/tag/v0.3.3) |
| Linux Client | 0.0.4 | x64 deb、AppImage、SHA256SUMS | [v0.0.4](https://github.com/HaoweiLi97/scrapefun-client-linux/releases/tag/v0.0.4) |
| macOS Client | 0.0.4 | arm64 DMG、更新 ZIP | [v0.0.4](https://github.com/HaoweiLi97/scrapefun-client-macos/releases/tag/v0.0.4) |
| Windows Client | 0.0.5 | x64 / ARM64 Setup.exe | [v0.0.5](https://github.com/HaoweiLi97/scrapefun-client-windows/releases/tag/v0.0.5) |
| Android Client | 0.2.8 | arm64-v8a / armeabi-v7a APK、SHA256SUMS | [v0.2.8](https://github.com/HaoweiLi97/scrapefun-client-android/releases/tag/v0.2.8) |

Docker 的稳定版通过 [`haoweil/scrapefun:latest`](https://hub.docker.com/r/haoweil/scrapefun/tags) 分发，测试版通过 `:beta` 分发；updater 使用独立的 `haoweil/scrapefun-updater` 镜像。具体标签和摘要以注册表为准。

## 频道与版本号

- **stable**：默认部署频道；GitHub 通常使用 `v<version>`，Docker 使用版本标签和 `latest` 别名。
- **beta**：用于试用测试版本；GitHub 预发布通常带 `-beta`，Docker 使用版本标签和 `beta` 别名。
- 各平台独立发布，Server 与 Client 的版本号可以不同。版本号相同也不能单独证明功能或协议完全一致。
- 本地源码、打包配置和计划中的包格式不代表它们已经发布。可下载范围以 Release Assets 为准。

## 更新方式

| 安装方式 | 更新方式 |
| --- | --- |
| Docker 一键部署 | 应用内 updater 或重跑一键脚本；不指定频道时保留现有频道 |
| NAS 手动 Compose | 更新镜像并重建服务；app 与 updater 频道保持一致 |
| macOS Server | Sparkle 应用内更新，或下载安装新版 DMG |
| Windows Server | Velopack 更新；旧 Inno 安装需先迁移一次 |
| Linux AppImage Client | AppImage 更新，或手动下载替换 |
| Linux deb Client | 使用系统包管理器安装新版包 |
| macOS / Windows Client | 客户端更新机制，或覆盖安装新版安装包 |
| Android Client | 应用校验更新信息后交由系统安装器安装，或手动安装同签名新版 APK |

## 升级与兼容性

升级 Server 前导出备份、暂停写入任务，并为重启预留时间。升级后实际检查登录、媒体库、播放、阅读及 Pro 状态。涉及数据库或配置迁移时，以该版发行说明为准。

切换 beta 或回到 stable 前均应备份。较新版本写入的数据不保证能被旧版本读取；回退时使用与目标版本兼容的备份。不要把替换旧二进制当作完整恢复流程。

本项目未在本文中承诺统一的 LTS 周期、全部第三方播放器兼容或跨任意版本无损降级。部署步骤见[文档中心](./docs/README.md)，异常报告见[支持说明](./SUPPORT.md)。
