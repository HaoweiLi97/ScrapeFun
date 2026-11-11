# 在飞牛 fnOS 上用 Docker 安装 ScrapeFun

这篇教程适合使用 x86-64（`amd64`）飞牛 NAS 的朋友。开始前，请先在飞牛里创建好存储空间，确认能打开 Docker 应用。用浏览器打开飞牛和 ScrapeFun 官网，接下来需要在两个页面之间切换。

## 1. 新建项目文件夹并复制原始路径

先在飞牛里打开 **文件管理 → 我的文件 → 新建文件夹**。文件夹名称填 `scrapefun`，选好存储空间，再点 **确定**。

下图的 ① 是填写名称，② 是确认创建。后面的截图也会用编号标出操作顺序，每张图都从 ① 开始。

![飞牛新建文件夹，框出文件夹名称和确定按钮](images/fnos-docker/01-new-folder.jpg)

选中刚建好的 `scrapefun` 文件夹，点 **更多 → 详细信息**，再在 **常规 → 位置** 旁边点 **复制原始路径**。

可以先把复制的内容粘贴到记事本里看看。完整的项目路径以 `/` 开头、以 `/scrapefun` 结尾。如果复制出来的是上一级文件夹路径，就在末尾加上 `/scrapefun`。

![飞牛文件夹详细信息中的复制原始路径](images/fnos-docker/05b-absolute-path.jpg)

教程里的示例路径是 `/vol1/1000/scrapefun`。每个人的存储空间和用户目录可能不一样，后面填写 **NAS 项目目录** 时，记得用你刚才复制并确认的路径。

## 2. 从 ScrapeFun 官网复制 Compose 配置

打开 [ScrapeFun 官网](https://scrapefun.com/)，点击顶部 **文档**。

![ScrapeFun 官网顶部导航中的文档入口](images/fnos-docker/02-site-docs.jpg)

在 **安装与部署** 里找到 **NAS Docker Compose**，打开后进入 **单文件 Compose 部署**。也可以直接打开 [官网 NAS 部署文档](https://scrapefun.com/#/docs/nas#single-compose)。

![文档中心安装与部署区域的 NAS Docker Compose 卡片](images/fnos-docker/03-nas-doc.jpg)

1. 把第一步确认的完整路径粘贴到 **NAS 项目目录**，替换网页里默认的 `/volume1/docker/scrapefun`。
2. 点 **生成并填入密钥**，网页会自动把登录密钥和更新 Token 填进配置。
3. 点代码框右上角的 **复制代码**。看到 **已复制** 后，切回飞牛页面。复制的配置里有密钥，请妥善保管。

![官网单文件配置区中的 NAS 项目目录、生成并填入密钥和复制代码](images/fnos-docker/06-generate-copy.jpg)

截图展示的是点击「生成并填入密钥」之前的页面。

## 3. 在飞牛创建 Compose 项目

打开 Docker，按图中 ① 进入 **Compose**，再按 ② 点 **新增项目**。③ 展示的是安装成功后的运行状态。

![飞牛 Docker 的 Compose 入口、新增项目按钮和运行中的 ScrapeFun 项目](images/fnos-docker/08-running.jpg)

在创建项目窗口的 **路径** 一栏选择文件夹。按下图 ① 选中 **我的文件 → scrapefun**，再按 ② 确认。

![飞牛选择路径弹窗中选中 scrapefun 文件夹](images/fnos-docker/05-select-folder.jpg)

回到创建项目窗口，按下图填写。

1. 项目名称填 `scrapefun`。
2. 选择刚才创建的文件夹。
3. 在 **来源** 选择 **创建docker-compose.yml**。
4. 把刚才从官网复制的整段 YAML 粘贴到编辑区，检查 `x-project-dir` 是否和第一步确认的完整路径一致。
5. 勾选 **创建项目后立即启动**。
6. 点 **确认**。如果 NAS 上的 `8096` 端口已经被其他服务占用，可以先把端口映射改成 `"18096:8096"`，之后用 `18096` 访问。

![飞牛创建项目表单中的项目名称、路径、YAML 编辑区和启动选项，更新 Token 已遮盖](images/fnos-docker/07-paste-preview.jpg)

官网配置会创建 `scrapefun` 和 `scrapefun-updater` 两个容器，后者通过 Docker socket 支持网页内更新。数据库和设置保存在挂载到 `/app/data` 的 Docker 命名卷里，以后重建项目时记得保留原数据卷。

## 4. 打开 ScrapeFun

回到 **Docker → Compose** 查看 `scrapefun` 项目。等它显示 **正在运行** 后，在同一局域网的浏览器里打开 `http://<飞牛局域网IP>:8096`。把地址里的 IP 换成你自己飞牛的局域网 IP。如果前面改过端口，也要把 `8096` 换成端口映射左边的数字。

第一次安装时，看到下面的初始化页面就说明安装完成了。如果沿用的是已经初始化过的数据卷，打开后会直接进入登录页面。

![ScrapeFun 首次启动后的初始化向导](images/fnos-docker/09-setup-clean.jpg)

如果页面暂时打不开，可以先等一会儿。第一次拉取镜像和启动服务需要一些时间。仍然打不开的话，到 **Docker → 容器** 看看 `scrapefun` 的运行状态、日志和端口映射是否正常。
