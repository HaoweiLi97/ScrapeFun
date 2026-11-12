# 在群晖 DSM 上用 Docker 安装 ScrapeFun

这篇教程适合使用 x86-64（`amd64`）群晖 NAS 的朋友。开始前，请先创建好存储空间，并在套件中心安装 **Container Manager**。教程在 DSM 虚拟机上实操，截图中的英文界面名称也在正文里标了出来。

截图里的数字表示该图中的操作顺序，每张图都从 ① 开始。

## 1. 创建项目文件夹

打开 **File Station（文件管理）**，选中 `docker` 共享文件夹，点 **Create → Create folder（新建文件夹）**。如果还没有 `docker` 共享文件夹，可以先在控制面板的共享文件夹里创建一个。

![File Station 中的 docker 目录和创建入口](https://assets.scrapefun.com/docs/synology-docker/v1/01-file-station.jpg)

文件夹名称填 `scrapefun`，然后点 **OK**。

![创建 scrapefun 文件夹](https://assets.scrapefun.com/docs/synology-docker/v1/02-create-folder.jpg)

选中刚创建的文件夹，点 **Action → Properties（操作 → 属性）**，在 **Location（位置）** 里查看完整路径，复制或记下来。

![文件夹属性中的完整路径](https://assets.scrapefun.com/docs/synology-docker/v1/03-properties.jpg)

本次实操的路径是 `/volume1/docker/scrapefun`。你的存储空间和文件夹名称可能不同，下面请填写自己的完整路径。

## 2. 从官网下载配置

打开 [ScrapeFun 官网](https://scrapefun.com/)，点顶部 **文档**。

![ScrapeFun 官网文档入口](https://assets.scrapefun.com/docs/fnos-docker/v1/02-site-docs.jpg)

在 **安装与部署** 里找到 **NAS Docker Compose**，然后进入 **单文件 Compose 部署**。也可以直接打开 [NAS 部署文档](https://scrapefun.com/#/docs/nas#single-compose)。

![官网 NAS Docker Compose 文档入口](https://assets.scrapefun.com/docs/fnos-docker/v1/03-nas-doc.jpg)

1. 在 **NAS 项目目录** 里填入刚才查看到的完整路径。
2. 点 **生成并填入密钥**。
3. 点 **复制代码**，看到 **已复制** 后切回群晖页面。配置中包含密钥，请妥善保管。

![官网 NAS 项目目录、生成密钥和复制代码](https://assets.scrapefun.com/docs/synology-docker/v1/04-config-before.jpg)

截图展示的是生成密钥之前的页面。

## 3. 创建 Container Manager 项目

打开 **Container Manager**，进入 **Project（项目）**，点 **Create（新增）**。

![Container Manager 的项目入口与创建按钮](https://assets.scrapefun.com/docs/synology-docker/v1/05-project-list.jpg)

在创建窗口填写项目名称 `scrapefun`，点击 **Set Path（设置路径）**，在 `docker` 共享文件夹下选中刚创建的 `scrapefun` 文件夹，再点 **Select（选择）**。

![选择项目目录](https://assets.scrapefun.com/docs/synology-docker/v1/06-select-path.jpg)

回到项目设置，按图中顺序操作。

1. 检查 **Project name（项目名称）** 是 `scrapefun`。
2. 检查 **Path（路径）** 指向刚才选择的文件夹。群晖这里显示的是共享文件夹路径 `/docker/scrapefun`，官网配置中的 `x-project-dir` 要填写属性里看到的完整路径 `/volume1/docker/scrapefun`。
3. 在 **Source（来源）** 中选择 **Create docker-compose.yml（创建 docker-compose.yml）**。
4. 把官网复制的整段配置粘贴到编辑区。
5. 按下方说明补充更新器的配置文件路径，再点击 **Next（下一步）**。

![创建项目窗口中的名称、路径、来源和编辑区域](https://assets.scrapefun.com/docs/synology-docker/v1/07-project-empty.jpg)

截图中的编辑区展示的是粘贴之前的状态。粘贴后请检查 `x-project-dir` 和第一步的完整路径一致。

本次实操中，群晖向导显示的文件名是 `docker-compose.yml`，实际保存的文件却是 `compose.yaml`。为了让网页更新找到这个文件，在粘贴的配置里找到 `updater` 下的 `environment`，添加 `UPDATER_COMPOSE_FILE` 这一行。路径要换成你自己的项目完整路径，并以 `/compose.yaml` 结尾。

```yaml
  updater:
    environment:
      UPDATER_COMPOSE_FILE: /volume1/docker/scrapefun/compose.yaml
```

在原有的 `updater` 和 `environment` 下添加这一行，保留原来的其他配置。如果 NAS 的 `8096` 端口已经被占用，可以把端口映射改为 `"18096:8096"`，之后用 `18096` 访问。

在 **Web portal settings（Web 门户设置）** 页面，保持 **Set up web portal via Web Station** 不勾选，点击 **Next**。

![Web 门户设置页面](https://assets.scrapefun.com/docs/synology-docker/v1/08-web-portal.jpg)

在 **Summary（摘要）** 页面检查项目名称和路径，勾选 **Start the project once it is created（创建后启动项目）**，点击 **Done（完成）**。等待项目拉取镜像并启动。

![项目摘要和创建后启动选项](https://assets.scrapefun.com/docs/synology-docker/v1/09-summary.jpg)

官网配置会创建 `scrapefun` 和 `scrapefun-updater` 两个容器，后者通过 Docker socket 支持网页内更新。数据库和设置保存在挂载到 `/app/data` 的 Docker 命名卷里，以后重建项目时记得保留原数据卷。

## 4. 打开 ScrapeFun

回到 Container Manager 的 **Project（项目）** 页面，确认 `scrapefun` 正在运行。在同一局域网的浏览器里打开 `http://<群晖局域网IP>:8096`。把 IP 换成自己群晖的地址，如果前面改过宿主机端口，也要把 `8096` 换成映射左侧的数字。

![群晖项目列表中运行的 ScrapeFun](https://assets.scrapefun.com/docs/synology-docker/v1/10-project-running.jpg)

也可以进入 **Container（容器）**，查看 `scrapefun` 和 `scrapefun-updater` 两个容器的状态。

![群晖容器列表中的两个 ScrapeFun 容器](https://assets.scrapefun.com/docs/synology-docker/v1/11-containers.jpg)

第一次安装时，看到 ScrapeFun 初始化页面就说明安装完成了。如果沿用了已经初始化的数据卷，打开后会进入登录页面。

![ScrapeFun 初始化页面](https://assets.scrapefun.com/docs/synology-docker/v1/12-setup.jpg)

如果页面暂时打不开，可以先等一会儿。第一次拉取镜像和启动服务需要一些时间。仍然打不开的话，到 Container Manager 的 **Container（容器）** 页面查看运行状态和日志。
