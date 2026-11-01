const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

function planUpgrade(config, current, app, updater, image) {
  const service = config.services?.[app];
  if (!service) throw Error('Application service is missing from Compose');
  const mounts = current?.Mounts || [];
  const root = mounts.find(m => m.Destination === '/app/data');
  let target;
  if (!root && current) {
    const database = mounts.find(m => m.Type === 'bind' && m.Destination === '/app/data/db');
    if (!database || path.posix.basename(database.Source) !== 'db') {
      throw Error('Cannot infer the legacy persistent data root; run the current one-click installer with its data migration option before updating.');
    }
    target = path.posix.dirname(database.Source);
    if (!path.posix.isAbsolute(target) || target === '/' || target.includes(':')) throw Error('Invalid legacy data root');
  }
  const overlay = {services: {}};
  if (target) overlay.services[app] = {volumes: [{type: 'bind', source: target.replaceAll('$', '$$'), target: '/app/data'}]};
  if (config.services?.[updater]) overlay.services[updater] = {
    image: '${SCRAPETAB_UPDATER_IMAGE:-' + image + '}',
    command: ['node', '/app/updater/server.cjs'],
    environment: {UPDATER_HEALTHCHECK_URL: `http://${app}:${service.environment?.PORT || 8096}/health/ready`}
  };
  return {target, overlay};
}
module.exports = {planUpgrade};

if (require.main === module) {
  const [configFile, container, app, updater, image, overlayFile, stateFile] = process.argv.slice(2);
  function docker(args, options = {}) {
    const result = spawnSync('docker', args, {encoding: 'utf8', ...options});
    if (result.error || result.status !== 0) throw Error('Docker upgrade preparation failed: ' + args[0] + ': ' + (result.error?.message || result.stderr));
    return String(result.stdout || '').trim();
  }
  const current = container ? JSON.parse(docker(['inspect', '--format', '{{json .}}', container])) : null;
  const plan = planUpgrade(JSON.parse(fs.readFileSync(configFile, 'utf8')), current, app, updater, image);
  let helper, archive, inspectionImage, stopped = false, prepared = false;
  try {
    if (plan.target) {
      const mergeScript = fs.readFileSync(path.join(__dirname, 'migrate-data-root.cjs'), 'utf8');
      // There is no host project-path assumption here: Docker copies from the
      // stopped old container into a temporary helper through its API.
      if (current.State?.Running) { docker(['stop', '--time', '60', container]); stopped = true; }
      // A stopped container cannot exec. Its writable-layer snapshot excludes
      // mounted databases/images, so listing it does not read those datasets.
      inspectionImage = docker(['commit', container]);
      const names = JSON.parse(docker(['run', '--rm', '--network', 'none', '--read-only', '--entrypoint', 'node', inspectionImage,
        '-e', 'console.log(JSON.stringify(require("node:fs").readdirSync("/app/data")))']));
      if (!Array.isArray(names) || names.some(name => typeof name !== 'string' || !name || name === '.' || name === '..' || name.includes('/'))) throw Error('Invalid legacy data inventory');
      const persisted = new Set(current.Mounts.map(m => m.Destination));
      const missing = names.filter(name => !persisted.has('/app/data/' + name));
      helper = docker(['create', '--network', 'none', '--entrypoint', 'node', '--volume', `${plan.target}:/upgrade-target`, image,
        '-e', mergeScript, '/tmp', '/upgrade-target']);
      archive = configFile + '.data.tar';
      for (const name of missing) {
        const fd = fs.openSync(archive, 'wx', 0o600);
        try { docker(['cp', '-a', `${container}:/app/data/${name}`, '-'], {encoding: undefined, stdio: ['ignore', fd, 'pipe']}); }
        finally { fs.closeSync(fd); }
        const input = fs.openSync(archive, 'r');
        try { docker(['cp', '-a', '-', `${helper}:/tmp`], {encoding: undefined, stdio: [input, 'ignore', 'pipe']}); }
        finally { fs.closeSync(input); }
        fs.rmSync(archive);
      }
      docker(['start', '--attach', helper]);
      const exit = docker(['inspect', '--format', '{{.State.ExitCode}}', helper]);
      if (exit !== '0') throw Error('Persistent data merge did not complete');
    }
    let overlay = plan.overlay;
    if (fs.existsSync(overlayFile)) {
      const previous = JSON.parse(fs.readFileSync(overlayFile, 'utf8'));
      // Preserve a root mount added by an earlier successful upgrade.
      if (!plan.target && previous.services?.[app]) overlay.services[app] = previous.services[app];
    }
    const temporary = overlayFile + '.' + process.pid + '.tmp';
    if (plan.target && stateFile) {
      if (/[\r\n]/.test(plan.target)) throw Error('Invalid persistent data path');
      const line = "SCRAPEFUN_DATA_DIR='" + plan.target.replaceAll("'", "\\'") + "'";
      const old = fs.readFileSync(stateFile, 'utf8');
      const next = /^SCRAPEFUN_DATA_DIR=/m.test(old) ? old.replace(/^SCRAPEFUN_DATA_DIR=.*$/gm, () => line) : old.replace(/\n?$/, '\n') + line + '\n';
      fs.writeFileSync(stateFile, next, {mode: 0o600});
    }
    fs.writeFileSync(temporary, JSON.stringify(overlay, null, 2) + '\n', {mode: 0o600});
    fs.renameSync(temporary, overlayFile);
    prepared = true;
    console.log(plan.target ? 'Legacy data root migrated and verified.' : 'Compose upgrade contract verified.');
  } finally {
    if (helper) { try { docker(['rm', '-f', helper]); } catch (error) { console.error(error.message); } }
    if (inspectionImage) { try { docker(['image', 'rm', inspectionImage]); } catch (error) { console.error(error.message); } }
    if (archive) fs.rmSync(archive, {force: true});
    if (stopped && !prepared) docker(['start', container]);
  }
}
