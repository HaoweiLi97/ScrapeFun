// Executed in an isolated updater container, with only the chosen data root
// mounted writable. Validate the entire merge before adding any missing file.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
function mergeDataRoot(source, target, excluded = new Set(), receipt = null) {
  const additions = [];
  const metadata = [];
  let verifying = false;
  const hash = file => {
    const fd = fs.openSync(file, 'r');
    try {
      const digest = crypto.createHash('sha256'), buffer = Buffer.alloc(1024 * 1024);
      let count;
      while ((count = fs.readSync(fd, buffer, 0, buffer.length, null))) digest.update(buffer.subarray(0, count));
      return digest.digest('hex');
    } finally { fs.closeSync(fd); }
  };
  function inspect(from, to) {
    const info = fs.lstatSync(from);
    if (!info.isDirectory() && !info.isFile()) throw Error('Unsupported data entry: ' + from);
    let existing;
    try { existing = fs.lstatSync(to); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    let digest;
    if (existing && (existing.isSymbolicLink() || existing.isDirectory() !== info.isDirectory()
        || (info.isFile() && (!existing.isFile() || hash(from) !== (digest = hash(to)))))) {
      throw Error('Conflicting persistent data: ' + to);
    }
    if (verifying && receipt && digest) receipt.push({path: path.relative(source, from), sha256: digest});
    if (!existing) additions.push({from, to, info});
    if (from !== source) metadata.push({to, info});
    if (info.isDirectory()) for (const name of fs.readdirSync(from)) {
      if (from === source && excluded.has(name)) continue;
      inspect(path.join(from, name), path.join(to, name));
    }
  }
  for (const {to, info} of metadata) {
    fs.chmodSync(to, info.mode & 0o777);
    fs.chownSync(to, info.uid, info.gid);
  }
  inspect(source, target);
  for (const {from, to, info} of additions) {
    if (info.isDirectory()) {
      fs.mkdirSync(to, {mode: info.mode & 0o777});
      fs.chmodSync(to, info.mode & 0o777);
      fs.chownSync(to, info.uid, info.gid);
    } else {
      const temporary = path.join(path.dirname(to), '.scrapefun-upgrade-' + crypto.randomUUID() + '.tmp');
      try {
        fs.copyFileSync(from, temporary, fs.constants.COPYFILE_EXCL);
        fs.chmodSync(temporary, info.mode & 0o777);
        fs.chownSync(temporary, info.uid, info.gid);
        // Updates are serialized and the old writer is stopped. Never publish
        // a partially copied credential or overwrite a newly appeared file.
        if (fs.existsSync(to)) throw Error('Persistent data changed during migration: ' + to);
        fs.renameSync(temporary, to);
      } finally { fs.rmSync(temporary, {force: true}); }
    }
  }
  // Verify copied bytes too before permitting the old container to be replaced.
  verifying = true;
  inspect(source, target);
  return additions.length;
}
module.exports = {mergeDataRoot};
if (require.main === module || process.argv[1] === '/tmp') {
  const [source, target] = process.argv.slice(require.main === module ? 2 : 1);
  console.log('Verified persistent data merge: ' + mergeDataRoot(source, target));
}
