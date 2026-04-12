# ScrapeFun Client for macOS

这是 ScrapeFun 的 macOS 客户端壳，只负责打开你已经部署好的 ScrapeFun 服务地址，不包含本地 `server`。

## 功能

- 直接连接现有 ScrapeFun 服务
- 作为普通 macOS 窗口应用运行，不在右上角常驻
- 独立窗口内嵌 `WKWebView`
- 可通过客户端内的「服务器地址」设置切换连接目标
- 在应用菜单里打开 `Settings...` 可以随时修改服务器地址
- 在应用菜单里打开 `Update Channel` 可以切换更新分支，自动检查会跟随当前分支
- 在应用菜单里打开 `Check Update...` 可以检查 GitHub Release 新版本
- 本地打包会先生成受保护的前端资源，并把 `protected-manifest.json` 一起带入发布包
- 生成 universal `.app` 与 `.dmg`
- 应用图标默认复用本机 Google Chrome 图标

## 本地构建

```bash
./scripts/build-scrapefun-client-macos.sh
```

构建产物默认输出到 `desktop/scrapefun-client-macos/build/`。
脚本默认不做代码签名；如果你要签名，可以通过 `SCRAPEFUN_CLIENT_CODESIGN_IDENTITY` 显式开启。

## 运行时配置

默认会优先读取环境变量：

- `SCRAPEFUN_CLIENT_WEB_URL`
- `SCRAPEFUN_DESKTOP_WEB_URL`

如果都没设置，首次启动会弹窗要求输入服务器地址；输入成功后会自动保存。

## Xcode 调试

可以直接用 Xcode 打开 `Package.swift` 调试宿主应用。

- 默认 Debug 构建会为 `WKWebView` 打开 Web Inspector
- 也可以手动设置 `SCRAPEFUN_DESKTOP_ENABLE_INSPECTOR=1`
- 如果想让桌面宿主直接加载指定服务器，可在 Xcode Scheme 的 Environment Variables 里设置 `SCRAPEFUN_CLIENT_WEB_URL=http://your-server:4000`
