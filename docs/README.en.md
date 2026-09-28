# ScrapeFun documentation

[简体中文](./README.md) · **English**

> Updated: 2026-09-28

Start with your deployment method. Server manages data and libraries; Client connects to an existing Server. Installers and update channels are released independently for each platform.

## Deployment and operations

| Guide | Task |
| --- | --- |
| [Docker deployment and operations](../DOCKER_GUIDE.en.md) | One-click Linux installation, channel changes, upgrades, and health checks |
| [Docker Compose deployment](../DOCKER_COMPOSE_DEPLOYMENT.en.md) | Manual configuration for NAS devices or management panels |
| [Persistent data, backup, and recovery](../DOCKER_DATA_AND_BACKUP.en.md) | Data directories, old mount migration, backups, and recovery drills |
| [Production Compose template](../docker-compose.remote.yml) | Check actual services, mounts, and updater configuration |
| [Environment example](../.env.example) | Find configuration fields; generate your own production secrets |

## Platform installation

- Server: [macOS](https://github.com/HaoweiLi97/scrapefun-server-macos/blob/main/README.en.md) · [Windows](https://github.com/HaoweiLi97/scrapefun-server-windows/blob/main/README.en.md)
- Client: [Linux](https://github.com/HaoweiLi97/scrapefun-client-linux/blob/main/README.en.md) · [macOS](https://github.com/HaoweiLi97/scrapefun-client-macos/blob/main/README.en.md) · [Windows](https://github.com/HaoweiLi97/scrapefun-client-windows/blob/main/README.en.md) · [Android](https://github.com/HaoweiLi97/scrapefun-client-android/blob/main/README.en.md)

## Extensions and support

- [Custom scraper development (English)](../server/SCRAPER_GUIDE.md)
- [Custom scraper development (Chinese)](../server/SCRAPER_GUIDE.zh-CN.md)
- [Releases and compatibility](../RELEASE_POLICY.en.md)
- [Support and feedback](../SUPPORT.en.md)
- [Security information](../SECURITY.en.md)
- [Licensing and agreements](../legal/README.en.md)

See the [online documentation](https://scrapefun.com/?lang=en#/docs) for libraries, playback, reading, and Pro usage.
