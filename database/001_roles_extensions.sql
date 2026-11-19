-- 001_roles_extensions.sql
-- Run as the migration owner (a non-superuser role that owns the schema) or a superuser for first install.
-- Roles are created NOLOGIN here; the setup guide gives each one a password / LOGIN in the cloud console.

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- digest(), gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email

DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['app_api','app_engine','app_ingest','app_auth','app_readonly'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOBYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE', r);
    END IF;
  END LOOP;
END $$;

-- app_api      : serves mobile app + web console requests. Subject to row-level security. Never owns tables.
-- app_engine   : background worker. Writes engine-owned projections (expected steps, alerts, scores).
-- app_ingest   : sensor ingestion service. Can only insert observations and read device credentials.
-- app_auth     : login service. Only role that can read credentials and refresh tokens.
-- app_readonly : analytics / BI. Read-only, still subject to RLS (see 005).

CREATE SCHEMA IF NOT EXISTS app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO app_api, app_engine, app_ingest, app_auth, app_readonly;
