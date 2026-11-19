-- 003_functions_triggers.sql — identity helpers, integrity rules, activation gate, hash chain.
-- These are the DATABASE-LEVEL enforcement of the rules in the build spec. The API checks the same rules for good
-- error messages, but the database is the last line of defence: even a buggy or compromised API cannot break them.

SET search_path = app, public;

-- ───────────── Identity helpers (the API sets app.user_id once per request, inside the transaction) ─────────────
-- The API does:   SELECT set_config('app.user_id', '<uuid from verified JWT>', true);   -- true = transaction-local
CREATE FUNCTION app.current_user_id() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('app.user_id', true), '')::uuid $$;

-- Roles and memberships are looked up from the tables (not from JWT claims) so revoking access takes effect at once.
CREATE FUNCTION app.winfield_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT winfield_role FROM app.users WHERE id = app.current_user_id() AND is_active $$;

CREATE FUNCTION app.is_winfield() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT app.winfield_role() IS NOT NULL $$;

CREATE FUNCTION app.has_winfield_role(roles text[]) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT COALESCE(app.winfield_role() = ANY(roles), false) $$;

CREATE FUNCTION app.is_farm_member(f uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT EXISTS (SELECT 1 FROM app.farm_memberships m JOIN app.users u ON u.id = m.user_id
                  WHERE m.farm_id = f AND m.user_id = app.current_user_id() AND m.active AND u.is_active) $$;

CREATE FUNCTION app.is_farm_owner(f uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT EXISTS (SELECT 1 FROM app.farm_memberships m JOIN app.users u ON u.id = m.user_id
                  WHERE m.farm_id = f AND m.user_id = app.current_user_id() AND m.active AND u.is_active AND m.farm_role = 'owner') $$;

CREATE FUNCTION app.manages_block(b uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT EXISTS (SELECT 1 FROM app.block_assignments ba
                  JOIN app.blocks bl ON bl.id = ba.block_id
                  JOIN app.farm_memberships m ON m.farm_id = bl.farm_id AND m.user_id = ba.user_id
                  JOIN app.users u ON u.id = ba.user_id
                  WHERE ba.block_id = b AND ba.user_id = app.current_user_id()
                    AND m.active AND u.is_active AND m.farm_role = 'manager') $$;

CREATE FUNCTION app.setting_bool(k text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS
$$ SELECT COALESCE((SELECT (value)::text::boolean FROM app.system_settings WHERE key = k), false) $$;

-- Team list for a farm without exposing other users' emails or phones.
CREATE FUNCTION app.farm_team(p_farm uuid)
RETURNS TABLE (user_id uuid, display_name text, farm_role text, block_ids uuid[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT m.user_id, u.display_name, m.farm_role,
         COALESCE(array_agg(ba.block_id) FILTER (WHERE ba.block_id IS NOT NULL), '{}')
  FROM app.farm_memberships m
  JOIN app.users u ON u.id = m.user_id
  LEFT JOIN app.block_assignments ba ON ba.user_id = m.user_id
       AND ba.block_id IN (SELECT id FROM app.blocks WHERE farm_id = p_farm)
  WHERE m.farm_id = p_farm AND m.active AND (app.is_farm_member(p_farm) OR app.is_winfield())
  GROUP BY m.user_id, u.display_name, m.farm_role
$$;

-- ───────────── Audit writer (the only way rows enter audit_log) ─────────────
CREATE FUNCTION app.write_audit(p_action text, p_resource text, p_farm uuid, p_result text, p_ip inet DEFAULT NULL, p_meta jsonb DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = app, pg_temp AS $$
  INSERT INTO app.audit_log(actor_id, actor_role, action, resource, farm_id, result, ip, meta)
  VALUES (app.current_user_id(),
          COALESCE(app.winfield_role(),
                   (SELECT m.farm_role FROM app.farm_memberships m
                     WHERE m.user_id = app.current_user_id() AND m.farm_id = p_farm AND m.active LIMIT 1)),
          p_action, p_resource, p_farm, p_result, p_ip, p_meta)
$$;

-- ───────────── Immutability ─────────────
CREATE FUNCTION app.trg_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only: % is not allowed. Add a correcting row instead.', TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'integrity_constraint_violation';
END $$;

CREATE TRIGGER events_immutable        BEFORE UPDATE OR DELETE ON app.events        FOR EACH ROW EXECUTE FUNCTION app.trg_immutable();
CREATE TRIGGER amendments_immutable    BEFORE UPDATE OR DELETE ON app.amendments    FOR EACH ROW EXECUTE FUNCTION app.trg_immutable();
CREATE TRIGGER audit_immutable         BEFORE UPDATE OR DELETE ON app.audit_log     FOR EACH ROW EXECUTE FUNCTION app.trg_immutable();
CREATE TRIGGER observations_immutable  BEFORE UPDATE OR DELETE ON app.observations  FOR EACH ROW EXECUTE FUNCTION app.trg_immutable();
CREATE TRIGGER events_no_truncate      BEFORE TRUNCATE ON app.events      FOR EACH STATEMENT EXECUTE FUNCTION app.trg_immutable();
CREATE TRIGGER amendments_no_truncate  BEFORE TRUNCATE ON app.amendments  FOR EACH STATEMENT EXECUTE FUNCTION app.trg_immutable();
CREATE TRIGGER audit_no_truncate       BEFORE TRUNCATE ON app.audit_log   FOR EACH STATEMENT EXECUTE FUNCTION app.trg_immutable();

-- ───────────── Event hash chain ─────────────
CREATE FUNCTION app.compute_event_hash(prev bytea, p_id uuid, p_cycle uuid, p_seq bigint, p_actor uuid,
                                       p_type text, p_occurred timestamptz, p_client uuid, p_payload jsonb)
RETURNS bytea LANGUAGE sql IMMUTABLE AS $$
  SELECT digest(
    COALESCE(prev, '\x'::bytea) ||
    convert_to(concat_ws('|', p_id, p_cycle, p_seq, p_actor, p_type,
                         to_char(p_occurred AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
                         p_client, p_payload::text), 'UTF8'),
    'sha256')
$$;

-- Runs BEFORE every event insert. This is the Winfield activation gate AND the tamper-evidence mechanism.
CREATE FUNCTION app.trg_events_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public, pg_temp AS $$
DECLARE c record; last_hash bytea; last_seq bigint; status_then text;
BEGIN
  SELECT id, farm_id, block_id, status INTO c FROM app.crop_cycles WHERE id = NEW.cycle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cycle % does not exist', NEW.cycle_id USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- THE GATE: nothing operational is recorded unless Winfield has activated the cycle.
  -- Offline-first twist: a late-synced event is judged by the cycle's status WHEN IT HAPPENED, not when it arrived.
  IF NEW.type = 'ack' AND c.status IN ('ACTIVE','SUSPENDED') THEN
    NULL;   -- safety alerts can still be acknowledged while suspended
  ELSIF c.status IN ('DRAFT','PENDING_ACTIVATION') THEN
    RAISE EXCEPTION 'Cycle is % — operational data cannot be recorded. Awaiting Winfield activation.', c.status
      USING ERRCODE = 'check_violation';
  ELSIF c.status = 'CLOSED' THEN
    RAISE EXCEPTION 'Cycle is CLOSED and archived — no further data can be recorded.' USING ERRCODE = 'check_violation';
  ELSE
    -- ACTIVE, SUSPENDED, COMPLETED or TERMINATED now. What was the status when the work happened?
    -- (10 minutes of tolerance so a slightly slow phone clock right after activation is not punished)
    SELECT h.status INTO status_then FROM app.cycle_status_history h
      WHERE h.cycle_id = NEW.cycle_id AND h.changed_at <= NEW.occurred_at + interval '10 minutes'
      ORDER BY h.changed_at DESC, h.id DESC LIMIT 1;
    IF status_then IS DISTINCT FROM 'ACTIVE' THEN
      RAISE EXCEPTION 'Cycle is % now and was % when this happened — operational data cannot be recorded for that period.',
        c.status, COALESCE(status_then, 'not yet created') USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  NEW.farm_id     := c.farm_id;      -- never trust the client for tenancy
  NEW.block_id    := c.block_id;
  NEW.received_at := clock_timestamp();

  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.cycle_id::text, 0));
  SELECT hash, seq INTO last_hash, last_seq FROM app.events WHERE cycle_id = NEW.cycle_id ORDER BY seq DESC LIMIT 1;
  NEW.seq       := COALESCE(last_seq, 0) + 1;
  NEW.prev_hash := last_hash;
  NEW.hash      := app.compute_event_hash(last_hash, NEW.id, NEW.cycle_id, NEW.seq, NEW.actor_id,
                                          NEW.type, NEW.occurred_at, NEW.client_event_id, NEW.payload);
  RETURN NEW;
END $$;
CREATE TRIGGER events_guard BEFORE INSERT ON app.events FOR EACH ROW EXECUTE FUNCTION app.trg_events_guard();

-- Returns (true, NULL) if every event in the cycle still matches its hash; otherwise the first broken sequence number.
CREATE FUNCTION app.verify_cycle_chain(p_cycle uuid) RETURNS TABLE (ok boolean, first_bad_seq bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = app, public, pg_temp AS $$
DECLARE r record; prev bytea := NULL; calc bytea;
BEGIN
  FOR r IN SELECT * FROM app.events WHERE cycle_id = p_cycle ORDER BY seq LOOP
    calc := app.compute_event_hash(prev, r.id, r.cycle_id, r.seq, r.actor_id, r.type, r.occurred_at, r.client_event_id, r.payload);
    IF calc <> r.hash OR r.prev_hash IS DISTINCT FROM prev THEN
      RETURN QUERY SELECT false, r.seq; RETURN;
    END IF;
    prev := r.hash;
  END LOOP;
  RETURN QUERY SELECT true, NULL::bigint;
END $$;

-- ───────────── Program versions: maker-checker + immutability once approved ─────────────
CREATE FUNCTION app.trg_program_version_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public, pg_temp AS $$
DECLARE role_a text; role_r text; me uuid := app.current_user_id();
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'DRAFT' THEN RAISE EXCEPTION 'new program versions must start as DRAFT'; END IF;
    RETURN NEW;
  END IF;

  IF NEW.authored_by <> OLD.authored_by OR NEW.program_id <> OLD.program_id OR NEW.version_no <> OLD.version_no THEN
    RAISE EXCEPTION 'author, program and version number can never change';
  END IF;

  IF OLD.status IN ('APPROVED','RETIRED') THEN
    IF NEW.content IS DISTINCT FROM OLD.content OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by THEN
      RAISE EXCEPTION 'approved program versions are immutable — create a new version instead';
    END IF;
    IF NEW.status <> OLD.status AND NOT (OLD.status = 'APPROVED' AND NEW.status = 'RETIRED') THEN
      RAISE EXCEPTION 'illegal status change % -> %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
  END IF;

  -- OLD is DRAFT or IN_REVIEW
  IF NEW.status = 'APPROVED' THEN
    IF OLD.status <> 'IN_REVIEW' THEN RAISE EXCEPTION 'only versions IN_REVIEW can be approved'; END IF;
    IF NEW.reviewed_by IS NULL OR NEW.reviewed_by = NEW.authored_by THEN
      RAISE EXCEPTION 'maker-checker: the reviewer must be a different person from the author';
    END IF;
    IF me IS NOT NULL AND NEW.reviewed_by <> me THEN
      RAISE EXCEPTION 'reviewed_by must be the person making this change';
    END IF;
    SELECT winfield_role INTO role_a FROM app.users WHERE id = NEW.authored_by;
    SELECT winfield_role INTO role_r FROM app.users WHERE id = NEW.reviewed_by AND is_active;
    IF role_a IS DISTINCT FROM 'agronomist' OR role_r IS DISTINCT FROM 'agronomist' THEN
      RAISE EXCEPTION 'both author and reviewer must be Winfield agronomists';
    END IF;
    NEW.published_at := now();
  ELSIF NEW.status = 'RETIRED' THEN
    RAISE EXCEPTION 'only APPROVED versions can be retired';
  ELSIF NEW.status NOT IN ('DRAFT','IN_REVIEW') THEN
    RAISE EXCEPTION 'illegal status %', NEW.status;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER program_version_guard BEFORE INSERT OR UPDATE ON app.program_versions
  FOR EACH ROW EXECUTE FUNCTION app.trg_program_version_guard();

-- ───────────── Crop cycles: state machine, frozen snapshot, two-person activation ─────────────
CREATE FUNCTION app.trg_cycle_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public, pg_temp AS $$
DECLARE pv record; sb record; ap text; me uuid := app.current_user_id(); farm_status text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'DRAFT' THEN RAISE EXCEPTION 'cycles are created as DRAFT'; END IF;
    SELECT v.status, v.content, p.crop_id, c.cycle_type INTO pv
      FROM app.program_versions v JOIN app.crop_programs p ON p.id = v.program_id JOIN app.crops c ON c.id = p.crop_id
      WHERE v.id = NEW.program_version_id;
    IF pv.status IS DISTINCT FROM 'APPROVED' THEN
      RAISE EXCEPTION 'only APPROVED program versions can be attached to a cycle (found %)', COALESCE(pv.status, 'none');
    END IF;
    SELECT crop_id, supply_date INTO sb FROM app.supply_batches WHERE id = NEW.supply_batch_id;
    IF sb.crop_id IS DISTINCT FROM pv.crop_id THEN
      RAISE EXCEPTION 'the supply batch crop does not match the program crop';
    END IF;
    NEW.program_snapshot := pv.content;               -- frozen now; later edits can never change an in-flight cycle
    NEW.cycle_type       := pv.cycle_type;
    NEW.clock_start_date := COALESCE(NEW.clock_start_date, sb.supply_date);
    NEW.requested_by := NULL; NEW.approved_by := NULL; NEW.requested_at := NULL; NEW.approved_at := NULL;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF NEW.farm_id <> OLD.farm_id OR NEW.block_id <> OLD.block_id OR NEW.supply_batch_id <> OLD.supply_batch_id
     OR NEW.program_version_id <> OLD.program_version_id OR NEW.program_snapshot IS DISTINCT FROM OLD.program_snapshot
     OR NEW.cycle_type <> OLD.cycle_type OR NEW.created_by <> OLD.created_by
     OR NEW.parent_cycle_id IS DISTINCT FROM OLD.parent_cycle_id THEN
    RAISE EXCEPTION 'farm, block, supply batch, program version and snapshot are fixed for the life of a cycle (use an amendment)';
  END IF;

  IF NEW.status <> OLD.status THEN
    IF NOT ((OLD.status, NEW.status) IN (
        ('DRAFT','PENDING_ACTIVATION'), ('PENDING_ACTIVATION','DRAFT'), ('PENDING_ACTIVATION','ACTIVE'),
        ('ACTIVE','SUSPENDED'), ('SUSPENDED','ACTIVE'), ('ACTIVE','COMPLETED'), ('ACTIVE','TERMINATED'),
        ('SUSPENDED','TERMINATED'), ('COMPLETED','CLOSED'), ('TERMINATED','CLOSED'))) THEN
      RAISE EXCEPTION 'illegal cycle status change % -> %', OLD.status, NEW.status;
    END IF;

    IF NEW.status = 'PENDING_ACTIVATION' THEN
      NEW.requested_by := COALESCE(me, NEW.requested_by);
      IF NEW.requested_by IS NULL THEN RAISE EXCEPTION 'an activation request needs a requester'; END IF;
      NEW.requested_at := now(); NEW.approved_by := NULL; NEW.approved_at := NULL;

    ELSIF NEW.status = 'DRAFT' THEN
      NEW.requested_by := NULL; NEW.requested_at := NULL;

    ELSIF NEW.status = 'ACTIVE' AND OLD.status = 'PENDING_ACTIVATION' THEN
      SELECT status INTO farm_status FROM app.farms WHERE id = NEW.farm_id;
      IF farm_status <> 'ACTIVE' THEN RAISE EXCEPTION 'the farm account is %, so cycles cannot be activated', farm_status; END IF;
      IF (SELECT c.is_demo FROM app.crops c JOIN app.crop_programs p ON p.crop_id = c.id
            JOIN app.program_versions v ON v.program_id = p.id WHERE v.id = NEW.program_version_id)
         AND NOT app.setting_bool('allow_demo_cycles') THEN
        RAISE EXCEPTION 'demo crops cannot be activated in this environment';
      END IF;
      IF NEW.approved_by IS NULL THEN RAISE EXCEPTION 'activation needs an approver'; END IF;
      IF me IS NOT NULL AND NEW.approved_by <> me THEN RAISE EXCEPTION 'approved_by must be the person making this change'; END IF;
      SELECT winfield_role INTO ap FROM app.users WHERE id = NEW.approved_by AND is_active;
      IF ap IS NULL OR ap NOT IN ('super_admin','operations') THEN
        RAISE EXCEPTION 'only an active Winfield super admin or operations user can approve an activation';
      END IF;
      IF app.setting_bool('require_two_person_activation') AND NEW.approved_by = NEW.requested_by THEN
        RAISE EXCEPTION 'two-person rule: the approver must be a different person from the requester';
      END IF;
      NEW.approved_at := now();

    ELSIF NEW.status IN ('SUSPENDED','TERMINATED') THEN
      IF COALESCE(length(NEW.status_reason), 0) < 5 THEN
        RAISE EXCEPTION 'a reason is required when moving a cycle to %', NEW.status;
      END IF;
    END IF;
  ELSE
    -- no status change: approval fields may not be altered by hand
    IF NEW.requested_by IS DISTINCT FROM OLD.requested_by OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
       OR NEW.requested_at IS DISTINCT FROM OLD.requested_at OR NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
      RAISE EXCEPTION 'approval fields change only through a status transition';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER cycle_guard BEFORE INSERT OR UPDATE ON app.crop_cycles
  FOR EACH ROW EXECUTE FUNCTION app.trg_cycle_guard();

-- Record every status change (used by the event gate above).
CREATE FUNCTION app.trg_cycle_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO app.cycle_status_history(cycle_id, status, changed_by) VALUES (NEW.id, NEW.status, app.current_user_id());
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER cycle_history AFTER INSERT OR UPDATE ON app.crop_cycles FOR EACH ROW EXECUTE FUNCTION app.trg_cycle_history();
CREATE TRIGGER cycle_history_immutable BEFORE UPDATE OR DELETE ON app.cycle_status_history FOR EACH ROW EXECUTE FUNCTION app.trg_immutable();

-- Amendments are only allowed on live cycles.
CREATE FUNCTION app.trg_amendment_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, pg_temp AS $$
DECLARE s text;
BEGIN
  SELECT status INTO s FROM app.crop_cycles WHERE id = NEW.cycle_id;
  IF s NOT IN ('ACTIVE','SUSPENDED') THEN RAISE EXCEPTION 'cycles in status % cannot be amended', s; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER amendment_guard BEFORE INSERT ON app.amendments FOR EACH ROW EXECUTE FUNCTION app.trg_amendment_guard();

-- ───────────── Sensor observations: tenancy comes from the registered device, never from the sender ─────────────
CREATE FUNCTION app.trg_observation_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, pg_temp AS $$
DECLARE d record;
BEGIN
  SELECT farm_id, block_id, status INTO d FROM app.devices WHERE id = NEW.device_id;
  IF NOT FOUND OR d.status <> 'ACTIVE' THEN RAISE EXCEPTION 'unknown or inactive device'; END IF;
  NEW.farm_id := d.farm_id; NEW.block_id := d.block_id; NEW.received_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER observation_guard BEFORE INSERT ON app.observations FOR EACH ROW EXECUTE FUNCTION app.trg_observation_guard();
