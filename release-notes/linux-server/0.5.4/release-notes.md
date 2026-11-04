# ScrapeFun 0.5.4

媒体库扫描更快响应，扫描过程中可以持续查看正在处理的内容。

## 改进

- 目录读取与作品入库交叉推进，收齐一部剧集或作品的文件后再统一处理，减少等待。
- 扫描时首页保持内容和布局稳定，减少闪烁与重复加载。
- 媒体库按钮准确显示排队、扫描等状态，任务详情显示当前文件或文件夹。
- 元数据补齐与目录索引在后台继续运行，不再占用任务列表。
- 扫描结束后自动为缺少封面的媒体库生成封面，默认使用自然叠放的经典样式。

## 更新前须知

- 此次更新需要重启服务端，播放和后台任务会短暂中断。

---

# ScrapeFun 0.5.4

Media library scans respond faster and show which files and folders are being processed.

## Improvements

- Directory discovery and library imports progress together, with each series or work collected before it is processed.
- The home page keeps its content and layout stable during scans, reducing flicker and repeated loading.
- Library buttons reflect queued and scanning states, while task details show the current file or folder.
- Metadata completion and directory indexing continue in the background without appearing in the task list.
- Libraries without a cover receive one automatically after scanning, using the classic layered style by default.

## Before updating

- This update restarts the server and briefly interrupts playback and background tasks.

---

完整技术变更 / Full technical changelog: https://github.com/HaoweiLi97/ScrapeFun/blob/main/CHANGELOG.md
