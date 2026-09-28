# 第三方组件与许可说明

**简体中文** · [English](./THIRD_PARTY_NOTICES.en.md)

> 文档更新：2026-09-28

ScrapeFun 的商业许可仅覆盖权利人拥有权利且明确采用该许可的内容。第三方组件分别保留其版权及许可证，相关许可赋予的使用、修改、源代码获取、替换、重新链接和分发权利不因 ScrapeFun 商业协议而被排除。

## 组件来源入口

下表用于定位项目及许可证；具体是否包含某一组件、其版本和构建选项，以对应发行包为准。这是一份公开来源索引，不是全部发行包的完整依赖清单或已完成的二进制许可审计。

| 组件或资源 | 用途 | 官方项目与许可入口 |
| --- | --- | --- |
| Node.js | Server 运行时 | [Node.js LICENSE](https://github.com/nodejs/node/blob/main/LICENSE) |
| Electron | 桌面客户端宿主 | [Electron LICENSE](https://github.com/electron/electron/blob/main/LICENSE) |
| FFmpeg / FFprobe | 媒体探测、字幕及媒体处理 | [FFmpeg Legal](https://ffmpeg.org/legal.html) |
| mpv / libmpv | 原生媒体播放 | [mpv Copyright](https://github.com/mpv-player/mpv/blob/master/Copyright) |
| mpv-android | Android 原生播放器集成来源 | [mpv-android](https://github.com/mpv-android/mpv-android) |
| Sparkle | macOS Server 更新 | [Sparkle LICENSE](https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE) |
| Velopack | Windows Server 安装和更新 | [Velopack LICENSE](https://github.com/velopack/velopack/blob/develop/LICENSE) |
| thumbfast | 部分播放器缩略图 | [thumbfast](https://github.com/po5/thumbfast) |

FFmpeg、mpv / libmpv 的适用许可取决于实际构建选项和依赖，不能只根据组件名称将发行包标记为 LGPL 或 GPL。模型、字体、图标及其他依赖同样需要依据实际来源和随包声明核对。

## 随发行提供的信息

发行方应按照相应组件许可证随包提供版权声明和许可文本；需要提供对应源代码、构建信息或其他材料时，也应按实际版本及许可证要求提供。若某一发行包没有列出必要的信息，不能用本页替代这些义务。

用户查询具体发行包的许可或源代码获取方式时，请联系 `scrapefun@outlook.com`，注明平台、版本和完整资产文件名。公开反馈请勿附带激活码、账号密码或私人媒体。

## 授权范围

软件、公开文档和第三方组件的授权边界见[许可与协议](./legal/README.md)。
