# Assumptions and decisions log

Every assumption, deviation and added dependency is recorded here with its reason. Newest milestone last.
"Decided" means the project owner ruled on it in the build conversation; "Assumed" means the build chose the
safer, more auditable option and it can be changed.

## Sources

| # | Item | Status |
|---|---|---|
| S1 | The addendum was supplied only as a PDF. It is committed as `docs/winfield-backend-security-addendum.pdf`; the master prompt refers to a `.md` of the same name, which was never supplied. | Assumed; supply the `.md` if one exists |
| S2 | `database/` is a byte-for-byte copy of `winfield-database/` from the supplied zip. Checksums are in `infra/database-baseline.sha256` (outside `database/` so the folder is never edited). `pnpm check:db-baseline` and CI fail on any change to a baseline file or any unexpected file. New files are allowed only as `database/NNN_*.sql` (NNN ≥ 007) or new files under `database/tests/`. | Decided |
| S3 | The baseline `run_all.sh` and `run_tests.py` stay untouched; `pnpm db:test` will call them (M1). The 007+ suites run as additional files after it. | Decided |
| S4 | Repository name is `winfarmapp` (the setup guide says `winfield`). | Decided |
| S5 | Addendum says 002 has 34 tables; it has 30, plus 3 in 006 (33). No behavioural impact. | Noted |
| S6 | Addendum §C.1 and the readiness review mention a four-way concurrent-write test; `run_tests.py` has no concurrency test. One will be added as a new test file in M1. | Planned (M1) |

## Configuration names

Secrets in `.env.example` match setup guide Part 6.3 exactly. These **non-secret** names were added by the build
(approved in principle; each listed with a dummy value in `.env.example`):

| Name | Why |
|---|---|
| `NODE_ENV`, `LOG_LEVEL` | Standard runtime mode and log verbosity |
| `API_PORT` (4000), `INGEST_PORT` (4100), `WORKER_HEALTH_PORT` (4200), `CONSOLE_PORT` (3000) | Listening ports; console defaults to 3000 as the guide (Part 5) expects |
| `S3_ENDPOINT`, `S3_FORCE_PATH_STYLE` | Needed for any S3-compatible store that is not AWS (local and some hosts) |
| `CLAMAV_HOST`, `CLAMAV_PORT` | Malware scanner used by the worker from M5 |

`DATABASE_URL_READONLY` is **not** added: no service uses `app_readonly` yet. Will be proposed if analytics needs it.

## Infrastructure (local)

| # | Item | Status |
|---|---|---|
| I1 | `compose.yaml` lives at the repository root (not `infra/`) because the setup guide's command is a plain `docker compose up -d` from the root. | Assumed |
| I2 | Images pinned by tag **and** digest: `postgres:16.16-alpine`, `redis:7.4.12-alpine`. Ports bind to 127.0.0.1 only. | Assumed |
| I3 | Local Postgres superuser password is the fixed dummy `local-dev-only`; locally the superuser is the migration owner. Never used outside local/CI. | Assumed |
| I4 | **S3-compatible store not yet in compose.** MinIO no longer publishes images on Docker Hub (`minio/minio` returns "repository does not exist"), and `quay.io` is blocked from the build environment, so no MinIO image could be pulled or verified. | **Open: needs decision** |
| I5 | ClamAV is added to compose in M5 (when the scan job exists), not M0. | Assumed |
| I6 | Redis 7.4 chosen over 8.x to stay on the long-used BullMQ-tested line; production uses the host's managed Redis. | Assumed |

## Tooling and code layout

| # | Item | Status |
|---|---|---|
| T1 | TypeScript **6.0.3**, not 7.0.2: `typescript-eslint` 8.73 supports only `typescript < 6.1`. | Assumed |
| T2 | React **19.3.0** across the monorepo: Expo SDK 58 pins it; Next 16 accepts it. One React version avoids duplicate-React bugs. | Assumed |
| T3 | `@types/node` 22.x to match the Node 22 runtime (`.nvmrc`, `engines`). | Assumed |
| T4 | NestJS 12 is ESM-only, so every package and service is ESM (`"type": "module"`). | Assumed |
| T5 | Workspace packages compile to `dist/`; root `typecheck`, `test` and `dev` build `packages/*` first. No turbo/nx. | Assumed |
| T6 | `packages/ui` (optional in addendum §B) is not created until a shared component exists. | Assumed |
| T7 | Purity of `packages/rules` is enforced by ESLint: no Node/DB/Redis imports, no `process`, `fetch`, timers, `crypto`, `Date.now()`, `new Date()` without arguments, `Math.random()`, `performance.now()`. Verified by a probe file (5 errors raised, then deleted). | Assumed |
| T8 | Root stubs (`db:migrate`, `db:test`, `e2e`, `bootstrap:admin`) exit **1** with "not implemented yet (arrives in Mx)" so a stub can never look like a pass. | Assumed |
| T9 | Mobile `bundleIdentifier`/`package` are not set: setup guide Part 1 #8 says this cannot be changed after publishing and is a Winfield decision. | Open (needed before M12 EAS config) |
| T10 | CodeQL is not used: code scanning on private repositories needs GitHub Code Security (paid). Semgrep OSS + gitleaks are used instead. | Decided (default) |
| T11 | gitleaks runs from its published container in CI, not `gitleaks-action` (which needs a paid licence for organisations). | Assumed |
| T12 | Semgrep excludes `docs/` and `database/` (supplied, unmodifiable files); everything we write is scanned. | Assumed |
| T13 | GitHub Actions are pinned to full commit SHAs (checkout v7.0.1, setup-node v7.1.0, pnpm/action-setup v6.1.1). | Assumed |
| T14 | CI fails on `pnpm audit --audit-level high`. Dependabot covers npm, GitHub Actions and docker-compose images weekly. | Decided |

## Dependencies added (M0)

Every version is pinned exactly (`save-exact=true`); `pnpm-lock.yaml` is committed. Each name was checked on the
npm registry for the official repository URL and package age before adding (typosquat check). pnpm 10 blocks
dependency install scripts by default; after install **no installed package declares a preinstall/install/postinstall
script**, so none was allowed to run.

| Package | Version | Where | Why | Approval |
|---|---|---|---|---|
| typescript | 6.0.3 | root dev | Language (addendum §B) | Stack + named |
| @types/node | 22.20.5 | root dev | Node type definitions | Named |
| eslint | 10.15.0 | root dev | Lint | Approved list |
| @eslint/js, typescript-eslint, eslint-config-prettier, globals | 10.0.1, 8.73.0, 10.1.8, 17.14.0 | root dev | ESLint for TypeScript, Prettier compatibility, environment globals | Named |
| prettier | 3.10.1 | root dev | Formatting | Approved list |
| vitest | 5.1.1 | root dev | Unit tests | Approved list |
| @nestjs/common, @nestjs/core, @nestjs/platform-fastify | 12.5.1 | api | API framework (NestJS on Fastify) | Stack |
| reflect-metadata, rxjs | 0.2.2, 7.8.2 | api | Required peers of NestJS | Named |
| fastify | 5.12.8 | ingest | Ingest service (addendum §B) | Stack |
| zod | 4.6.7 | shared, api | Validation (addendum §B) | Stack |
| next, react, react-dom | 16.4.6, 19.3.0, 19.3.0 | console | Web console (addendum §B) | Stack |
| @types/react, @types/react-dom | 19.3.0 | console, mobile | React type definitions | Stack (TypeScript) |
| expo, react-native | 58.0.26, 0.88.1 | mobile | Mobile app (addendum §B); versions from Expo's own `bundledNativeModules.json` | Stack |

Notable transitive dependency: `noxcturnal` 0.1.14 comes from `@expo/metro-config` (repository `github.com/expo/noxcturnal`,
Expo maintainer). Checked because the name was unfamiliar; legitimate.

Known advisory at M0 (below the high/critical gate): **moderate**, `minimatch` < 11.0.1 (ReDoS via glob
amplification), via `expo > @expo/fingerprint`. Build-time tool only; will clear when Expo updates.
