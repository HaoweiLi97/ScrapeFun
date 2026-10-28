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
import unittest
from unittest.mock import patch

DIRECTORY = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('tools', DIRECTORY / 'linux-server-tools.py')
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


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

    def test_update_preserves_beta_channel_and_passes_deploy_directory(self):
        mock = self.deploy / 'operations/one-click-compose-deploy.sh'
        mock.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        result = self.run_manager('update')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['beta', str(self.deploy)])
        self.assertNotEqual(self.run_manager('update', 'other').returncode, 0)


if __name__ == '__main__': unittest.main()
