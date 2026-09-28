# Releases and compatibility

[简体中文](./RELEASE_POLICY.md) · **English**

> Updated: 2026-09-28. The version table is a snapshot of public releases checked on this date. Open each release page for the current status.

## Published stable releases

| Product | Stable version | Download assets | Release |
| --- | --- | --- | --- |
| macOS Server | 0.3.3 | arm64 DMG | [v0.3.3](https://github.com/HaoweiLi97/scrapefun-server-macos/releases/tag/v0.3.3) |
| Windows Server | 0.3.3 | x64 Setup.exe | [v0.3.3](https://github.com/HaoweiLi97/scrapefun-server-windows/releases/tag/v0.3.3) |
| Linux Client | 0.0.4 | x64 deb, AppImage, SHA256SUMS | [v0.0.4](https://github.com/HaoweiLi97/scrapefun-client-linux/releases/tag/v0.0.4) |
| macOS Client | 0.0.4 | arm64 DMG, update ZIP | [v0.0.4](https://github.com/HaoweiLi97/scrapefun-client-macos/releases/tag/v0.0.4) |
| Windows Client | 0.0.5 | x64 / ARM64 Setup.exe | [v0.0.5](https://github.com/HaoweiLi97/scrapefun-client-windows/releases/tag/v0.0.5) |
| Android Client | 0.2.8 | arm64-v8a / armeabi-v7a APKs, SHA256SUMS | [v0.2.8](https://github.com/HaoweiLi97/scrapefun-client-android/releases/tag/v0.2.8) |

Docker stable releases are distributed through [`haoweil/scrapefun:latest`](https://hub.docker.com/r/haoweil/scrapefun/tags), and prereleases through `:beta`. The updater uses the separate `haoweil/scrapefun-updater` image. The registry is authoritative for specific tags and digests.

## Channels and version numbers

- **stable**: the default deployment channel. GitHub normally uses `v<version>`; Docker uses version tags and the `latest` alias.
- **beta**: for trying prereleases. GitHub prerelease tags normally include `-beta`; Docker uses version tags and the `beta` alias.
- Platforms release independently. Server and Client version numbers may differ. Matching version numbers alone do not prove identical features or protocols.
- Local source code, packaging configuration, and planned package formats do not establish that an asset has been released. Available downloads are defined by Release Assets.

## Update methods

| Installation | Update method |
| --- | --- |
| One-click Docker deployment | In-app updater or rerun the one-click script; omitting the channel preserves the existing channel |
| Manual NAS Compose | Update images and recreate services; keep app and updater on the same channel |
| macOS Server | In-app Sparkle update or install a newer DMG |
| Windows Server | Velopack update; older Inno installations need a one-time migration |
| Linux AppImage Client | AppImage update or download and replace manually |
| Linux deb Client | Install the newer package with the system package manager |
| macOS / Windows Client | Client update mechanism or install the newer package over the current installation |
| Android Client | The app verifies update information and invokes the system installer, or manually install a newer APK with the same signature |

## Upgrades and compatibility

Before upgrading Server, export a backup, pause write tasks, and allow time for a restart. After upgrading, check login, libraries, playback, reading, and Pro status. Follow the specific release notes for database or configuration migrations.

Back up before switching to beta or returning to stable. An older version is not guaranteed to read data written by a newer version. Use a backup compatible with the target version when rolling back. Replacing a binary alone is not a complete recovery procedure.

This document does not promise a uniform LTS cycle, compatibility with every third-party player, or lossless downgrades between arbitrary versions. See [documentation](./docs/README.en.md) for deployment and [support](./SUPPORT.en.md) for issue reporting.
