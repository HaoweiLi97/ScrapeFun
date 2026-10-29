# ScrapeFun Server Android 0.4.3

Improve media identification, scan progress, task management, and playback state synchronization.

- Improve matching with complete titles, aliases, years and folder context, reducing uncertain automatic matches. Improve season and episode recognition while preserving manually confirmed bindings.
- Show library additions and enrichment progress during scanning. Filter and sort tasks, inspect queued work and retry failures, with fewer duplicate notifications.
- Fix missing or duplicate items when filtering, sorting and paging through large libraries. Better preserve linked files and user records when rematching or merging entries.
- Keep media details, subtitles, reading progress and continue-watching records synchronized with background changes.
- Improve continuous playback and next-episode transitions, avoid briefly displaying the previous episode, and improve subtitle import binding and refresh.

## Installation and updates

- This is the Android Server application, installed separately from Android Client. It supports Android 9 or later on arm64-v8a devices.
- The APK uses the same release signing certificate as the previous version. Its version is 0.4.3 (versionCode 4003). Stop the server and preserve a full data backup before installing the update over the existing app.
- Verify the download against SHA256SUMS and follow Android's prompt to authorize installation from the current source.
- Allow sufficient free space for installation and first launch. Connect through a browser or client after the initial preparation completes.
