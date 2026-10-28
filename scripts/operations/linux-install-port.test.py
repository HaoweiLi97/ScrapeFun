#!/usr/bin/env python3
"""Port regression checks; native installs use private mounts and fake services."""
import hashlib
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import select
import shutil
import socket
import subprocess
import tarfile
import tempfile
import termios
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / 'scripts/one-click-native-deploy.sh'
INSTALLER = ROOT / 'scripts/release/install-scrapefun-linux-server.sh'
COMPOSE = ROOT / 'scripts/one-click-compose-deploy.sh'
spec = importlib.util.spec_from_file_location('linux_tools', ROOT / 'scripts/operations/linux-server-tools.py')
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class Arguments(unittest.TestCase):
    def test_truncated_entry_does_not_run_partial_installation(self):
        source = NATIVE.read_text()
        result = subprocess.run(['bash'], input=source[:source.index('source_base=')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_invalid_ports_fail_before_any_installation_work(self):
        for script in (NATIVE, INSTALLER, COMPOSE):
            for port in ('0', '65536', '-1', 'abc', '80:8096', '99999999999999999999', '1\nHOST=x'):
                with self.subTest(script=script.name, port=port):
                    result = subprocess.run(['bash', str(script), '--port', port], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('port must be a number', result.stderr)
            for arguments in (['--port'], ['--port=']):
                result = subprocess.run(['bash', str(script), *arguments], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('--port requires a value', result.stderr)

    def test_help_documents_port_option(self):
        for script in (NATIVE, INSTALLER, COMPOSE):
            result = subprocess.run(['bash', str(script), '--help'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('--port PORT', result.stdout)

    def test_compose_preserves_and_validates_saved_or_explicit_ports(self):
        source = COMPOSE.read_text()
        functions = '\n'.join(re.search(r'^' + name + r'\(\) \{.*?^\}', source, re.M | re.S)[0]
                              for name in ('read_env_value', 'validate_app_host_port', 'resolve_app_host_port'))
        with tempfile.TemporaryDirectory() as directory:
            saved = Path(directory) / '.updater.env'
            saved.write_text('APP_HOST_PORT=19097\n')
            for explicit, expected in (('', '19097'), ('18096', '18096'), ('08096', '8096')):
                code = functions + '\nresolve_app_host_port\nprintf "%s" "$APP_HOST_PORT"\n'
                result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + code], capture_output=True, text=True,
                                        env={**os.environ, 'APP_HOST_PORT': explicit, 'UPDATER_ENV_FILE': str(saved)})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)
            saved.write_text('APP_HOST_PORT=65536\n')
            result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + functions + '\nresolve_app_host_port'],
                                    capture_output=True, text=True,
                                    env={**os.environ, 'APP_HOST_PORT': '', 'UPDATER_ENV_FILE': str(saved)})
            self.assertNotEqual(result.returncode, 0)


class NativeInstallation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.geteuid() != 0 or not shutil.which('unshare'):
            raise unittest.SkipTest('native integration checks require root and mount namespaces')
        check = subprocess.run(['unshare', '--mount', 'true'], capture_output=True)
        if check.returncode:
            raise unittest.SkipTest('mount namespaces are unavailable')

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='scrapefun-port-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config, self.install, self.data = (self.root / name for name in ('config', 'install', 'data'))
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.units = self.root / 'units'
        self.units.mkdir()
        self.log = self.root / 'commands.log'
        self.env = {key: value for key, value in os.environ.items()
                    if key != 'APP_HOST_PORT' and not key.startswith('SCRAPEFUN_')}
        self.env.update(PATH=str(self.bin) + ':' + os.environ['PATH'],
                        SCRAPEFUN_INSTALL_DIR=str(self.install), SCRAPEFUN_DATA_DIR=str(self.data),
                        SCRAPEFUN_CONFIG_DIR=str(self.config), SCRAPEFUN_SERVICE_USER='root',
                        SCRAPEFUN_SERVICE_NAME='scrapefun-port-test.service',
                        SCRAPEFUN_NODE_BINARY=str(self.bin / 'node'),
                        SCRAPEFUN_GPU_MODE='none', COMMAND_LOG=str(self.log), SCRAPEFUN_HEALTH_TIMEOUT='2')
        self.executable('node', '''case "$1" in
  -p) echo 22 ;; --version) echo v22.0.0 ;; -e) printf fixture-generated-secret ;;
  scripts/verify-protected.cjs) exit "${VERIFY_STATUS:-0}" ;;
esac
''')
        self.executable('systemctl', '''printf '%s\\n' "$*" >> "$COMMAND_LOG"
if [[ "$1" == is-active ]]; then exit "${INITIAL_ACTIVE:-1}"; fi
if [[ "$1" == is-enabled ]]; then exit "${INITIAL_ENABLED:-1}"; fi
if [[ "$1" == start && -f "$SCRAPEFUN_CONFIG_DIR/server.env" ]]; then
  grep '^PORT=' "$SCRAPEFUN_CONFIG_DIR/server.env" >> "$COMMAND_LOG"
  if [[ "${SIGNAL_ON_START:-0}" == 1 && ! -f "$SCRAPEFUN_CONFIG_DIR/signalled" ]]; then
    touch "$SCRAPEFUN_CONFIG_DIR/signalled"
    kill -TERM "$PPID"
  fi
fi
''')
        self.executable('curl', 'printf "%s\\n" "$*" >> "$COMMAND_LOG"\n')
        for command in ('ffmpeg', 'ffprobe', 'usermod'):
            self.executable(command, 'exit 0\n')
        self.executable('getent', 'exit 1\n')  # Do not modify host group membership.
        release = self.root / 'source/release'
        (release / 'server/dist/pro-runtime').mkdir(parents=True)
        (release / 'client/dist').mkdir(parents=True)
        (release / 'start.sh').write_text('# fixture\n')
        (release / 'server/dist/index.js').write_text('// fixture\n')
        (release / 'RELEASE.json').write_text(json.dumps({'architecture': 'amd64', 'channel': 'stable', 'version': '0.4.2'}))
        self.archive = self.root / 'release.tar.gz'
        with tarfile.open(self.archive, 'w:gz') as archive:
            archive.add(release, arcname='release')
        Path(str(self.archive) + '.sha256').write_text(hashlib.sha256(self.archive.read_bytes()).hexdigest() + '\n')
        self.env['SCRAPEFUN_NATIVE_ARCHIVE'] = str(self.archive)

    def executable(self, name, content):
        script = self.bin / name
        script.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + content)
        script.chmod(0o755)

    def command(self, *arguments, entry=False):
        # Only the namespace sees the disposable unit directory. Real systemd
        # never receives any requests; all other install operations stay in /tmp.
        return ['unshare', '--mount', '--propagation', 'private', 'bash', '-c',
                'mount --bind "$1" /etc/systemd/system; shift; exec "$@"', 'fixture', str(self.units),
                'bash', str(NATIVE if entry else INSTALLER), *([] if entry else [str(self.archive)]), *arguments]

    def run_install(self, *arguments, entry=False, **environment):
        return subprocess.run(self.command(*arguments, entry=entry), capture_output=True, text=True,
                              env={**self.env, **environment}, timeout=30)

    def assert_success(self, result, port):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'PORT={port}\n', (self.config / 'server.env').read_text())
        self.assertIn(f'PORT={port}\n', (self.config / 'management.env').read_text())
        self.assertIn(f'127.0.0.1:{port}', result.stdout)
        self.assertIn(f'127.0.0.1:{port}/health/ready', self.log.read_text())

    def test_default_and_environment_ports_through_one_click_entry(self):
        self.assert_success(self.run_install(entry=True), 8096)
        self.assert_success(self.run_install(entry=True, APP_HOST_PORT='18096'), 18096)

    def test_cli_overrides_environment_and_update_keeps_port_and_secret(self):
        self.assert_success(self.run_install('stable', '--port', '18096', entry=True, APP_HOST_PORT='19096'), 18096)
        original = (self.config / 'server.env').read_text()
        self.assert_success(self.run_install(entry=True), 18096)
        self.assertEqual((self.config / 'server.env').read_text(), original)
        self.assert_success(self.run_install('--port=28096'), 28096)
        self.assertIn('APP_AUTH_SECRET=fixture-generated-secret\n', (self.config / 'server.env').read_text())
        with tarfile.open(next((self.config / 'backups').glob('*.tar.gz'))) as backup:
            self.assertIn('PORT=18096\n', backup.extractfile('server.env').read().decode())

    def test_failed_port_change_restores_configuration_and_service(self):
        self.assert_success(self.run_install('--port', '18096'), 18096)
        (self.install / 'old-marker').write_text('old installation')
        (self.config / 'operations/old-marker').write_text('old management tools')
        with (self.config / 'scrapefun').open('a') as entry: entry.write('\n# old management marker\n')
        old_entry = (self.config / 'scrapefun').read_bytes()
        original = (self.config / 'server.env').read_bytes()
        management = (self.config / 'management.env').read_bytes()
        unit = (self.units / 'scrapefun-port-test.service').read_bytes()
        result = self.run_install('--port', '28096', SCRAPEFUN_HEALTH_TIMEOUT='0', INITIAL_ACTIVE='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.config / 'server.env').read_bytes(), original)
        self.assertEqual((self.config / 'management.env').read_bytes(), management)
        self.assertEqual((self.units / 'scrapefun-port-test.service').read_bytes(), unit)
        self.assertTrue((self.install / 'old-marker').is_file())
        self.assertTrue((self.config / 'operations/old-marker').is_file())
        self.assertEqual((self.config / 'scrapefun').read_bytes(), old_entry)
        self.assertEqual(self.log.read_text().splitlines()[-1], 'PORT=18096')

    def test_invalid_update_leaves_configuration_and_service_untouched(self):
        self.assert_success(self.run_install('--port', '18096'), 18096)
        original = (self.config / 'server.env').read_bytes()
        commands = self.log.read_bytes()
        result = self.run_install('--port', '65536')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.config / 'server.env').read_bytes(), original)
        self.assertEqual(self.log.read_bytes(), commands)

    def test_existing_config_without_port_and_without_final_newline(self):
        self.config.mkdir()
        (self.config / 'server.env').write_text('APP_AUTH_SECRET=existing-secret')
        self.assert_success(self.run_install('--port', '08096'), 8096)
        self.assertEqual((self.config / 'server.env').read_text(), 'APP_AUTH_SECRET=existing-secret\nPORT=8096\n')

    def test_check_only_leaves_installation_and_service_untouched(self):
        result = self.run_install('--check', '--install-deps', entry=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.install.exists())
        self.assertFalse(self.data.exists())
        self.assertNotIn('stop ', self.log.read_text())
        self.assertNotIn('start ', self.log.read_text())

    def test_unsupported_libc_and_architecture_fail_before_installation(self):
        self.executable('getconf', 'echo musl\n')
        result = self.run_install('--check', entry=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('glibc Linux', result.stderr)
        self.executable('uname', 'if [[ "$1" == -s ]]; then echo Linux; else echo aarch64; fi\n')
        result = self.run_install('--check', entry=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Linux amd64', result.stderr)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.log.exists())

    def test_download_failure_preserves_the_existing_service(self):
        self.env.pop('SCRAPEFUN_NATIVE_ARCHIVE')
        self.executable('curl', 'exit 22\n')
        result = self.run_install(entry=True, INITIAL_ACTIVE='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('download failed', result.stderr)
        self.assertFalse(self.config.exists())
        self.assertNotIn('stop ', self.log.read_text())

    def test_missing_native_libraries_fail_before_stopping_service(self):
        release = self.root / 'source/release'
        (release / 'server/dist/pro-runtime/invalid.node').write_text('invalid ELF fixture')
        with tarfile.open(self.archive, 'w:gz') as archive: archive.add(release, arcname='release')
        Path(str(self.archive) + '.sha256').write_text(hashlib.sha256(self.archive.read_bytes()).hexdigest() + '\n')
        result = self.run_install(INITIAL_ACTIVE='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('incompatible native runtime libraries', result.stderr)
        self.assertNotIn('stop ', self.log.read_text())

    def test_low_port_grants_only_the_bind_capability(self):
        self.assert_success(self.run_install('--port', '1023'), 1023)
        unit = (self.units / 'scrapefun-port-test.service').read_text()
        self.assertIn('User=root\n', unit)  # Test fixture identity; production defaults to scrapefun.
        self.assertIn('AmbientCapabilities=CAP_NET_BIND_SERVICE\n', unit)
        self.assertIn('CapabilityBoundingSet=CAP_NET_BIND_SERVICE\n', unit)

    def test_occupied_port_does_not_stop_an_existing_service(self):
        with socket.socket() as listener:
            listener.bind(('0.0.0.0', 0))
            listener.listen()
            result = self.run_install('--port', str(listener.getsockname()[1]), INITIAL_ACTIVE='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unavailable', result.stderr)
        self.assertNotIn('stop ', self.log.read_text())
        self.assertNotIn('start ', self.log.read_text())

    def test_lock_blocks_concurrent_installs_before_service_changes(self):
        self.config.mkdir()
        with (self.config / '.operations.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('another native operation', result.stderr)
        self.assertFalse(self.log.exists())

    def test_checksum_and_protected_verification_fail_without_stopping_service(self):
        for environment in ({'VERIFY_STATUS': '1'}, {}):
            with self.subTest(environment=environment):
                if not environment: self.archive.write_bytes(b'corrupted archive')
                self.log.unlink(missing_ok=True)
                result = self.run_install(INITIAL_ACTIVE='0', **environment)
                self.assertNotEqual(result.returncode, 0)
                commands = self.log.read_text() if self.log.exists() else ''
                self.assertNotIn('stop ', commands)
                self.assertNotIn('start ', commands)
                self.assertFalse((self.config / 'server.env').exists())

    def test_signal_during_activation_rolls_back_port_and_restarts_old_service(self):
        self.assert_success(self.run_install('--port', '18096'), 18096)
        original = (self.config / 'server.env').read_bytes()
        result = self.run_install('--port', '28096', INITIAL_ACTIVE='0', SIGNAL_ON_START='1')
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assertEqual((self.config / 'server.env').read_bytes(), original)
        self.assertEqual(self.log.read_text().splitlines()[-1], 'PORT=18096')

    def test_failed_data_rollback_preserves_recovery_files_without_restarting(self):
        self.assert_success(self.run_install('--port', '18096'), 18096)
        custom = self.root / 'custom-operations'
        custom.mkdir()
        shutil.copy(ROOT / 'scripts/operations/scrapefun.sh', custom / 'scrapefun.sh')
        (custom / 'linux-server-tools.py').write_text(
            'import os, sys\n'
            'if sys.argv[1] == "restore": sys.exit(1)\n'
            f'os.execv(sys.executable, [sys.executable, {str(ROOT / "scripts/operations/linux-server-tools.py")!r}, *sys.argv[1:]])\n')
        self.log.write_text('')
        result = self.run_install('--port', '28096', SCRAPEFUN_OPERATION_SOURCE=str(custom),
                                  INITIAL_ACTIVE='0', SCRAPEFUN_HEALTH_TIMEOUT='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('自动数据回退失败', result.stderr)
        self.assertIn('恢复资料保留在', result.stderr)
        self.assertNotIn('PORT=18096', self.log.read_text())
        self.assertTrue(list(self.root.glob('.scrapefun-install.*/old-server.env')))

    def test_failed_first_install_removes_unit_configuration_and_autostart(self):
        result = self.run_install(SCRAPEFUN_HEALTH_TIMEOUT='0')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.config / 'server.env').exists())
        self.assertFalse((self.config / 'management.env').exists())
        self.assertFalse((self.units / 'scrapefun-port-test.service').exists())
        self.assertIn('disable scrapefun-port-test.service', self.log.read_text())

    def test_selected_version_is_verified_against_offline_manifest(self):
        self.assert_success(self.run_install('--version', '0.4.2', entry=True), 8096)
        self.log.write_text('')
        result = self.run_install('--version', '0.4.1', entry=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('archive version differs', result.stderr)
        self.assertNotIn('stop ', self.log.read_text())

    def test_saved_paths_and_gpu_environment_are_reused(self):
        self.assert_success(self.run_install('--port', '18096'), 18096)
        saved_gpu = self.config / 'gpu.env'
        saved_gpu.write_text('CUSTOM_GPU_SETTING=retained\n')
        # A caller only needs to identify the existing config directory.
        for name in ('SCRAPEFUN_INSTALL_DIR', 'SCRAPEFUN_DATA_DIR', 'SCRAPEFUN_SERVICE_NAME',
                     'SCRAPEFUN_SERVICE_USER', 'SCRAPEFUN_NODE_BINARY', 'SCRAPEFUN_GPU_MODE'):
            self.env.pop(name, None)
        self.assert_success(self.run_install(entry=True), 18096)
        self.assertEqual(saved_gpu.read_text(), 'CUSTOM_GPU_SETTING=retained\n')

    def test_install_deps_uses_an_isolated_verified_node_and_reuses_it(self):
        self.env.pop('SCRAPEFUN_NODE_BINARY')
        self.executable('node', 'if [[ "$1" == -p ]]; then echo 25; else echo v25.0.0; fi\n')
        fixtures = self.root / 'node-downloads'
        node = fixtures / 'node-v22.99.0-linux-x64/bin/node'
        node.parent.mkdir(parents=True)
        node.write_text('#!/usr/bin/env bash\ncase "$1" in -p) echo 22 ;; --version) echo v22.99.0 ;; -e) printf isolated-secret ;; esac\n')
        node.chmod(0o755)
        with tarfile.open(fixtures / 'node.tar.gz', 'w:gz') as archive:
            archive.add(node.parent.parent, arcname='node-v22.99.0-linux-x64')
        checksum = hashlib.sha256((fixtures / 'node.tar.gz').read_bytes()).hexdigest()
        (fixtures / 'checksums').write_text(checksum + '  node-v22.99.0-linux-x64.tar.gz\n')
        (fixtures / 'index.json').write_text(json.dumps([{'version': 'v22.99.0', 'files': ['linux-x64']}]))
        self.env['NODE_FIXTURES'] = str(fixtures)
        self.executable('curl', '''printf '%s\\n' "$*" >> "$COMMAND_LOG"
target='' url=''
while [[ $# -gt 0 ]]; do
  case "$1" in -o) target="$2"; shift 2 ;; https://*|http://*) url="$1"; shift ;; *) shift ;; esac
done
case "$url" in
  https://nodejs.org/dist/index.json) cp "$NODE_FIXTURES/index.json" "$target" ;;
  */SHASUMS256.txt) cp "$NODE_FIXTURES/checksums" "$target" ;;
  https://nodejs.org/*.tar.gz) cp "$NODE_FIXTURES/node.tar.gz" "$target" ;;
esac
''')
        self.assert_success(self.run_install('--install-deps', entry=True), 8096)
        runtime = self.config / 'runtime/node-v22.99.0-linux-x64/bin/node'
        self.assertTrue(runtime.is_file())
        self.assertEqual(runtime.stat().st_uid, 0)
        self.assertEqual(runtime.stat().st_mode & 0o022, 0)
        self.assertIn(f'NODE_BIN={runtime}\n', (self.config / 'management.env').read_text())
        downloads = self.log.read_text().count('https://nodejs.org/')
        self.assert_success(self.run_install('--install-deps', entry=True), 8096)
        self.assertEqual(self.log.read_text().count('https://nodejs.org/'), downloads)
        self.assertIn('echo 25', (self.bin / 'node').read_text())

    def test_base_dependencies_use_native_package_manager_without_system_upgrade(self):
        for manager, user_package in (('apt-get', 'passwd'), ('dnf', 'shadow-utils'), ('yum', 'shadow-utils'),
                                      ('zypper', 'shadow'), ('pacman', 'shadow')):
            with self.subTest(manager=manager):
                binaries = self.root / manager
                binaries.mkdir()
                for name in ('bash', 'env', 'unshare', 'mount', 'dirname', 'sed', 'tail', 'awk', 'uname', 'getconf', 'mkdir', 'mv',
                             'cp', 'cat', 'rm', 'readlink', 'realpath', 'mktemp', 'python3', 'sha256sum', 'tar', 'gzip',
                             'runuser', 'install', 'id', 'chown', 'find', 'chmod', 'date', 'grep', 'hostname'):
                    (binaries / name).symlink_to(shutil.which(name))
                for name in ('node', 'systemctl', 'curl', 'ffmpeg', 'getent', 'usermod'):
                    (binaries / name).symlink_to(self.bin / name)
                package_log = binaries / 'packages.log'
                installer = binaries / manager
                installer.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$PACKAGE_LOG"
if [[ "$*" == *install* || "$*" == *'-S '* ]]; then
  ln -sf /usr/bin/flock "$TARGET_BIN/flock"
  ln -sf /usr/sbin/useradd "$TARGET_BIN/useradd"
  ln -sf "$FIXTURE_BIN/ffprobe" "$TARGET_BIN/ffprobe"
fi
''')
                # ln is only used by the fake package manager and never touches the host.
                (binaries / 'ln').symlink_to(shutil.which('ln'))
                installer.chmod(0o755)
                check = self.run_install('--check', '--install-deps', entry=True, PATH=str(binaries),
                                         PACKAGE_LOG=str(package_log), TARGET_BIN=str(binaries), FIXTURE_BIN=str(self.bin))
                self.assertNotEqual(check.returncode, 0)
                self.assertIn('missing commands', check.stderr)
                self.assertFalse(package_log.exists())
                result = self.run_install('--install-deps', entry=True, PATH=str(binaries),
                                          PACKAGE_LOG=str(package_log), TARGET_BIN=str(binaries), FIXTURE_BIN=str(self.bin))
                self.assert_success(result, 8096)
                commands = package_log.read_text()
                self.assertIn('ffmpeg', commands)
                self.assertIn('util-linux', commands)
                self.assertIn(user_package, commands)
                self.assertNotIn('upgrade', commands)

    def test_terminal_prompt_reads_from_tty_even_with_piped_stdin(self):
        master, slave = os.openpty()
        def terminal():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        process = subprocess.Popen(self.command(entry=True), stdin=subprocess.PIPE, stdout=slave, stderr=slave,
                                   env=self.env, preexec_fn=terminal, pass_fds=(slave,))
        os.close(slave)
        self.addCleanup(os.close, master)
        output = b''
        prompt_count = 0
        deadline = time.monotonic() + 25
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.2)[0]:
                    try: chunk = os.read(master, 65536)
                    except OSError: break
                    if not chunk: break
                    output += chunk
                    count = output.count('服务端端口 [8096]:'.encode())
                    if count > prompt_count:
                        os.write(master, b'65536\n' if prompt_count == 0 else b'18096\n')
                        prompt_count = count
                if process.poll() is not None: break
            process.wait(timeout=2)
            self.assertEqual(process.returncode, 0, output.decode())
            self.assertEqual(prompt_count, 2, output.decode())
            self.assertIn('PORT=18096\n', (self.config / 'server.env').read_text())
        finally:
            if process.poll() is None: process.kill(); process.wait()
            process.stdin.close()


class Preflight(unittest.TestCase):
    def test_paths_reject_nested_locations_and_configuration_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'separate'):
                tools.deployment_paths(str(root / 'install'), str(root / 'install/data'), str(root / 'config'))
            config = root / 'config'
            config.mkdir()
            (config / 'server.env').symlink_to(root / 'elsewhere')
            with self.assertRaisesRegex(ValueError, 'regular file'):
                tools.deployment_paths(str(root / 'install'), str(root / 'data'), str(config))

    def test_backup_and_extraction_refuse_insufficient_space_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(tools.shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(1, 1, 0)):
                with self.assertRaisesRegex(ValueError, 'backup disk space'):
                    tools.backup_space(root / 'data', root / 'config')
                archive = root / 'empty.tar.gz'
                with tarfile.open(archive, 'w:gz'): pass
                with self.assertRaisesRegex(ValueError, 'disk space for extraction'):
                    tools.extract(archive, root / 'extract')
            self.assertFalse((root / 'extract').exists())


if __name__ == '__main__':
    unittest.main()
