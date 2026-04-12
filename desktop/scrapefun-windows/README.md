# ScrapeFun Desktop for Windows

Windows 版 ScrapeFun 原生宿主，采用 `.NET 8 + WPF + WebView2 + NotifyIcon`，职责与现有 macOS 宿主保持一致：

- 托盘常驻，后台托管 ScrapeFun 服务
- 使用 WebView2 承载前端页面
- 通过桌面桥接把前端播放请求转给 `mpv.exe`
- 首次运行自动把 `runtime-template` 解压到 `%AppData%\ScrapeFunDesktop`
- 默认数据目录：
  - `%AppData%\ScrapeFunDesktop\data`
  - `%AppData%\ScrapeFunDesktop\logs`
  - `%AppData%\ScrapeFunDesktop\run`
  - `%AppData%\ScrapeFunDesktop\runtime`

## 本地构建

在 Windows 环境执行：

```powershell
pwsh ./scripts/build-scrapefun-desktop-windows.ps1
```

默认构建结果输出到：

`desktop/scrapefun-windows/build/publish`

## 构建输入

构建脚本会组装以下资源：

- `client/dist` protected bundle
- `server/dist` protected bundle
- `server/node_modules`
- `node.exe`
- `mpv.exe`
- 共享 `mpv` 脚本资源：`desktop/shared/mpv/common`

可通过环境变量覆盖：

- `SCRAPEFUN_WINDOWS_NODE_BINARY`
- `SCRAPEFUN_WINDOWS_MPV_BINARY`
- `SCRAPEFUN_WINDOWS_RUNTIME`
- `SCRAPEFUN_WINDOWS_VERSION`
