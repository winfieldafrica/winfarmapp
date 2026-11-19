-- 005_rls_grants.sql — who can do what, per table. Default is DENY: a table with RLS enabled and no matching policy returns nothing.
-- The API connects as app_api and sets app.user_id per request. It never connects as the table owner.
-- (Table owners bypass RLS, which is why the owner credentials are used only by the migration runner.)

SET search_path = app, public;

-- Shorthand used in policies
-- is_winfield()                : any active Winfield staff
-- has_winfield_role('{...}')   : specific Winfield roles
-- is_farm_member(farm_id)      : active owner or manager of that farm
-- is_farm_owner(farm_id)       : active owner of that farm
-- manages_block(block_id)      : manager assigned to that block

-- Enable RLS everywhere.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users','user_credentials','refresh_tokens','farms','farm_memberships','blocks','block_assignments',
    'crops','varieties','threats','products','crop_programs','program_versions',
    'supply_batches','crop_cycles','cycle_status_history','cycle_stages','expected_steps','events','media','scouting_records',
    'devices','device_credentials','observations','alerts','compliance_snapshots','amendments',
    'notification_outbox','audit_log','system_settings']
  LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- Start from nothing, then grant narrowly.
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM PUBLIC, app_api, app_engine, app_ingest, app_auth, app_readonly;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;

-- ───────────── Identity ─────────────
GRANT SELECT ON app.users TO app_api, app_readonly;
GRANT INSERT, UPDATE ON app.users TO app_api;
CREATE POLICY users_select ON app.users FOR SELECT TO app_api, app_readonly
  USING (id = app.current_user_id() OR app.is_winfield());
CREATE POLICY users_insert ON app.users FOR INSERT TO app_api
  WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY users_update ON app.users FOR UPDATE TO app_api
  USING (app.has_winfield_role('{super_admin}') OR id = app.current_user_id())
  WITH CHECK (app.has_winfield_role('{super_admin}') OR (id = app.current_user_id() AND kind = (SELECT kind FROM app.users WHERE id = app.current_user_id())));

-- Credentials and refresh tokens: only the login service. The API role cannot read them at all.
GRANT SELECT, INSERT, UPDATE, DELETE ON app.user_credentials, app.refresh_tokens TO app_auth;
GRANT SELECT ON app.users TO app_auth;
CREATE POLICY auth_all_users ON app.users FOR SELECT TO app_auth USING (true);
CREATE POLICY auth_all_creds ON app.user_credentials FOR ALL TO app_auth USING (true) WITH CHECK (true);
CREATE POLICY auth_all_rt    ON app.refresh_tokens    FOR ALL TO app_auth USING (true) WITH CHECK (true);

-- ───────────── Farms, memberships, blocks ─────────────
GRANT SELECT, INSERT, UPDATE ON app.farms, app.blocks TO app_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON app.farm_memberships, app.block_assignments TO app_api;
GRANT SELECT ON app.farms, app.blocks, app.farm_memberships, app.block_assignments TO app_readonly, app_engine;

CREATE POLICY farms_select ON app.farms FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(id));
CREATE POLICY farms_write  ON app.farms FOR INSERT TO app_api WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY farms_update ON app.farms FOR UPDATE TO app_api USING (app.has_winfield_role('{super_admin,operations}'))
  WITH CHECK (app.has_winfield_role('{super_admin,operations}'));

CREATE POLICY blocks_select ON app.blocks FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY blocks_insert ON app.blocks FOR INSERT TO app_api WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY blocks_update ON app.blocks FOR UPDATE TO app_api USING (app.has_winfield_role('{super_admin,operations}'))
  WITH CHECK (app.has_winfield_role('{super_admin,operations}'));

-- Winfield staff create the owner; the owner may invite/remove managers (never other owners).
CREATE POLICY members_select ON app.farm_memberships FOR SELECT TO app_api, app_readonly
  USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY members_winfield ON app.farm_memberships FOR ALL TO app_api
  USING (app.has_winfield_role('{super_admin,operations}')) WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY members_owner_insert ON app.farm_memberships FOR INSERT TO app_api
  WITH CHECK (farm_role = 'manager' AND app.is_farm_owner(farm_id));
CREATE POLICY members_owner_update ON app.farm_memberships FOR UPDATE TO app_api
  USING (farm_role = 'manager' AND app.is_farm_owner(farm_id)) WITH CHECK (farm_role = 'manager' AND app.is_farm_owner(farm_id));

CREATE POLICY assign_select ON app.block_assignments FOR SELECT TO app_api, app_readonly
  USING (app.is_winfield() OR app.is_farm_member((SELECT farm_id FROM app.blocks b WHERE b.id = block_id)));
CREATE POLICY assign_write ON app.block_assignments FOR ALL TO app_api
  USING (app.has_winfield_role('{super_admin,operations}') OR app.is_farm_owner((SELECT farm_id FROM app.blocks b WHERE b.id = block_id)))
  WITH CHECK (app.has_winfield_role('{super_admin,operations}') OR app.is_farm_owner((SELECT farm_id FROM app.blocks b WHERE b.id = block_id)));

-- ───────────── Catalog: Winfield only (farms read their program through the cycle snapshot) ─────────────
GRANT SELECT, INSERT, UPDATE ON app.crops, app.varieties, app.threats, app.products, app.crop_programs, app.program_versions TO app_api;
GRANT SELECT ON app.crops, app.varieties, app.threats, app.products, app.crop_programs, app.program_versions TO app_engine, app_readonly;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['crops','varieties','threats','products','crop_programs','program_versions'] LOOP
    EXECUTE format('CREATE POLICY %I ON app.%I FOR SELECT TO app_api, app_readonly USING (app.is_winfield())', t || '_select', t);
    EXECUTE format('CREATE POLICY %I ON app.%I FOR INSERT TO app_api WITH CHECK (app.has_winfield_role(%L))', t || '_insert', t, '{super_admin,agronomist}');
    EXECUTE format('CREATE POLICY %I ON app.%I FOR UPDATE TO app_api USING (app.has_winfield_role(%L)) WITH CHECK (app.has_winfield_role(%L))', t || '_update', t, '{super_admin,agronomist}', '{super_admin,agronomist}');
  END LOOP;
END $$;
CREATE POLICY engine_read_catalog ON app.program_versions FOR SELECT TO app_engine USING (true);
CREATE POLICY engine_read_crops   ON app.crops            FOR SELECT TO app_engine USING (true);
CREATE POLICY engine_read_threats ON app.threats          FOR SELECT TO app_engine USING (true);

-- ───────────── Supply and cycles ─────────────
GRANT SELECT, INSERT, UPDATE ON app.supply_batches, app.crop_cycles TO app_api;
GRANT SELECT ON app.supply_batches, app.crop_cycles TO app_engine, app_readonly;
GRANT UPDATE (projected_end_date, planting_date_confirmed) ON app.crop_cycles TO app_engine;

CREATE POLICY batches_select ON app.supply_batches FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY batches_insert ON app.supply_batches FOR INSERT TO app_api WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY batches_update ON app.supply_batches FOR UPDATE TO app_api USING (app.has_winfield_role('{super_admin,operations}'))
  WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY batches_engine ON app.supply_batches FOR SELECT TO app_engine USING (true);

-- Farm users can read their farm's cycles (including the program snapshot) but can never change them.
CREATE POLICY cycles_select ON app.crop_cycles FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY cycles_insert ON app.crop_cycles FOR INSERT TO app_api WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY cycles_update ON app.crop_cycles FOR UPDATE TO app_api USING (app.has_winfield_role('{super_admin,operations}'))
  WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY cycles_engine_read   ON app.crop_cycles FOR SELECT TO app_engine USING (true);
CREATE POLICY cycles_engine_update ON app.crop_cycles FOR UPDATE TO app_engine USING (status = 'ACTIVE') WITH CHECK (status = 'ACTIVE');

GRANT SELECT ON app.cycle_status_history TO app_api, app_readonly, app_engine;
CREATE POLICY cycle_hist_select ON app.cycle_status_history FOR SELECT TO app_api, app_readonly
  USING (app.is_winfield() OR app.is_farm_member((SELECT c.farm_id FROM app.crop_cycles c WHERE c.id = cycle_id)));
CREATE POLICY cycle_hist_engine ON app.cycle_status_history FOR SELECT TO app_engine USING (true);

-- Engine-owned projections: engine writes, farm and Winfield users read.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['cycle_stages','expected_steps','scouting_records','compliance_snapshots'] LOOP
    EXECUTE format('GRANT SELECT ON app.%I TO app_api, app_readonly', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON app.%I TO app_engine', t);
    EXECUTE format($f$CREATE POLICY %I ON app.%I FOR SELECT TO app_api, app_readonly
       USING (app.is_winfield() OR app.is_farm_member((SELECT c.farm_id FROM app.crop_cycles c WHERE c.id = cycle_id)))$f$, t || '_select', t);
    EXECUTE format('CREATE POLICY %I ON app.%I FOR ALL TO app_engine USING (true) WITH CHECK (true)', t || '_engine', t);
  END LOOP;
END $$;

-- ───────────── Events (the core record) ─────────────
GRANT SELECT, INSERT ON app.events TO app_api;
GRANT SELECT ON app.events TO app_engine, app_readonly;
-- Read: Winfield staff; the farm owner (whole farm); a manager (only their assigned blocks).
CREATE POLICY events_select ON app.events FOR SELECT TO app_api, app_readonly
  USING (app.is_winfield() OR app.is_farm_owner(farm_id) OR app.manages_block(block_id));
CREATE POLICY events_engine ON app.events FOR SELECT TO app_engine USING (true);
-- Write (farm_id / block_id were already overwritten from the cycle by the BEFORE INSERT trigger):
CREATE POLICY events_insert_manager ON app.events FOR INSERT TO app_api
  WITH CHECK (actor_id = app.current_user_id() AND app.manages_block(block_id)
              AND type NOT IN ('annotation','verification'));
CREATE POLICY events_insert_owner_ack ON app.events FOR INSERT TO app_api
  WITH CHECK (actor_id = app.current_user_id() AND app.is_farm_owner(farm_id) AND type = 'ack');
CREATE POLICY events_insert_winfield ON app.events FOR INSERT TO app_api
  WITH CHECK (actor_id = app.current_user_id()
              AND app.has_winfield_role('{agronomist,field_officer,operations,super_admin}')
              AND type IN ('annotation','verification'));

GRANT SELECT, INSERT ON app.media TO app_api;
GRANT SELECT, UPDATE ON app.media TO app_engine;   -- virus-scan result
CREATE POLICY media_select ON app.media FOR SELECT TO app_api USING (app.is_winfield() OR app.is_farm_owner(farm_id) OR
  (app.is_farm_member(farm_id) AND uploaded_by = app.current_user_id()));
CREATE POLICY media_insert ON app.media FOR INSERT TO app_api
  WITH CHECK (uploaded_by = app.current_user_id() AND app.is_farm_member(farm_id));
CREATE POLICY media_engine ON app.media FOR ALL TO app_engine USING (true) WITH CHECK (true);

-- ───────────── Devices and sensor data ─────────────
GRANT SELECT, INSERT, UPDATE ON app.devices TO app_api;
GRANT SELECT ON app.devices TO app_ingest, app_engine, app_readonly;
CREATE POLICY devices_select ON app.devices FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY devices_insert ON app.devices FOR INSERT TO app_api WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY devices_update ON app.devices FOR UPDATE TO app_api USING (app.has_winfield_role('{super_admin,operations}'))
  WITH CHECK (app.has_winfield_role('{super_admin,operations}'));
CREATE POLICY devices_ingest ON app.devices FOR SELECT TO app_ingest USING (true);
CREATE POLICY devices_engine ON app.devices FOR SELECT TO app_engine USING (true);

GRANT SELECT, INSERT, UPDATE ON app.device_credentials TO app_ingest;
CREATE POLICY devcred_ingest ON app.device_credentials FOR ALL TO app_ingest USING (true) WITH CHECK (true);

GRANT INSERT ON app.observations TO app_ingest;
GRANT SELECT ON app.observations TO app_api, app_engine, app_readonly;
CREATE POLICY obs_ingest_insert ON app.observations FOR INSERT TO app_ingest WITH CHECK (true);
CREATE POLICY obs_select ON app.observations FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY obs_engine ON app.observations FOR SELECT TO app_engine USING (true);

-- ───────────── Alerts, amendments, notifications ─────────────
GRANT SELECT ON app.alerts TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON app.alerts TO app_engine;
CREATE POLICY alerts_select ON app.alerts FOR SELECT TO app_api, app_readonly USING (app.is_winfield() OR app.is_farm_member(farm_id));
CREATE POLICY alerts_engine ON app.alerts FOR ALL TO app_engine USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON app.amendments TO app_api;
GRANT SELECT ON app.amendments TO app_engine, app_readonly;
CREATE POLICY amend_select ON app.amendments FOR SELECT TO app_api, app_readonly
  USING (app.is_winfield() OR app.is_farm_member((SELECT c.farm_id FROM app.crop_cycles c WHERE c.id = cycle_id)));
CREATE POLICY amend_insert ON app.amendments FOR INSERT TO app_api
  WITH CHECK (created_by = app.current_user_id() AND app.has_winfield_role('{super_admin,agronomist}'));
CREATE POLICY amend_engine ON app.amendments FOR SELECT TO app_engine USING (true);

GRANT SELECT, INSERT, UPDATE ON app.notification_outbox TO app_engine;
GRANT SELECT ON app.notification_outbox TO app_api;
CREATE POLICY outbox_engine ON app.notification_outbox FOR ALL TO app_engine USING (true) WITH CHECK (true);
CREATE POLICY outbox_self   ON app.notification_outbox FOR SELECT TO app_api USING (user_id = app.current_user_id() OR app.has_winfield_role('{super_admin}'));

-- ───────────── Audit and settings ─────────────
GRANT SELECT ON app.audit_log TO app_api, app_readonly;
CREATE POLICY audit_select ON app.audit_log FOR SELECT TO app_api, app_readonly USING (app.has_winfield_role('{super_admin,analyst}'));
-- No INSERT policy or grant: rows enter only through app.write_audit() (SECURITY DEFINER).
GRANT EXECUTE ON FUNCTION app.write_audit(text,text,uuid,text,inet,jsonb) TO app_api, app_auth, app_engine, app_ingest;
GRANT USAGE ON SEQUENCE app.audit_log_id_seq TO app_api;   -- harmless; inserts go through the definer function

GRANT SELECT, UPDATE ON app.system_settings TO app_api;
GRANT SELECT ON app.system_settings TO app_engine;
CREATE POLICY settings_select ON app.system_settings FOR SELECT TO app_api USING (app.is_winfield());
CREATE POLICY settings_update ON app.system_settings FOR UPDATE TO app_api USING (app.has_winfield_role('{super_admin}')) WITH CHECK (app.has_winfield_role('{super_admin}'));
CREATE POLICY settings_engine ON app.system_settings FOR SELECT TO app_engine USING (true);

-- Helper functions the API role needs to call
GRANT EXECUTE ON FUNCTION app.current_user_id(), app.winfield_role(), app.is_winfield(), app.has_winfield_role(text[]),
  app.is_farm_member(uuid), app.is_farm_owner(uuid), app.manages_block(uuid), app.setting_bool(text),
  app.farm_team(uuid), app.verify_cycle_chain(uuid) TO app_api, app_readonly, app_engine;
GRANT EXECUTE ON FUNCTION app.current_user_id() TO app_auth, app_ingest;
GRANT EXECUTE ON FUNCTION app.compute_event_hash(bytea,uuid,uuid,bigint,uuid,text,timestamptz,uuid,jsonb) TO app_api, app_engine;
