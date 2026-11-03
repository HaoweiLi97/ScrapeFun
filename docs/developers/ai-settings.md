# AI 接入与配置

[简体中文](ai-settings.md) · [English](ai-settings.en.md)

2026-11-03

<a id="start"></a>

## 配置入口与条件

本指南按当前标记为 0.5.1 的开发版本核对，已发布版本的入口和能力可能不同。管理员在 Server 的“设置 → AI 配置”管理文本、语音与图像服务；元数据翻译的绑定与行为位于“刮削与匹配”。界面没有对应选项时先核对实例版本。

文本 AI 使用兼容 Chat Completions 的服务。服务地址、模型标识和密钥由你使用的服务商提供；仅支持其他协议的地址不能直接当作该接口使用。云端模型产生的费用和额度由服务商管理。外部 AI 按[刮削器规范](scrapers.md)编写扩展不需要先配置站内文本 AI。

<a id="text"></a>

## 添加文本 AI 连接

1. 在“AI 配置”的文本 AI 区域添加连接。
2. 填写名称、接口地址、API Key 和模型，按需要启用连接。
3. 获取模型列表，选择或输入真实模型 ID，再执行连接测试。
4. 保存后，在需要的功能中选择此连接，并验证一次实际请求。

| 配置项 | 填写方法 |
| --- | --- |
| 名称 | 自己辨认连接用途的名称，可为不同服务分别创建连接 |
| 接口地址 | 服务 API 基地址，例如虚构的 `https://ai.example/v1`；也可填写完整 `/chat/completions` 地址 |
| API Key | AI 服务商密钥；不同于 ScrapeFun 登录 token。文本连接测试要求非空密钥 |
| 模型 | 服务实际提供且当前密钥可用的模型 ID，保留大小写与完整名称 |
| 启用 | 连接需启用后才能供绑定的功能使用 |

地址不填写网页聊天地址，也不在 URL 中嵌入账号密码或 Key。按服务商要求保留版本路径；不要自动为所有服务猜测同一个 `/v1`。本地兼容服务同样需要满足该请求协议；无鉴权服务仅在该服务明确接受非空占位 Key 时才可用占位值测试。

连接由 Server 发起。Docker 中的 localhost 指容器自身；本机可用不等于容器可达。填写 Server 实际能访问的地址，并确保相应端口只向所需网络开放。远程连接使用 HTTPS。

获取模型成功只证明目录请求被接受，不证明所选模型可执行。部分服务不提供模型目录或使用别名，可以直接填写模型 ID 后测试。更改地址、Key 或模型后重新测试；测试成功不会自动保存尚未保存的表单。

<a id="translation"></a>

## 绑定元数据翻译

在“刮削与匹配 → 元数据翻译”选择已启用的文本 AI 连接，再设置翻译范围、标题清理、提示词及刮削时自动翻译。保存连接与选择功能绑定是两个步骤；添加了连接却未绑定、停用了已绑定连接，都可能导致功能不可用。

先对一条测试作品执行翻译，检查标题、简介、年份和卷集编号，再启用自动翻译。修改翻译范围不会自动证明已有媒体资料全部重新翻译。自定义提示词应保留原文事实、ID 与编号；不要把 API Key 或账号信息放进提示词。

翻译会把需要处理的文字发送给所选服务商。使用前确认这些资料适合发送到该服务。文本 AI 连接与语音 AI 配置分别管理，不能用文本连接测试替代音频功能验收。

<a id="voice"></a>

## 语音 AI 与听书

在“AI 配置”中添加语音连接，选择与服务一致的协议，再填写以下字段。当前提供 Audio Speech 和 Chat Completions Audio 两种协议选项，文本模型可用不代表它能输出音频。

| 配置项 | 用途 |
| --- | --- |
| 协议、接口地址 | Audio Speech 对应 `/audio/speech`；Chat Completions Audio 对应支持音频的 `/chat/completions`；按服务要求填写基地址或完整地址 |
| 模型、API 密钥 | 使用支持所选音频协议的模型及其凭据；部分本机 Audio Speech 服务允许空密钥，以页面校验为准 |
| 首选音色 ID | 服务实际支持的音色 ID，不用显示名称替代 |
| 音色列表地址、音色表 | 通过服务提供的音色接口获取，或手动维护音色表；音色目录不是所有服务都有的统一接口 |
| 朗读指引 | 可选的语气与朗读要求，是否生效取决于模型与协议 |
| 启用 | 保存并启用后，在阅读器听书入口选择对应音色 |

先测试一小段文字，检查能否生成并播放音频、音色是否正确，再用于长篇听书。不同协议的模型、音色和返回格式不能随意互换。发送给远程语音服务的书籍文字同样需要考虑资料隐私。

<a id="images"></a>

## 图像增强

图像增强的引擎与模型在“AI 配置”中选择，设备、分块、线程与输出等参数位于“高级设置”。按实例显示的可用能力和模型清单选择；不同平台、硬件和模型的可用性可能不同。

图像增强不使用文本连接的 Key 和模型。先用少量漫画页面检查清晰度、耗时与资源占用；更换模型后重新检查。需要相应产品权益的能力以实例页面提示为准。

<a id="api"></a>

## 连接测试 API

以下接口需要[管理员 Bearer 会话](api.md#authentication)，使用自己的 Server 地址。两个接口都按本次请求的值测试，不保存配置；会向填写的 AI 服务发起请求，模型测试可能产生用量。

| 接口 | 请求与响应 |
| --- | --- |
| `POST /api/settings/ai/text/models` | 请求 `{url,key}`；成功返回 `{models:[modelId,...],keyStatus:"valid"}` |
| `POST /api/settings/ai/text/test` | 请求 `{url,key,model}`；成功返回 `{success:true,keyStatus:"valid",latencyMs,model}` |

```json
{"url":"https://ai.example/v1","key":"YOUR_AI_PROVIDER_KEY","model":"YOUR_MODEL_ID"}
```

上例为测试请求示意，域名与凭据均为占位值。Server 的 Authorization 头放 ScrapeFun 会话 token，请求体的 key 放 AI 服务商 Key，两者不能互换。

```bash
jq -n '{url:env.AI_BASE_URL,key:env.AI_API_KEY,model:env.AI_MODEL}' |
curl --fail-with-body --silent --show-error --max-time 60 \
  --request POST "$SCRAPEFUN_URL/api/settings/ai/text/test" \
  --header "Authorization: Bearer $SCRAPEFUN_TOKEN" \
  --header 'Content-Type: application/json' --data-binary @-
```

调用前在本地设置这些环境变量，不公开打印其值。成功后仍需在设置页保存并绑定连接。连接失败时 HTTP 可能为 400、403、502 或 504，应同时读取 error、code、keyStatus、solution（若有），不能把所有 502 都理解为 Key 无效。

<a id="troubleshooting"></a>

## 故障处理

| 现象或错误 | 检查方式 |
| --- | --- |
| `AI_API_KEY_MISSING` | 填写服务商 Key；文本测试不接受空值 |
| `AI_AUTH_FAILED`、`AI_ACCESS_DENIED` | 检查 Key 是否失效、权限及服务商限制 |
| `AI_MODEL_NOT_LISTED` | 检查目录中的 ID；模型别名可通过实际测试确认 |
| `AI_REQUEST_REJECTED` | 检查协议、接口路径、模型与请求兼容性 |
| `AI_BALANCE_INSUFFICIENT`、`AI_RATE_LIMITED` | 检查服务商余额、配额和频率，避免循环重试 |
| DNS、连接或超时错误 | 从 Server 所在环境检查地址与网络；这些错误不能证明 Key 无效 |
| `AI_EMPTY_RESPONSE` | 服务接受了请求，但没有可用文本；检查所选模型与返回格式 |
| 测试通过但功能不可用 | 检查保存、启用状态、功能绑定，以及该功能所需的模型能力 |

分享配置截图和日志前删除 Key、会话 token、私有服务地址及个人资料。常用设置的入口与验证方法见[设置指南](settings.md)。
