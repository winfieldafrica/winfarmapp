-- 006_supporting_tables.sql — invitations, push-notification devices, consent records.
SET search_path = app, public;

-- Consent: append-only record of what each person agreed to. The latest row per (user, purpose) is their current choice.
CREATE TABLE app.consents (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES app.users(id),
  purpose        text NOT NULL CHECK (purpose IN ('terms','privacy','location','photos','activity','notifications')),
  granted        boolean NOT NULL,
  policy_version text NOT NULL,
  recorded_at    timestamptz NOT NULL DEFAULT now(),
  ip             inet,
  source         text NOT NULL DEFAULT 'app'
);
CREATE INDEX ON app.consents(user_id, purpose, recorded_at DESC);
CREATE TRIGGER consents_immutable BEFORE UPDATE OR DELETE ON app.consents FOR EACH ROW EXECUTE FUNCTION app.trg_immutable();

-- Invitations: the token itself is emailed/SMSed; only its hash is stored.
CREATE TABLE app.farm_invites (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id          uuid NOT NULL REFERENCES app.farms(id) ON DELETE CASCADE,
  farm_role        text NOT NULL CHECK (farm_role IN ('owner','manager')),
  email            citext NOT NULL,
  token_hash       bytea NOT NULL UNIQUE,
  invited_by       uuid NOT NULL REFERENCES app.users(id),
  expires_at       timestamptz NOT NULL,
  accepted_at      timestamptz,
  accepted_user_id uuid REFERENCES app.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > created_at)
);
CREATE INDEX ON app.farm_invites(farm_id);

CREATE TABLE app.user_devices (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  platform     text NOT NULL CHECK (platform IN ('ios','android','web')),
  push_token   text,
  app_version  text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz,
  UNIQUE (user_id, push_token)
);

ALTER TABLE app.consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.farm_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.user_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app.consents, app.farm_invites, app.user_devices FROM PUBLIC;

-- Consents: a person records and reads their own; super admin can read all (for audits / data-subject requests).
GRANT SELECT, INSERT ON app.consents TO app_api;
CREATE POLICY consents_select ON app.consents FOR SELECT TO app_api USING (user_id = app.current_user_id() OR app.has_winfield_role('{super_admin}'));
CREATE POLICY consents_insert ON app.consents FOR INSERT TO app_api WITH CHECK (user_id = app.current_user_id());

-- Invites: Winfield ops create owner/manager invites; a farm owner may invite managers only.
GRANT SELECT, INSERT ON app.farm_invites TO app_api;
GRANT SELECT, UPDATE ON app.farm_invites TO app_auth;
CREATE POLICY invites_select ON app.farm_invites FOR SELECT TO app_api USING (app.is_winfield() OR app.is_farm_owner(farm_id));
CREATE POLICY invites_ops_insert ON app.farm_invites FOR INSERT TO app_api
  WITH CHECK (invited_by = app.current_user_id() AND app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY invites_owner_insert ON app.farm_invites FOR INSERT TO app_api
  WITH CHECK (invited_by = app.current_user_id() AND farm_role = 'manager' AND app.is_farm_owner(farm_id));
CREATE POLICY invites_auth ON app.farm_invites FOR ALL TO app_auth USING (true) WITH CHECK (true);

-- Push devices: each person manages only their own; the worker reads them to send notifications.
GRANT SELECT, INSERT, UPDATE ON app.user_devices TO app_api;
GRANT SELECT ON app.user_devices TO app_engine;
CREATE POLICY udev_self   ON app.user_devices FOR ALL TO app_api USING (user_id = app.current_user_id()) WITH CHECK (user_id = app.current_user_id());
CREATE POLICY udev_engine ON app.user_devices FOR SELECT TO app_engine USING (true);
GRANT SELECT ON app.consents TO app_engine;
CREATE POLICY consents_engine ON app.consents FOR SELECT TO app_engine USING (true);
