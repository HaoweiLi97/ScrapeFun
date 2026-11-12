# Debian 原生安装 ScrapeFun

本教程以没有 GPU 直通的 Debian 13（trixie）x86-64 虚拟机为例，实测安装了 ScrapeFun 0.5.10 稳定版。用能执行 `sudo` 的账号登录 Debian，并确认机器可以访问 Debian 软件源、GitHub 和 Node.js 官网。

## 1. 检查系统

```bash
cat /etc/os-release
uname -m
ps -p 1 -o comm=
```

确认架构显示 `x86_64`，最后一条命令显示 `systemd`。如果终端提示找不到 `curl`，先安装它。

```bash
sudo apt update && sudo apt install -y curl
```

## 2. 复制命令并安装

**没有 GPU 直通的虚拟机请保留 `--gpu-mode none`。** 这个参数会跳过漫画增强的硬件 GPU 检测。

点代码块右上角的 **复制代码**，把整条命令粘贴到 Debian 终端，再按回车。首次安装默认使用稳定版和 `8096` 端口。

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-native-deploy.sh | sudo bash -s -- --install-deps --non-interactive --gpu-mode none
```

`--install-deps` 会安装缺少的依赖，`--non-interactive` 会直接使用默认或已保存的设置。实测中，脚本从 Debian 软件源安装了 FFmpeg 和 FFprobe，并下载和校验了 ScrapeFun 使用的独立 Node.js 22。首次下载依赖和安装包可能需要几分钟。

这次实测中，默认 GPU 检测报了 `No hardware Vulkan device`，安装随即停止。遇到这个提示时，复制上面的命令重试。需要启用 GPU 漫画增强时，先让 Debian 能访问支持 Vulkan 的硬件，再按[显卡环境说明](https://scrapefun.com/#/docs/linux#gpu)设置。

实测时预检显示 `unverified distribution/version`，随后返回了 `PASS` 并继续安装。看到「ScrapeFun 原生服务已就绪」后，检查服务状态。

```bash
sudo scrapefun status
sudo scrapefun health
```

状态应显示 `active (running)`，健康检查应返回 `"ready":true`。

## 3. 打开 ScrapeFun

在能访问 Debian 的浏览器里打开 `http://服务器IP:8096`，把服务器 IP 换成你自己的地址。第一次打开时，在「欢迎使用 ScrapeFun」页面选择语言并继续初始化。

如果虚拟机用了 NAT 端口转发，请使用宿主机地址和转发后的端口。

如果服务还没就绪，用下面的命令查看日志，按 `Ctrl+C` 退出。健康检查已通过时，可以检查访问地址、端口转发或防火墙。

```bash
sudo scrapefun logs --follow
```

程序默认安装在 `/opt/scrapefun`，数据在 `/var/lib/scrapefun`，配置在 `/etc/scrapefun/server.env`。自定义端口、更新和备份命令见[原生 systemd 安装与维护](https://scrapefun.com/#/docs/linux#native)。
