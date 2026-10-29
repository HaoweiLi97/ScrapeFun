#!/usr/bin/env python3
"""Root-owned systemd worker for the native server's file-based update bridge."""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import tempfile


def now():
    return datetime.now(timezone.utc).isoformat()


def trusted(path):
    """Never execute code/configuration writable by the application account."""
    path = Path(path)
    for item in (path, *path.parents):
        info = item.lstat()
        if stat.S_ISLNK(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            # /tmp is allowed as an ancestor for isolated installer tests, but
            # the deployment itself and every non-sticky ancestor stay private.
            if item != path and stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and info.st_mode & stat.S_ISVTX:
                continue
            raise ValueError('Unsafe updater path: ' + str(item))
    return path


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.write('\n')
            os.fchmod(stream.fileno(), 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_record(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > 4096:
            raise ValueError('Invalid updater record')
        value = json.loads(stream.read(4097))
    if not isinstance(value, dict):
        raise ValueError('Invalid updater record')
    return value


def maintenance_active(directory):
    if not directory.exists():
        return False
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('Invalid maintenance directory')
    for file in directory.iterdir():
        try:
            pid = read_record(file).get('pid')
            if type(pid) is not int or pid <= 0:
                return True
            try:
                os.kill(pid, 0)
                return True
            except ProcessLookupError:
                pass
        except FileNotFoundError:
            pass
    return False


def run(config):
    config = trusted(config)
    state = trusted(config / 'updater')
    inbox = state / 'requests'
    if inbox.is_symlink() or not inbox.is_dir():
        raise ValueError('Invalid updater inbox')
    request_file = inbox / 'request.json'
    status_file = state / 'status.json'
    install_lock = inbox / 'desktop-update-install.lock'
    with open(state / 'worker.lock', 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if not os.path.lexists(request_file):
            return
        status = dict(available=True, status='running', running=True, progress=None,
                      stage='installing', message='Updating the Linux server.', startedAt=now(),
                      finishedAt=None, targetVersion=None, logFile=str(state / 'update.log'))
        child = None
        interrupted = False

        def stop(_signum, _frame):
            nonlocal interrupted
            interrupted = True
            if child is not None and child.poll() is None:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

        previous_signals = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
        try:
            request = read_record(request_file)
            if (request.get('action') != 'apply' or request.get('channel') not in ('stable', 'beta')
                    or not re.fullmatch(r'[A-Za-z0-9-]{1,80}', str(request.get('requestId', '')))):
                raise ValueError('Invalid native update request')
            status['requestId'] = request['requestId']
            try:
                previous = read_record(status_file)
            except FileNotFoundError:
                previous = {}
            if previous.get('requestId') == request['requestId']:
                if previous.get('status') == 'running':
                    raise ValueError('The previous native update was interrupted. Check the server before retrying.')
                if previous.get('status') in ('succeeded', 'failed'):
                    status = previous
                    return  # Receipt was saved before a worker crash; do not install twice.
            # Publish the lock before checking Web backup/restore activity.
            atomic_json(install_lock, {'pid': os.getpid()})
            if maintenance_active(inbox / 'desktop-maintenance'):
                raise ValueError('Backup or restore is running. Retry the update when it finishes.')
            atomic_json(status_file, status)
            # No request field can choose a command, URL, archive, environment or path.
            command = trusted(config / 'operations/one-click-native-deploy.sh')
            with open(state / 'update.log', 'w') as log:
                os.chmod(state / 'update.log', 0o600)
                if interrupted:
                    raise ValueError('Native update interrupted')
                child = subprocess.Popen(['/bin/bash', str(command), request['channel'],
                                          '--config-dir', str(config), '--non-interactive'],
                                         env={'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                                              'LANG': 'C.UTF-8'},
                                         stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                if interrupted:
                    stop(signal.SIGTERM, None)
                result = child.wait()
            if result or interrupted:
                raise ValueError('Native update failed. See the updater log; the installer attempted to restore the previous installation.')
            settings = dict(line.split('=', 1) for line in (config / 'management.env').read_text().splitlines() if '=' in line)
            release = json.loads((Path(settings['INSTALL_DIR']) / 'RELEASE.json').read_text())
            status.update(status='succeeded', stage='complete', targetVersion=release.get('version'),
                          message='Linux server updated successfully.')
        except Exception as error:
            status.update(status='failed', stage='failed', message=str(error))
        finally:
            status.update(running=False, progress=100, finishedAt=now())
            atomic_json(status_file, status)
            # Leave the request present until status is final, preventing a
            # second API request from overtaking a running installation.
            request_file.unlink(missing_ok=True)
            install_lock.unlink(missing_ok=True)
            for sig, handler in previous_signals.items():
                signal.signal(sig, handler)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config-dir', required=True, type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Native updater requires root')
    run(args.config_dir)
