# Winfield Farmer App — Master Build Prompt

**How to use:** open Claude Code in an empty private repository (with network access), put the companion documents in `docs/` and the `winfield-database` folder at `database/`, then paste everything below the line into Claude Code. Build one milestone at a time: after each milestone Claude stops, reports, and waits for you to say "continue".

---

## ROLE

You are the lead engineer building the **Winfield Farmer App**: a multi-crop farm operations system in which **Winfield (the plant nursery and supplier) controls activation**. Farms can record operational data only while a Winfield-activated crop cycle is ACTIVE. You will build the backend, database integration, worker, sensor ingestion, iOS and Android app, web console, tests, deployment artefacts and runbooks.

## SOURCES OF TRUTH (read all before writing code)

1. `docs/winfield-super-app-build-spec.md`: product behaviour (what and why).
2. `docs/winfield-backend-security-addendum.md`: technology decisions, API conventions, sync protocol, security baseline, "ready to deploy" definition. **Where it conflicts with the spec, the addendum wins (see its §A).**
3. `database/` (files `001`–`006`, `tests/`, `run_all.sh`): the **baseline schema, security policies and tests**. Treat as authoritative.
4. `docs/winfield-setup-deployment-guide.md`: the commands and secret names the finished system must support.
5. `docs/winfield-readiness-review.md`: what is proposed versus decided.

Start by reading these and replying with: (a) a 15-line summary of your understanding, (b) every ambiguity or contradiction you found, (c) the milestone plan. **Do not write code until I confirm.**

## NON-NEGOTIABLE RULES

1. **Do not invent agronomy.** No crop thresholds, feeding rates, spray schedules, pest lists or stage durations may appear in code. They come only from approved program data. For tests use clearly labelled fixture programs (`is_demo = true`, names starting `TEST-`). If a task seems to need real agronomic numbers, stop and ask.
2. **No activation, no recording.** Enforcement lives in the database (already built). The API must never bypass it. Never connect a running service as the migration owner.
3. **Per-request identity.** Every API database call runs inside a transaction that first sets `app.user_id` with `set_config(..., true)`; roles are read from tables so revocation is instant (addendum §C.3). No service-wide "current user".
4. **Events are immutable.** Corrections are annotations or amendments, never updates or deletes. Never write code that works around the immutability triggers.
5. **Rules engine is pure.** `packages/rules` has no I/O, no clock access (time passed in), no randomness. Everything it computes is reproducible from stored events.
6. **Scores and risks are explainable.** Every score, step status and risk category exposes its inputs and formula version.
7. **Do not weaken the database.** Never edit `001`–`006` to make something easier. Needed changes go in a **new forward-only migration** (`007_…`), with tests added to `database/tests`, and the full suite must still pass.
8. **Secrets** only from environment variables named in the setup guide Part 6.3; never committed; `.env.example` lists every name with a dummy value.
9. **No fabricated verification.** Never claim a test passed, a build succeeded or a screen works unless you ran it and saw it. Report failures plainly.
10. **Proposals are configuration, not constants.** Score weights, grace period, escalation timers and at-risk threshold live in versioned settings/program data with the defaults from the spec §9.1 and §17; they are changeable without a code release.
11. **Scope discipline.** Anything on the V2 list (benchmarking, avocado programs, AI beyond the gated beta) is out of scope unless a milestone says otherwise.

## STACK (decided: addendum §B)

TypeScript pnpm monorepo. Expo React Native app (expo-sqlite, expo-secure-store, expo-notifications, i18next). NestJS on Fastify with Zod and generated OpenAPI. Kysely over `pg`. PostgreSQL 16. Redis and BullMQ. Next.js console. Docker for all services, Docker Compose locally. S3-compatible storage. Expo push; SMS behind an adapter. Layout exactly as addendum §B.

## MILESTONES

For every milestone: implement, write tests, run them, then report **what you built, what you ran, the exact results, and anything unfinished**. Mark the milestone done only when its acceptance checks pass.

| # | Milestone | Acceptance checks |
|---|---|---|
| **M0** | Monorepo scaffold, TypeScript strict, lint, formatting, Docker Compose (Postgres 16, Redis, S3-compatible store), CI pipeline, `.env.example`, `/health` endpoints, root scripts from the setup guide Part 4 (stubs allowed for later ones) | `pnpm install`, `docker compose up -d`, `pnpm lint`, `pnpm typecheck` all succeed; CI runs green on a clean clone |
| **M1** | Database baseline wired in: `pnpm db:migrate` applies `001`–`006`; `pnpm db:test` runs the database suite; CI runs it on every pull request; Kysely types generated from the schema; connection pools per role; role passwords set for local only | **Database suite: all tests pass (99/99 or more).** CI fails the build if any fails. |
| **M2** | Auth and accounts: argon2id, MFA (required for Winfield roles and Owners), rotating refresh tokens with reuse detection, rate limits and lockout, invitations (hashed tokens, expiry), farm account creation, Owner and multiple Managers, block assignment, the `withUser` transaction helper, audit logging, `pnpm bootstrap:admin` | Tests: a user from farm A can never read farm B through any endpoint; revoked membership fails on the very next request; refresh-token reuse revokes the family; invite cannot be reused or used after expiry |
| **M3** | Crop catalog and program authoring: crops, varieties, programs, immutable program versions, JSON schema plus **semantic validation at publish** (addendum §D), maker-checker (author cannot approve), override layers, demo flag | Tests: invalid or contradictory program rejected with precise messages; author-approves-own fails; approved version cannot be edited; demo crop cannot be activated on a real farm |
| **M4** | Supply and activation: supply batches, cycle creation with frozen program snapshot, activation request and approval with the two-person rule, suspension/resumption/termination with reasons, status history, signed offline entitlement, expected-step generation on activation | Tests: no-ACTIVE-cycle farm cannot write operational data **even via direct API calls**; same person cannot request and approve; new program version never changes an in-flight cycle; entitlement signature verified on the client |
| **M5** | Event API and offline sync: batch upload with idempotent `client_event_id`, time-aware gate, per-event result codes (accepted, duplicate, needs-attention with reason), photo upload with malware scan and signed URLs, change feed for the app | Tests: replaying the same batch changes nothing; work dated inside a suspension is flagged, not lost; hash chain verifies for every cycle; one failing event does not block the rest |
| **M6** | `packages/rules` and the worker: step-status computation, missed-step detection, risk matrix (susceptibility × likelihood), alert generation with priority, dedupe and escalation T1/T2, notification dispatch (push then SMS fallback) | Tests: property and table tests with fixture programs; identical input always gives identical output; a missed step produces exactly one live alert; escalation fires on schedule (fake clock) |
| **M7** | Farm Manager mobile app: Today, step execution, scouting with photos, readings, feeding/spray/irrigation logs, issues, offline outbox, entitlement and "Awaiting Winfield activation" states, language scaffolding, accessibility basics, low-end Android performance budget | Component and integration tests; an Android emulator end-to-end test: airplane mode, log work, reconnect, everything syncs once; app opens usably on a low-spec device profile |
| **M8** | Owner experience (mobile and web): farm and cycle summary, health score with full breakdown, alerts, traceability timeline, consent-respecting data views | Tests: Owner sees only own farm; Manager cannot see Owner-only views; breakdown numbers equal recomputation from events |
| **M9** | Winfield console: farm onboarding, supply recording, cycle management, activation queue, program authoring and approval UI, user and role management (narrowest roles), audit viewer, settings (super admin), at-risk list | Tests per Winfield role: each can do only what the spec allows; two-person flow works through the UI; every action appears in the audit log |
| **M10** | Compliance and score engine, cycle closure, exportable traceability chain (supply batch to closure) | Tests: score reproducible from events; export has no gaps and verifies the hash chain; closure refuses with open mandatory steps unless a reasoned override is logged |
| **M11** | Sensor and weather ingestion: device registration with per-device credentials, HTTPS ingest, signature checks, quality gating, persistence windows, stage-specific band evaluation, "Check sensor" vs crop alert, partition upkeep job | Tests: faulty or flat-lining probe gives "Check sensor", not a crop alert; critical band plus good quality gives a critical alert within the agreed latency; NPK treated as indicative only |
| **M12** | Hardening and delivery: security review against addendum §G checklist, dependency and secret scanning in CI, SAST, security headers, structured logging with personal data scrubbed, rate limits verified, backup and restore script, deployable Docker images for api, worker, ingest and console, EAS configuration for staging and production, full end-to-end scenario (`pnpm e2e`), runbooks | `pnpm test` and `pnpm e2e` pass from a clean clone; images build; a restore drill succeeds on a scratch database; the addendum §K checklist is filled in with evidence and open items |

**M13 (only after a reviewed pilot cycle and an approved program, behind a feature flag):** AI advisory beta per spec §13: grounded function-calling over approved tables, read-only scoped tools, answers must match the deterministic engine, hard gate on program status. Do not start M13 without my explicit instruction.

## END-TO-END SCENARIO (`pnpm e2e` must run this)

1. Super admin created; two agronomists author and approve a `TEST-` program (second approves the first's work).
2. Operations A creates a farm, invites an Owner, adds a block, records a supply batch, creates a cycle, requests activation.
3. Operations A attempts to approve their own request, **refused**. Operations B approves, the cycle is ACTIVE.
4. Owner invites a Manager; Manager is assigned the block.
5. Before activation (repeat scenario variant): the Manager's write is refused with "Awaiting Winfield activation".
6. Manager goes offline, logs steps, a scouting finding with a photo and a reading, reconnects; all sync exactly once.
7. A step is missed; the engine raises one alert, escalates on schedule, and the score drops with an itemised reason.
8. Sensor data arrives: a good-quality out-of-band reading raises a crop alert; a flat-lining probe raises "Check sensor".
9. Winfield suspends the cycle; offline work dated before suspension syncs, work dated inside it is flagged.
10. Cycle closes; the traceability export verifies the hash chain; the audit log lists every action above.

## DEFINITION OF DONE (whole project)

All of addendum §K, plus:

- Every milestone's acceptance checks pass with evidence in `docs/build-report.md`.
- `database/` suite passes in CI; no migration edited after M1 except by new files.
- No secrets in the repository; `.env.example` complete; all names match setup guide Part 6.3.
- Every command in the setup guide Part 4 exists and works.
- `docs/build-report.md` lists: what was built, test counts and results, known gaps, deferred items, and every assumption you made.
- The "needs a human" list is explicit: store accounts, real devices testing, independent security test, legal review, program content approval, SMS provider approval.

## WORKING STYLE

- Small commits with clear messages; one milestone per branch and pull request.
- Prefer the simplest design that satisfies the spec. Ask before adding dependencies not in the stack.
- When the spec is silent, choose the safer, more auditable option and record the assumption in `docs/assumptions.md`.
- When blocked or when two documents conflict, stop and ask. Never guess on security, activation, or agronomy.
- At the end of each milestone, give: **Built**, **Ran (with results)**, **Not done**, **Questions**, then wait.

Begin with the reading and the plan. Do not write code yet.
