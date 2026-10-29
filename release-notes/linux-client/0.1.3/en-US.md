# ScrapeFun Linux Client 0.1.3

Improve playback transitions, media state updates, and desktop taskbar integration.

## Improvements and fixes

- Fix launcher and taskbar icon mismatches and duplicate icons on some Linux desktops.
- Improve continuous playback and next-episode transitions, avoid briefly showing the previous episode title, and make resume prompts consistent across detail pages.
- Keep media details, subtitle lists, reading progress, and continue-watching records up to date with fewer manual refreshes.
- Show newly imported media during scans and refresh artwork and library results after enrichment.
- Filter and sort tasks, with clearer progress, retries, and notifications.

## Installation and compatibility

- Linux x64 DEB and AppImage packages are provided. Requires glibc 2.34 or later.
- Requires X11 or a Wayland session with XWayland. Pure Wayland and musl systems are not supported.
- DEB uses the system libmpv and updates through the system package manager. AppImage includes its playback libraries and supports in-app updates.
- Connect to ScrapeFun Server 0.4.3 or later for the complete scan, matching, task progress, and state synchronization experience.
