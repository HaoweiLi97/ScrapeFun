# ScrapeFun Android Client 0.5.0

Improve playback, reading, and library browsing, with clearer page recovery and future updates.

## Improvements and fixes

- Improve loading of media details and related content, reducing waits while browsing and returning to lists.
- Unify poster, backdrop, and avatar cropping for easier previews and saving.
- Improve comic source selection, resume artwork, EPUB layout and navigation, and audiobook starting positions and reading progress handoff.
- Add retry and recovery options after page loading errors, reducing blank pages.
- Use the shared `0.5.0` base version and correctly recognize future stable fixes named `0.5.0-patch.N`.
- Improve native playback controls, danmaku and volume controls, player switching, decoding recovery for some videos, and server connection page layout.

## Installation and compatibility

- Requires Android 7.0 or later; ARM64 and ARMv7 packages are provided.
- This release uses a new client signing identity and cannot directly update apps signed with the old certificate. Keep your existing app and data, and back up connections and settings before migrating; do not uninstall the existing app to bypass a signature mismatch.
- Install this base release before receiving stable fixes in the same series.
