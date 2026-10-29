# ScrapeFun 0.4.4

Fix web-based updates for native Linux servers, preserving update status, settings and data, with recovery when installation fails.

## Fixes

- Fix native Linux installations incorrectly using the Docker update workflow when checking or installing updates from the web interface.
- Native Linux servers can check and manually install updates from the web interface. Update status survives server stops and restarts, reports completion, and restores the previous installation and data on failure.
- Improve updater-tool installation for older setups, offline updates and configuration recovery while preserving ports, authentication settings and data locations.
- Keep updates mutually exclusive with backup and restore operations.

## Before updating

- Existing native Linux installations must first rerun the public one-click installation command or use `sudo scrapefun update`. This installs the new server and update components required for web-based installation. Custom instances should retain their configuration directory.
- This release updates only native Linux amd64 Server packages and the accompanying installation and update scripts. Verify SHA256SUMS.
- Updating restarts the server and briefly interrupts playback and background work. Preserve a full data backup first.
