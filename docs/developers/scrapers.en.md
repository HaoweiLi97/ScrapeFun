# Scraper development reference

[简体中文](scrapers.md) · [English](scrapers.en.md)

2026-11-03

<a id="start"></a>

## Start authoring

This user extension contract was checked against the current development version marked 0.5.1; released builds may differ. Export a TypeScript class extending `BaseScraper`, save it as a separate `.scraper.ts` file, and test it in the scraper editor before saving. Examples are purpose-written extension templates and contain no product implementation source.

The [movie source template](https://github.com/HaoweiLi97/ScrapeFun/blob/main/docs/developers/examples/generic-metadata.scraper.ts) covers search, pagination, details, and errors. The [comic source template](https://github.com/HaoweiLi97/ScrapeFun/blob/main/docs/developers/examples/generic-comic.scraper.ts) adds chapters and image pages. The [cleaning template](https://github.com/HaoweiLi97/ScrapeFun/blob/main/docs/developers/examples/filename-cleaning.js) handles filenames. Templates target synthetic `.example` APIs; adapt endpoints, requests, and field mappings before contacting a real provider. Access only authorized data and respect provider terms and rate limits.

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

The empty implementation illustrates structure only. Real sources must query the provider and map results. Import identifiers are editor-provided extension interfaces; you do not need application source or changes to internal product files. Ordinary Node.js projects cannot resolve these imports directly.

<a id="capabilities"></a>

## Identity and capabilities

| Property | Rules |
| --- | --- |
| `name` | Stable, unique source name set by `super(name)`; do not rename after saving |
| `supportedTypes` | Choose one primary type for a base source: `movie`, `tv`, `comic`, or `book`; `resource` is retained for legacy compatibility |
| `supportsMetadataLanguagePreferences` | Default false; enable only when metadata language preferences are actually consumed |
| `supportsImageLanguagePreferences` | Default false; enable only when image language preferences are actually consumed |
| `supportsEmbeddedActors` | Enable only when scrape supplies embedded person records |
| `importInputs` | Accepted manual-import inputs; defaults to ID only; entries are `{kind,example,urlPrefix?}`, where kind is `id`, `url`, `filename`, or `query` |

Declaring URL input does not implement URL-to-ID parsing; implement it yourself. A search result's `uniqueId` must be accepted unchanged by scrape. Prefer a stable namespaced ID such as `example:123`, never a temporary signed URL, page number, or array index.

HTTP testing and saving can include `capabilityConfig`, consistent with the code:

```json
{"version":1,"supportedTypes":["movie"],"supportsMetadataLanguagePreferences":false,"supportsImageLanguagePreferences":false}
```

<a id="methods"></a>

## Method reference

Methods return Promises unless explicitly marked synchronous. query, id, chapterId, name, and playUrl are strings; ids is string[]. options is an optional `Record<string,any>` object; read only supported options and do not assume every HTTP endpoint forwards it.

| Signature | Return value and purpose |
| --- | --- |
| `search(query, options?)` | `ScrapedMetadata[]` or a page object; keyword candidates; required by BaseScraper |
| `scrape(id, options?)` | `ScrapedMetadata` or null; details by stable ID; required by BaseScraper |
| `getComicVolumes(id, options?)` | `ScrapedSeason[]`; volume metadata for matching local comics, not reader chapters or images |
| `getComicChapters(id)` | `ScrapedComicChapter[]`; comic chapter directory |
| `getComicPages(id, chapterId)` | `ScrapedComicPage[]`; ordered image pages for a chapter |
| `getImages(id, options?)` | `ScrapedArtwork[]`; available posters, backdrops, thumbnails, and title logos |
| `getMatchRuntimes(ids, options?)` | `Record<string,number>`; batched runtimes in minutes; omit unknown IDs |
| `discover(options?)` | Media array or `{items,complete,hasMore?}`; discover works for virtual libraries |
| `searchActor(name, options?)` | `ScrapedActor[]`; person candidates |
| `scrapeActor(id, options?)` | `ScrapedActor` or null; person details |
| `getVideoUrl(id)` | string or null; usable video address, not a watch-page HTML URL |
| `getPlaybackHeaders(id, playUrl?)` | `Record<string,string>`; headers needed to access the resource |
| `supportsSearch()` | Synchronous boolean; whether search is currently available |
| `supportsScrape()` | Synchronous boolean; whether media details are currently available |
| `getConnectivityUrls()` | Synchronous `string[]`; a few lightweight provider check URLs |
| `checkConnectivity()` | void, boolean, or `{ok,message?,endpoint?}`; custom reachability check |

Omit unimplemented optional methods rather than declaring capabilities with fake results. A person-only source can export a class without extending BaseScraper, with name, person methods, and `supportedTypes:[]`. Cover images alone do not make a comic source readable.

<a id="search"></a>

## Search, pagination, and languages

query is the search text. Common options are `type`, `page`, `pageSize`, `metadataLanguagePreferences`, and `imageLanguagePreferences`. Pages start at 1. Language preferences are ordered string arrays; handle supported languages and fallbacks explicitly.

```json
{"items":[],"page":1,"pageSize":20,"hasMore":false,"total":0}
```

A page object must include items, page, pageSize, and hasMore; total is optional. Arrays suit sources without pagination. A nonempty page does not prove there is another page. Avoid fetching an unlimited number of pages per request.

Return null when scrape cannot find a work and an empty array when search has no matches. Throw errors for network, authentication, and parsing failures instead of disguising them as successful empty results. A provider 404 may map to null; rate limits and service failures remain errors.

<a id="metadata"></a>

## Media data

| Field | Type and meaning |
| --- | --- |
| `uniqueId`, `title`, `source` | Required nonempty strings; source matches the source name |
| `posters`, `fanarts`, `thumbs` | Required `string[]`; empty arrays when absent; posters, backdrops, and thumbnails |
| `type` | Explicitly set the declared media type where possible |
| `originalTitle`, `author`, `summary` | Optional strings |
| `aliases`, `alternateTitles` | Optional `string[]` of provider aliases; prefer aliases for new sources |
| `year`, `rating` | Optional numbers; do not replace missing numbers with empty strings |
| `genres`, `tags` | Optional `string[]` |
| `actors`, `directors`, `studios` | Optional name arrays |
| `actorsList`, `directorsList`, `studiosList` | Optional structured people, directors, and studios |
| `seasons`, `episodes` | Optional season/volume and episode records, described below |
| `artworks`, `logos`, `thumbnail` | Optional artwork directory, logo URL array, and single thumbnail URL |
| `keywords` | Optional `{name,tmdbId?}[]` |
| `trailers` | Optional `{url,name,site,type,language?,official?}[]`; site is YouTube/Vimeo, type is Trailer/Teaser |
| `serialStartDate`, `serialEndDate`, `airStatus`, `officialRating` | Optional strings for serialization dates, status, and content rating |
| `imdbId`, `tmdbId` | Optional strings; include only when verified |

Do not put Server database IDs into source uniqueId or return custom internal control fields. Use valid absolute HTTP(S) artwork addresses and resolve provider-relative URLs.

```json
{"uniqueId":"example:123","title":"Example work","source":"Example Source","type":"movie","year":2026,"posters":[],"fanarts":[],"thumbs":[]}
```

Season or volume records require `seasonNumber:number`; optional fields are title, summary, poster, airDate, episodeCount, and rating. Episodes require `seasonNumber:number` and `episodeNumber:number`; optional fields are title, summary, rating, airDate, image, tmdbSeasonNumber, and tmdbEpisodeNumber. Use getComicVolumes for volume matching and the chapter methods below for virtual comic reading.

<a id="comics"></a>

## Comic chapters and image pages

getComicChapters returns chapters in reading order. Each requires id and title; optional fields are kind (chapter/volume/extra), group (id and title), pageCount, and revision. Chapter IDs must be stable and unique within the work, nonempty, and at most 512 UTF-16 code units. A directory contains 1–10000 items.

getComicPages receives the work ID and chapter ID and returns images in reading order. Each page requires id and url; optional fields are name, headers, and revision. Page IDs are stable and unique within the chapter. Return 1–2000 pages. url must address an accessible HTTP(S) image, not a reader webpage.

```json
{
  "chapters":[{"id":"chapter-1","title":"Chapter 1","kind":"chapter","pageCount":2}],
  "pages":[
    {"id":"page-1","url":"https://images.example/123/1/1.jpg"},
    {"id":"page-2","url":"https://images.example/123/1/2.jpg"}
  ]
}
```

This example shows two arrays; each method returns its corresponding chapters or pages array, not the outer demonstration object. Include headers only when needed, using supported fields such as Referer, User-Agent, Cookie, Authorization, Accept, and Origin. Never forward private credentials to unrelated domains or publish authenticated results. revision can identify provider content updates; temporary URLs must not become chapter or page IDs.

<a id="people-images"></a>

## People and artwork

ScrapedActor requires `name:string`. Common optional fields are id, url, altName, aliases, image, images, intro, role, gender, nationality, placeOfBirth, bornDate, deathDate, homepage, knownForDepartment, tmdbId, and imdbId. Directors use the same structure. Provider person IDs differ from Server person IDs; person search and detail methods return provider IDs.

ScrapedStudio requires name; id, logo, and originCountry are optional. Use the appropriate separate fields for actor photos, media title logos, and studio logos.

ScrapedArtwork requires type and url. type is poster, backdrop, thumbnail, or logo. Optional fields are previewUrl, language, width, height, and source. Omit unknown language; use the string `"null"`, not JSON null, for explicitly language-neutral artwork. After declaring language support, getImages must consume options.imageLanguagePreferences.

<a id="discovery-playback"></a>

## Discovery and resource addresses

discover supplies a virtual library with works; it is not just the first search page. Return `complete:true` only for a complete upstream snapshot. Paginated or incomplete retrieval must report complete:false. Never swallow network failures and report a complete empty snapshot. Automatic removal of old mappings may depend on snapshot completeness; verify results before enabling related cleanup.

getVideoUrl resolves a resource address; getPlaybackHeaders supplies necessary headers. Return null when no video exists and throw on network or parsing failures. Templates must not bypass provider access controls. Client usability also depends on URL expiration, service configuration, and client support; returning a URL is not proof of successful playback.

<a id="helpers"></a>

## Network helpers and legacy functions

Class sources can make requests through `networkAxios.get/post`, with explicit request timeouts. `await this.fetchHtml(url)` returns a Cheerio query object for static HTML. `await this.getCustomConfig(key)` returns a user setting as string or undefined. `await this.getFlareSolverrUrl()` returns the configured optional service address. Keep settings and sensitive headers out of logs.

This contract does not promise browser automation, page JavaScript execution, or interactive actions. A helper containing browser in its name is not evidence of these capabilities.

Legacy function sources still support the methods below. Prefer classes for new sources to access comic, artwork, discovery, and request-header extension methods.

| Function | Purpose |
| --- | --- |
| `async function search(query, ctx)` | Search |
| `async function scrape(id, ctx)` | Details |
| `async function getVideoUrl(id, ctx)` | Video address |
| `async function searchActor(name, ctx)` | Person search |
| `async function scrapeActor(id, ctx)` | Person details |

ctx provides options, configs, axios, cheerio, fetchHtml, and fetchHtmlFlareSolverr. Renaming a class optional method into a top-level function does not make the legacy wrapper call it. Separate filename-cleaning rules use synchronous `function clean(input)`, returning a string without network requests or Promises.

<a id="validation"></a>

## Validation and integration

Test normal search, no matches, a second page, stable-ID details, provider 404, timeouts, and rate limits. For comics, verify several chapters and first/last image order. Test person and artwork methods separately. Confirm language preferences take effect, errors are preserved, and logs contain no credentials.

Then follow [scraper testing and management](scraper-api.en.md), save, and verify registration. Validate scanning or imports in a small test library before touching real data. Run only trusted extension code. AI must not overwrite sources, delete data, or enable snapshot cleanup without explicit authorization.
