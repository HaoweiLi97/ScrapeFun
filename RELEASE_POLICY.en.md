# Releases and compatibility

[简体中文](./RELEASE_POLICY.md) · **English**

> macOS, Linux, Docker and Windows Store entries updated: 2026-10-29. Other entries retain an earlier public snapshot. Each release page or Store listing is authoritative.

## Published stable releases

| Product | Stable version | Download assets | Release |
| --- | --- | --- | --- |
| macOS Server | 0.4.3 | arm64 DMG | [v0.4.3](https://github.com/HaoweiLi97/scrapefun-server-macos/releases/tag/v0.4.3) |
| Windows Server | 0.4.2; 0.4.3 in Store certification | Microsoft Store / x64 MSIX | [Microsoft Store](https://apps.microsoft.com/detail/9N83B6RSWG01) |
| Linux Server | 0.4.3 | Native glibc Linux amd64 archive, SHA256SUMS | [v0.4.3](https://github.com/HaoweiLi97/scrapefun-server-linux/releases/tag/v0.4.3) |
| Linux Client | 0.1.3 | x64 deb, AppImage, SHA256SUMS | [v0.1.3](https://github.com/HaoweiLi97/scrapefun-client-linux/releases/tag/v0.1.3) |
| macOS Client | 0.1.3 | arm64 DMG, update ZIP | [v0.1.3](https://github.com/HaoweiLi97/scrapefun-client-macos/releases/tag/v0.1.3) |
| Windows Client | 0.1.3 | Microsoft Store / x64 APPX | [Microsoft Store](https://apps.microsoft.com/detail/9NM3HPS675QH) |
| Android Client | 0.2.8 | arm64-v8a / armeabi-v7a APKs, SHA256SUMS | [v0.2.8](https://github.com/HaoweiLi97/scrapefun-client-android/releases/tag/v0.2.8) |

Docker 0.4.3 is published through [`haoweil/scrapefun:latest`](https://hub.docker.com/r/haoweil/scrapefun/tags); prereleases use `:beta`. The updater uses `haoweil/scrapefun-updater`. The 0.4.3 images target linux/amd64. Use `:0.4.3` to pin the version and keep app and updater on the same version.

New Windows packages use Microsoft Store x64 APPX/MSIX. Separate EXE installers are no longer provided. Existing EXE users should export an application backup and follow the migration instructions. Server 0.4.3 has been submitted and will become available after certification; the Store may still offer 0.4.2 meanwhile.

macOS Server 0.4.3 and Client 0.1.3 require Apple Silicon and macOS 26.0 or later. These packages have ad-hoc integrity signatures and are not Developer ID signed or notarized. Follow the installation steps in each release.

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
| Windows Server | Microsoft Store updates; older EXE installations require backup and migration |
| Linux AppImage Client | AppImage update or download and replace manually |
| Linux deb Client | Install the newer package with the system package manager |
| macOS / Windows Client | Client update mechanism or install the newer package over the current installation |
| Android Client | The app verifies update information and invokes the system installer, or manually install a newer APK with the same signature |

## Upgrades and compatibility

Before upgrading Server, export a backup, pause write tasks, and allow time for a restart. After upgrading, check login, libraries, playback, reading, and Pro status. Follow the specific release notes for database or configuration migrations.

Back up before switching to beta or returning to stable. An older version is not guaranteed to read data written by a newer version. Use a backup compatible with the target version when rolling back. Replacing a binary alone is not a complete recovery procedure.

This document does not promise a uniform LTS cycle, compatibility with every third-party player, or lossless downgrades between arbitrary versions. See [documentation](./docs/README.en.md) for deployment and [support](./SUPPORT.en.md) for issue reporting.
