# ScrapeFun Custom Scraper Development Guide

This guide documents the current custom scraper model used by ScrapeFun.

It covers:

- custom scraper script structure
- supported media types
- movie / TV metadata shape
- actor scraping support
- virtual scraper library creation

## 1. What a custom scraper can do

A custom scraper can provide one or more of these capabilities:

- `search(query, ctx)`: search media items
- `scrape(id, ctx)`: fetch full metadata for one item
- `getVideoUrl(id, ctx)`: resolve a playable URL
- `searchActor(name, ctx)`: search actors
- `scrapeActor(id, ctx)`: fetch full actor details

For virtual libraries, a scraper can additionally provide:

- `discover(options)`: return a catalog of items for automatic virtual-library sync

## 2. Script structure

Custom scraper scripts are plain JavaScript or TypeScript snippets executed in the ScrapeFun runtime.

Minimal media scraper example:

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

## 3. Runtime helpers

Inside scraper scripts, these values are available:

- `input`: current query or item id
- `type`: current execution mode
- `axios`
- `cheerio`
- `console`
- `require(...)`
- `ctx.fetchHtml(url)`
- `ctx.fetchHtmlFlareSolverr(url)`
- `ctx.configs`
- `options`

Current execution modes include:

- `search`
- `scrape`
- `video`
- `actor_search`
- `actor_scrape`

## 4. Declaring supported media types

ScrapeFun currently recognizes these scraper-side metadata types:

- `movie`
- `tv`
- `resource`

Declare scraper support near the top of your script:

```ts
const supportedTypes = ['movie'];
```

or:

```ts
const supportedTypes = ['tv'];
```

or:

```ts
const supportedTypes = ['movie', 'tv'];
```

Notes:

- If omitted, ScrapeFun treats the scraper as `movie` by default.
- The current library UI mainly creates media libraries as `movie` or `tv`.
- `resource` is scraper metadata capability, not the normal filesystem media-library type used in the main library form.

## 5. Media library types

At the library level, ScrapeFun currently uses two primary media-library types:

- `movie`
- `tv`

Typical mapping:

- movie library -> movie-oriented scraper, movie metadata
- tv library -> series / anime / episode-oriented scraper, TV metadata

In practice:

- use `movie` for films, AV movies, single-title content
- use `tv` for series, anime seasons, episodic content

For TV-oriented libraries, your scraper should usually return `type: 'tv'` from both `search` and `scrape`.

## 6. ScrapedMetadata shape

Current metadata shape:

| Property | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `uniqueId` | `string` | Yes | Stable source-side id |
| `title` | `string` | Yes | Display title |
| `source` | `string` | Yes | Scraper source name |
| `type` | `'movie' \| 'tv' \| 'resource'` | Recommended | Strongly recommended |
| `originalTitle` | `string` | No | Original title |
| `year` | `number` | No | Release year |
| `summary` | `string` | No | Description |
| `rating` | `number` | No | Numeric rating |
| `directors` | `string[]` | No | Directors |
| `actors` | `string[]` | No | Actor names |
| `actorsList` | `ScrapedActor[]` | No | Rich actor objects |
| `genres` | `string[]` | No | Genres |
| `posters` | `string[]` | Recommended | Poster URLs |
| `fanarts` | `string[]` | Recommended | Backdrop URLs |
| `thumbs` | `string[]` | Recommended | Thumbnail URLs |
| `seasons` | `ScrapedSeason[]` | TV only | Optional season metadata |
| `episodes` | `ScrapedEpisode[]` | TV only | Optional episode metadata |
| `studios` | `string[]` | No | Studio names |
| `tags` | `string[]` | No | Tags |
| `officialRating` | `string` | No | Rating certification |
| `imdbId` | `string` | No | External id |
| `tmdbId` | `string` | No | External id |

Important:

- Always return arrays for `posters`, `fanarts`, and `thumbs`, even if empty.
- `uniqueId` must remain stable between `search`, `scrape`, and `getVideoUrl`.
- For virtual libraries, ScrapeFun uses `source + uniqueId` to build internal metadata identity.

## 7. TV metadata

If your scraper supports TV/anime libraries, return `type: 'tv'` and optionally provide `seasons` and `episodes`.

Example:

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

## 8. Actor support

If a scraper includes:

- `searchActor(...)`
- `scrapeActor(...)`

ScrapeFun will treat it as actor-capable.

Actor object shape can include:

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

## 9. Video playback

`getVideoUrl(id, ctx)` should return either:

- a direct media URL
- a resolved watch page / embed URL

Example:

```ts
async function getVideoUrl(id, ctx) {
  const $ = await ctx.fetchHtml(`https://example.com/watch/${encodeURIComponent(id)}`);
  return $('video source').attr('src') || null;
}
```

## 10. FlareSolverr support

For Cloudflare-protected sites, use:

```ts
const $ = await ctx.fetchHtmlFlareSolverr(url);
```

This requires `FLARESOLVERR_URL` to be configured in your server environment.

## 11. Virtual scraper libraries

ScrapeFun supports a virtual library mode for scraper-driven catalogs.

This is different from a normal filesystem/WebDAV library:

- normal library: metadata is built from files under real paths
- virtual library: metadata is created directly from scraper results

Current virtual-library source mode:

```text
virtual_scraper
```

When a library is created in this mode, ScrapeFun stores a virtual path similar to:

```text
virtual://<scraper-slug>/<library-slug>/
```

## 12. When to use a virtual library

Use a virtual scraper library when:

- the source is catalog-like and does not depend on local files
- you want scraper results to appear as a browseable library
- playback comes from scraper-side `getVideoUrl(...)`
- you want “sync from scraper” behavior instead of filesystem scanning

Typical examples:

- online animation catalog
- streaming-site browser
- resource index scraper

## 13. Creating a virtual library

Virtual libraries are created through the library save flow with:

- `type`: usually `movie` or `tv`
- `sourceMode`: `virtual_scraper`
- `scraper`: scraper name
- `virtualConfig`: optional config object

API shape:

```json
{
  "name": "Virtual Anime",
  "type": "tv",
  "scraper": "hanime1",
  "sourceMode": "virtual_scraper",
  "virtualConfig": {
    "seedQuery": "2026"
  }
}
```

Notes:

- If `path` is omitted, ScrapeFun auto-generates a virtual path.
- `type` should match the kind of metadata your scraper returns.
- For anime/series-style catalogs, prefer `type: "tv"`.

## 14. Virtual discovery

For automatic catalog sync, implement:

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

ScrapeFun will:

1. call `discover(config)`
2. optionally call `scrape(item.uniqueId)` for detail enrichment
3. create or update metadata entries
4. map them into the virtual library

If `discover` is not available but `virtualConfig.seedQuery` exists, ScrapeFun can fall back to `search(seedQuery)`.

## 15. Virtual sync and manual import

Current library endpoints:

- `POST /libraries/:id/virtual-sync`
- `POST /libraries/:id/manual-import`

### Virtual sync

Use this when your scraper supports `discover(...)`.

It refreshes the library catalog from scraper-discovered items.

### Manual import

Use this when you already know source ids or URLs and want to import specific entries.

Request shape:

```json
{
  "items": [
    "22444",
    "https://hanime1.me/watch?v=22444",
    "hanime1_22444.mp4"
  ]
}
```

or:

```json
{
  "text": "22444\n22445\n22446"
}
```

The scraper's `scrape(input, ctx)` must be able to normalize these inputs into a valid source item.

## 16. Best practices

- Keep `uniqueId` stable and source-native.
- Always declare `supportedTypes`.
- Return `type` explicitly in metadata.
- For TV libraries, return `type: 'tv'` consistently.
- Prefer full `scrape(...)` detail over minimal search-only results.
- Return empty arrays instead of `undefined` for image lists where possible.
- Make `getVideoUrl(...)` fast and deterministic.
- Design `scrape(...)` so manual import can accept ids or normalized URLs when useful.
- If building a virtual library scraper, implement `discover(...)`.

## 17. Common pitfalls

- Returning `movie` metadata into a `tv` library
- Omitting `supportedTypes` and accidentally defaulting to `movie`
- Returning unstable `uniqueId` values
- Returning scalar image fields instead of arrays
- Forgetting to configure FlareSolverr for protected sites
- Building a virtual library scraper without `discover(...)` or without a useful `seedQuery`

## 18. Quick checklist

Before shipping a new scraper, verify:

- `search(...)` works
- `scrape(...)` returns stable `uniqueId`
- `type` is correct
- `supportedTypes` is declared
- image arrays are valid
- `getVideoUrl(...)` works if playback is needed
- `discover(...)` works if the scraper will back a virtual library
