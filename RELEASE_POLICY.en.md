# Releases and compatibility

[简体中文](./RELEASE_POLICY.md) · **English**

> Checked: 2026-11-03. Platforms release independently; see the corresponding release for system requirements and installation notes.

## Published stable releases

| Product | Stable version | Download assets | Release |
| --- | --- | --- | --- |
| macOS Server | 0.5.0 | arm64 DMG, SHA-256 / manual installation | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-server-macos/releases/tag/v0.5.0) |
| Windows Server | 0.5.0 | x64 EXE, update package, SHA256SUMS; Microsoft Store channel | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-server-windows/releases/tag/v0.5.0) · [Store](https://apps.microsoft.com/detail/9N83B6RSWG01) |
| Linux Server | 0.5.0 | Native glibc Linux amd64 archive, SHA256SUMS | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-server-linux/releases/tag/v0.5.0) |
| Android Server | 0.5.0 | Signed arm64-v8a APK, update manifest, SHA256SUMS | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-server-android/releases/tag/v0.5.0) |
| Linux Client | 0.5.0 | x64 deb, AppImage, SHA256SUMS | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-client-linux/releases/tag/v0.5.0) |
| macOS Client | 0.5.0 | arm64 DMG, SHA-256 / manual installation | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-client-macos/releases/tag/v0.5.0) |
| Windows Client | 0.5.0 | x64 EXE, update files, SHA256SUMS; Microsoft Store APPX | [v0.5.0](https://github.com/HaoweiLi97/scrapefun-client-windows/releases/tag/v0.5.0) · [Store](https://apps.microsoft.com/detail/9NM3HPS675QH) |
| Android Client | 0.5.1 | arm64-v8a / armeabi-v7a APKs, SHA256SUMS | [v0.5.1](https://github.com/HaoweiLi97/scrapefun-client-android/releases/tag/v0.5.1) |

Docker 0.5.0 is published through [`haoweil/scrapefun:latest`](https://hub.docker.com/r/haoweil/scrapefun/tags); prereleases use `:beta`. The updater uses `haoweil/scrapefun-updater`. The 0.5.0 images target linux/amd64. Use `:0.5.0` to pin the version and keep app and updater on the same version.

Windows GitHub releases provide x64 EXE installers and automatic-update files. Microsoft Store remains a separate APPX/MSIX channel, with availability determined by its listing. GitHub EXEs are unsigned; Windows may show an unknown publisher warning. Verify downloads against SHA256SUMS. Continue using the same installation channel, and back up data before switching channels.

macOS Server 0.5.0 requires Apple Silicon / macOS 27.0 or later, and Client 0.5.0 requires Apple Silicon / macOS 26.5 or later. Both have ad-hoc integrity signatures without Developer ID signing or Apple notarization. This version is available for manual installation only, without an in-app automatic upgrade; follow each Release page for first-launch instructions.

Native Linux Server 0.5.0 supports web-based installation of updates. When upgrading an older installation, first rerun the one-click installation command or use `sudo scrapefun update` once; retain `--config-dir` for a custom instance. Afterward, updates can be installed manually from the web interface. Linux Client 0.5.0 starts through X11 / XWayland by default; Wayland desktops require XWayland.

## Channels and version numbers

New releases follow [SemVer](https://semver.org/): stable fixes use three-part versions such as 0.5.0 → 0.5.1; only prereleases use -beta.N or -rc.N suffixes. The previous -patch.N naming plan is retired and remains supported only when reading historical versions for upgrades. Platforms advance independently; numeric Store package identities are separate from public versions.

- **stable**: the default deployment channel. GitHub normally uses `v<version>`; Docker uses version tags and the `latest` alias.
- **beta**: for trying prereleases. GitHub prerelease tags normally include `-beta`; Docker uses version tags and the `beta` alias.
- Platforms release independently. Server and Client version numbers may differ. Matching version numbers alone do not prove identical features or protocols.
- Local source code, packaging configuration, and planned package formats do not establish that an asset has been released. Available downloads are defined by Release Assets.

## Update methods

| Installation | Update method |
| --- | --- |
| One-click Docker deployment | In-app updater or rerun the one-click script; omitting the channel preserves the existing channel |
| Manual NAS Compose | Update images and recreate services; keep app and updater on the same channel |
| macOS Server | Install the 0.5.0 DMG manually; back up data and quit the old server first |
| Windows Server | In-app updates for GitHub EXE installations; Microsoft Store updates for Store installations. Back up before switching channels. |
| Linux AppImage Client | AppImage update or download and replace manually |
| Linux deb Client | Install the newer package with the system package manager |
| macOS / Windows Client | Install macOS 0.5.0 manually; Windows retains its existing channel update method |
| Android Client | The app verifies update information and invokes the system installer, or manually install a newer APK with the same signature |

## Upgrades and compatibility

Before upgrading Server, export a backup, pause write tasks, and allow time for a restart. After upgrading, check login, libraries, playback, reading, and Pro status. Follow the specific release notes for database or configuration migrations.

Back up before switching to beta or returning to stable. An older version is not guaranteed to read data written by a newer version. Use a backup compatible with the target version when rolling back. Replacing a binary alone is not a complete recovery procedure.

This document does not promise a uniform LTS cycle, compatibility with every third-party player, or lossless downgrades between arbitrary versions. See [documentation](./docs/README.en.md) for deployment and [support](./SUPPORT.en.md) for issue reporting.
