# ScrapeFun 0.4.3

Improve media identification, scan progress, task management, and Linux installation and updates.

## Improvements

- Matching gives greater weight to complete titles, aliases, years, and folder context to better distinguish movies, franchises, TV series, and comics, with fewer uncertain automatic matches.
- New library items and enrichment progress appear during scanning. Filter and sort tasks, inspect queued work, retry failures, and manage read notifications.
- Native Linux installation supports custom ports, pinned versions, unattended installation, and preflight checks, with clearer guidance for missing dependencies.

## Fixes

- Improve season and episode recognition, folder ownership, and retries for unmatched items. Rechecking automatic episode assignments preserves manually confirmed bindings.
- Fix missing or duplicate results when filtering, sorting, and paging through large libraries.
- Improve preservation of linked files and user records when manually rematching or merging entries, and fix delayed enrichment status, duplicate task notifications, and slow scan refreshes.
- Improve Linux configuration and port retention, download verification, backup and restore, and recovery after failed updates.
- Keep media details, subtitle lists, reading progress, and continue-watching records in sync with background changes, reducing manual refreshes and inconsistent page states.
- Fix the previous episode title or state briefly appearing during continuous playback, and improve next-episode transitions, subtitle import binding and refresh, and read-aloud status updates.

## Before updating

- Windows Server uses x64 APPX/MSIX packages. Separate EXE installers are no longer provided. Existing EXE users should back up data and follow the final migration instructions.
- Native Linux packages target glibc Linux amd64 and require the Node, systemd, and media dependencies listed in the installation guide.
- Updating restarts the server and briefly interrupts playback and background work. Back up your data first.
