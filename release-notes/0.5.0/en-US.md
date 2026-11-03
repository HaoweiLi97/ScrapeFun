# ScrapeFun 0.5.0

Improve playback, comic and book reading, and library browsing, while fixing configuration and data compatibility when upgrading older servers.

## Improvements

- Improve loading of media details and related content, reducing waits while browsing and returning to the library.
- Unify image cropping for easier previews and saving of posters, backdrops, and avatars.

## Fixes

- Fix inconsistencies in comic source selection, volume grouping, and artwork shown when resuming reading.
- Improve EPUB layout and touch and mouse navigation, and fix audiobook starting positions and reading progress handoff.
- Add retry and recovery options after page loading failures, reducing cases where an error leaves a blank page.
- Fix configuration, network storage credentials, and data directory handling during some older server upgrades; improve Linux runtime updates and Android installation space checks.

## Before updating

- Follow the normal upgrade process for your existing app and platform, retaining your connection settings and data locations.
- Updating the server restarts it and briefly interrupts connections. Keep a complete data backup beforehand.
- Windows downloads on GitHub use EXE installers; Microsoft Store uses MSIX/APPX. Keep your existing installation channel and back up your data before changing channels.
- Windows EXE installers are unsigned and may show an unknown publisher warning; verify the SHA-256 checksum. Store packages require Microsoft Store certification and signing before distribution.
