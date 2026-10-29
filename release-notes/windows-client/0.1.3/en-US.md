# ScrapeFun Windows Client 0.1.3

Make library scan progress and background work easier to follow.

## Improvements and fixes

- Show newly imported media during scans and refresh artwork and library results after enrichment.
- Filter and sort tasks, with clearer running, queued, and attention-required states.
- Improve enrichment progress, retries, history, and read notifications while reducing duplicate alerts.
- Clarify automatic matching settings and episode file assignment guidance to reduce uncertain automatic matches.
- Keep media details, subtitles, reading progress, and continue-watching records up to date with fewer manual refreshes.
- Improve continuous playback and next-episode transitions, avoid briefly showing the previous episode title, and make resume prompts consistent across detail pages.

## Installation and compatibility

- Supports Windows x64, starting with Windows 10 version 2004 (build 19041).
- EXE installers are available on GitHub; Microsoft Store provides APPX/MSIX. Both channels use client version 0.1.3. GitHub EXEs are unsigned, so Windows may show an unknown publisher warning. Verify SHA-256 against this release.
- Connect to ScrapeFun Server 0.4.3 or later for the complete scan, matching, and task progress experience.
- EXE users can continue using their existing installation channel. Back up connections and preferences before switching between Store and EXE channels; installation and data transfer across channels depend on validation results.
