#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
import warnings
from unittest.mock import patch

DIRECTORY = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('tools', DIRECTORY / 'linux-server-tools.py')
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class SystemPreflight(unittest.TestCase):
    def test_archive_preflight_uses_target_disk_and_cleans_up_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            install = parent / 'not-created/app'
            def extracted(archive, scratch, destination):
                self.assertEqual(Path(scratch).parent, parent)
                self.assertEqual(destination, install)
                release = Path(scratch) / 'release'
                release.mkdir()
                (release / 'start.sh').write_text('#!/bin/sh\n')
                return release
            with patch.object(tools, 'extract_release', side_effect=extracted), patch.object(tools.subprocess, 'run'), patch.object(tools, 'release_check', side_effect=ValueError('incompatible engine')):
                with self.assertRaisesRegex(ValueError, 'incompatible engine'):
                    tools.check_archive('unused.tar.gz', install, '/usr/bin/node')
            self.assertEqual(list(parent.iterdir()), [])

    def test_prisma_engine_prefers_native_then_validated_bundled_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = root / 'server/node_modules/.prisma/client'
            client.mkdir(parents=True)
            debian = client / 'libquery_engine-debian-openssl-3.0.x.so.node'
            debian.touch()
            with patch.object(tools, 'os_release', return_value={'ID': 'fedora'}):
                self.assertEqual(tools.prisma_engine(root), debian)
                rhel = client / 'libquery_engine-rhel-openssl-3.0.x.so.node'
                rhel.touch()
                self.assertEqual(tools.prisma_engine(root), rhel)
            with patch.object(tools, 'os_release', return_value={'ID': 'ubuntu'}):
                self.assertEqual(tools.prisma_engine(root), debian)
            debian.unlink(); rhel.unlink()
            (root / 'server/node_modules/@prisma/client').mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, 'missing.*query engine'): tools.prisma_engine(root)

    def test_os_release_precedence_fallback_and_no_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            etc, usr = root / 'etc-release', root / 'usr-release'
            usr.write_text('ID=debian\nVERSION_ID="12"\n')
            self.assertEqual(tools.os_release((etc, usr))['ID'], 'debian')
            etc.write_text('ID=fedora\nVERSION_ID="43"\nPRETTY_NAME="$(touch must-not-execute)"\n')
            result = tools.os_release((etc, usr))
            self.assertEqual(result['ID'], 'fedora')
            self.assertEqual(result['PRETTY_NAME'], '$(touch must-not-execute)')
            self.assertFalse((root / 'must-not-execute').exists())
            etc.write_text('ID=custom\n')
            self.assertNotIn('VERSION_ID', tools.os_release((etc, usr)))

    def test_mount_selection_uses_closest_mount_and_filesystem_flags(self):
        with tempfile.TemporaryDirectory() as directory:
            info = Path(directory) / 'mountinfo'
            info.write_text('1 0 8:1 / / rw - ext4 /dev/a rw\n'
                            '2 1 8:2 / /opt rw,noexec - ext4 /dev/b rw\n'
                            '3 2 8:3 / /opt/exec rw - ext4 /dev/c rw\n'
                            '4 1 8:4 / /data rw - ext4 /dev/d ro\n')
            self.assertIn('noexec', tools.mount_options('/opt/app', info))
            self.assertNotIn('noexec', tools.mount_options('/opt/exec/app', info))
            self.assertNotIn('noexec', tools.mount_options('/optional/app', info))
            self.assertIn('ro', tools.mount_options('/data/app', info))

    def test_readonly_noexec_and_exhausted_inodes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [str(Path(directory) / name) for name in ('app', 'data', 'config')]
            for options, message in [({'ro'}, 'read-only'), ({'noexec'}, 'noexec')]:
                with patch.object(tools, 'mount_options', return_value=options):
                    with self.assertRaisesRegex(ValueError, message): tools.filesystem_check(*paths)
            with patch.object(tools, 'mount_options', return_value=set()), patch.object(tools.os, 'statvfs', return_value=SimpleNamespace(f_files=1000, f_favail=0)):
                with self.assertRaisesRegex(ValueError, 'inodes'): tools.filesystem_check(*paths)


class ArchiveExtraction(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / 'release.tar.gz'
        with tarfile.open(self.archive, 'w:gz') as archive:
            directory = tarfile.TarInfo('root'); directory.type = tarfile.DIRTYPE; directory.mode = 0o750
            archive.addfile(directory)
            content = b'#!/bin/sh\nexit 0\n'
            script = tarfile.TarInfo('root/start.sh'); script.mode = 0o755; script.size = len(content)
            archive.addfile(script, io.BytesIO(content))
            config = tarfile.TarInfo('root/server.env'); config.mode = 0o440; config.size = 6
            archive.addfile(config, io.BytesIO(b'KEY=1\n'))

    def assert_extracted(self, destination):
        self.assertEqual((destination / 'root/start.sh').read_bytes(), b'#!/bin/sh\nexit 0\n')
        self.assertEqual((destination / 'root/server.env').read_bytes(), b'KEY=1\n')
        if os.name == 'posix':
            self.assertEqual((destination / 'root').stat().st_mode & 0o777, 0o750)
            self.assertEqual((destination / 'root/start.sh').stat().st_mode & 0o777, 0o755)
            self.assertEqual((destination / 'root/server.env').stat().st_mode & 0o777, 0o440)

    @unittest.skipUnless(hasattr(tarfile, 'data_filter'), 'requires extraction filters')
    def test_explicit_policy_avoids_warnings_and_preserves_permissions(self):
        def reject_default(member, destination):
            raise AssertionError('extraction must explicitly select its policy')
        destination = self.root / 'extract'
        with patch.object(tarfile.TarFile, 'extraction_filter', staticmethod(reject_default)):
            with warnings.catch_warnings():
                warnings.simplefilter('error', DeprecationWarning)
                tools.extract(self.archive, destination)
        self.assert_extracted(destination)

    def test_python_without_filter_api_still_extracts(self):
        with tarfile.open(self.archive, 'r:gz') as archive:
            class LegacyArchive:
                def __enter__(self): return self
                def __exit__(self, *args): pass
                def getmembers(self): return archive.getmembers()
                # Deliberately accept only the pre-filter API's arguments.
                def extractall(self, destination, members):
                    options = {'filter': 'fully_trusted'} if hasattr(tarfile, 'data_filter') else {}
                    archive.extractall(destination, members=members, **options)
            legacy_tarfile = SimpleNamespace(open=lambda *args: LegacyArchive())
            destination = self.root / 'legacy'
            with patch.object(tools, 'tarfile', legacy_tarfile):
                tools.extract(self.archive, destination)
        self.assert_extracted(destination)

    @unittest.skipUnless(os.name == 'posix', 'requires POSIX links')
    def test_release_extracts_safe_symlinks_and_hardlinks(self):
        with tarfile.open(self.archive, 'w:gz') as archive:
            content = b'console.log("prisma");\n'
            script = tarfile.TarInfo('root/server/node_modules/prisma/build/index.js'); script.size = len(content)
            archive.addfile(script, io.BytesIO(content))
            link = tarfile.TarInfo('root/server/node_modules/.bin/prisma')
            link.type = tarfile.SYMTYPE; link.linkname = '../prisma/build/index.js'; archive.addfile(link)
            hardlink = tarfile.TarInfo('root/prisma.js')
            hardlink.type = tarfile.LNKTYPE; hardlink.linkname = script.name; archive.addfile(hardlink)
        destination = self.root / 'links'
        with warnings.catch_warnings():
            warnings.simplefilter('error', DeprecationWarning)
            tools.extract(self.archive, destination, allow_links=True)
        self.assertTrue((destination / link.name).is_symlink())
        self.assertEqual((destination / link.name).read_bytes(), content)
        self.assertTrue(os.path.samefile(destination / script.name, destination / hardlink.name))


class Snapshots(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.data = self.root / 'data'
        (self.data / 'db').mkdir(parents=True)
        self.config = self.root / 'server.env'
        self.config.write_text('APP_AUTH_SECRET=private-test-value\nPORT=19096\n')
        with sqlite3.connect(self.data / 'db/dev.db') as db:
            db.execute('create table marker(value text)')
            db.execute("insert into marker values ('original')")

    def tearDown(self):
        self.temporary.cleanup()

    def backup(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            tools.backup(self.data, self.config, self.root / 'backups')
        return Path(output.getvalue().strip())

    def test_roundtrip_preserves_database_files_permissions_and_current_config(self):
        (self.data / 'config').mkdir()
        (self.data / 'config/setting.json').write_text('{"setting":true}')
        (self.data / 'cache').mkdir()
        (self.data / 'cache/reproducible').write_text('cache')
        self.data.chmod(0o750)
        archive = self.backup()
        self.assertEqual(archive.stat().st_mode & 0o777, 0o600)
        self.assertTrue(Path(str(archive) + '.sha256').exists())
        self.config.write_text('PORT=29096\n')
        with sqlite3.connect(self.data / 'db/dev.db') as db:
            db.execute("update marker set value = 'changed'")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            tools.restore(archive, self.data)
        previous = Path(output.getvalue().strip())
        with sqlite3.connect(self.data / 'db/dev.db') as db:
            self.assertEqual(db.execute('select value from marker').fetchone()[0], 'original')
        with sqlite3.connect(previous / 'db/dev.db') as db:
            self.assertEqual(db.execute('select value from marker').fetchone()[0], 'changed')
        self.assertFalse((self.data / 'cache').exists())
        self.assertTrue((self.data / 'config/setting.json').exists())
        self.assertEqual(self.data.stat().st_mode & 0o777, 0o750)
        self.assertEqual(self.config.read_text(), 'PORT=29096\n')

    def test_refuses_destination_inside_data_and_broad_restore_paths(self):
        with self.assertRaises(ValueError):
            tools.backup(self.data, self.config, self.data / 'backups')
        for value in ['/', '/var/lib', '/usr/local', str(Path.home())]:
            with self.assertRaises(ValueError): tools.safe_root(value)

    def test_refuses_corrupt_database_and_data_symlinks(self):
        (self.data / 'link').symlink_to(self.config)
        with self.assertRaises(ValueError): self.backup()
        (self.data / 'link').unlink()
        (self.data / 'db/dev.db').write_text('corrupt')
        with self.assertRaises(sqlite3.DatabaseError): self.backup()

    def test_backup_tampering_is_rejected_before_data_change(self):
        archive = self.backup()
        unpacked = self.root / 'unpacked'
        unpacked.mkdir()
        tools.extract(archive, unpacked)
        (unpacked / 'server.env').write_text('tampered')
        with tarfile.open(archive, 'w:gz') as tar:
            for item in unpacked.iterdir(): tar.add(item, arcname=item.name)
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            tools.restore(archive, self.data)
        tools.check_db(self.data)

    def test_archive_traversal_special_files_and_link_parent_are_rejected(self):
        for name, kind, target in [('../escape', tarfile.REGTYPE, ''), ('/escape', tarfile.REGTYPE, ''),
                                   ('root/link', tarfile.SYMTYPE, '../../escape'),
                                   ('root/device', tarfile.CHRTYPE, '')]:
            with self.subTest(name=name):
                archive = self.root / 'malicious.tar.gz'
                with tarfile.open(archive, 'w:gz') as tar:
                    member = tarfile.TarInfo(name); member.type = kind; member.linkname = target; tar.addfile(member)
                with self.assertRaises(ValueError): tools.extract(archive, self.root / 'extract', True)
        archive = self.root / 'link-parent.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            link = tarfile.TarInfo('root/link'); link.type = tarfile.SYMTYPE; link.linkname = 'safe'; tar.addfile(link)
            tar.addfile(tarfile.TarInfo('root/link/overwrite'))
        with self.assertRaisesRegex(ValueError, 'through a link'): tools.extract(archive, self.root / 'extract', True)

    def test_safe_node_module_links_are_allowed_only_for_release_archives(self):
        archive = self.root / 'release.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            member = tarfile.TarInfo('root/server/node_modules/.bin/prisma')
            member.type = tarfile.SYMTYPE; member.linkname = '../prisma/build/index.js'; tar.addfile(member)
        with tarfile.open(archive) as tar: tools.members(tar, True)
        with tarfile.open(archive) as tar:
            with self.assertRaises(ValueError): tools.members(tar, False)

    def test_legacy_migration_failure_leaves_original_fts_and_user_data(self):
        schema = self.root / 'server/prisma/schema.prisma'
        schema.parent.mkdir(parents=True)
        schema.write_text('test schema')
        with sqlite3.connect(self.data / 'db/dev.db') as db:
            db.execute('CREATE VIRTUAL TABLE WebDAVFileSearch USING fts5(value)')
            db.execute("INSERT INTO WebDAVFileSearch VALUES ('indexed')")
        def failed_migration(command, **kwargs):
            self.assertNotIn('--accept-data-loss', command)
            candidate = kwargs['env']['DATABASE_URL'][5:]
            with sqlite3.connect(candidate) as db:
                self.assertIsNone(db.execute("SELECT name FROM sqlite_master WHERE name='WebDAVFileSearch'").fetchone())
            raise subprocess.CalledProcessError(1, command)
        with patch.object(tools.subprocess, 'run', failed_migration):
            with self.assertRaises(subprocess.CalledProcessError): tools.prepare_legacy(self.data, schema, '/fake/node')
        with sqlite3.connect(self.data / 'db/dev.db') as db:
            self.assertEqual(db.execute('select value from WebDAVFileSearch').fetchone()[0], 'indexed')
            self.assertEqual(db.execute('select value from marker').fetchone()[0], 'original')

    def test_legacy_migration_success_commits_checked_copy_and_skips_repeat_sync(self):
        schema = self.root / 'server/prisma/schema.prisma'
        schema.parent.mkdir(parents=True); schema.write_text('test schema')
        def migrate(command, **kwargs):
            with sqlite3.connect(kwargs['env']['DATABASE_URL'][5:]) as db:
                db.execute('ALTER TABLE marker ADD COLUMN migrated TEXT')
        with patch.object(tools.subprocess, 'run', migrate): tools.prepare_legacy(self.data, schema, '/fake/node')
        with sqlite3.connect(self.data / 'db/dev.db') as db:
            self.assertEqual(db.execute('select value,migrated from marker').fetchone(), ('original', None))
        with patch.object(tools.subprocess, 'run') as mocked:
            tools.prepare_legacy(self.data, schema, '/fake/node')
            mocked.assert_not_called()


class Manager(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.deploy = self.root / 'deployment with spaces'
        (self.deploy / 'operations').mkdir(parents=True)
        (self.deploy / 'docker-compose.remote.yml').write_text('services: {}')
        (self.deploy / '.updater.env').write_text('APP_HOST_PORT=19097\nSCRAPEFUN_DATA_DIR=./data with spaces\nUPDATE_CURRENT_TAG=beta\n')
        (self.deploy / 'data with spaces').mkdir()
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.log = self.root / 'commands.jsonl'
        mock = self.bin / 'docker'
        mock.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["COMMAND_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
        mock.chmod(0o755)
        curl = self.bin / 'curl'; curl.write_text('#!/bin/sh\nexit "${CURL_STATUS:-0}"\n'); curl.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.bin) + ':' + os.environ['PATH'], 'COMMAND_LOG': str(self.log)}

    def tearDown(self): self.temporary.cleanup()

    def run_manager(self, *arguments, **env):
        return subprocess.run(['bash', str(DIRECTORY / 'scrapefun.sh'), '--deploy-dir', str(self.deploy), *arguments],
                              env={**self.env, **env}, text=True, capture_output=True, timeout=15)

    def test_lifecycle_quotes_paths_and_start_waits_for_readiness(self):
        for command, expected in [('start', ['up', '-d']), ('stop', ['stop']), ('restart', ['restart', 'app', 'updater'])]:
            result = self.run_manager(command)
            self.assertEqual(result.returncode, 0, result.stderr)
            call = json.loads(self.log.read_text().splitlines()[-1])
            self.assertEqual(call[2], str(self.deploy / '.updater.env'))
            self.assertEqual(call[-len(expected):], expected)
        self.assertIn('19097', self.run_manager('url').stdout)

    def test_readiness_failure_is_failure_and_non_tty_menu_never_waits(self):
        result = self.run_manager('wait-ready', CURL_STATUS='22', SCRAPEFUN_HEALTH_TIMEOUT='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('未就绪', result.stderr)
        result = self.run_manager('menu')
        self.assertEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout)

    def test_status_propagates_health_failure(self):
        self.assertNotEqual(self.run_manager('status', CURL_STATUS='22').returncode, 0)

    def test_local_health_bypasses_proxy(self):
        (self.bin / 'curl').write_text('#!/bin/sh\n[ "$1" = --noproxy ] && [ "$2" = "*" ]\n')
        for command in ('health', 'wait-ready'):
            result = self.run_manager(command, http_proxy='http://127.0.0.1:1', SCRAPEFUN_HEALTH_TIMEOUT='1')
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_update_preserves_beta_channel_and_passes_deploy_directory(self):
        mock = self.deploy / 'operations/one-click-compose-deploy.sh'
        mock.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        result = self.run_manager('update')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['beta', str(self.deploy)])
        self.assertNotEqual(self.run_manager('update', 'other').returncode, 0)


if __name__ == '__main__': unittest.main()
