-- 002_schema.sql  — tables, constraints, indexes
-- Conventions: uuid primary keys, timestamptz everywhere, CHECK constraints instead of enums (easier to migrate),
-- program content is versioned JSONB validated against a JSON Schema in the application layer.

SET search_path = app, public;

-- ───────────────────────── Identity ─────────────────────────
CREATE TABLE app.users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         citext NOT NULL UNIQUE,
  display_name  text   NOT NULL,
  kind          text   NOT NULL CHECK (kind IN ('winfield','farm')),
  winfield_role text   CHECK (winfield_role IN ('super_admin','agronomist','operations','analyst','field_officer')),
  phone         text,
  locale        text   NOT NULL DEFAULT 'en',
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'winfield') = (winfield_role IS NOT NULL))
);

-- Credentials live apart from profile data so ordinary API queries can never touch them.
CREATE TABLE app.user_credentials (
  user_id             uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  password_hash       text NOT NULL,                -- argon2id, never plain or fast hashes
  mfa_secret_enc      bytea,                        -- encrypted by the application with a KMS-held key
  mfa_enabled         boolean NOT NULL DEFAULT false,
  failed_attempts     int NOT NULL DEFAULT 0,
  locked_until        timestamptz,
  password_changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.refresh_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  token_hash   bytea NOT NULL UNIQUE,               -- store only a hash of the token
  family_id    uuid NOT NULL,                       -- rotation family: reuse of a revoked token revokes the family
  device_label text,
  issued_at    timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  revoked_at   timestamptz,
  replaced_by  uuid REFERENCES app.refresh_tokens(id)
);
CREATE INDEX ON app.refresh_tokens(user_id);
CREATE INDEX ON app.refresh_tokens(family_id);

-- ───────────────────────── Farms ─────────────────────────
CREATE TABLE app.farms (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  country     text NOT NULL,
  region      text,
  status      text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED')),
  created_by  uuid NOT NULL REFERENCES app.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.farm_memberships (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id    uuid NOT NULL REFERENCES app.farms(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  farm_role  text NOT NULL CHECK (farm_role IN ('owner','manager')),
  active     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (farm_id, user_id)
);
-- exactly one active owner per farm
CREATE UNIQUE INDEX one_active_owner_per_farm ON app.farm_memberships(farm_id) WHERE farm_role = 'owner' AND active;
CREATE INDEX ON app.farm_memberships(user_id) WHERE active;

CREATE TABLE app.blocks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id      uuid NOT NULL REFERENCES app.farms(id) ON DELETE CASCADE,
  name         text NOT NULL,
  area_ha      numeric(10,2),
  geo_boundary jsonb,                 -- GeoJSON polygon (swap for PostGIS geometry if spatial queries are needed)
  elevation_m  int,
  region       text,
  soil_profile jsonb,                 -- clay %, CEC, mineral ppm, pH, lab date (versioned inside the document)
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (farm_id, name),
  UNIQUE (id, farm_id)                -- lets child tables prove block/farm consistency with a composite FK
);

CREATE TABLE app.block_assignments (
  block_id uuid NOT NULL REFERENCES app.blocks(id) ON DELETE CASCADE,
  user_id  uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  PRIMARY KEY (block_id, user_id)
);

-- ───────────────────────── Catalog (Winfield-only) ─────────────────────────
CREATE TABLE app.crops (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL UNIQUE,
  cycle_type text NOT NULL CHECK (cycle_type IN ('SHORT_CYCLE','CONTINUOUS_HARVEST','PERENNIAL')),
  is_active  boolean NOT NULL DEFAULT true,
  is_demo    boolean NOT NULL DEFAULT false   -- demo/sample crops can never be activated in production
);
CREATE TABLE app.varieties (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  crop_id uuid NOT NULL REFERENCES app.crops(id),
  name    text NOT NULL,
  UNIQUE (crop_id, name)
);
CREATE TABLE app.threats (          -- pest / disease / disorder library
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key     text NOT NULL UNIQUE,
  name    text NOT NULL,
  kind    text NOT NULL CHECK (kind IN ('pest','disease','disorder')),
  content jsonb NOT NULL,           -- symptoms, favourable conditions, scouting method, thresholds, sources
  status  text NOT NULL DEFAULT 'UNVALIDATED' CHECK (status IN ('UNVALIDATED','APPROVED','RETIRED'))
);
CREATE TABLE app.products (
  id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name    text NOT NULL,
  kind    text NOT NULL CHECK (kind IN ('fertiliser','crop_protection','other')),
  content jsonb NOT NULL,           -- analysis, rate range, safety / pre-harvest interval, cost
  status  text NOT NULL DEFAULT 'UNVALIDATED' CHECK (status IN ('UNVALIDATED','APPROVED','RETIRED'))
);
CREATE TABLE app.crop_programs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  crop_id    uuid NOT NULL REFERENCES app.crops(id),
  variety_id uuid REFERENCES app.varieties(id),
  region     text,
  name       text NOT NULL
);
CREATE TABLE app.program_versions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id  uuid NOT NULL REFERENCES app.crop_programs(id),
  version_no  int  NOT NULL,
  status      text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','IN_REVIEW','APPROVED','RETIRED')),
  content     jsonb NOT NULL,      -- full stage tree; validated against program.schema.json by the API before save
  authored_by uuid NOT NULL REFERENCES app.users(id),
  reviewed_by uuid REFERENCES app.users(id),
  published_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (program_id, version_no)
);

-- ───────────────────────── Supply and cycles ─────────────────────────
CREATE TABLE app.supply_batches (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id          uuid NOT NULL REFERENCES app.farms(id),
  block_id         uuid NOT NULL,
  crop_id          uuid NOT NULL REFERENCES app.crops(id),
  variety_id       uuid REFERENCES app.varieties(id),
  nursery_lot_code text NOT NULL,
  quantity         int  NOT NULL CHECK (quantity > 0),
  plant_spec       jsonb,
  supply_date      date NOT NULL,
  delivery_note_ref text,
  created_by       uuid NOT NULL REFERENCES app.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (block_id, farm_id) REFERENCES app.blocks(id, farm_id),
  UNIQUE (id, farm_id, block_id)
);

CREATE TABLE app.crop_cycles (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id             uuid NOT NULL REFERENCES app.farms(id),
  block_id            uuid NOT NULL,
  supply_batch_id     uuid NOT NULL,
  program_version_id  uuid NOT NULL REFERENCES app.program_versions(id),
  program_snapshot    jsonb NOT NULL,            -- frozen copy of the approved version at creation
  cycle_type          text NOT NULL CHECK (cycle_type IN ('SHORT_CYCLE','CONTINUOUS_HARVEST','PERENNIAL')),
  parent_cycle_id     uuid REFERENCES app.crop_cycles(id),   -- perennial seasonal sub-cycles
  status              text NOT NULL DEFAULT 'DRAFT'
                      CHECK (status IN ('DRAFT','PENDING_ACTIVATION','ACTIVE','SUSPENDED','COMPLETED','TERMINATED','CLOSED')),
  clock_start_date    date,
  planting_date_confirmed date,
  projected_end_date  date,
  requested_by        uuid REFERENCES app.users(id),
  requested_at        timestamptz,
  approved_by         uuid REFERENCES app.users(id),
  approved_at         timestamptz,
  status_reason       text,
  created_by          uuid NOT NULL REFERENCES app.users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (block_id, farm_id) REFERENCES app.blocks(id, farm_id),
  FOREIGN KEY (supply_batch_id, farm_id, block_id) REFERENCES app.supply_batches(id, farm_id, block_id),
  UNIQUE (id, farm_id)
);
CREATE INDEX ON app.crop_cycles(farm_id, status);
CREATE INDEX ON app.crop_cycles(block_id);

-- Every status a cycle has been in, with the time it changed. Lets the event gate judge a late-synced (offline)
-- event by the cycle's status WHEN THE WORK HAPPENED, so legitimate offline work is never lost.
CREATE TABLE app.cycle_status_history (
  id         bigserial PRIMARY KEY,
  cycle_id   uuid NOT NULL REFERENCES app.crop_cycles(id) ON DELETE CASCADE,
  status     text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid
);
CREATE INDEX ON app.cycle_status_history(cycle_id, changed_at);

CREATE TABLE app.cycle_stages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id      uuid NOT NULL REFERENCES app.crop_cycles(id) ON DELETE CASCADE,
  stage_key     text NOT NULL,
  name          text NOT NULL,
  ord           int  NOT NULL,
  planned_start date NOT NULL,
  planned_end   date NOT NULL,
  actual_start  date,
  actual_end    date,
  confirm_event_id uuid,
  variance_days int,
  UNIQUE (cycle_id, stage_key),
  UNIQUE (cycle_id, ord)
);

CREATE TABLE app.expected_steps (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id       uuid NOT NULL REFERENCES app.crop_cycles(id) ON DELETE CASCADE,
  cycle_stage_id uuid REFERENCES app.cycle_stages(id) ON DELETE CASCADE,
  step_key       text NOT NULL,
  kind           text NOT NULL CHECK (kind IN ('feeding','spray','irrigation_check','scouting','health_check','cultural','reading','stage_transition')),
  title          text NOT NULL,
  earliest_at    timestamptz NOT NULL,
  due_at         timestamptz NOT NULL,
  latest_at      timestamptz NOT NULL,
  grace_hours    int NOT NULL DEFAULT 0,
  critical       boolean NOT NULL DEFAULT false,
  prescription   jsonb,
  evidence_required jsonb,
  status         text NOT NULL DEFAULT 'PENDING'
                 CHECK (status IN ('PENDING','DUE','OVERDUE','COMPLETED_ON_TIME','COMPLETED_LATE','COMPLETED_WITH_DEVIATION','SKIPPED_APPROVED','MISSED')),
  completed_event_id uuid,
  deviation      jsonb,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (earliest_at <= due_at AND due_at <= latest_at)
);
CREATE INDEX ON app.expected_steps(cycle_id, status, due_at);

-- ───────────────────────── Events (immutable, hash-chained per cycle) ─────────────────────────
CREATE TABLE app.events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id        uuid NOT NULL,
  farm_id         uuid NOT NULL,                 -- set by trigger from the cycle; never trusted from the client
  block_id        uuid NOT NULL,                 -- set by trigger from the cycle
  actor_id        uuid NOT NULL REFERENCES app.users(id),
  type            text NOT NULL CHECK (type IN
                  ('work_log','input_application','scouting','health_check','reading',
                   'receipt_confirmation','stage_confirmation','ack','annotation','verification')),
  occurred_at     timestamptz NOT NULL,          -- device time when the action happened (may be offline)
  received_at     timestamptz NOT NULL DEFAULT now(),
  lat             double precision,
  lon             double precision,
  payload         jsonb NOT NULL,
  seq             bigint NOT NULL,               -- per-cycle sequence, assigned by trigger; defines hash-chain order
  client_event_id uuid NOT NULL,                 -- idempotency key so offline retries never double-write
  annotates_event_id uuid REFERENCES app.events(id),
  prev_hash       bytea,
  hash            bytea NOT NULL,
  FOREIGN KEY (cycle_id, farm_id) REFERENCES app.crop_cycles(id, farm_id),
  UNIQUE (cycle_id, client_event_id),
  UNIQUE (cycle_id, seq),
  CHECK (type NOT IN ('annotation','verification') OR annotates_event_id IS NOT NULL)
);
CREATE INDEX ON app.events(cycle_id, received_at);
CREATE INDEX ON app.events(farm_id, type, occurred_at);

CREATE TABLE app.media (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id     uuid NOT NULL REFERENCES app.farms(id),
  cycle_id    uuid REFERENCES app.crop_cycles(id),
  event_id    uuid REFERENCES app.events(id),
  storage_key text NOT NULL UNIQUE,
  sha256      bytea NOT NULL,
  mime        text NOT NULL CHECK (mime IN ('image/jpeg','image/png','image/webp')),
  bytes       int  NOT NULL CHECK (bytes > 0 AND bytes <= 15000000),
  exif        jsonb,
  scan_state  text NOT NULL DEFAULT 'PENDING' CHECK (scan_state IN ('PENDING','CLEAN','REJECTED')),
  uploaded_by uuid NOT NULL REFERENCES app.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.scouting_records (         -- engine-written projection of scouting events
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id  uuid NOT NULL REFERENCES app.crop_cycles(id) ON DELETE CASCADE,
  event_id  uuid NOT NULL REFERENCES app.events(id),
  threat_id uuid NOT NULL REFERENCES app.threats(id),
  severity  int  NOT NULL CHECK (severity BETWEEN 0 AND 5),
  incidence_pct numeric(5,2),
  location  jsonb,
  observed_at timestamptz NOT NULL
);
CREATE INDEX ON app.scouting_records(cycle_id, observed_at);

-- ───────────────────────── Devices and sensor data ─────────────────────────
CREATE TABLE app.devices (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id          uuid NOT NULL REFERENCES app.farms(id),
  block_id         uuid NOT NULL,
  vendor           text NOT NULL,
  serial           text NOT NULL,
  depth_cm         int,
  position         jsonb,
  status           text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACTIVE','DISABLED')),
  calibration_date date,
  registered_by    uuid NOT NULL REFERENCES app.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (block_id, farm_id) REFERENCES app.blocks(id, farm_id),
  UNIQUE (vendor, serial),
  UNIQUE (id, farm_id, block_id)
);
CREATE TABLE app.device_credentials (       -- readable only by app_ingest
  device_id       uuid PRIMARY KEY REFERENCES app.devices(id) ON DELETE CASCADE,
  secret_hash     text NOT NULL,
  rotated_at      timestamptz NOT NULL DEFAULT now()
);

-- High-volume time series: declarative monthly partitions (see 005). Convert to a TimescaleDB hypertable if preferred.
CREATE TABLE app.observations (
  device_id   uuid NOT NULL,
  farm_id     uuid NOT NULL,
  block_id    uuid NOT NULL,
  metric      text NOT NULL CHECK (metric IN ('soil_moisture','ec','ph','n','p','k','temperature','humidity','rainfall','tension')),
  value       double precision NOT NULL,
  unit        text NOT NULL,
  observed_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  quality     text NOT NULL DEFAULT 'GOOD' CHECK (quality IN ('GOOD','SUSPECT','BAD')),
  PRIMARY KEY (device_id, metric, observed_at)
) PARTITION BY RANGE (observed_at);

-- ───────────────────────── Alerts, scores, amendments, outbox ─────────────────────────
CREATE TABLE app.alerts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id    uuid NOT NULL REFERENCES app.crop_cycles(id) ON DELETE CASCADE,
  farm_id     uuid NOT NULL REFERENCES app.farms(id),
  block_id    uuid REFERENCES app.blocks(id),
  source      text NOT NULL CHECK (source IN ('schedule','risk','reading','sensor','compliance','winfield')),
  priority    text NOT NULL CHECK (priority IN ('INFO','ACTION','HIGH','CRITICAL')),
  title       text NOT NULL,
  detail      jsonb,
  state       text NOT NULL DEFAULT 'OPEN' CHECK (state IN ('OPEN','ACKED','RESOLVED','SUPPRESSED')),
  dedupe_key  text NOT NULL,
  escalation_level int NOT NULL DEFAULT 0,     -- 0 manager, 1 owner, 2 Winfield agronomist
  opened_at   timestamptz NOT NULL DEFAULT now(),
  ack_event_id uuid REFERENCES app.events(id),
  resolved_at timestamptz
);
-- one live alert per condition: prevents alert storms
CREATE UNIQUE INDEX one_live_alert_per_condition ON app.alerts(cycle_id, dedupe_key) WHERE state IN ('OPEN','ACKED');
CREATE INDEX ON app.alerts(farm_id, state, priority);

CREATE TABLE app.compliance_snapshots (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id      uuid NOT NULL REFERENCES app.crop_cycles(id) ON DELETE CASCADE,
  block_id      uuid REFERENCES app.blocks(id),
  computed_at   timestamptz NOT NULL DEFAULT now(),
  formula_version text NOT NULL,
  components    jsonb NOT NULL,                 -- each component: value, weight, contributing event ids
  weighted_total numeric(5,2) NOT NULL CHECK (weighted_total BETWEEN 0 AND 100),
  ci_low        numeric(5,2),
  ci_high       numeric(5,2),
  has_sensor_data boolean NOT NULL DEFAULT false
);
CREATE INDEX ON app.compliance_snapshots(cycle_id, computed_at DESC);

CREATE TABLE app.amendments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id   uuid NOT NULL REFERENCES app.crop_cycles(id),
  version_no int  NOT NULL,
  reason     text NOT NULL CHECK (length(reason) >= 10),
  changes    jsonb NOT NULL,
  created_by uuid NOT NULL REFERENCES app.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cycle_id, version_no)
);

CREATE TABLE app.notification_outbox (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id    uuid REFERENCES app.farms(id),
  user_id    uuid NOT NULL REFERENCES app.users(id),
  channel    text NOT NULL CHECK (channel IN ('push','sms','whatsapp','email')),
  template   text NOT NULL,
  payload    jsonb NOT NULL,
  state      text NOT NULL DEFAULT 'QUEUED' CHECK (state IN ('QUEUED','SENT','FAILED','SKIPPED')),
  attempts   int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at    timestamptz
);
CREATE INDEX ON app.notification_outbox(state, created_at) WHERE state = 'QUEUED';

-- ───────────────────────── Audit and settings ─────────────────────────
CREATE TABLE app.audit_log (
  id         bigserial PRIMARY KEY,
  at         timestamptz NOT NULL DEFAULT now(),
  actor_id   uuid,
  actor_role text,
  action     text NOT NULL,
  resource   text NOT NULL,
  farm_id    uuid,
  result     text NOT NULL CHECK (result IN ('allowed','denied')),
  ip         inet,
  meta       jsonb
);
CREATE INDEX ON app.audit_log(at DESC);
CREATE INDEX ON app.audit_log(farm_id, at DESC);

CREATE TABLE app.system_settings (
  key        text PRIMARY KEY,
  value      jsonb NOT NULL,
  updated_by uuid REFERENCES app.users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.system_settings(key, value) VALUES
  ('require_two_person_activation', 'true'::jsonb),
  ('allow_demo_cycles',             'false'::jsonb),
  ('offline_grace_days',            '14'::jsonb),
  ('score_formula_version',         '"v1-proposed"'::jsonb);
