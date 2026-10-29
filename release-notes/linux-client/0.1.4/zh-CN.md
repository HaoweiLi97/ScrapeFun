# ScrapeFun Linux Client 0.1.4

- 修复部分 Linux 桌面下直接启动失败、需要手动添加 `--ozone-platform=x11` 的问题。DEB 与 AppImage 现在默认通过 X11 / XWayland 启动，无需额外输入参数。
- 继续使用 0.1.3 的媒体库、播放、阅读和任务体验；已有连接与设置可继续使用。

适用于 Linux x64。Wayland 桌面需提供 XWayland；更新前请退出客户端，再安装新版 DEB 或替换 AppImage。
