# Scrapefun

Next-generation, cloud-drive-native scraping and media management platform.

Scrapefun is an integrated system for WebDAV/AList media libraries: scraping, subtitle operations, playback compatibility, and library administration in one workflow.

## Core Capabilities

- Custom scrapers with scriptable `search / scrape / getVideoUrl` pipelines.
- Custom filename cleaning rules, including per-scraper binding and test execution.
- Composite scrapers with priority-based fallback.
- Built-in WebDAV file browser with list, move, copy, rename, delete, and folder creation.
- 302 direct-link forwarding for AList/WebDAV streaming (`/api/scrape/alist/stream`).
- Direct/proxy playback switching with automatic link resolution and retry logic.
- Proactive subtitle search from the player and media detail flows.
- One-click subtitle pack import (`.zip`, `.rar`, `.7z`) plus direct subtitle upload.
- Per-user media progress tracking (movie + episode) with realtime sync via WebSocket.
- AI metadata translation and AI chat-based writing workflow.
- User management with admin role and library-level access control.
- Library management with scraper binding, ordering, and scoped visibility.
- Jellyfin/Emby compatibility layer for traditional clients such as Infuse, VidHub, SenPlayer, and Yamby, plus other compatible clients.


