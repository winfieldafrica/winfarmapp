// `pnpm dev`: builds shared packages, then runs api, worker and ingest (tsc --watch + node --watch)
// and the console (next dev). Reads .env if present. Infrastructure comes from `docker compose up -d`.
import { spawn, spawnSync } from 'node:child_process';

const run = (cmd, args, opts = {}) => {
  const r = spawnSync(cmd, args, { stdio: 'inherit', ...opts });
  if (r.status !== 0) process.exit(r.status ?? 1);
};

run('pnpm', ['--filter', './packages/*', 'run', 'build']);
const children = [];
const start = (name, cmd, args, cwd) => {
  const child = spawn(cmd, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
  const prefix = (chunk) =>
    chunk
      .toString()
      .split('\n')
      .filter(Boolean)
      .map((l) => `[${name}] ${l}`)
      .join('\n') + '\n';
  child.stdout.on('data', (c) => process.stdout.write(prefix(c)));
  child.stderr.on('data', (c) => process.stderr.write(prefix(c)));
  children.push(child);
};

for (const svc of ['api', 'worker', 'ingest']) {
  const cwd = `apps/${svc}`;
  run('pnpm', ['exec', 'tsc', '-p', 'tsconfig.json'], { cwd });
  start(
    `${svc}:tsc`,
    'pnpm',
    ['exec', 'tsc', '-p', 'tsconfig.json', '--watch', '--preserveWatchOutput'],
    cwd,
  );
  start(svc, 'node', ['--env-file-if-exists=../../.env', '--watch', 'dist/main.js'], cwd);
}
start('console', 'pnpm', ['run', 'dev'], 'apps/console');

const stop = () => {
  for (const c of children) c.kill('SIGTERM');
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
