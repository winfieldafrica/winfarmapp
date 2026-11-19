# Winfield Farmer App

Multi-crop farm operations system in which Winfield controls activation. Start with `docs/`:
the build spec, the backend/security addendum (wins on conflict), and the setup and deployment guide.

## Local development

```bash
cp .env.example .env
pnpm install
docker compose up -d
pnpm dev
```

Root commands (setup guide Part 4): `pnpm install`, `docker compose up -d`, `pnpm db:migrate`, `pnpm db:test`,
`pnpm test`, `pnpm e2e`, `pnpm bootstrap:admin`, `pnpm dev`. Also `pnpm lint`, `pnpm typecheck`,
`pnpm check:db-baseline`.

`database/` is the supplied, tested baseline. Never edit files `001`–`006` or the supplied tests; add a new
`007_…` migration with new tests instead. Build progress and evidence: `docs/build-report.md`;
decisions: `docs/assumptions.md`.
