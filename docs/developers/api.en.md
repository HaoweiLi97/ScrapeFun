# API integration reference

[简体中文](api.md) · [English](api.en.md)

2026-11-03

<a id="scope"></a>

## Addresses and scope

These selected native ScrapeFun HTTP APIs were checked against the current development version marked 0.5.1. Released builds may differ; verify your own instance first. This is not an inventory of internal endpoints. Use your deployed Server address, such as `http://127.0.0.1:8096`, rather than the product portal. Use HTTPS for remote connections.

The [OpenAPI description](https://scrapefun.com/developers/openapi.json) is machine readable. [GitHub documentation](https://github.com/HaoweiLi97/ScrapeFun/tree/main/docs/developers) includes Markdown and extension examples. See the separate [scraper authoring](scrapers.en.md) and [testing and management](scraper-api.en.md) guides.

Requests and responses use JSON. Success can return an object, an array, or an empty response; there is no universal `data` wrapper. Keep provider IDs, Server metadata IDs, library IDs, and task IDs distinct. Example domains and IDs are synthetic.

<a id="authentication"></a>

## Authentication and permissions

Complete Server initialization through the UI first. Scripts calling `POST /api/auth/login` must send `X-ScrapeFun-Platform: api` to request Bearer mode explicitly. The body contains string fields `username` and `password`, with an optional boolean `remember`. Do not omit the platform header and assume the returned token supports Bearer authentication.

```http
POST /api/auth/login HTTP/1.1
Host: localhost:8096
Content-Type: application/json
X-ScrapeFun-Platform: api

{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD","remember":false}
```

Success includes `token`, `authMode`, `expiresAt` (Unix milliseconds), and `user`. Check that `authMode` is `bearer`, treat the token as opaque, and send it in `Authorization: Bearer <token>`. A cookie-mode placeholder token cannot authenticate Bearer requests. Never put credentials, complete login responses, or tokens in public repositories, URLs, screenshots, or AI conversations.

| Endpoint | Purpose | Success response |
| --- | --- | --- |
| `GET /api/auth/me` | Read the current user | `{user}` |
| `POST /api/auth/logout` | End the current session | HTTP 204, no body |
| `POST /api/auth/logout-all` | End all sessions for the current user | `{success:true}` |

Regular users can access only permitted libraries. Scanning, bulk metadata updates, and task management require an administrator. Cookie-authenticated writes must also pass origin checks; prefer Bearer for automation. AI requests have the same permissions as other requests.

<a id="metadata"></a>

## Query media

| Endpoint | Input | Response |
| --- | --- | --- |
| `GET /api/libraries` | None | Array of visible libraries, including `id`, `name`, `type`, and other fields |
| `GET /api/metadata` | Query parameters below | `{items,total,page,pageSize}` |
| `GET /api/metadata/detail/{id}` | Server metadata ID | Media detail object; 404 if unavailable or inaccessible |
| `GET /api/metadata/{id}/episodes` | Optional `season` query | `{metadataId,season,episodes}` |
| `GET /api/metadata/{id}/files` | Server metadata ID | `{metadataId,files}` |

| List parameter | Type and rules |
| --- | --- |
| `q` | Optional URL-encoded search text |
| `libraryIds` | Optional comma-separated library IDs |
| `type` | Optional, such as `movie`, `tv`, `comic`, or `book` |
| `favorite` | String `true` filters favorites |
| `page` | Starts at 1; default 1 |
| `pageSize` | Default 20; range 1–100 |
| `view` | `card` or `full`; default `full` |
| `sortBy`, `sortOrder` | Common fields: `title`, `year`, `rating`, `createdAt`; `asc` or `desc`; default newest creation first |

Common media fields include `id`, `title`, `type`, `year`, `summary`, and `rating`. Fields vary by view and media type; missing values may be null. Treat returned resource addresses as private because they may contain access information.

```bash
curl --fail-with-body --get "$SCRAPEFUN_URL/api/metadata" \
  --header "Authorization: Bearer $SCRAPEFUN_TOKEN" \
  --data-urlencode 'q=Example work' \
  --data-urlencode 'page=1' --data-urlencode 'pageSize=20' \
  --data-urlencode 'view=card'
```

Set environment variables locally. `SCRAPEFUN_URL` is the Server address without a trailing slash. Never print `SCRAPEFUN_TOKEN` in public logs.

<a id="user-state"></a>

## Favorites and watched state

`PATCH /api/metadata/{id}/favorite` accepts `{favorite:boolean}` and returns `{success:true,favorite:boolean}`. It updates only the current user's favorite state.

`PATCH /api/metadata/{id}/watched` accepts `{watched:boolean,episodeId?:string}` and returns `{success:true}`. The episode must belong to the media item. Setting watched to false clears the current user's corresponding progress; marking an entire show unwatched also resets its episodes. AI should perform these writes only when the user requests them.

<a id="tasks"></a>

## Scanning and task tracking

These endpoints require an administrator. Obtain real library IDs from the library list. Scanning and updating apply to filesystem libraries, not virtual libraries.

| Endpoint | Body | Behavior |
| --- | --- | --- |
| `POST /api/libraries/{id}/scan` | Optional `{fullRefresh:false}` | Start a scan; true also refreshes existing metadata |
| `POST /api/libraries/{id}/update` | Optional `{mode:"missing"}` | `missing` fills gaps; `all` updates everything and is the default |

Success returns `{success:true,taskId,message}`: the task has started, not finished. Conflicts may return 409 with `taskIds`. After a lost connection, inspect existing tasks before submitting another write.

| Endpoint | Parameters and response |
| --- | --- |
| `GET /api/tasks` | `scope=active`, `history`, or `inbox`, optional `limit`; returns `{scope,unreadCount,tasks}` |
| `GET /api/tasks/{id}` | Returns a task object |
| `GET /api/tasks/{id}/events` | Returns `{events}` |
| `POST /api/tasks/{id}/cancel` | Cancel only when the task allows it |
| `POST /api/tasks/{id}/pause` | Pause a supported task |
| `POST /api/tasks/{id}/resume` | Resume a supported paused task |
| `POST /api/tasks/{id}/retry` | Retry; follow a new `taskId` if returned |

Tasks include `id`, `kind`, `title`, `status`, `phase`, `summary`, `progress`, and `capabilities`. Progress commonly has `current`, `total`, and `percent`; unknown values may be null. States include `queued`, `running`, `paused`, `succeeded`, `failed`, `cancelled`, and `needs_attention`. Check actual `capabilities` for cancel, pause, resume, and retry support instead of inferring support from status alone.

<a id="errors"></a>

## Errors and automation

| HTTP status | Handling |
| --- | --- |
| 400 | Check parameters and library type; do not retry unchanged requests in a loop |
| 401 | Missing or expired session; authenticate again |
| 403 | Insufficient permissions or incomplete initialization; check user and instance state |
| 404 | Object missing or inaccessible to the current user |
| 409 | Task or version conflict; read current state before proceeding |
| 429 | Honor `Retry-After` when present and reduce request frequency |
| 500 | Inspect the error and upstream services; confirm whether a write took effect before retrying |

Errors usually contain `error`; some also contain `code`. Do not assume every endpoint uses an identical error shape. Read lists page by page. Poll tasks at intervals and stop on completion or when human attention is needed. Give AI this reference and the scraper contract, specify the objective, instance version, and permitted writes, and keep credentials in the execution environment.
