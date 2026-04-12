# ScrapeFun v1.2.6 Update Guide

> [!IMPORTANT]
> **Performance Critical Update**
> This version introduces significant database schema changes (indexes) and query optimizations (WAL mode, concurrent queries) to fix performance issues with large libraries and WebDAV.

## Quick Update (Docker)

If you have the `update.sh` script:

```bash
chmod +x update.sh
./update.sh
```

## Built-In Sidecar Updater

ScrapeFun now supports a built-in sidecar updater container for Docker Compose deployments.  
This is the recommended mode for NAS users because it does not require starting a separate host process by hand.

1. Use the official compose template.
2. Optionally set:
   ```env
   UPDATE_DOCKERHUB_REPO=haoweil/scrapefun
   UPDATE_DEFAULT_CHANNEL=stable
   ```
3. Start the stack with Docker Compose as usual.
4. In Settings, choose `Stable` or `Beta`, then click `Update Now`.

The sidecar updater container receives the selected channel and target tag, writes `.updater.env`, recreates only the `app` service, and waits for `/health` to pass.

## Manual Update

1. **Pull the latest image:**
   ```bash
   docker pull haoweil/scrapetab:latest
   ```

2. **Recreate the container:**
   ```bash
   docker stop scrapetab
   docker rm scrapetab
   docker compose up -d
   ```

3. **Apply Database Optimizations (CRITICAL):**
   After the container starts, you MUST run this command to apply the new database indexes:
   ```bash
   docker exec scrapetab npx prisma db push
   ```
   *Note: If you skip this step, the application may fail to start or be extremely slow.*

## Changes in v1.2.6
- **Database Indexing:** Added indexes to `MediaFile` (url), `Metadata` (source, type), and `Image` (url) for faster lookups.
- **SQLite Optimization:** Enabled WAL (Write-Ahead Logging) mode for better concurrency.
- **Query Optimization:** Implemented "Two-Step Fetch" for WebDAV to avoid database timeouts.
- **WebDAV Caching:** Added in-memory caching for WebDAV settings.
- **Client Optimization:** Request cancellation added to UI to prevent redundant server load.
