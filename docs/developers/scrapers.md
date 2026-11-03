# 刮削器开发参考

[简体中文](scrapers.md) · [English](scrapers.en.md)

2026-11-03

<a id="start"></a>

## 开始编写

本规范按当前标记为 0.5.1 的开发版本核对，已发布版本的能力可能不同，供用户编写自定义扩展。推荐导出继承 `BaseScraper` 的 TypeScript 类，将其保存为独立的 `.scraper.ts` 文件，在刮削器编辑器中测试后保存。示例是专门编写的扩展模板，不包含产品实现源码。

[电影来源模板](https://github.com/HaoweiLi97/ScrapeFun/blob/main/docs/developers/examples/generic-metadata.scraper.ts)提供搜索、分页、详情和错误处理；[漫画来源模板](https://github.com/HaoweiLi97/ScrapeFun/blob/main/docs/developers/examples/generic-comic.scraper.ts)增加章节与图片页；[清洗模板](https://github.com/HaoweiLi97/ScrapeFun/blob/main/docs/developers/examples/filename-cleaning.js)用于文件名处理。模板使用虚构的 `.example` API，修改域名、请求和字段映射后才能连接真实来源。仅使用获准访问的数据，遵守来源的使用条款和请求频率限制。

```typescript
import { BaseScraper } from './base.scraper';
import type { ScrapedMetadata, ScraperMediaType } from './types';
import { networkAxios } from '../utils/network-proxy';

export class ExampleSource extends BaseScraper {
  public supportedTypes: ScraperMediaType[] = ['movie'];
  constructor() { super('Example Source'); }

  async search(query: string): Promise<ScrapedMetadata[]> {
    return [];
  }

  async scrape(id: string): Promise<ScrapedMetadata | null> {
    return null;
  }
}
```

上述空实现仅展示结构。真实来源应执行查询并映射结果。导入名是编辑器提供的扩展接口，无需下载应用源码或修改产品内部文件。普通 Node.js 项目不能直接解析这些导入。

<a id="capabilities"></a>

## 名称与能力声明

| 属性 | 规则 |
| --- | --- |
| `name` | 稳定且唯一的来源名称，由 `super(name)` 设置；保存后不要改名 |
| `supportedTypes` | 基础来源选择一个主要类型：`movie`、`tv`、`comic`、`book`；`resource` 为兼容旧来源保留 |
| `supportsMetadataLanguagePreferences` | 默认 false；实际消费元数据语言偏好后才设为 true |
| `supportsImageLanguagePreferences` | 默认 false；实际消费图片语言偏好后才设为 true |
| `supportsEmbeddedActors` | scrape 确实提供内嵌人物资料时才设为 true |
| `importInputs` | 手动导入接受的输入类型，默认仅 ID；每项为 `{kind,example,urlPrefix?}`，kind 为 `id`、`url`、`filename` 或 `query` |

声明支持 URL 不会自动完成 URL 到作品 ID 的解析，必须在来源中实现。搜索返回的 `uniqueId` 必须能原样传给 scrape；建议使用 `example:123` 这样的稳定 ID，不要使用临时签名地址、页码或数组下标。

HTTP 测试和保存可以传入 `capabilityConfig`，声明须与代码一致：

```json
{"version":1,"supportedTypes":["movie"],"supportsMetadataLanguagePreferences":false,"supportsImageLanguagePreferences":false}
```

<a id="methods"></a>

## 方法总表

除明确标注同步的方法外，下表均返回 Promise。query、id、chapterId、name、playUrl 均为 string，ids 为 string[]。options 为可选的 `Record<string,any>` 对象；只读取自己支持的选项，不要假定所有 HTTP 入口都会透传它。

| 方法签名 | 返回值与用途 |
| --- | --- |
| `search(query, options?)` | `ScrapedMetadata[]` 或分页对象；按关键字搜索候选，BaseScraper 必须实现 |
| `scrape(id, options?)` | `ScrapedMetadata` 或 null；按稳定 ID 获取详情，BaseScraper 必须实现 |
| `getComicVolumes(id, options?)` | `ScrapedSeason[]`；提供本地漫画卷册匹配资料，不是阅读章节或图片列表 |
| `getComicChapters(id)` | `ScrapedComicChapter[]`；返回漫画章节目录 |
| `getComicPages(id, chapterId)` | `ScrapedComicPage[]`；返回指定章节的有序图片页 |
| `getImages(id, options?)` | `ScrapedArtwork[]`；作品可选海报、背景、缩略图和标题 Logo |
| `getMatchRuntimes(ids, options?)` | `Record<string,number>`；批量提供作品时长，单位分钟；未知 ID 省略 |
| `discover(options?)` | 作品数组或 `{items,complete,hasMore?}`；为虚拟媒体库发现作品 |
| `searchActor(name, options?)` | `ScrapedActor[]`；搜索人物候选 |
| `scrapeActor(id, options?)` | `ScrapedActor` 或 null；人物详情 |
| `getVideoUrl(id)` | string 或 null；解析可用视频地址，不返回播放页 HTML 地址 |
| `getPlaybackHeaders(id, playUrl?)` | `Record<string,string>`；访问资源需要的请求头 |
| `supportsSearch()` | 同步 boolean；声明当前是否可搜索 |
| `supportsScrape()` | 同步 boolean；声明当前是否可获取作品详情 |
| `getConnectivityUrls()` | 同步 `string[]`；提供少量轻量来源检查地址 |
| `checkConnectivity()` | void、boolean 或 `{ok,message?,endpoint?}`；自定义可达性检查 |

未实现的可选方法直接省略，不要用假结果声明能力。仅人物来源可以不继承 BaseScraper，自行导出包含 name、人物方法及 `supportedTypes:[]` 的类。不要因为漫画来源能返回封面，就声称它具有章节阅读能力。

<a id="search"></a>

## 搜索、分页与语言

query 为待搜索文字。options 常用 `type`、`page`、`pageSize`、`metadataLanguagePreferences`、`imageLanguagePreferences`；页码从 1 开始。语言偏好为按优先顺序排列的字符串数组，应由来源按实际支持能力处理和回退。

```json
{"items":[],"page":1,"pageSize":20,"hasMore":false,"total":0}
```

分页对象中的 items、page、pageSize、hasMore 必须明确；total 可省略。数组适合无分页来源。不要用“本页非空”代替“还有下一页”，也不要在每个请求中无限抓取所有页面。

scrape 找不到作品时返回 null；search 无匹配时返回空数组。网络失败、认证失败、解析异常应抛出错误，不能伪装成成功的空结果。上游 404 可映射为 null；限流和服务故障应保留为失败。

<a id="metadata"></a>

## 作品数据

| 字段 | 类型与含义 |
| --- | --- |
| `uniqueId`、`title`、`source` | 必填非空 string；source 与来源名称一致 |
| `posters`、`fanarts`、`thumbs` | 必填 `string[]`，无图片时返回空数组；分别为海报、背景、缩略图 |
| `type` | 建议明确填写声明的媒体类型 |
| `originalTitle`、`author`、`summary` | 可选 string：原名、作者、简介 |
| `aliases`、`alternateTitles` | 可选 `string[]`，来源提供的别名；新来源优先 aliases |
| `year`、`rating` | 可选 number；年份和评分，不用空字符串代替缺失数字 |
| `genres`、`tags` | 可选 `string[]`，分类与标签 |
| `actors`、`directors`、`studios` | 可选名称数组 |
| `actorsList`、`directorsList`、`studiosList` | 可选结构化人物、导演和制作方数组 |
| `seasons`、`episodes` | 可选季/卷与剧集资料，见下文 |
| `artworks`、`logos`、`thumbnail` | 可选图片目录、Logo URL 数组、单张缩略图 URL |
| `keywords` | 可选 `{name,tmdbId?}[]` |
| `trailers` | 可选 `{url,name,site,type,language?,official?}[]`；site 为 YouTube/Vimeo，type 为 Trailer/Teaser |
| `serialStartDate`、`serialEndDate`、`airStatus`、`officialRating` | 可选 string：连载起止、状态、内容分级 |
| `imdbId`、`tmdbId` | 可选 string，只有确认准确时填写 |

不要将 Server 数据库 ID 填入来源 uniqueId，也不要返回自定义内部控制字段。图片使用有效的绝对 HTTP(S) 地址；将上游相对地址转换为绝对地址。

```json
{"uniqueId":"example:123","title":"Example work","source":"Example Source","type":"movie","year":2026,"posters":[],"fanarts":[],"thumbs":[]}
```

季或卷记录的必填字段为 `seasonNumber:number`；可选 title、summary、poster、airDate、episodeCount、rating。剧集必填 `seasonNumber:number` 与 `episodeNumber:number`；可选 title、summary、rating、airDate、image、tmdbSeasonNumber、tmdbEpisodeNumber。卷册匹配使用 getComicVolumes；虚拟漫画阅读使用下一节的章节方法。

<a id="comics"></a>

## 漫画章节与图片页

getComicChapters 返回阅读顺序排列的章节数组，每章必填 id、title，可选 kind（chapter/volume/extra）、group（含 id、title）、pageCount、revision。章节 ID 在同一作品内保持唯一和稳定，非空且不超过 512 个 UTF-16 码元；单次目录为 1–10000 项。

getComicPages 的两个参数分别是作品 ID 和章节 ID，返回阅读顺序排列的图片页数组。每页必填 id、url，可选 name、headers、revision；页 ID 在章节内唯一且稳定，单次为 1–2000 页。url 是可访问的 HTTP(S) 图片资源，不是阅读网页。

```json
{
  "chapters":[{"id":"chapter-1","title":"Chapter 1","kind":"chapter","pageCount":2}],
  "pages":[
    {"id":"page-1","url":"https://images.example/123/1/1.jpg"},
    {"id":"page-2","url":"https://images.example/123/1/2.jpg"}
  ]
}
```

上例展示两种返回数组，方法应分别返回 chapters 或 pages，不返回外层演示对象。headers 仅在必要时提供 Referer、User-Agent、Cookie、Authorization、Accept、Origin 等受支持的头；不要将私密凭据发送到无关域名，或把带凭据的结果公开。revision 可用于表达上游内容修订；不要用短期资源地址作为章节或页 ID。

<a id="people-images"></a>

## 人物与图片

ScrapedActor 必填 `name:string`；常用可选字段包括 id、url、altName、aliases、image、images、intro、role、gender、nationality、placeOfBirth、bornDate、deathDate、homepage、knownForDepartment、tmdbId、imdbId。导演条目使用相同结构。人物来源 ID 与 Server 人物 ID 不同；人物搜索与详情返回的是来源 ID。

ScrapedStudio 必填 name，可选 id、logo、originCountry。演员照片、作品标题 Logo 与制作方 Logo 用各自对应字段，避免混用。

ScrapedArtwork 必填 type 和 url；type 为 poster、backdrop、thumbnail、logo。可选 previewUrl、language、width、height、source。language 未知时省略；明确无语言的图使用字符串 `"null"`，不是 JSON null。开启语言能力后，getImages 应处理 options.imageLanguagePreferences。

<a id="discovery-playback"></a>

## 发现与资源地址

discover 用于虚拟库发现，不等于搜索第一页。仅在确实拿到整个上游快照时返回 `complete:true`。分页、失败或不完整抓取应返回 complete:false；不要吞掉网络异常后报告完整空快照。自动清理旧映射可能依赖完整快照，首次接入应先验证结果再启用相关清理。

getVideoUrl 解析资源地址，getPlaybackHeaders 可补充该地址需要的请求头。找不到视频可返回 null；网络或解析失败应抛错。不要让模板绕过上游访问控制。资源是否能被客户端使用还取决于有效期、服务配置和客户端能力，返回一个 URL 不等于已完成播放验收。

<a id="helpers"></a>

## 网络辅助与旧式函数

类来源可通过 `networkAxios.get/post` 发请求，并明确设置请求超时；`await this.fetchHtml(url)` 返回 Cheerio 查询对象，用于静态 HTML。`await this.getCustomConfig(key)` 读取用户配置，返回 string 或 undefined；`await this.getFlareSolverrUrl()` 获取用户配置的可选服务地址。配置值和请求头不要写进日志。

本规范不承诺浏览器自动化、页面 JavaScript 执行或交互动作支持；不要因为辅助方法名称带 browser 就依赖这些能力。

旧式函数来源仍支持下表。新来源优先使用类，以获得漫画、图片、发现和请求头等完整扩展能力。

| 函数 | 用途 |
| --- | --- |
| `async function search(query, ctx)` | 搜索 |
| `async function scrape(id, ctx)` | 详情 |
| `async function getVideoUrl(id, ctx)` | 视频地址 |
| `async function searchActor(name, ctx)` | 人物搜索 |
| `async function scrapeActor(id, ctx)` | 人物详情 |

ctx 提供 options、configs、axios、cheerio、fetchHtml、fetchHtmlFlareSolverr。不要将类可选方法直接改名为函数后假定旧式包装会调用它。独立文件名清洗规则使用同步 `function clean(input)`，必须返回 string，不做网络请求或返回 Promise。

<a id="validation"></a>

## 验收与接入

先测试正常搜索、无结果、第二页、稳定 ID 详情、上游 404、超时和限流。漫画还需验证多个章节及首尾图片顺序；人物和图片方法分别测试。确认语言偏好确实生效，错误不被吞掉，日志中没有凭据。

然后按[刮削器测试与管理](scraper-api.md)保存并核对注册结果，在小型测试库验证扫描或导入后再用于真实资料。只运行自己信任的扩展代码。不要让 AI 在没有明确授权的情况下覆盖现有来源、删除数据或启用快照清理。
