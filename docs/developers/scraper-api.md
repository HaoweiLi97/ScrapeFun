# 刮削器测试与管理 API

[简体中文](scraper-api.md) · [English](scraper-api.en.md)

2026-11-03

<a id="entry-points"></a>

## 选择调用方式

本文按当前标记为 0.5.1 的开发版本核对，已发布版本的能力可能不同。先阅读[API 认证](api.md#authentication)与[刮削器编写规范](scrapers.md)。路径相对于自己的 Server。登录用户可读取活动来源、搜索和直接调用；代码测试、保存和管理写操作、预览与图片目录要求管理员。资料访问权限仍然适用。

| 目标 | 接口 | 行为 |
| --- | --- | --- |
| 查看活动来源 | `GET /api/scrape/scrapers` | 读取可用来源与能力 |
| 临时测试代码 | `POST /api/config/test` | 不保存来源或正式入库；代码自身仍可访问外部服务 |
| 直接搜索或详情 | `POST /api/scrape/trigger` | 不正式入库 |
| 搜索匹配候选 | `GET /api/scrape/search` | 不创建媒体记录 |
| 预览来源详情 | `POST /api/scrape/preview` | 不正式入库 |
| 保存来源 | `POST /api/config/system` | 写入来源并尝试注册 |

只运行信任的扩展代码。临时测试成功不表示已保存来源或更新媒体库。

<a id="test-request"></a>

## 工作台请求

`POST /api/config/test` 接受以下字段，不接受额外的管理保存字段。

| 字段 | 规则 |
| --- | --- |
| `code` | 必填非空 string，扩展代码最多 512 KiB |
| `input` | 必填非空 string，搜索文字、作品 ID 或人物 ID，最多 8192 字符 |
| `type` | 必填，下表列出的测试动作 |
| `name` | 可选来源名，最长 120 字符，与代码声明一致 |
| `capabilityConfig` | 可选，与代码一致的能力配置，格式见编写规范 |
| `category` | 可选声明的媒体类型，与 options.type 一致 |
| `options` | 可选 JSON 对象，按方法传入 |
| `cleaning` | 默认 `{mode:"none"}`；仅 search 可用 `{mode:"inline",code:"..."}` |
| `timeoutMs` | 默认 30000，范围 100–60000 毫秒 |

| type | input 与 options |
| --- | --- |
| `search` | input 为查询；options 可传 page、pageSize、已声明支持的语言偏好 |
| `scrape` | input 为来源作品 ID |
| `discover` | input 仍须非空，如 `discover`；options 按来源要求 |
| `video` | input 为作品 ID；不接受 category 或非空 options |
| `playback` | input 为作品 ID；同时检查视频地址与请求头；不接受 category 或非空 options |
| `comic_chapters` | input 为作品 ID |
| `comic_pages` | input 为作品 ID，options.chapterId 必填 |
| `comic_image` | 同上，另需从 0 开始的 options.pageIndex |
| `actor_search` | input 为人物姓名 |
| `actor_scrape` | input 为来源人物 ID |

没有 images 测试动作，getImages 通过已注册来源验证。绑定的清洗规则不会自动用于临时测试，需要时提供 inline 代码。此请求不接受 cleaningScriptId。

将本地扩展文件读入 JSON，避免手动转义。下列命令只临时测试，不保存：

```bash
jq -n --rawfile code ./generic-metadata.scraper.ts \
  '{code:$code,name:"Generic Metadata Source",type:"search",input:"Example work",category:"movie",options:{page:1,pageSize:20}}' |
curl --fail-with-body --silent --show-error --max-time 45 \
  --request POST "$SCRAPEFUN_URL/api/config/test" \
  --header "Authorization: Bearer $SCRAPEFUN_TOKEN" \
  --header 'Content-Type: application/json' --data-binary @-
```

成功返回 result、logs、executionId、durationMs、phase、truncation，部分动作另有 applied。result 结构取决于动作。truncation.logs 或 truncation.result 为 true 表示输出不完整。失败时检查 HTTP 状态、error、code 和日志；日志分享前需脱敏。

<a id="registered"></a>

## 调用已注册来源

`GET /api/scrape/scrapers?type=movie` 返回活动来源数组，常见字段为 name、supportedTypes、methodCapabilities、hasImageSupport、hasActorSupport 及语言偏好标记。使用规范 name，不用文件名代替，并按实际能力调用。

`POST /api/scrape/trigger` 接受以下直接搜索请求：

```json
{"scraper":"Generic Metadata Source","query":"Example work"}
```

获取详情使用来源 ID：

```json
{"scraper":"Generic Metadata Source","id":"generic-metadata:123"}
```

返回 `{success:true,data:...}`；同时传 id 与 query 时 id 优先。不透传任意 options、page/pageSize 或语言偏好，搜索也不保留来源分页对象。验证选项和分页使用工作台。

| 接口 | 输入与返回 |
| --- | --- |
| `GET /api/scrape/search` | 查询参数 q、scraper、type；返回匹配候选数组。明确来源与类型，参数做 URL 编码；不是分页透传 |
| `POST /api/scrape/preview` | 管理员；`{scraper,id,type?}`，返回预览详情，不正式入库 |
| `GET /api/scrape/video` | 查询参数 scraper、id；返回 `{videoUrl}`，不含完整请求头，调试请求头用 playback 测试 |
| `GET /api/scrape/images` | 管理员；查询参数 scraper、id，可选逗号分隔的 imageLanguagePreferences；返回 `{scraper,providerId,images,imageLanguagePreferences}`，需 getImages 能力 |

<a id="save"></a>

## 保存与注册

`GET /api/config/system` 向已登录用户返回来源管理列表，包括用户扩展代码、id、version、enabled 和能力。不要公开该响应，它可能包含用户配置或扩展凭据。

`POST /api/config/system` 要求管理员。新建使用 code、name、filename，可选 capabilityConfig、cleaningScriptId。filename 为单个 `.scraper.ts` 文件名，不含目录；code 是自己的扩展。

```json
{"name":"Generic Metadata Source","filename":"generic-metadata.scraper.ts","code":"<YOUR_EXTENSION_CODE>"}
```

编辑时先读最新记录，额外传原 id 与 baseVersion，保持 name 和文件名不变。baseVersion 使用读到的 version；409 后重新读取并合并。cleaningScriptId 省略保留绑定，null 解绑。

响应包含 success、scraper、version、receipt。分别检查 `receipt.persistence.state` 为 saved，以及 `receipt.registration.state` 为 registered。disabled 表示停用；failed 或 unavailable 表示不可作为活动来源。HTTP 200 不证明注册成功。普通保存无需重启 Server，再读活动来源列表核对。

| 管理接口 | 请求与限制 |
| --- | --- |
| `POST /api/config/system/toggle` | `{name,enabled:boolean}` |
| `POST /api/config/system/reorder` | `{names:[name,...]}`，设置列表顺序 |
| `DELETE /api/config/system/{filename}` | 删除允许删除的来源；建议 `If-Match: "<version>"` 防止并发覆盖 |

来源名须唯一，不冒用已有或系统保留名称。存在引用时删除可能返回 409；检查 references，由用户决定处理方式，不自动解绑或删除资料。旧 `/api/config` 创建和旧 `/{id}` 修改入口已停用。

<a id="cleaning"></a>

## 文件名清洗

规则为同步 `function clean(input)`，返回 string。创建字段为 content，测试字段为 code。读取需登录，写入和测试需管理员。

| 接口 | 输入与返回 |
| --- | --- |
| `GET /api/cleaning` | 读取规则与 ID |
| `POST /api/cleaning` | `{name,content}` 新建 |
| `PUT /api/cleaning/{id}` | `{name,content}` 更新 |
| `POST /api/cleaning/test` | `{code,input}` → `{success,cleanedName,logs}` |
| `POST /api/cleaning/reorder` | `{ids:[id,...]}` |
| `DELETE /api/cleaning/{id}` | 删除可删除的规则并清理相关绑定 |

name 为 1–120 字符，代码最多 512 KiB，测试 input 最多 8192 字符。内置受保护规则不能修改或删除。测试带年份、季集、中文书名和普通标题的文件名，避免破坏识别信息。

`GET /api/scrape/clean?q=<filename>&scraper=<name>` 返回 `{cleaned}`，检查实际清洗效果。通过保存接口的 cleaningScriptId 绑定规则；临时测试成功不证明绑定生效，应分别核对。

<a id="composite"></a>

## 组合来源

`GET /api/composite` 返回组合列表。管理员通过 `POST /api/composite` 创建或更新：

```json
{"name":"Combined Movies","memberNames":["Source A","Source B"],"isActive":true}
```

更新加原 id，保持 name 不变。memberNames 是有序的完整替换列表，至少一个可用基础来源，不允许自身、重复或嵌套组合。检查 runtime.state 与 registered，不能仅凭 isActive 判断就绪。删除使用 `DELETE /api/composite/{id}`，有引用时可能返回 409。

组合候选 ID 不透明，详情请求须原样传回，不当作上游裸 ID。列表顺序不等于总是只用第一个来源。组合目前不通用转发 getImages、getComicChapters、getComicPages；漫画阅读请选择实现相应方法的基础来源。
