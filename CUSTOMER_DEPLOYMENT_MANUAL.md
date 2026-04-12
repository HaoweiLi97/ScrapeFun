# Scrapefun 用户部署说明书

这份文档面向最终部署 Scrapefun 的用户或运维人员，目标是把部署、升级、备份恢复和授权配置讲清楚。

## 1. 部署方式

当前推荐的生产部署方式是 Docker。

支持两种落地方式：

1. 手动部署：用户自己准备 `docker-compose.yml` 和 `server.env`
2. 半自动部署：维护方在本地构建镜像后，用远程部署脚本推送到目标机器

如果是普通用户自部署，优先看“手动部署”。
如果是你自己给客户远程发版，优先看“远程部署脚本”。

## 2. 运行前提

目标机器建议满足：

1. Linux x86_64
2. 已安装 Docker Engine
3. 已安装 Docker Compose Plugin
4. 可以访问 Scrapefun 镜像源
5. 如果启用授权功能，可以访问你的 license server

建议额外准备：

1. 一个稳定域名或反向代理
2. 可访问的 FlareSolverr
3. 足够的磁盘空间给数据库和图片缓存

## 3. 目录结构

建议在服务器上使用一个固定目录，例如：

```bash
mkdir -p ~/scrapetab
cd ~/scrapetab
```

这个目录下至少放两份文件：

1. `docker-compose.yml`
2. `server.env`

## 4. 推荐的生产 compose

可以直接使用项目里的远程 compose 作为生产模板：

- [`docker-compose.remote.yml`](./docker-compose.remote.yml)

它的关键点是：

1. 使用 `host` 网络模式
2. 持久化数据库、图片和 scraper 目录
3. 持久化 `config` 数据，保留安装实例授权状态

一个典型示例如下：

```yaml
version: '3.8'

services:
  app:
    image: haoweil/scrapetab:latest
    container_name: scrapetab
    network_mode: "host"
    env_file:
      - ./server.env
    environment:
      - NODE_ENV=production
      - FLARESOLVERR_URL=http://127.0.0.1:8191/v1
    volumes:
      - scrapetab_data:/app/server/prisma
      - scrapetab_images:/app/public/images
      - scrapetab_scrapers:/app/server/src/scrapers
      - scrapetab_config:/app/data/config
    restart: unless-stopped

volumes:
  scrapetab_data:
  scrapetab_images:
  scrapetab_scrapers:
  scrapetab_config:
```

## 5. `server.env` 应该怎么配

可以从：

- [`.env.example`](./.env.example)

复制出一份 `server.env`。

最少建议配置这些：

```env
NODE_ENV=production
PORT=4000
FLARESOLVERR_URL=http://127.0.0.1:8191/v1
JWT_SECRET=replace_with_a_strong_secret
```

DockerHub 公共部署默认不需要任何授权 env。
基础功能可以直接启动，只有在应用内激活 Pro 时才会和官方授权服务器建立绑定。

### 授权配置规则

这里有三个边界要守住：

1. 客户环境不要放 `LICENSE_BOOTSTRAP_ADMIN_KEY`
2. 客户环境不要手填 `LICENSE_INSTANCE_ID` / `LICENSE_SERVER_API_KEY`
3. Docker 生产环境务必持久化 `db / images / config`，尤其是 `config`

官方分发版中，这几项已经内置，不再要求客户自行配置：

1. 授权服务器地址
2. 授权模式
3. 响应签名校验开关
4. 响应验签公钥

实例级 runtime 凭据会在首次成功激活 Pro 时自动下发并落库，用户不需要手动接触：

1. `LICENSE_INSTANCE_ID`
2. `LICENSE_SERVER_API_KEY`
3. `installationId`
4. `installationLease`

## 6. 手动部署步骤

### 第一步：准备文件

把这两个文件放到服务器目录：

1. `docker-compose.yml`
2. `server.env`

### 第二步：拉镜像

```bash
docker pull haoweil/scrapetab:latest
```

### 第三步：启动

```bash
cd ~/scrapetab
docker compose up -d
```

### 第四步：看日志

```bash
docker compose logs -f app
```

正常情况下会看到：

1. Prisma schema 同步
2. 本地图片整理任务
3. `Server running on port 4000`

### 第五步：浏览器访问

默认访问：

```text
http://<server-ip>:4000
```

## 7. 首次授权流程

如果要启用 premium 功能，当前默认流程是：

1. 用户直接启动 Scrapefun
2. 先使用基础功能
3. 在设置页输入 `License Key`
4. Scrapefun 首次激活时自动向官方授权服务器完成实例注册
5. 服务端返回并持久化 runtime 凭据与 installation lease

### 为什么不把 bootstrap admin key 发给客户

因为那会让客户部署环境具备实例申请和轮换能力，权限过大。

现在推荐策略是：

1. bootstrap 只用于内部运维或兼容路径
2. DockerHub 用户不接触安装令牌、runtime 凭据或 admin key
3. premium 许可由签名 installation lease + 机器指纹共同约束

## 8. 升级方式

### 方式一：手动升级

```bash
cd ~/scrapetab
docker pull haoweil/scrapetab:latest
docker compose up -d --force-recreate app
```

这个方式会保留原来的 volumes：

1. `scrapetab_data`
2. `scrapetab_images`
3. `scrapetab_scrapers`

所以数据库、图片和 scraper 不会因为重启丢失。

### 方式一增强：启用 sidecar updater

如果你希望用户在 Scrapetab 设置页中直接点“立即更新”，推荐使用 compose 模板里内置的 sidecar updater。  
它会跟 `app` 一起启动，不需要额外手工跑命令。

建议在部署目录额外准备一个 `.env`，至少包含：

```env
UPDATE_DOCKERHUB_REPO=haoweil/scrapefun
UPDATE_DEFAULT_CHANNEL=stable
```

设置页支持两条更新分支：

1. `stable`：只跟踪正式版 tag
2. `beta`：允许跟踪带预发布标记的 beta 版本

当前 `docker-compose.remote.yml` 已内置 `updater` 服务，并支持通过 `SCRAPETAB_IMAGE` 切换镜像 tag；updater 会自动写入该值并重建 `app` 服务。

### 方式二：远程脚本升级

内部维护时我会使用两套远程发布脚本：

1. `deploy_remote_auto.sh`
2. `deploy_remote_auto_chrome.sh`

它们适合维护方把本地构建好的镜像推送到指定远程机器。

特点：

1. 本地构建 amd64 镜像
2. 自动上传 `docker-compose.yml`
3. 自动上传清洗后的 `server.env`
4. 会自动过滤：
   - `LICENSE_BOOTSTRAP_ADMIN_KEY`
   - `LICENSE_BOOTSTRAP_NOTES`

注意：

1. 这两个脚本属于内部运维流程，不在公开仓库提供
2. 客户自部署不建议直接复用，最好按自己的机器名和密码改造

## 9. 备份与恢复

### 应用内备份

当前支持在设置页直接导出和恢复备份。

导出内容包括：

1. SQLite 数据库
2. 图片目录
3. scraper 文件

当前导出已经改成流式处理，图片按 `store` 模式写入 zip，内存峰值比早期实现低。

### 建议的运维备份

除了应用内备份，生产上仍建议定期备份这三个 volume：

1. `scrapetab_data`
2. `scrapetab_images`
3. `scrapetab_scrapers`

可以用：

```bash
docker volume inspect scrapetab_data
docker volume inspect scrapetab_images
docker volume inspect scrapetab_scrapers
```

先确认宿主机上的真实挂载位置，再做宿主机级备份。

## 10. 常见问题

### 1. 重启后数据会不会丢

不会，只要这三个 volume 还在：

1. `scrapetab_data`
2. `scrapetab_images`
3. `scrapetab_scrapers`

### 2. 为什么不要删 volume

因为 SQLite 数据库就在 `scrapetab_data` 里。删了这个 volume，相当于删库。

### 3. 为什么部署后会“自动激活”

如果部署复用了旧数据库或旧 volume，就可能把旧实例状态一起带过去。

现在的授权机制是安装实例绑定。只要你把同一份持久化数据目录带过去，服务就会把它视为同一个安装实例继续运行。

### 4. 激活服务器地址要不要隐藏

不需要把 `LICENSE_SERVER_URL` 当成核心秘密。

真正要防的是：

1. `LICENSE_BOOTSTRAP_ADMIN_KEY`
2. 高权限管理凭据
3. 可跨实例滥用的授权状态复制

### 5. 为什么要保留 `config` volume

因为 premium 激活后的安装实例凭据会保存在持久化数据里。

如果把 `config` 或整个持久化目录删掉，这个实例就会被视为一次重新安装，需要重新输入 `License Key`。

## 11. 交付给客户时的最小清单

给客户交付 Scrapefun 时，至少确认下面这些项：

1. 提供 `docker-compose.yml`
2. 提供 `server.env`
3. `server.env` 里不包含 `LICENSE_BOOTSTRAP_ADMIN_KEY`
4. 已说明 Pro 激活只需要在页面输入 `License Key`
5. compose 已持久化 `db / images / config`
6. 已说明如何备份 volumes
7. 已说明升级命令

## 12. 一套最短可执行流程

如果用户只是想最快部署一套可用实例，可以按下面做：

```bash
mkdir -p ~/scrapetab
cd ~/scrapetab
```

写入 `docker-compose.yml` 和 `server.env` 后执行：

```bash
docker pull haoweil/scrapetab:latest
docker compose up -d
docker compose logs -f app
```

看到服务启动完成后，浏览器打开：

```text
http://<server-ip>:4000
```

如果还要启用 premium：

1. 确认 `db / images / config` 持久化目录已经正确挂载
2. 确认官方授权服务器可达
3. 在页面内输入有效的 `License Key`
