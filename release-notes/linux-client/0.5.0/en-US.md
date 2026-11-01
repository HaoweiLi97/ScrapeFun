# ScrapeFun Linux Client 0.5.0

Improve playback, reading, and library browsing, with clearer page recovery and future updates.

## Improvements and fixes

- Improve loading of media details and related content, reducing waits while browsing and returning to lists.
- Unify poster, backdrop, and avatar cropping for easier previews and saving.
- Improve comic source selection, resume artwork, EPUB layout and navigation, and audiobook starting positions and reading progress handoff.
- Add retry and recovery options after page loading errors, reducing blank pages.
- Use the shared `0.5.0` base version and correctly recognize future stable fixes named `0.5.0-patch.N`.

## Installation and compatibility

- Linux x64 DEB and AppImage packages are provided. Choose the format appropriate for your distribution and existing installation.
- Install this base release before receiving stable fixes in the same series.
- Requires glibc 2.34 or later and an X11 desktop or a Wayland session with XWayland; pure Wayland and musl systems are not supported.
- DEB uses the system libmpv and updates through the package manager; AppImage bundles its playback library and supports in-app updates.
