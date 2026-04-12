# ScrapeFun 自定义 Scraper 开发指南

这份文档说明 ScrapeFun 当前使用的自定义 scraper 模型。

内容包括：

- 自定义 scraper 脚本结构
- 支持的媒体类型
- 电影 / 剧集元数据结构
- 演员刮削支持
- 虚拟 scraper 媒体库创建方式

## 1. 自定义 scraper 能做什么

一个自定义 scraper 可以实现以下一种或多种能力：

- `search(query, ctx)`：搜索媒体条目
- `scrape(id, ctx)`：抓取单个条目的完整元数据
- `getVideoUrl(id, ctx)`：解析可播放地址
- `searchActor(name, ctx)`：搜索演员
- `scrapeActor(id, ctx)`：抓取演员详情

如果要支持虚拟媒体库，还可以额外实现：

- `discover(options)`：返回一个目录列表，用于自动同步虚拟媒体库

## 2. 脚本结构

自定义 scraper 脚本本质上是一段在 ScrapeFun 运行时中执行的 JavaScript / TypeScript 代码。

最小媒体 scraper 示例：

```ts
const supportedTypes = ['movie'];

async function search(query, ctx) {
  return [
    {
      uniqueId: 'example-1',
      title: `Result for ${query}`,
      source: 'ExampleSource',
      type: 'movie',
      posters: [],
      fanarts: [],
      thumbs: []
    }
  ];
}

async function scrape(id, ctx) {
  return {
    uniqueId: id,
    title: 'Example Title',
    originalTitle: 'Example Original Title',
    year: 2026,
    summary: 'Example summary.',
    rating: 8.2,
    directors: ['Director A'],
    actors: ['Actor A', 'Actor B'],
    genres: ['Drama'],
    posters: ['https://example.com/poster.jpg'],
    fanarts: ['https://example.com/backdrop.jpg'],
    thumbs: ['https://example.com/thumb.jpg'],
    source: 'ExampleSource',
    type: 'movie'
  };
}

async function getVideoUrl(id, ctx) {
  return `https://example.com/watch/${encodeURIComponent(id)}`;
}
```

## 3. 运行时可用对象

在 scraper 脚本里，当前可直接使用这些值：

- `input`：当前查询词或当前条目 id
- `type`：当前执行模式
- `axios`
- `cheerio`
- `console`
- `require(...)`
- `ctx.fetchHtml(url)`
- `ctx.fetchHtmlFlareSolverr(url)`
- `ctx.configs`
- `options`

当前执行模式包括：

- `search`
- `scrape`
- `video`
- `actor_search`
- `actor_scrape`

## 4. 声明支持的媒体类型

ScrapeFun 当前在 scraper 层识别这几种元数据类型：

- `movie`
- `tv`
- `resource`

建议在脚本顶部声明：

```ts
const supportedTypes = ['movie'];
```

或：

```ts
const supportedTypes = ['tv'];
```

或：

```ts
const supportedTypes = ['movie', 'tv'];
```

说明：

- 如果不写，系统默认按 `movie` 处理。
- 当前媒体库界面主要创建 `movie` 和 `tv` 两种媒体库。
- `resource` 是 scraper 元数据能力，不是主媒体库表单里的常规文件库类型。

## 5. 媒体库类型

在媒体库层面，ScrapeFun 当前主要使用两种类型：

- `movie`
- `tv`

通常映射关系如下：

- movie 媒体库 -> 电影向 scraper -> 电影元数据
- tv 媒体库 -> 剧集 / 动漫 / 分集内容 scraper -> TV 元数据

实际建议：

- `movie`：电影、单片、单条目内容
- `tv`：剧集、动漫、分季分集内容

如果你的 scraper 面向动漫或剧集库，通常应该在 `search` 和 `scrape` 中都返回 `type: 'tv'`。

## 6. ScrapedMetadata 结构

当前元数据结构如下：

| 字段 | 类型 | 是否必需 | 说明 |
| :--- | :--- | :--- | :--- |
| `uniqueId` | `string` | 是 | 数据源侧稳定 id |
| `title` | `string` | 是 | 展示标题 |
| `source` | `string` | 是 | scraper 来源名 |
| `type` | `'movie' \| 'tv' \| 'resource'` | 强烈建议 | 建议始终显式返回 |
| `originalTitle` | `string` | 否 | 原标题 |
| `year` | `number` | 否 | 年份 |
| `summary` | `string` | 否 | 简介 |
| `rating` | `number` | 否 | 评分 |
| `directors` | `string[]` | 否 | 导演列表 |
| `actors` | `string[]` | 否 | 演员名列表 |
| `actorsList` | `ScrapedActor[]` | 否 | 完整演员对象 |
| `genres` | `string[]` | 否 | 类型列表 |
| `posters` | `string[]` | 建议 | 海报 URL |
| `fanarts` | `string[]` | 建议 | 背景图 URL |
| `thumbs` | `string[]` | 建议 | 缩略图 URL |
| `seasons` | `ScrapedSeason[]` | 仅 TV | 季信息 |
| `episodes` | `ScrapedEpisode[]` | 仅 TV | 分集信息 |
| `studios` | `string[]` | 否 | 制作方 |
| `tags` | `string[]` | 否 | 标签 |
| `officialRating` | `string` | 否 | 分级信息 |
| `imdbId` | `string` | 否 | 外部 id |
| `tmdbId` | `string` | 否 | 外部 id |

注意：

- 即使为空，也建议返回数组形式的 `posters`、`fanarts`、`thumbs`。
- `search`、`scrape`、`getVideoUrl` 之间的 `uniqueId` 必须保持稳定。
- 对虚拟媒体库来说，系统会使用 `source + uniqueId` 作为内部身份的一部分。

## 7. TV 元数据

如果你的 scraper 支持剧集 / 动漫媒体库，建议返回 `type: 'tv'`，并按需提供 `seasons` 与 `episodes`。

示例：

```ts
const supportedTypes = ['tv'];

async function scrape(id, ctx) {
  return {
    uniqueId: id,
    title: 'Example Series',
    source: 'ExampleTV',
    type: 'tv',
    posters: ['https://example.com/poster.jpg'],
    fanarts: ['https://example.com/backdrop.jpg'],
    thumbs: [],
    seasons: [
      {
        seasonNumber: 1,
        title: 'Season 1',
        poster: 'https://example.com/season1.jpg',
        episodeCount: 12
      }
    ],
    episodes: [
      {
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Episode 1',
        summary: 'Pilot episode'
      },
      {
        seasonNumber: 1,
        episodeNumber: 2,
        title: 'Episode 2'
      }
    ]
  };
}
```

## 8. 演员支持

如果一个 scraper 实现了：

- `searchActor(...)`
- `scrapeActor(...)`

ScrapeFun 会把它识别为支持演员数据的 scraper。

演员对象可以包含这些字段：

- `name`
- `role`
- `altName`
- `aliases`
- `image`
- `images`
- `nationality`
- `bornDate`
- `intro`
- `bloodType`
- `cup`
- `measurements`
- `height`
- `debutDate`
- `constellation`
- `hobby`
- `skill`
- `genre`
- `age`
- `bust`
- `waist`
- `hips`

## 9. 播放地址解析

`getVideoUrl(id, ctx)` 可以返回：

- 直链媒体地址
- 可播放页面或 embed 地址

示例：

```ts
async function getVideoUrl(id, ctx) {
  const $ = await ctx.fetchHtml(`https://example.com/watch/${encodeURIComponent(id)}`);
  return $('video source').attr('src') || null;
}
```

## 10. FlareSolverr 支持

如果目标站点有 Cloudflare 防护，可以使用：

```ts
const $ = await ctx.fetchHtmlFlareSolverr(url);
```

这要求服务端环境中正确配置 `FLARESOLVERR_URL`。

## 11. 虚拟 scraper 媒体库

ScrapeFun 支持一种“由 scraper 直接生成目录内容”的虚拟媒体库模式。

它和普通文件/WebDAV 媒体库的区别是：

- 普通媒体库：根据真实文件路径建立元数据
- 虚拟媒体库：直接根据 scraper 返回结果建立元数据

当前虚拟媒体库的 sourceMode 为：

```text
virtual_scraper
```

创建这种媒体库时，系统会自动生成类似这样的虚拟路径：

```text
virtual://<scraper-slug>/<library-slug>/
```

## 12. 什么场景适合虚拟媒体库

适用于：

- 数据源本身像一个在线目录，不依赖本地文件
- 希望把 scraper 结果直接展示成可浏览媒体库
- 播放依赖 scraper 的 `getVideoUrl(...)`
- 希望通过 scraper 同步目录，而不是靠文件扫描

典型例子：

- 在线动漫目录
- 流媒体站点浏览器
- 资源索引 scraper

## 13. 创建虚拟媒体库

虚拟媒体库通过保存媒体库时传入这些字段创建：

- `type`：通常是 `movie` 或 `tv`
- `sourceMode`：`virtual_scraper`
- `scraper`：scraper 名称
- `virtualConfig`：可选配置对象

API 示例：

```json
{
  "name": "Virtual Anime",
  "type": "tv",
  "scraper": "ExampleCatalog",
  "sourceMode": "virtual_scraper",
  "virtualConfig": {
    "seedQuery": "2026"
  }
}
```

说明：

- 如果不传 `path`，系统会自动生成虚拟路径。
- `type` 应该和 scraper 返回的数据类型匹配。
- 对动漫/剧集类目录，一般建议使用 `type: "tv"`。

## 14. 虚拟发现 discover

如果要支持自动同步目录，建议实现：

```ts
async function discover(options) {
  return [
    {
      uniqueId: 'item-1',
      title: 'Catalog Item',
      source: 'ExampleSource',
      type: 'tv',
      posters: [],
      fanarts: [],
      thumbs: []
    }
  ];
}
```

ScrapeFun 会按以下流程处理：

1. 调用 `discover(config)`
2. 如果有 `scrape(item.uniqueId)`，再抓一次详情做补全
3. 创建或更新元数据
4. 把结果挂到虚拟媒体库下

如果没有 `discover`，但 `virtualConfig.seedQuery` 存在，系统也可以回退到 `search(seedQuery)`。

## 15. 虚拟同步与手动导入

当前可用的媒体库接口：

- `POST /libraries/:id/virtual-sync`
- `POST /libraries/:id/manual-import`

### virtual-sync

适用于实现了 `discover(...)` 的 scraper。

它会根据 scraper 返回的目录结果刷新整个虚拟媒体库。

### manual-import

适用于你已经知道具体源 id、URL 或输入文本，想手动导入指定条目。

请求示例：

```json
{
  "items": [
    "22444",
    "https://example.com/watch?id=22444",
    "example_22444.mp4"
  ]
}
```

或者：

```json
{
  "text": "22444\n22445\n22446"
}
```

这要求 scraper 的 `scrape(input, ctx)` 能把这些输入归一化为可识别条目。

## 16. 最佳实践

- 保持 `uniqueId` 稳定并且尽量使用源站原生 id。
- 始终声明 `supportedTypes`。
- 始终显式返回 `type`。
- 对 TV 媒体库，稳定返回 `type: 'tv'`。
- `scrape(...)` 尽量返回完整详情，而不是只有搜索摘要。
- 图片字段尽量返回数组，即使为空。
- `getVideoUrl(...)` 尽量保证快且稳定。
- 如果支持手动导入，尽量让 `scrape(...)` 兼容 id 或标准化 URL。
- 如果这个 scraper 要驱动虚拟媒体库，建议实现 `discover(...)`。

## 17. 常见坑

- 往 `tv` 媒体库里返回 `movie` 类型元数据
- 没声明 `supportedTypes`，结果默认按 `movie` 处理
- `uniqueId` 不稳定
- 图片字段返回成字符串而不是数组
- 站点受 Cloudflare 保护但没配置 FlareSolverr
- 想做虚拟媒体库却没有实现 `discover(...)`，也没有可用的 `seedQuery`

## 18. 快速检查清单

上线一个新 scraper 前，建议确认：

- `search(...)` 正常
- `scrape(...)` 返回稳定 `uniqueId`
- `type` 正确
- `supportedTypes` 已声明
- 图片数组格式正确
- 如果需要播放，`getVideoUrl(...)` 正常
- 如果用于虚拟媒体库，`discover(...)` 可用
