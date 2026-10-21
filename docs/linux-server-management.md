# Linux 服务端安装与管理

Linux 服务端保留两种安装方式，两者提供同一套 Web 管理界面和 API。普通 Linux 主机可选 Docker Compose 或原生 systemd；NAS 可使用 Docker；ARM64 设备必须先确认对应标签提供 ARM64 镜像，不能直接使用 amd64 镜像。原生发布包目前仅支持 glibc Linux amd64，需要 Node.js 20/22/24、Python 3、curl、systemd、FFmpeg 和 FFprobe，硬件加速还需要主机驱动。

一键安装脚本和部署说明随公共部署仓库发布；下列公网命令使用 main 分支当前版本。

## 一键安装

Docker 保留现有命令：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh | bash
```

原生 systemd：

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-native-deploy.sh | sudo bash
```

Beta 在任一命令的末尾使用 `bash -s -- beta`（原生使用 `sudo bash -s -- beta`）。原生脚本会查找对应渠道的正式发布包，下载并检查 SHA-256，再安装运行；不会在用户服务器上编译源码。没有对应架构或渠道的发布包时，在修改现有安装前退出。

满足上述系统要求后，运行对应的一键命令即可，无需再手动下载发行包或重复执行安装程序。门户下载页直接展示标准命令及复制按钮，Beta 命令放在下方的折叠区域；Docker 与原生 systemd 是两种可选安装方式，不需要依次执行。

| 位置 | Docker | 原生 systemd |
| --- | --- | --- |
| 管理命令 | `~/scrapefun/scrapefun` | `sudo scrapefun` |
| 应用 | Docker 镜像 | `/opt/scrapefun` |
| 数据 | `~/scrapefun-data` | `/var/lib/scrapefun` |
| 配置 | `~/scrapefun/server.env` | `/etc/scrapefun/server.env` |
| 日志 | Compose logs | systemd journal |
| 自启 | Docker restart policy | `scrapefun.service` |

脚本会等待 `/health/ready` 成功后显示完成和访问地址；仅进程存活不代表安装成功。默认端口 8096，首次安装可通过 `APP_HOST_PORT` 修改。原生配置文件由 root 持有，密钥不会显示在管理概览里。

## 统一管理入口

直接运行管理命令可打开终端菜单；管道、CI 等非交互环境只输出帮助，不会等待输入。以下以原生安装为例，Docker 把 `sudo scrapefun` 替换为 `~/scrapefun/scrapefun`：

```bash
sudo scrapefun status
sudo scrapefun start
sudo scrapefun stop
sudo scrapefun restart
sudo scrapefun logs --follow
sudo scrapefun health
sudo scrapefun url
sudo scrapefun doctor
sudo scrapefun update          # 沿用当前 stable/beta 渠道
sudo scrapefun update beta
sudo scrapefun backup
sudo scrapefun restore /path/to/backup.tar.gz
```

同机两种部署可以通过 `scrapefun --mode docker --deploy-dir /path/to/compose status` 明确选择；应用端口和 Docker updater 端口也要避免冲突。数据目录不会自动在两种部署之间搬迁。

原生改端口或其他配置后编辑 `/etc/scrapefun/server.env` 并重启。可配置 `FFMPEG_PATH`、`FFPROBE_PATH`；GPU 驱动由主机负责，安装器为服务账号加入现有 video/render 组。Docker 自动检测 GPU 并补齐运行环境，安装前执行硬件 Vulkan 与漫画增强预检。

## 漫画增强：自动检测与安装显卡环境

一键脚本默认使用 auto：优先识别 WSL2 /dev/dxg，其次 NVIDIA 和 Intel/AMD DRI。缺少所需 GPU 环境时自动安装；已安装且验证通过的环境会直接复用。无需另外安装 CUDA Toolkit，漫画增强使用 NCNN Vulkan。

Ubuntu/Debian 的 WSL2 会自动构建并安装经过校验的独立 Dozen Vulkan 驱动；普通 Linux 原生版会补装 Vulkan loader、工具及 Mesa 驱动。NVIDIA 用户态 Vulkan 库仅安装与当前驱动匹配的版本。

普通 Linux 的 NVIDIA Docker 模式会在缺失时安装 NVIDIA Container Toolkit，并为本机系统 Docker 配置运行时；首次配置需要重启 Docker，可能短暂影响其他容器。远程、自定义或 rootless 守护进程不会被自动改写。

WSL2 的 Windows 显卡驱动需已支持 GPU 透传。Dozen 仍为实验性驱动；当前已验证 RTX 4060 Ti，其他设备与 NAS 的驱动安装仍以厂商支持为准。自动补装目前支持 Ubuntu/Debian；其他发行版需要预装 GPU 环境。

Docker 安装前会以实际服务用户运行硬件 Vulkan 和五种内置增强引擎测试；软件渲染器 llvmpipe/lavapipe 不会被当作硬件显卡。原生安装会检查主机硬件 Vulkan，安装后可在设置页运行相同的引擎能力测试。

WSL 配置直接写入主 Compose 文件和原生服务环境，后续一键更新继续沿用。WSL Docker 守护进程必须位于可访问 /dev/dxg 和驱动目录的同一发行版内。

可用 SCRAPEFUN_GPU_MODE=none 禁用显卡环境安装，也可指定 wsl、nvidia 或 dri。自动模式的硬件测试失败时会明确提示 CPU 回退；显式指定 GPU 模式失败则停止部署。环境安装失败会停止部署，不会替换现有应用容器。

验收结果：当前发布的 v0.4.0 原生版和 Docker 版均在 WSL2 的 RTX 4060 Ti 上通过 Waifu2x Fast、Waifu2x、Real-CUGAN SE、Real-CUGAN Pro 和 Real-ESRGAN 测试，512×768 图像放大为 1024×1536，严格 GPU 模式无 CPU 回退，观测到显卡利用率最高 76%。

阅读器选择 GPU 0，分块大小选择自动（tile=0）。Real-CUGAN 在本环境的 tile=32 分块测试发生崩溃，实际页面请先使用自动分块验证。nvidia-smi 正常不等于 Vulkan 已可用，应以设置页能力测试和实际增强结果为准。

## 原生更新与数据保护

原生更新先校验下载文件、压缩包路径和受保护服务端清单，再停止服务、检查 SQLite 并备份数据，最后切换程序。既有端口、密钥、配置和数据位置保持不变。失败时切回旧程序、旧服务配置和更新前数据，返回非零退出码；旧版本、失败版本和数据副本保留，供管理员检查。备份和安装使用同一个操作锁。

新包使用与 Windows、Docker 相同的事务式 `prepare-storage`。已发布的旧 0.3.3 原生包没有这个入口，兼容启动会先做 SQLite 完整性检查和数据库快照，再在私有数据库副本上执行不带 `--accept-data-loss` 的 Prisma 同步。FTS 搜索缓存只在副本中清理，应用启动后重建；副本通过完整性检查后才提交。涉及可能丢失用户数据的结构变更会失败，不覆盖原数据库。相同 schema 的后续启动仅检查数据库完整性。

Docker 更新沿用现有一键脚本，保留渠道、数据根、GPU 和迁移保护；Web 设置页仍使用已有 updater 更新流程。

原生备份保存数据库、用户文件和一份 `server.env`，默认排除可重建缓存和日志；备份含密钥，权限为 0600，应放在数据目录之外。恢复先检查压缩包成员、校验和和 SQLite，保留原数据目录，再切换。恢复后检查就绪状态，失败则恢复原数据。原生恢复保留当前 `server.env`；归档中的配置用于管理员另行检查。Docker 继续使用已有备份、恢复、加密、远端复制和定时备份工具，详细选项见 [系统运维](./system-operations.md)。

## 本地和离线安装

工作区运行 Docker 脚本：

```bash
bash scripts/one-click-compose-deploy.sh stable /path/to/deployment
```

原生可复用已下载的正式发布包，旁边必须存在 `.sha256` 文件：

```bash
sudo env SCRAPEFUN_NATIVE_ARCHIVE=/path/to/scrapefun-server-linux-amd64-0.3.3-stable.tar.gz \
  bash scripts/one-click-native-deploy.sh stable
```

自定义原生路径使用 `SCRAPEFUN_INSTALL_DIR`、`SCRAPEFUN_DATA_DIR`、`SCRAPEFUN_CONFIG_DIR`，服务使用 `SCRAPEFUN_SERVICE_NAME`、`SCRAPEFUN_SERVICE_USER`，Node 路径使用 `SCRAPEFUN_NODE_BINARY`。三个目录必须独立，使用绝对路径，原生 systemd 路径支持字母、数字、下划线、短横线、点和斜线。自定义配置目录的管理入口是 `sudo /path/to/config/scrapefun`，不会替换全局命令。

测试命令：

```bash
python3 scripts/operations/linux-server-tools.test.py -v
bash scripts/operations/operations.test.sh
```
