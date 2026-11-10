#!/usr/bin/env python3
"""Archive validation and stopped-service snapshots for native Linux installs."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import tarfile
import tempfile
import subprocess
import re
import socket
import shlex
import platform
from datetime import datetime, timezone


# The CLI and the installation report share this compatibility matrix.
# Unlisted versions require the same capability checks, but are not certified.
LINUX_SUPPORT = {
    'ubuntu': {'22.04': 'WSL verified (0.5.0 install/reinstall/update)', '24.04': 'VM verified (0.4.4 -> 0.5.0, rollback, reboot)'},
    'debian': {'12': 'VM verified (0.4.4 -> 0.5.0, rollback, reboot)'},
    'fedora': {'43': 'VM verified (SELinux Enforcing, firewalld, rollback, reboot)'},
}


def os_release(paths=('/etc/os-release', '/usr/lib/os-release')):
    source = next((Path(path) for path in paths if Path(path).is_file()), None)
    if source is None:
        raise ValueError('cannot identify Linux: /etc/os-release and /usr/lib/os-release are missing')
    result = {}
    for line in source.read_text().splitlines():
        key, separator, value = line.partition('=')
        if separator and key in ('ID', 'ID_LIKE', 'VERSION_ID', 'PRETTY_NAME'):
            fields = shlex.split(value, comments=True)
            result[key] = ' '.join(fields)
    return result


def mount_options(path, mountinfo='/proc/self/mountinfo'):
    path = Path(path).resolve()
    found = (0, set())
    for line in Path(mountinfo).read_text().splitlines():
        fields, _, filesystem = line.partition(' - ')
        fields = fields.split()
        mount = Path(re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), fields[4]))
        if path == mount or mount in path.parents:
            if len(mount.parts) >= found[0]:
                found = (len(mount.parts), set(fields[5].split(',')) | set(filesystem.split()[2].split(',')))
    return found[1]


def filesystem_check(install, data, config, node=None):
    for value in (install, data, config):
        parent = Path(value)
        while not parent.exists(): parent = parent.parent
        options = mount_options(parent)
        if 'ro' in options:
            raise ValueError('read-only deployment filesystem: ' + value)
        if 'noexec' in options and (value == install or (node and Path(value) in Path(node).parents)):
            raise ValueError('noexec filesystem cannot run application/runtime: ' + value)
        stat = os.statvfs(parent)
        if stat.f_files and stat.f_favail < 256:
            raise ValueError('insufficient free inodes: ' + value)


def system_check(install, data, config, node=None):
    identity = os_release()
    status = LINUX_SUPPORT.get(identity.get('ID'), {}).get(identity.get('VERSION_ID'), 'unverified distribution/version')
    print('OS: {} {} | {}'.format(identity.get('ID', 'unknown'), identity.get('VERSION_ID', 'unknown'), status), flush=True)
    libc = os.confstr('CS_GNU_LIBC_VERSION') or ''
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ValueError('only Linux amd64 native releases are available')
    if not libc.startswith('glibc ') or tuple(int(n) for n in libc.split()[1].split('.')[:2]) < (2, 28):
        raise ValueError('glibc 2.28+ is required; musl/Alpine is unsupported')
    if not Path('/run/systemd/system').is_dir():
        raise ValueError('systemd must be running; enable it in WSL before installing')
    deployment_paths(install, data, config)
    filesystem_check(install, data, config, node)
    backup_space(data, config)
    print('PASS: amd64, {}, systemd, deployment paths, writable mounts and backup space'.format(libc), flush=True)
    enforcing = Path('/sys/fs/selinux/enforce')
    if enforcing.exists():
        mode = 'Enforcing' if enforcing.read_text().strip() == '1' else 'Permissive'
        if not shutil.which('restorecon'):
            raise ValueError('SELinux is enabled but restorecon is missing; install policycoreutils')
    else:
        mode = 'disabled/unavailable'
    print('SELinux: ' + mode, flush=True)
    if shutil.which('firewall-cmd'):
        active = subprocess.run(['firewall-cmd', '--state'], capture_output=True, text=True).returncode == 0
        print('firewalld: ' + ('active; allow the selected TCP port in the appropriate zone for remote access' if active else 'inactive'), flush=True)
    if shutil.which('ufw'):
        result = subprocess.run(['ufw', 'status'], capture_output=True, text=True)
        print('UFW: ' + result.stdout.splitlines()[0] if result.stdout else 'UFW: status unavailable', flush=True)


def prisma_engine(release):
    release = Path(release)
    client = release / 'server/node_modules/.prisma/client'
    candidates = sorted(client.glob('libquery_engine-*.so.node'))
    if not candidates:
        if (release / 'server/node_modules/@prisma/client').exists():
            raise ValueError('release is missing its Prisma query engine')
        return None
    identity = os_release()
    families = (identity.get('ID', '') + ' ' + identity.get('ID_LIKE', '')).split()
    family = 'rhel' if any(item in families for item in ('fedora', 'rhel', 'centos')) else 'debian'
    # Published amd64 archives contain a Debian-named glibc/OpenSSL 3 engine.
    # Select the host-specific engine when present; the bundled fallback must
    # pass an actual SQLite query before we allow it on another distribution.
    for target in (family + '-openssl-3.0.x', 'debian-openssl-3.0.x'):
        candidate = client / ('libquery_engine-' + target + '.so.node')
        if candidate in candidates: return candidate
    if len(candidates) == 1: return candidates[0]
    raise ValueError('cannot select a compatible Prisma query engine from this release')


def release_check(release, node):
    release = Path(release)
    subprocess.run([node, 'scripts/verify-protected.cjs'], cwd=release / 'server', check=True)
    modules = list((release / 'server/dist/pro-runtime').glob('*.node'))
    engine = prisma_engine(release)
    if engine: modules.append(engine)
    for module in modules:
        result = subprocess.run(['ldd', str(module)], capture_output=True, text=True)
        if result.returncode or 'not found' in result.stdout + result.stderr:
            raise ValueError('incompatible native runtime libraries for {}: {}'.format(module.name, result.stdout + result.stderr))
    if engine:
        with tempfile.TemporaryDirectory(prefix='scrapefun-db-check-') as scratch:
            probe = "const {PrismaClient}=require('@prisma/client'); const db=new PrismaClient({datasources:{db:{url:process.env.SCRAPEFUN_PROBE_DB}}}); (async()=>{try{await db.$queryRawUnsafe('SELECT 1');}catch(e){console.error(e.message);process.exitCode=1;}finally{await db.$disconnect();}})();"
            result = subprocess.run([node, '-e', probe], cwd=release / 'server', capture_output=True, text=True, timeout=45,
                                    env={**os.environ, 'PRISMA_QUERY_ENGINE_LIBRARY': str(engine.resolve()),
                                         'SCRAPEFUN_PROBE_DB': 'file:' + scratch + '/probe.db'})
            if result.returncode:
                raise ValueError('Prisma database engine preflight failed: ' + result.stderr)
        print('PASS: Prisma SQLite connection (' + engine.name + ')', flush=True)
    print('PASS: protected release manifest and native runtime libraries', flush=True)


def extract_release(archive, destination, install=None):
    extract(archive, destination, allow_links=True, space_destination=install)
    roots = list(Path(destination).iterdir())
    if len(roots) != 1 or not (roots[0] / 'start.sh').is_file() or not (roots[0] / 'server/dist/index.js').is_file():
        raise ValueError('invalid Linux server release layout')
    release = json.loads((roots[0] / 'RELEASE.json').read_text())
    if release.get('architecture') != 'amd64' or release.get('channel') not in ['stable', 'beta']:
        raise ValueError('unsupported Linux server release')
    return roots[0]


def check_archive(archive, install, node):
    # Fedora commonly mounts /tmp as a small tmpfs. Validate on the target
    # filesystem, in a disposable sibling, without modifying the installed app.
    parent = Path(install).parent
    while not parent.exists(): parent = parent.parent
    with tempfile.TemporaryDirectory(prefix='.scrapefun-check-', dir=parent) as scratch:
        release = extract_release(archive, scratch, install)
        subprocess.run(['bash', '-n', str(release / 'start.sh')], check=True)
        release_check(release, node)


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hash_stream(stream)


def hash_stream(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(block)
    return result.hexdigest()


def members(archive, allow_links=False):
    entries = archive.getmembers()
    links = set()
    names = set()
    for entry in entries:
        path = PurePosixPath(entry.name)
        if path.is_absolute() or ".." in path.parts or str(path) in names:
            raise ValueError(f"unsafe/duplicate archive path: {entry.name}")
        names.add(str(path))
        if entry.isdir() or entry.isfile():
            continue
        if not allow_links or not (entry.issym() or entry.islnk()):
            raise ValueError(f"unsupported archive member: {entry.name}")
        target = PurePosixPath(entry.linkname)
        if target.is_absolute():
            raise ValueError(f"absolute archive link: {entry.name}")
        # Permit ordinary node_modules ../ links, but refuse interior '..'
        # components that could traverse another link before stepping upward.
        descended = False
        for part in target.parts:
            if part == '..' and descended:
                raise ValueError(f"ambiguous archive link traversal: {entry.name}")
            if part not in ['.', '..']: descended = True
        parts = list(path.parent.parts) if entry.issym() else []
        for part in target.parts:
            if part == "..":
                if len(parts) <= 1:
                    raise ValueError(f"escaping archive link: {entry.name}")
                parts.pop()
            elif part != ".":
                parts.append(part)
        if not parts or parts[0] != path.parts[0]:
            raise ValueError(f"escaping archive link: {entry.name}")
        links.add(path)
    for entry in entries:
        if any(parent in links for parent in PurePosixPath(entry.name).parents):
            raise ValueError(f"archive writes through a link: {entry.name}")
    return entries


def extract(path, destination, allow_links=False, space_destination=None):
    with tarfile.open(path, "r:gz") as archive:
        entries = members(archive, allow_links)
        required = sum(entry.size for entry in entries if entry.isfile()) + 64 * 1024 * 1024
        for target in {str(destination), str(space_destination or destination)}:
            parent = Path(target)
            while not parent.exists(): parent = parent.parent
            if shutil.disk_usage(parent).free < required:
                raise ValueError(f"insufficient disk space for extraction at {parent}: need {required // (1024 * 1024)} MiB")
            stat = os.statvfs(parent)
            if stat.f_files and stat.f_favail < len(entries) + 128:
                raise ValueError('insufficient free inodes for release extraction at ' + str(parent))
        # members() validates paths, links and file types before extraction.
        # Keep archive permissions/metadata instead of relying on the default
        # filter, which changes in Python 3.14. Older Python 3.10 builds lack
        # filter support; detect the API because it was also backported.
        if hasattr(tarfile, "data_filter"):
            archive.extractall(destination, members=entries, filter="fully_trusted")
        else:
            archive.extractall(destination, members=entries)


def check_db(root):
    db = root / "db/dev.db"
    if not db.exists():
        return
    with sqlite3.connect(f"file:{db}?mode=ro", uri=True) as connection:
        if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise ValueError("SQLite integrity check failed")


def safe_root(value):
    raw = Path(value)
    path = raw.resolve()
    broad = {Path(p).resolve() for p in ["/", "/var/lib", "/usr/local", "/home", "/etc", "/usr", "/opt", "/var", "/root", "/tmp"]}
    if not raw.is_absolute() or raw.is_symlink() or path in broad or path == Path.home().resolve() or len(path.parts) < 3:
        raise ValueError(f"unsafe directory: {value}")
    return path


def deployment_paths(install, data, config):
    paths = []
    for value in (install, data, config):
        path = safe_root(value)
        if not re.fullmatch(r'/[A-Za-z0-9_./-]+', value) or '..' in Path(value).parts or path != Path(value):
            raise ValueError('unsafe systemd deployment path: ' + value)
        if path.exists() and not path.is_dir():
            raise ValueError('deployment path must be a directory: ' + value)
        paths.append(path)
    for index, first in enumerate(paths):
        for second in paths[index + 1:]:
            if first == second or first in second.parents or second in first.parents:
                raise ValueError('install, data and configuration directories must be separate')
    for name in ('server.env', 'management.env', 'gpu.env', '.operations.lock', 'scrapefun'):
        candidate = paths[2] / name
        if candidate.is_symlink() or (candidate.exists() and not candidate.is_file()):
            raise ValueError('configuration must be a regular file: ' + str(candidate))
    for name in ('runtime', 'operations', 'updater', 'updater/requests'):
        directory = paths[2] / name
        if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
            raise ValueError('management path must be a directory without symlinks: ' + str(directory))
    updater = paths[2] / 'updater'
    if updater.exists():
        if updater.stat().st_uid != 0 or updater.stat().st_mode & 0o022:
            raise ValueError('updater directory must be root-owned and not writable by other users')
        for name in ('status.json', 'worker.lock', 'update.log'):
            file = updater / name
            if file.is_symlink() or (file.exists() and (not file.is_file() or file.stat().st_uid != 0 or file.stat().st_mode & 0o022)):
                raise ValueError('unsafe updater state: ' + str(file))


def check_port(port):
    # Bind on every IPv4 interface, matching the default server HOST. Never
    # kill the owner of an occupied port or assume a listening app is ours.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('0.0.0.0', port))
        except OSError as error:
            raise ValueError(f'TCP port {port} is unavailable: {error}; choose --port PORT') from error


BACKUP_CACHE_DIRECTORIES = {
    'cache', 'temp', 'logs', 'book-cache', 'book-tts-cache', 'comic-cache', 'image-cache',
    'video-proxy-cache', 'video-startup-cache', 'transcode-cache', 'image-upscale-cache',
    'media-probe', 'media-probe-v2', 'subtitle-mirror',
}


def backup_space(data, config):
    # A snapshot temporarily holds the inner and outer archive together.
    # Estimate conservatively without counting regenerable caches.
    data = Path(data)
    size = 0
    if data.is_dir():
        for root, directories, files in os.walk(data, followlinks=False):
            if Path(root) == data:
                directories[:] = [name for name in directories if name not in BACKUP_CACHE_DIRECTORIES]
            for name in files:
                file = Path(root) / name
                if not file.is_symlink(): size += file.stat().st_size
    parent = Path(config)
    while not parent.exists(): parent = parent.parent
    required = 2 * size + 64 * 1024 * 1024
    if shutil.disk_usage(parent).free < required:
        raise ValueError(f'insufficient backup disk space: need at least {required // (1024 * 1024)} MiB')


def backup(data, config, output):
    data = safe_root(data)
    output = Path(output).resolve()
    if output == data or data in output.parents:
        raise ValueError("backup destination must be outside the data directory")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    check_db(data)
    with tempfile.TemporaryDirectory(dir=output) as scratch:
        scratch = Path(scratch)
        def include(entry):
            if PurePosixPath(entry.name).parts[0] in BACKUP_CACHE_DIRECTORIES:
                return None
            if not (entry.isfile() or entry.isdir()):
                raise ValueError(f"data backup refuses links/special files: {entry.name}")
            return entry
        with tarfile.open(scratch / "data.tar.gz", "w:gz") as archive:
            for child in sorted(data.iterdir()):
                archive.add(child, arcname=child.name, filter=include)
        shutil.copyfile(config, scratch / "server.env")
        manifest = {"format": "scrapefun-native-backup-v1", "createdAt": datetime.now(timezone.utc).isoformat(),
                    "sha256": {name: digest(scratch / name) for name in ["data.tar.gz", "server.env"]}}
        (scratch / "manifest.json").write_text(json.dumps(manifest))
        result = output / f"scrapefun-native-backup-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}.tar.gz"
        with tarfile.open(result, "w:gz") as archive:
            for name in ["manifest.json", "data.tar.gz", "server.env"]:
                archive.add(scratch / name, arcname=name)
        result.chmod(0o600)
        (Path(str(result) + ".sha256")).write_text(f"{digest(result)}  {result.name}\n")
        print(result)


def verified_backup(archive, scratch):
    extract(archive, scratch)
    if {item.name for item in scratch.iterdir()} != {"manifest.json", "data.tar.gz", "server.env"}:
        raise ValueError("unexpected backup layout")
    manifest = json.loads((scratch / "manifest.json").read_text())
    if manifest.get("format") != "scrapefun-native-backup-v1":
        raise ValueError("unsupported backup format")
    for name in ["data.tar.gz", "server.env"]:
        if manifest.get("sha256", {}).get(name) != digest(scratch / name):
            raise ValueError(f"backup checksum mismatch: {name}")
    data = scratch / "data"
    data.mkdir()
    extract(scratch / "data.tar.gz", data)
    check_db(data)
    return data


def restore(archive, data):
    data = safe_root(data)
    with tempfile.TemporaryDirectory(dir=data.parent) as scratch:
        restored = verified_backup(archive, Path(scratch))
        old_stat = data.stat()
        for directory, subdirs, files in os.walk(restored):
            os.chown(directory, old_stat.st_uid, old_stat.st_gid)
            for name in files:
                os.chown(Path(directory) / name, old_stat.st_uid, old_stat.st_gid)
        restored.chmod(old_stat.st_mode & 0o777)
        previous = data.with_name(data.name + ".previous-" + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
        os.rename(data, previous)
        try:
            os.rename(restored, data)
        except BaseException:
            os.rename(previous, data)
            raise
        print(previous)


def prepare_legacy(data, schema, node):
    """Synchronize old releases on a private DB copy before committing it."""
    data, schema = Path(data), Path(schema).resolve()
    database = data / 'db/dev.db'
    stamp = data / 'config/.native-prisma-schema.sha256'
    expected = digest(schema)
    check_db(data)
    if database.exists() and stamp.exists() and stamp.read_text().strip() == expected:
        print('Legacy schema already prepared; SQLite integrity OK')
        return
    snapshots = database.parent / 'backups'
    snapshots.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=database.parent) as scratch:
        candidate = Path(scratch) / 'dev.db'
        if database.exists() and database.stat().st_size:
            snapshot = snapshots / ('pre-legacy-prepare-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.db')
            with sqlite3.connect(database) as original:
                with sqlite3.connect(snapshot) as target: original.backup(target)
                with sqlite3.connect(candidate) as target: original.backup(target)
            snapshot.chmod(0o600)
        # FTS5 is a derived search cache, outside Prisma's schema. Remove it
        # only on the candidate DB; the application rebuilds it at startup.
        with sqlite3.connect(candidate) as connection:
            for name in ['WebDAVFileSearch_ai', 'WebDAVFileSearch_ad', 'WebDAVFileSearch_au']:
                connection.execute(f'DROP TRIGGER IF EXISTS "{name}"')
            connection.execute('DROP TABLE IF EXISTS "WebDAVFileSearch"')
        environment = {**os.environ, 'DATABASE_URL': 'file:' + str(candidate)}
        subprocess.run([node, 'node_modules/prisma/build/index.js', 'db', 'push', '--skip-generate',
                        '--schema', str(schema)], cwd=schema.parent.parent, env=environment, check=True)
        with sqlite3.connect(candidate) as source:
            if source.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
                raise ValueError('candidate SQLite integrity check failed')
            with sqlite3.connect(database) as target: source.backup(target)
        stamp.parent.mkdir(exist_ok=True)
        stamp.write_text(expected + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["extract-release", "backup", "verify-backup", "restore", "prepare-legacy", "preflight", "check-port", "system-check", "release-check", "compatibility", "prisma-engine", "check-archive"])
    parser.add_argument("--archive")
    parser.add_argument("--destination")
    parser.add_argument("--data")
    parser.add_argument("--config")
    parser.add_argument("--output")
    parser.add_argument("--schema")
    parser.add_argument("--node")
    parser.add_argument("--install")
    parser.add_argument("--port", type=int)
    args = parser.parse_args()
    if args.command == 'compatibility':
        print('| Distribution | Version | Validation |\n| --- | --- | --- |')
        for distribution, versions in LINUX_SUPPORT.items():
            for version, status in versions.items(): print('| {} | {} | {} |'.format(distribution, version, status))
    elif args.command == 'system-check':
        system_check(args.install, args.data, args.config, args.node)
    elif args.command == 'release-check':
        release_check(args.install, args.node)
    elif args.command == 'prisma-engine':
        engine = prisma_engine(args.install)
        if engine: print(engine.relative_to(args.install))
    elif args.command == 'check-archive':
        check_archive(args.archive, args.install, args.node)
    elif args.command == "preflight":
        deployment_paths(args.install, args.data, args.config)
        backup_space(args.data, args.config)
    elif args.command == "check-port":
        if args.port is None or not 1 <= args.port <= 65535: raise ValueError('invalid port')
        check_port(args.port)
    elif args.command == "extract-release":
        print(extract_release(args.archive, args.destination, args.install))
    elif args.command == "backup":
        backup(args.data, args.config, args.output)
    elif args.command == "restore":
        restore(args.archive, args.data)
    elif args.command == "prepare-legacy":
        prepare_legacy(args.data, args.schema, args.node)
    else:
        with tempfile.TemporaryDirectory() as scratch:
            verified_backup(args.archive, Path(scratch))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, tarfile.TarError, sqlite3.Error, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Error: {error}")
