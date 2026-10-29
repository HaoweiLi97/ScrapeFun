# ScrapeFun Linux Client 0.1.4

- Fix startup failures on some Linux desktops that previously required manually adding `--ozone-platform=x11`. DEB and AppImage now start through X11 / XWayland by default, without extra arguments.
- Retain the library, playback, reading and task experience from 0.1.3, along with existing connections and preferences.

For Linux x64. Wayland desktops require XWayland. Exit the client before installing the newer DEB or replacing the AppImage.
