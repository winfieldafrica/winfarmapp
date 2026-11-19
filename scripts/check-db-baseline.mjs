// Verifies database/ still matches the supplied winfield-database/ baseline byte-for-byte.
// Manifest: infra/database-baseline.sha256 (kept outside database/ so database/ itself is never edited).
// New files are allowed only as forward migrations (database/NNN_*.sql with NNN >= 007) or new test files.
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const dbDir = join(root, 'database');
const manifest = readFileSync(join(root, 'infra/database-baseline.sha256'), 'utf8')
  .trim()
  .split('\n')
  .map((line) => {
    const [hash, path] = line.split(/\s+/);
    return { hash, path: path.replace(/^\.\//, '') };
  });

const walk = (dir) =>
  readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : [relative(dbDir, p)];
  });

const errors = [];
for (const { hash, path } of manifest) {
  let actual;
  try {
    actual = createHash('sha256')
      .update(readFileSync(join(dbDir, path)))
      .digest('hex');
  } catch {
    errors.push(`missing baseline file: database/${path}`);
    continue;
  }
  if (actual !== hash) errors.push(`modified baseline file: database/${path}`);
}

const known = new Set(manifest.map((m) => m.path));
for (const path of walk(dbDir)) {
  if (known.has(path)) continue;
  const m = /^(\d{3})_[a-z0-9_]+\.sql$/.exec(path);
  const isForwardMigration = m && Number(m[1]) >= 7;
  const isNewTestFile = path.startsWith('tests/');
  if (!isForwardMigration && !isNewTestFile) errors.push(`unexpected file in database/: ${path}`);
}

if (errors.length) {
  console.error(errors.join('\n'));
  console.error('database/ baseline check FAILED. Never edit 001-006; add a new 007+ migration instead.');
  process.exit(1);
}
console.log(`database/ baseline OK (${manifest.length} files match).`);
