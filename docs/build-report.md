# Build report

Evidence for each milestone. Only results that were actually run and observed are recorded here.

## M0: Monorepo scaffold

**Status: built; acceptance partly verified. Not done: S3 store in compose, CI run on GitHub (see below).**

### Built

- pnpm workspace with the addendum §B layout: `apps/{api,worker,ingest,console,mobile}`, `packages/{shared,rules}`,
  `database/` (baseline, unmodified), `infra/`, `docs/`.
- TypeScript strict (`strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`), ESLint (typescript-eslint strict),
  Prettier. Purity rules for `packages/rules`.
- `/health` on all four services: api (NestJS + Fastify), ingest (Fastify), worker (node:http), console (Next.js route).
- `compose.yaml`: Postgres 16.16 and Redis 7.4.12, digest-pinned, healthchecks, bound to 127.0.0.1.
- `.env.example`: every setup guide Part 6.3 secret name with dummy values, plus documented non-secret names.
- Root scripts from setup guide Part 4: `dev`, `test` work; `db:migrate`, `db:test`, `e2e`, `bootstrap:admin` are
  stubs that exit 1. Plus `lint`, `typecheck`, `build`, `format`, `check:db-baseline`.
- CI: `.github/workflows/ci.yml` (install, baseline check, lint, typecheck, test, audit; compose + live health),
  `.github/workflows/security.yml` (gitleaks, Semgrep OSS, weekly schedule), `.github/dependabot.yml`.

### Ran (local, 2026-11-19, Node 22.23.5, pnpm 10.28.0, Docker 29.10.0)

| Command | Result |
|---|---|
| `pnpm install` | 645 packages; no install scripts declared by any dependency |
| `pnpm lint` | ESLint 0 problems; Prettier "All matched files use Prettier code style!" |
| `pnpm typecheck` | 7 workspace projects, 0 errors |
| `pnpm test` | 5 files, **9/9 tests passed** |
| `pnpm check:db-baseline` | "database/ baseline OK (9 files match)"; tamper test (appended a line to 002 + added a stray file) → exit 1 naming both; restored → OK |
| `docker compose up -d` | postgres and redis both **healthy**; `select version()` → PostgreSQL 16.16; `redis-cli ping` → PONG |
| `pnpm dev` + curl `/health` | api :4000, ingest :4100, worker :4200, console :3000 all HTTP 200 `{"status":"ok",...}` |
| `database/run_all.sh` against compose Postgres (informational; wired in M1) | **99/99 passed** |
| `pnpm audit --audit-level high` | exit 0; 1 moderate (minimatch via expo) |
| `pnpm db:migrate`, `db:test`, `e2e`, `bootstrap:admin` | each prints "not implemented yet (arrives in Mx)" and exits 1, as intended |
| gitleaks 8.30.1 `git` mode (history) | no leaks |
| gitleaks `dir` mode (working tree) | 4 hits, all in `apps/console/.next/` (Next dev cache, gitignored, never committed) |
| Semgrep OSS 1.186.0 | **could not run locally**: `semgrep.dev` (rule registry) is blocked by this environment's proxy. Runs in CI. |

### CI on GitHub (PR #1)

First run, head `6bf8e47`:

| Job | Result |
|---|---|
| install, baseline, lint, typecheck, test, audit | success |
| docker compose up + /health on every service | success |
| secret scan (gitleaks) | success |
| SAST (Semgrep OSS) | **failure**: 7 blocking findings, all missing supply-chain settings (pnpm `minimumReleaseAge`, `trustPolicy`, `blockExoticSubdeps`; npm `min-release-age`; Dependabot `cooldown` ×3) |

Fix: settings added (assumptions T15); the lockfile was re-resolved under them (0 of 708 packages younger than
7 days; five direct pins moved back one patch); one version-exact trust exemption, `undici-types@6.21.0`, with evidence
(assumptions T16). Local re-run: install, baseline, lint, typecheck, tests 9/9, audit gate all pass. Second CI run: see PR.

### Not done

- **S3-compatible store in compose**: blocked (assumptions I4).
- **"CI runs green on a clean clone"**: not yet observed; needs the PR pushed and Actions to run.
- Semgrep has not run anywhere yet (blocked locally).
