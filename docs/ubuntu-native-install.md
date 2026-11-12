# Ubuntu 原生安装 ScrapeFun

## 1. 检查 Ubuntu 环境

本教程以 Ubuntu Server 24.04 LTS、x86-64 为例，实测安装了 ScrapeFun 服务端 0.5.10 稳定版。用能执行 `sudo` 的账号登录 Ubuntu，确认系统能访问 Ubuntu 软件源、Node.js 官网和 GitHub。

```bash
cat /etc/os-release
uname -m
ps -p 1 -o comm=
```

确认架构是 `x86_64`，最后一条命令显示 `systemd`。如果终端提示找不到 `curl`，先安装它。

```bash
sudo apt update && sudo apt install -y curl
```

## 2. 复制命令并安装

点代码块右上角的 **复制代码**，把整条命令粘贴到 Ubuntu 终端，按回车执行。首次安装使用稳定版和 `8096` 端口。

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-native-deploy.sh | sudo bash -s -- --install-deps --non-interactive
```

`--install-deps` 会补齐缺少的依赖。实测中，脚本安装了 FFmpeg 和 FFprobe，并下载、校验了 ScrapeFun 使用的独立 Node.js 22。首次下载依赖和发布包可能需要几分钟。看到「ScrapeFun 原生服务已就绪」后，运行以下命令检查服务。

```bash
sudo scrapefun status
sudo scrapefun health
```

状态应显示 `active (running)`，健康检查应返回 `"ready":true`。

## 3. 打开 ScrapeFun

在能访问这台 Ubuntu 的浏览器里打开 `http://服务器IP:8096`，把服务器 IP 换成你自己的地址。第一次打开时，看到「欢迎使用 ScrapeFun」就可以选择语言并继续初始化。

如果 Ubuntu 跑在虚拟机里，请使用能从浏览器访问的 IP 和端口。通过 NAT 做了端口转发时，用宿主机地址和转发后的端口。

如果网页打不开，先运行上一步的健康检查。服务未就绪时，复制下面的命令查看日志，按 `Ctrl+C` 退出。健康检查通过时，检查访问地址、端口转发或防火墙。

```bash
sudo scrapefun logs --follow
```

程序默认安装在 `/opt/scrapefun`，数据在 `/var/lib/scrapefun`，配置在 `/etc/scrapefun/server.env`。自定义端口、更新和备份命令见[原生 systemd 安装与维护](https://scrapefun.com/#/docs/linux#native)。
