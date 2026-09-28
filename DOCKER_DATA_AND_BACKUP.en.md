# Docker persistent data, backup, and recovery

[简体中文](./DOCKER_DATA_AND_BACKUP.md) · **English**

> Updated: 2026-09-28

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
| `images` | Posters, backdrops, generated covers, and reading backgrounds | Yes |
| `user-avatars` | User avatars | Yes |
| `config` | Runtime configuration for system scrapers | Yes |
| `custom-scrapers` | Legacy-compatible custom scraper files | When present |
| `local-subtitles` | Local subtitles | Yes |
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
  | bash -s -- stable ~/scrapefun --migrate-data-root
```

The migration process:

1. Stop app write tasks and retain an in-app backup.
2. Stop app while retaining the old container.
3. Copy other, unmounted directories from the old container's `/app/data` into the host's unified data root.
4. Confirm the database, images, configuration, avatars, subtitles, and other directories are together.
5. Change Compose to a single root mount and recreate app.
6. Verify login, libraries, images, scrapers, and playback before deleting the old container or migration copies.

If you cannot determine which files exist only in the old container, retain it and seek support before proceeding.

## In-app backup (recommended)

Open **Settings → General → Backup and Restore** and select **Export**. Current `snapshot-v4` backups use a consistent SQLite snapshot and record each file's size and SHA-256. They include the database, images, avatars, scraper configuration, and local subtitles. Rebuildable media caches, temporary files, and logs are excluded.

Imports still support `snapshot-v3`, `snapshot-v2`, and `backup.json`. Restore checks paths, individual files, space, and SQLite before changing current data, and rolls back interrupted operations. Export a new `snapshot-v4` immediately after restoring an older backup. Backups may contain storage connection settings; encrypt them and copy them to another device.

## Full host backup

Disaster recovery needs both the data directory and deployment configuration. The one-click installer places verified operations tools in the deployment directory:

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

The following commands use the one-click deployment's `docker-compose.remote.yml` / `.updater.env`. The manual NAS example instead uses `docker compose ps` and `docker compose logs --tail=200 app`. Adjust access ports to match your configuration.

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
