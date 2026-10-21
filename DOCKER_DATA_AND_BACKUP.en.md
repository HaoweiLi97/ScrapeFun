# Docker persistent data, backup, and recovery

[简体中文](./DOCKER_DATA_AND_BACKUP.md) · **English**

> Updated: 2026-10-20

Containers can be recreated; business data must remain on the host. The recommended Compose configuration mounts the complete data root at `/app/data`:

```yaml
services:
  app:
    volumes:
      - ${SCRAPEFUN_DATA_DIR:-./scrapefun-data}:/app/data
```

Do not mount only individual directories such as `db`, `images`, `config`, or `custom-scrapers`. Such a configuration protects only those listed directories. New runtime directories, including avatars, models, or caches, may otherwise remain in the container's writable layer and be lost when it is recreated.

## Data directories

The one-click installer defaults to `~/scrapefun-data`, alongside the deployment directory. Manual NAS Compose deployments commonly use `./scrapefun-data` within the project directory. The actual path follows `SCRAPEFUN_DATA_DIR` in `.updater.env` or the Compose configuration.

Keep deployment configuration with the business data. Do not upload secrets, storage passwords, or backup files to public issues. Restrict access to off-device backups or encrypt them.

| Subdirectory | Contents | Included in app backup |
| --- | --- | --- |
| `db` | SQLite database, settings, users, libraries, progress, and tasks | Yes |
| `images` | Posters, backdrops, generated covers, and reading backgrounds | Standard may omit rebuildable remote images |
| `user-avatars` | User avatars | Yes |
| `config` | Runtime configuration for system scrapers | Yes |
| `custom-scrapers` | Legacy-compatible custom scraper files | When present |
| `local-subtitles` | Local subtitles | Yes |
| `artwork-sources`, `file-artwork`, `storage-credentials` | Artwork sources, file covers, storage credentials | Yes |
| `video-proxy-cache`, `transcode-cache` | Video proxy and transcoding caches | No; can be rebuilt |
| `comic-cache`, `image-cache`, `image-upscale-cache` | Comic and image caches | No; can be rebuilt |
| `media-probe-v2`, `temp`, `logs`, `cache` | Probe results, temporary files, and logs | No; can be rebuilt |

## Migrate older per-directory mounts

Inspect the current container first:

```bash
docker inspect scrapefun \
  --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

If multiple mounts such as `/app/data/db` and `/app/data/images` appear, do not edit Compose and recreate the container directly. The current one-click script stops by default and requires explicit migration:

```bash
curl -fsSL https://raw.githubusercontent.com/HaoweiLi97/ScrapeFun/main/scripts/one-click-compose-deploy.sh \
  | bash -s -- ~/scrapefun --migrate-data-root
```

The command preserves the current channel; replace `~/scrapefun` with your actual deployment directory. Export an application backup yourself before running it; the migration script does not create one automatically.

The migration process:

1. Before running the script, pause write tasks and export an in-app backup yourself.
2. Stop app while retaining the old container.
3. Copy other, unmounted directories from the old container's `/app/data` into the host's unified data root.
4. Confirm the database, images, configuration, avatars, subtitles, and other directories are together.
5. Change Compose to a single root mount and recreate app.
6. The installer recreates app after a successful copy. Verify login, libraries, images, scrapers, and playback, and retain the exported backup.

If you cannot determine which files exist only in the old container, retain it and seek support before proceeding.

## In-app backup (recommended)

Export a ZIP from Backup and Restore in Settings. Current `snapshot-v5` includes a consistent database snapshot, per-file sizes and SHA-256, artwork sources, file covers, avatars, local subtitles, storage credentials, and scraper files.

Standard backups omit remote images with reliable recorded rebuild sources and rebuild them after restoration. Full application backups retain those images. Both exclude reproducible caches, temporary files, and logs. A full application backup is not a complete host backup.

Imports support `snapshot-v4`, `snapshot-v3`, `snapshot-v2`, and `backup.json`. Older applications may not import v5; verify compatibility first. Backups may contain storage passwords: restrict access or encrypt and keep an off-host copy. Application ZIPs do not include host deployment configuration such as `server.env`; back it up separately.

## Full host backup

Disaster recovery needs both data and deployment configuration. These tools require the one-click installer’s `docker-compose.remote.yml` and `.updater.env`; manual NAS Compose requires a separate backup workflow. The one-click installer places operations tools in its deployment directory:

```bash
cd ~/scrapefun
./operations/backup-docker.sh --deploy-dir "$PWD" --output-dir /srv/backups/scrapefun
```

The tool reads `.updater.env`, stops and resumes app, checks SQLite, archives data and configuration, generates a manifest/SHA-256, and retains 7 daily, 4 weekly, and 6 monthly recovery points. Caches are excluded unless `--include-caches` is added. Symbolic links and special files are rejected before archiving to avoid unsafe or incomplete backups.

Optional encryption and off-host verification:

```bash
./operations/backup-docker.sh \
  --deploy-dir "$PWD" \
  --output-dir /srv/backups/scrapefun \
  --age-recipient age1YOUR_PUBLIC_KEY \
  --rclone-remote minio:scrapefun/backups
```

Replace `age1YOUR_PUBLIC_KEY` with your actual age recipient. `server.env` and `.updater.env` may contain secrets. Keep the age private key outside the data and backup directories. An off-host backup counts as verified only after it is downloaded again and passes SHA-256 verification.

When installing a systemd timer with `install-docker-backup-timer.sh`, notification destinations are stored in root-readable `/etc/scrapefun-backup.env`, rather than the `ExecStart` command line.

## Restore an app backup

1. Export the current instance as a fallback.
2. Ensure no scan, scrape, organization, transcoding, or update tasks are running.
3. Select **Import** in **Settings → General → Backup and Restore**.
4. Upload a ZIP exported by ScrapeFun and wait for a successful restore and automatic restart.
5. Check login, users, libraries, images, scrapers, WebDAV / AList, and playback and reading progress.

Restore validates the archive and SQLite, writes to staging, and commits the changes at restart. Failures roll back. Successful restores retain the pre-restore database, keeping the latest 3 by default; these local copies do not replace off-device backups.

## Restore a complete data directory

Use the restore tool instead of overwriting the current directory:

```bash
cd ~/scrapefun
./operations/restore-docker.sh \
  --deploy-dir "$PWD" \
  --backup /srv/backups/scrapefun/scrapefun-docker-backup-YYYYMMDDTHHMMSSZ.tar.gz
```

The tool validates outer and inner archives, checks available space, extracts into a new directory, checks SQLite, preserves existing data as `.pre-restore-*`, and verifies readiness after startup. Encrypted archives require `--age-identity /secure/path/identity.txt`. Delete older directories only after verifying recovery and creating a new backup.

Run isolated recovery drills regularly:

```bash
./operations/drill-docker-backup.sh --backup /srv/backups/scrapefun/BACKUP_FILE.tar.gz
```

## Checks after recovery

The following commands use the one-click deployment's `docker-compose.remote.yml` / `.updater.env`. The manual NAS example instead uses `docker compose --env-file .env --env-file .updater.env ps` and `docker compose --env-file .env --env-file .updater.env logs --tail=200 app`. Adjust access ports to match your configuration.

```bash
docker compose --env-file .updater.env -f docker-compose.remote.yml ps
docker compose --env-file .updater.env -f docker-compose.remote.yml logs --tail=200 app
curl -fsS http://127.0.0.1:8096/health/live
curl -fsS http://127.0.0.1:8096/health/ready
```

`/health/ready` checks startup, database access, data-directory permissions, and restore transactions. Also verify login, libraries, posters and avatars, local subtitles, scraper registration, WebDAV / AList, and actual playback.

## Avoid accidental data loss

- Do not run `docker compose down -v`.
- Do not delete or empty `scrapefun-data`.
- Do not extract a new backup over a running instance's data directory.
- Do not back up only the SQLite database; database and file resources must come from the same point in time.
- Before removing a NAS Compose project, confirm the panel will not delete its bind-mounted directory.
- After updating or recreating containers, confirm the same host directory remains mounted at `/app/data`.

[Documentation](./docs/README.en.md) · [Docker operations](./DOCKER_GUIDE.en.md) · [Support](./SUPPORT.en.md) · [Licensing](./legal/README.en.md)
