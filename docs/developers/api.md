# API 接入参考

[简体中文](api.md) · [English](api.en.md)

2026-11-03

<a id="scope"></a>

## 地址与适用范围

以下为 ScrapeFun 自有 HTTP API 的精选接口，按当前标记为 0.5.1 的开发版本核对；已发布版本的能力可能不同，先在自己的实例验证。本文不构成所有内部接口的清单。API 地址是你部署的 Server，例如 `http://127.0.0.1:8096`，不是产品门户地址。远程连接使用 HTTPS。

[OpenAPI 描述](https://scrapefun.com/developers/openapi.json)可供工具读取。[GitHub 文档](https://github.com/HaoweiLi97/ScrapeFun/tree/main/docs/developers)提供 Markdown 和扩展示例。[刮削器编写](scrapers.md)与[测试和管理](scraper-api.md)另有专篇。

请求和响应使用 JSON；成功可能返回对象、数组或空响应，不存在统一的 `data` 包装。不要把刮削器的来源 ID、Server 的元数据 ID、媒体库 ID 或任务 ID 混用。本文的示例域名和 ID 都是虚构值。

<a id="authentication"></a>

## 登录与权限

先通过页面完成 Server 初始化。脚本调用 `POST /api/auth/login` 时发送 `X-ScrapeFun-Platform: api`，明确请求 Bearer 模式；请求体为 `username`、`password` 字符串，可选 `remember` 布尔值。不要省略平台头后假定一定返回可用的 Bearer token。

```http
POST /api/auth/login HTTP/1.1
Host: localhost:8096
Content-Type: application/json
X-ScrapeFun-Platform: api

{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD","remember":false}
```

成功响应包含 `token`、`authMode`、`expiresAt`（Unix 毫秒）和 `user`。确认 `authMode` 为 `bearer`，将 token 当作不透明字符串，通过后续请求的 `Authorization: Bearer <token>` 传递。Cookie 模式中的占位 token 不能用于 Bearer 认证。不要把凭据、完整登录响应或 token 写进公开仓库、URL、截图或 AI 对话。

| 接口 | 用途 | 成功响应 |
| --- | --- | --- |
| `GET /api/auth/me` | 查询当前登录用户 | `{user}` |
| `POST /api/auth/logout` | 结束当前会话 | HTTP 204，无正文 |
| `POST /api/auth/logout-all` | 结束当前用户全部会话 | `{success:true}` |

普通用户只能访问获准的媒体库。扫描、元数据批量更新和任务管理需要管理员。Cookie 写请求还需要符合来源校验；自动化优先使用 Bearer。API 权限不会因为由 AI 发起而变化。

<a id="metadata"></a>

## 查询媒体

| 接口 | 输入 | 响应 |
| --- | --- | --- |
| `GET /api/libraries` | 无 | 当前用户可见的媒体库数组，含 `id`、`name`、`type` 等 |
| `GET /api/metadata` | 下表查询参数 | `{items,total,page,pageSize}` |
| `GET /api/metadata/detail/{id}` | Server 元数据 ID | 作品详情对象；不可见或不存在时 404 |
| `GET /api/metadata/{id}/episodes` | 可选查询参数 `season` | `{metadataId,season,episodes}` |
| `GET /api/metadata/{id}/files` | Server 元数据 ID | `{metadataId,files}` |

| 媒体列表参数 | 类型与规则 |
| --- | --- |
| `q` | 可选搜索文字，需 URL 编码 |
| `libraryIds` | 可选，逗号分隔的媒体库 ID |
| `type` | 可选，如 `movie`、`tv`、`comic`、`book` |
| `favorite` | 传字符串 `true` 筛选收藏 |
| `page` | 从 1 开始，默认 1 |
| `pageSize` | 默认 20，范围 1–100 |
| `view` | `card` 或 `full`，默认 `full` |
| `sortBy`、`sortOrder` | 常用 `title`、`year`、`rating`、`createdAt`；`asc` 或 `desc`，默认按创建时间降序 |

作品常见字段为 `id`、`title`、`type`、`year`、`summary`、`rating`；不同视图和媒体类型返回的字段不同，缺失值可能为 null。结果中的资源地址可能带有访问权限信息，应视为私有数据。

```bash
curl --fail-with-body --get "$SCRAPEFUN_URL/api/metadata" \
  --header "Authorization: Bearer $SCRAPEFUN_TOKEN" \
  --data-urlencode 'q=Example work' \
  --data-urlencode 'page=1' --data-urlencode 'pageSize=20' \
  --data-urlencode 'view=card'
```

环境变量由调用者在本地设置；`SCRAPEFUN_URL` 为不带末尾斜杠的 Server 地址。不要在公开日志中打印 `SCRAPEFUN_TOKEN`。

<a id="user-state"></a>

## 收藏与已看状态

`PATCH /api/metadata/{id}/favorite` 接受 `{favorite:boolean}`，返回 `{success:true,favorite:boolean}`，只修改当前用户收藏。

`PATCH /api/metadata/{id}/watched` 接受 `{watched:boolean,episodeId?:string}`，返回 `{success:true}`。episodeId 必须属于该作品。将已看设为 false 会清除当前用户对应进度；整部剧设为未看还会重置各集状态。AI 应在用户明确要求时才执行这些写入。

<a id="tasks"></a>

## 扫描与任务跟踪

以下接口要求管理员。先从媒体库列表获取真实 ID。扫描和更新适用于文件型媒体库，不适用于虚拟库。

| 接口 | 请求体 | 行为 |
| --- | --- | --- |
| `POST /api/libraries/{id}/scan` | 可选 `{fullRefresh:false}` | 启动扫描；true 会刷新已有元数据 |
| `POST /api/libraries/{id}/update` | 可选 `{mode:"missing"}` | `missing` 补缺；`all` 更新全部，省略时默认 all |

成功返回 `{success:true,taskId,message}`，表示已启动任务，不表示工作已经完成。重复任务可能返回 409；响应可能带 `taskIds`。连接中断时先检查现有任务，避免直接重复提交。

| 接口 | 参数与响应 |
| --- | --- |
| `GET /api/tasks` | `scope=active`、`history` 或 `inbox`，可选 `limit`；返回 `{scope,unreadCount,tasks}` |
| `GET /api/tasks/{id}` | 返回单个任务对象 |
| `GET /api/tasks/{id}/events` | 返回 `{events}` |
| `POST /api/tasks/{id}/cancel` | 取消任务；仅在任务允许时调用 |
| `POST /api/tasks/{id}/pause` | 暂停受支持的任务 |
| `POST /api/tasks/{id}/resume` | 继续已暂停且受支持的任务 |
| `POST /api/tasks/{id}/retry` | 重试；如返回新 `taskId`，改为跟踪新任务 |

任务包含 `id`、`kind`、`title`、`status`、`phase`、`summary`、`progress` 和 `capabilities`。progress 常见字段为 `current`、`total`、`percent`，未知进度可能为 null。状态包括 `queued`、`running`、`paused`、`succeeded`、`failed`、`cancelled`、`needs_attention`。以实际 `capabilities` 判断 cancel、pause、resume、retry 是否可用，不要仅根据状态推断。

<a id="errors"></a>

## 错误与自动化调用

| HTTP 状态 | 处理方式 |
| --- | --- |
| 400 | 检查参数和媒体库类型，不原样循环重试 |
| 401 | 会话缺失或过期，重新登录 |
| 403 | 权限不足或尚未初始化；使用有权的用户并检查实例状态 |
| 404 | 对象不存在或当前用户不可见 |
| 409 | 任务或版本冲突，读回当前状态后处理 |
| 429 | 遵守 `Retry-After`（若返回），降低频率 |
| 500 | 读取错误正文，排查实例和上游服务；写请求先核实是否已生效 |

错误正文通常含 `error`，部分接口另有 `code`。不要假设每个接口都有相同错误结构。列表按页读取；任务使用间隔轮询，完成或需人工处理时停止。给 AI 使用时提供本文和刮削器规范，先说明目标、实例版本和允许的读写范围，凭据仅保存在执行环境中。
