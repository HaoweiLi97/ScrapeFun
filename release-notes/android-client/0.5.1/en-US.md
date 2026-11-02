# ScrapeFun Android Client 0.5.1

This update improves remote connection stability during long playback sessions and after inactivity.

## Improvements and fixes

- Maintains established remote connections while the app is running, independently of page refreshes or returning home.
- Automatically attempts to reconnect when a connection stops responding, reducing the need to restart the app.
- Continues to use the official connection nodes, including an Asian node.

## Installation

- ARM64 and ARMv7 APKs are available for Android 7.0 and later.
- Uses the same package name and signing identity as 0.5.0, allowing an update that preserves app data. Do not uninstall an existing app to bypass a signing mismatch.
