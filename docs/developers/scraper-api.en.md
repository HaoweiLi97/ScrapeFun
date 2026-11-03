# Scraper testing and management API

[简体中文](scraper-api.md) · [English](scraper-api.en.md)

2026-11-03

<a id="entry-points"></a>

## Choose an entry point

Checked against the current development version marked 0.5.1; released builds may differ. Read [API authentication](api.en.md#authentication) and the [scraper authoring contract](scrapers.en.md) first. Paths are relative to your Server. Signed-in users can list active sources, search, and invoke them directly. Code testing, saving and management writes, previews, and artwork directories require an administrator. Data access permissions still apply.

| Goal | Endpoint | Behavior |
| --- | --- | --- |
| List active sources | `GET /api/scrape/scrapers` | Read available sources and capabilities |
| Temporarily test code | `POST /api/config/test` | Does not save sources or commit media; code itself can contact external services |
| Direct search or details | `POST /api/scrape/trigger` | Does not commit media |
| Search matching candidates | `GET /api/scrape/search` | Does not create media records |
| Preview provider details | `POST /api/scrape/preview` | Does not commit media |
| Save a source | `POST /api/config/system` | Persist the source and attempt registration |

Run only trusted extension code. A successful temporary test does not mean the source was saved or a library was updated.

<a id="test-request"></a>

## Workbench requests

`POST /api/config/test` accepts these fields, not additional management-save fields.

| Field | Rules |
| --- | --- |
| `code` | Required nonempty extension-code string, up to 512 KiB |
| `input` | Required nonempty query, work ID, or person ID string, up to 8192 characters |
| `type` | Required action from the table below |
| `name` | Optional source name, at most 120 characters, consistent with the code |
| `capabilityConfig` | Optional capability declaration matching the code; see authoring reference |
| `category` | Optional declared media type, consistent with options.type |
| `options` | Optional JSON object passed according to the method |
| `cleaning` | Default `{mode:"none"}`; search alone accepts `{mode:"inline",code:"..."}` |
| `timeoutMs` | Default 30000, range 100–60000 milliseconds |

| type | input and options |
| --- | --- |
| `search` | Query input; options may include page, pageSize, and declared language preferences |
| `scrape` | Provider work ID |
| `discover` | Still requires nonempty input, such as `discover`; options depend on the source |
| `video` | Work ID; no category or nonempty options |
| `playback` | Work ID; checks video address and headers together; no category or nonempty options |
| `comic_chapters` | Work ID |
| `comic_pages` | Work ID with required options.chapterId |
| `comic_image` | Same, plus zero-based options.pageIndex |
| `actor_search` | Person name |
| `actor_scrape` | Provider person ID |

There is no images test action; validate getImages through a registered source. Bound cleaning rules are not automatically applied to temporary tests; provide inline code when needed. This request does not accept cleaningScriptId.

Read the local extension file into JSON instead of manually escaping it. This command tests temporarily without saving:

```bash
jq -n --rawfile code ./generic-metadata.scraper.ts \
  '{code:$code,name:"Generic Metadata Source",type:"search",input:"Example work",category:"movie",options:{page:1,pageSize:20}}' |
curl --fail-with-body --silent --show-error --max-time 45 \
  --request POST "$SCRAPEFUN_URL/api/config/test" \
  --header "Authorization: Bearer $SCRAPEFUN_TOKEN" \
  --header 'Content-Type: application/json' --data-binary @-
```

Success returns result, logs, executionId, durationMs, phase, and truncation; some actions also include applied. result depends on the action. truncation.logs or truncation.result being true means incomplete output. On failure inspect HTTP status, error, code, and logs. Redact logs before sharing.

<a id="registered"></a>

## Invoke registered sources

`GET /api/scrape/scrapers?type=movie` returns active sources, commonly including name, supportedTypes, methodCapabilities, hasImageSupport, hasActorSupport, and language-preference flags. Use the canonical name rather than the filename, and call supported capabilities only.

`POST /api/scrape/trigger` accepts this direct search request:

```json
{"scraper":"Generic Metadata Source","query":"Example work"}
```

For details use a provider ID:

```json
{"scraper":"Generic Metadata Source","id":"generic-metadata:123"}
```

Returns `{success:true,data:...}`; id takes precedence over query. Arbitrary options, page/pageSize, and language preferences are not forwarded, and search does not preserve provider page envelopes. Use the workbench to validate options and pagination.

| Endpoint | Input and response |
| --- | --- |
| `GET /api/scrape/search` | Query q, scraper, type; matching candidate array. Choose source and type explicitly and URL-encode parameters; not a pagination pass-through |
| `POST /api/scrape/preview` | Administrator; `{scraper,id,type?}` returns preview details without committing media |
| `GET /api/scrape/video` | Query scraper, id; returns `{videoUrl}` without complete headers; use playback testing for headers |
| `GET /api/scrape/images` | Administrator; query scraper, id, optional comma-separated imageLanguagePreferences; returns `{scraper,providerId,images,imageLanguagePreferences}`; requires getImages |

<a id="save"></a>

## Save and register

`GET /api/config/system` returns a management list to signed-in users, including user extension code, id, version, enabled, and capabilities. Never publish this response; it may contain user configuration or extension credentials.

`POST /api/config/system` requires an administrator. Create with code, name, and filename, optionally capabilityConfig and cleaningScriptId. filename is a single `.scraper.ts` basename without directories; code is your extension.

```json
{"name":"Generic Metadata Source","filename":"generic-metadata.scraper.ts","code":"<YOUR_EXTENSION_CODE>"}
```

Before editing, read the latest record, include its original id and baseVersion, and keep name and filename unchanged. Use the returned version as baseVersion. On 409, read again and merge. Omit cleaningScriptId to preserve the binding or send null to unbind.

The response includes success, scraper, version, and receipt. Check `receipt.persistence.state` is saved separately from `receipt.registration.state` being registered. disabled means disabled; failed or unavailable means not usable as an active source. HTTP 200 does not prove registration. Ordinary saves need no Server restart; verify through the active-source list.

| Management endpoint | Body and constraints |
| --- | --- |
| `POST /api/config/system/toggle` | `{name,enabled:boolean}` |
| `POST /api/config/system/reorder` | `{names:[name,...]}` changes list order |
| `DELETE /api/config/system/{filename}` | Delete an eligible source; use `If-Match: "<version>"` to guard against concurrent changes |

Names must be unique and cannot impersonate existing or reserved system names. References may block deletion with 409. Inspect references and let the user decide, rather than automatically unbinding or deleting data. Legacy `/api/config` creation and legacy `/{id}` updates are retired.

<a id="cleaning"></a>

## Filename cleaning

A rule is a synchronous `function clean(input)` returning a string. Creation uses content; testing uses code. Reading requires sign-in; writes and testing require an administrator.

| Endpoint | Input and response |
| --- | --- |
| `GET /api/cleaning` | Read rules and IDs |
| `POST /api/cleaning` | `{name,content}` creates a rule |
| `PUT /api/cleaning/{id}` | `{name,content}` updates a rule |
| `POST /api/cleaning/test` | `{code,input}` → `{success,cleanedName,logs}` |
| `POST /api/cleaning/reorder` | `{ids:[id,...]}` |
| `DELETE /api/cleaning/{id}` | Delete an eligible rule and clear associated bindings |

name is 1–120 characters, code at most 512 KiB, and test input at most 8192 characters. Protected built-in rules cannot be modified or deleted. Test filenames with years, season/episode markers, Chinese book titles, and plain titles without destroying identification information.

`GET /api/scrape/clean?q=<filename>&scraper=<name>` returns `{cleaned}` to check actual cleaning. Bind the rule through cleaningScriptId when saving a source. A successful temporary test does not prove the binding took effect; verify separately.

<a id="composite"></a>

## Composite sources

`GET /api/composite` lists composites. Administrators create or update with `POST /api/composite`:

```json
{"name":"Combined Movies","memberNames":["Source A","Source B"],"isActive":true}
```

Updates include the original id and unchanged name. memberNames is an ordered replacement list with at least one available base source. Self-reference, duplicates, and nesting are not allowed. Check runtime.state and registered rather than treating isActive alone as readiness. Delete through `DELETE /api/composite/{id}`; references may produce 409.

Composite candidate IDs are opaque; pass them unchanged to details rather than treating them as bare provider IDs. List order does not mean only the first source is always used. Composites do not currently forward generic getImages, getComicChapters, or getComicPages methods. For comic reading, choose a base source implementing the relevant methods.
