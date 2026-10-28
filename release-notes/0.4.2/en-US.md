# ScrapeFun 0.4.2

Add virtual comic libraries and improve offline downloads, metadata translation, reading, account linking, and server management.

## New features

- Virtual comic libraries support searching, importing, syncing chapters, and online reading through compatible HTTP scraper sources, with saved reading progress. ScrapeFun Pro is required.
- Metadata translation and text AI settings let administrators configure translation services and check their connections.

## Improvements

- Virtual libraries include source templates and search import, with improved duplicate handling, source synchronization, and unavailable-source messages.
- Improved offline download settings, task status, and the transition from pending media entries to downloaded local files.
- Improved account linking, unlinking, and moving between servers. Linking shows merged entitlements and requires confirmation before transferring lifetime licenses. Free accounts can also link and unlink; unlinking preserves existing account Pro entitlements.
- Windows Server adds a native management window for status, logs, service controls, ports, and LAN access.

## Fixes

- Fixed delayed account and license state updates after website unlinking. Unlinking ends previous remote connections; moving to another server requires new client approval.
- Fixed unstable binding direction and page transitions in two-page comic reading, and improved remote playback range reads and seeking.

## Before updating

- This release provides Windows x64, Linux amd64, and Android arm64-v8a server packages.
- Updating restarts the service, upgrades the metadata synchronization data structure, and briefly interrupts playback and background tasks. Keep a data backup before installation.
- Virtual comics require a compatible source script. Sites requiring browser execution and full-book offline downloads of virtual comics are currently unsupported.
- Comic image enhancement retains Waifu2x, Real-CUGAN, and Real-ESRGAN and no longer requires Pro. The old ONNX and Core ML engines have been removed. Video enhancement is unaffected.
