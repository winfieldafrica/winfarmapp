#!/usr/bin/env bash
# Builds a throwaway database, applies every migration in order, loads test fixtures, runs the full test suite.
# Needs: PostgreSQL 16 client tools (psql) and a reachable PostgreSQL server where you may create a database.
# Usage:  PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=... ./run_all.sh
set -euo pipefail
cd "$(dirname "$0")"
DB="${TEST_DB:-winfield_test}"
psql -q -d postgres -c "DROP DATABASE IF EXISTS ${DB}" -c "CREATE DATABASE ${DB}"
for f in 001_roles_extensions.sql 002_schema.sql 003_functions_triggers.sql 004_observation_partitions.sql 005_rls_grants.sql 006_supporting_tables.sql tests/fixtures.sql; do
  echo "applying $f"; psql -q -v ON_ERROR_STOP=1 -d "${DB}" -f "$f" >/dev/null
done
PGDATABASE="${DB}" python3 tests/run_tests.py
