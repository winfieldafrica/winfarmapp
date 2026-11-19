#!/usr/bin/env python3
"""
Winfield database test suite.
Each test runs in its own transaction that is ALWAYS rolled back, as a given DB role + app user,
and expects either success ("ok") or a failure containing a specific phrase.

Usage:  PGHOST=... PGPORT=... PGUSER=postgres PGDATABASE=wf python3 tests/run_tests.py
"""
import os, subprocess, sys

U = lambda x: f"00000000-0000-0000-0000-0000000000{x}"
SUPER, OPS1, OPS2, AGR1, AGR2, ANALYST, FIELD = U("a1"), U("a2"), U("a3"), U("a4"), U("a5"), U("a6"), U("a7")
OWNER_A, MGR_A1, MGR_A2, OWNER_B, MGR_B, SPARE = U("b1"), U("b2"), U("b3"), U("c1"), U("c2"), U("c9")
FARM_A, FARM_B = U("f1"), U("f2")
BLK_A1, BLK_A2, BLK_B1 = U("e1"), U("e2"), U("e3")
CYC_A1, CYC_B1, CYC_A2_DRAFT = ("00000000-0000-0000-0000-0000000000c1", "00000000-0000-0000-0000-0000000000c2", "00000000-0000-0000-0000-0000000000c3")
PV_APPROVED, PV_DRAFT = U("d3"), U("d4")
PROGRAM, CROP = U("d2"), U("d1")
BATCH_A1 = "00000000-0000-0000-0000-00000000ba01"
BATCH_A2 = "00000000-0000-0000-0000-00000000ba03"
DEVICE = U("dd")

def ev(cycle, actor, typ="work_log", cid=None, extra=""):
    import uuid
    cid = cid or str(uuid.uuid4())
    return (f"INSERT INTO app.events(cycle_id,actor_id,type,occurred_at,payload,client_event_id{extra and ','+extra.split('=')[0]}) "
            f"VALUES ('{cycle}','{actor}','{typ}',now(),'{{}}','{cid}'{extra and ','+extra.split('=')[1]});")

def count_is(sql, n):
    return f"DO $$ DECLARE c int; BEGIN SELECT count(*) INTO c FROM ({sql}) q; IF c <> {n} THEN RAISE EXCEPTION 'expected {n} rows, got %', c; END IF; END $$;"

def rows_affected_is(dml, n):
    return (f"DO $$ DECLARE c int; BEGIN {dml} GET DIAGNOSTICS c = ROW_COUNT; "
            f"IF c <> {n} THEN RAISE EXCEPTION 'expected {n} rows affected, got %', c; END IF; END $$;")

# (name, pre-SQL as superuser, db role, app user, SQL, expectation: "ok" or phrase that must appear in the error)
T = []
def t(name, role, user, sql, expect="ok", pre=""):
    T.append((name, pre, role, user, sql, expect))

# ───────── Tenant isolation ─────────
t("Manager sees only their own farm",              "app_api", MGR_A1, count_is("SELECT 1 FROM app.farms", 1))
t("Manager cannot see another farm's events",      "app_api", MGR_A1, count_is(f"SELECT 1 FROM app.events WHERE farm_id='{FARM_B}'", 0))
t("Manager sees events only for assigned blocks",  "app_api", MGR_A2, count_is("SELECT 1 FROM app.events", 0))
t("Assigned manager sees their block's events",    "app_api", MGR_A1, count_is("SELECT 1 FROM app.events", 1))
t("Owner sees all events on own farm",             "app_api", OWNER_A, count_is("SELECT 1 FROM app.events", 1))
t("Other farm's owner sees nothing of farm A",     "app_api", OWNER_B, count_is(f"SELECT 1 FROM app.events WHERE farm_id='{FARM_A}'", 0))
t("Winfield analyst sees every farm's events",     "app_api", ANALYST, count_is("SELECT 1 FROM app.events", 2))
t("Farm users cannot read the Winfield catalog",   "app_api", MGR_A1, count_is("SELECT 1 FROM app.crops", 0))
t("Winfield staff can read the catalog",           "app_api", ANALYST, count_is("SELECT 1 FROM app.crops", 1))
t("Manager sees only their own user row",          "app_api", MGR_A1, count_is("SELECT 1 FROM app.users", 1))
t("Manager cannot read credentials",               "app_api", MGR_A1, "SELECT * FROM app.user_credentials;", "permission denied")
t("API role cannot read refresh tokens",           "app_api", MGR_A1, "SELECT * FROM app.refresh_tokens;", "permission denied")
t("Login service can read credentials",            "app_auth", None, count_is("SELECT 1 FROM app.user_credentials", 1))
t("Team list hides emails but shows own farm",     "app_api", MGR_A1, count_is(f"SELECT * FROM app.farm_team('{FARM_A}')", 3))
t("Team list is empty for another farm",           "app_api", MGR_A1, count_is(f"SELECT * FROM app.farm_team('{FARM_B}')", 0))
t("Farm user cannot see another farm's cycles",    "app_api", MGR_A1, count_is(f"SELECT 1 FROM app.crop_cycles WHERE farm_id='{FARM_B}'", 0))

# ───────── The Winfield activation gate ─────────
t("Manager can log on an ACTIVE cycle",            "app_api", MGR_A1, ev(CYC_A1, MGR_A1))
t("Manager cannot log on a cycle not yet activated","app_api", MGR_A2, ev(CYC_A2_DRAFT, MGR_A2), "Awaiting Winfield activation")
t("Manager cannot log on another block's cycle",   "app_api", MGR_A2, ev(CYC_A1, MGR_A2), "row-level security")
t("Manager cannot log on another farm's cycle",    "app_api", MGR_A1, ev(CYC_B1, MGR_A1), "row-level security")
t("Cannot log as someone else",                    "app_api", MGR_A1, ev(CYC_A1, MGR_A2), "row-level security")
t("Client cannot choose tenancy: farm/block are overwritten from the cycle", "app_api", MGR_A1,
  ev(CYC_A1, MGR_A1, cid="20000000-0000-0000-0000-000000000001", extra=f"farm_id='{FARM_B}'") +
  f"DO $$ BEGIN IF (SELECT farm_id FROM app.events WHERE client_event_id='20000000-0000-0000-0000-000000000001') <> '{FARM_A}' THEN RAISE EXCEPTION 'tenancy leaked'; END IF; END $$;")
t("Owner may acknowledge alerts",                  "app_api", OWNER_A, ev(CYC_A1, OWNER_A, "ack"))
t("Owner cannot write work logs",                  "app_api", OWNER_A, ev(CYC_A1, OWNER_A, "work_log"), "row-level security")
t("Manager cannot write Winfield annotations",     "app_api", MGR_A1, ev(CYC_A1, MGR_A1, "annotation"), "row-level security")
t("Duplicate offline retry is rejected (idempotent)", "app_api", MGR_A1,
  ev(CYC_A1, MGR_A1, cid="10000000-0000-0000-0000-000000000001"), "duplicate key")
t("Suspended cycle blocks work logs",              "app_api", MGR_A1, ev(CYC_A1, MGR_A1), "SUSPENDED",
  pre=f"UPDATE app.crop_cycles SET status='SUSPENDED', status_reason='contract review' WHERE id='{CYC_A1}';")
t("Suspended cycle still allows safety acknowledgement", "app_api", MGR_A1, ev(CYC_A1, MGR_A1, "ack"),
  pre=f"UPDATE app.crop_cycles SET status='SUSPENDED', status_reason='contract review' WHERE id='{CYC_A1}';")

# ───────── Offline work is judged by when it HAPPENED ─────────
BACKDATE = lambda cyc, status, mins: (f"ALTER TABLE app.cycle_status_history DISABLE TRIGGER cycle_history_immutable;"
    f"UPDATE app.cycle_status_history SET changed_at = now() - interval '{mins} minutes' WHERE cycle_id='{cyc}' AND status='{status}';"
    f"ALTER TABLE app.cycle_status_history ENABLE TRIGGER cycle_history_immutable;")
SUSPEND_30M_AGO = (BACKDATE(CYC_A1, "ACTIVE", 2*24*60) +
    f"UPDATE app.crop_cycles SET status='SUSPENDED', status_reason='contract review' WHERE id='{CYC_A1}';" +
    BACKDATE(CYC_A1, "SUSPENDED", 30))
def ev_at(cycle, actor, when_sql):
    import uuid
    return (f"INSERT INTO app.events(cycle_id,actor_id,type,occurred_at,payload,client_event_id) "
            f"VALUES ('{cycle}','{actor}','work_log',{when_sql},'{{}}','{uuid.uuid4()}');")
t("Offline work done BEFORE a suspension is accepted on late sync", "app_api", MGR_A1, ev_at(CYC_A1, MGR_A1, "now() - interval '1 hour'"), pre=SUSPEND_30M_AGO)
t("Work done AFTER the suspension is still refused",               "app_api", MGR_A1, ev_at(CYC_A1, MGR_A1, "now() - interval '10 minutes'"), "SUSPENDED", pre=SUSPEND_30M_AGO)
t("Work dated before activation is refused",                       "app_api", MGR_A1, ev_at(CYC_A1, MGR_A1, "now() - interval '3 days'"), "was not yet created",
  pre=BACKDATE(CYC_A1, "ACTIVE", 2*24*60))
t("Late-synced work is accepted after the cycle completes",        "app_api", MGR_A1, ev_at(CYC_A1, MGR_A1, "now() - interval '1 hour'"),
  pre=BACKDATE(CYC_A1, "ACTIVE", 2*24*60) + f"UPDATE app.crop_cycles SET status='COMPLETED' WHERE id='{CYC_A1}';")
t("Nothing can be added once a cycle is CLOSED",                   "postgres", None, ev_at(CYC_A1, MGR_A1, "now()"), "CLOSED",
  pre=f"UPDATE app.crop_cycles SET status='COMPLETED' WHERE id='{CYC_A1}'; UPDATE app.crop_cycles SET status='CLOSED' WHERE id='{CYC_A1}';")
t("Status history cannot be rewritten",                            "postgres", None, "UPDATE app.cycle_status_history SET status='ACTIVE';", "append-only")

# ───────── Immutability and tamper evidence ─────────
t("Events cannot be updated (even by a superuser)", "postgres", None, "UPDATE app.events SET payload='{}';", "append-only")
t("Events cannot be deleted (even by a superuser)", "postgres", None, "DELETE FROM app.events;", "append-only")
t("Events cannot be truncated (even with CASCADE)", "postgres", None, "TRUNCATE app.events CASCADE;", "append-only")
t("API role has no UPDATE right on events",        "app_api", MGR_A1, "UPDATE app.events SET payload='{}';", "permission denied")
t("Audit log rows cannot be deleted",              "postgres", None, "DELETE FROM app.audit_log;", "append-only",
  pre="SELECT app.write_audit('seed','x',NULL,'allowed');")
t("Audit log rows cannot be edited",               "postgres", None, "UPDATE app.audit_log SET result='denied';", "append-only",
  pre="SELECT app.write_audit('seed','x',NULL,'allowed');")
t("Audit log cannot be truncated",                 "postgres", None, "TRUNCATE app.audit_log;", "append-only")
t("Hash chain verifies for an untouched cycle",    "postgres", None,
  ev(CYC_A1, MGR_A1) + ev(CYC_A1, MGR_A1) +
  f"DO $$ BEGIN IF NOT (SELECT ok FROM app.verify_cycle_chain('{CYC_A1}')) THEN RAISE EXCEPTION 'chain broken'; END IF; END $$;")
t("Hash chain detects tampering",                  "postgres", None,
  ev(CYC_A1, MGR_A1) +
  "ALTER TABLE app.events DISABLE TRIGGER events_immutable;" +
  f"UPDATE app.events SET payload='{{\"forged\":true}}' WHERE cycle_id='{CYC_A1}' AND seq=1;" +
  f"DO $$ BEGIN IF (SELECT ok FROM app.verify_cycle_chain('{CYC_A1}')) THEN RAISE EXCEPTION 'tampering NOT detected'; END IF; END $$;")

# ───────── Activation workflow and two-person rule ─────────
REQUEST = f"UPDATE app.crop_cycles SET status='PENDING_ACTIVATION' WHERE id='{CYC_A2_DRAFT}';"
t("Operations can request an activation",          "app_api", OPS1, REQUEST)
t("Requester cannot approve their own request",    "app_api", OPS1, REQUEST + f"UPDATE app.crop_cycles SET status='ACTIVE', approved_by='{OPS1}' WHERE id='{CYC_A2_DRAFT}';", "two-person rule")
t("A second person approves and the farm can then log", "postgres", None,
  f"SET LOCAL app.user_id='{OPS1}';" + REQUEST +
  f"SET LOCAL app.user_id='{OPS2}';UPDATE app.crop_cycles SET status='ACTIVE', approved_by='{OPS2}' WHERE id='{CYC_A2_DRAFT}';" +
  ev(CYC_A2_DRAFT, MGR_A2))
t("Approver cannot impersonate another approver",  "postgres", None,
  f"SET LOCAL app.user_id='{OPS1}';" + REQUEST +
  f"SET LOCAL app.user_id='{OPS1}';UPDATE app.crop_cycles SET status='ACTIVE', approved_by='{OPS2}' WHERE id='{CYC_A2_DRAFT}';", "person making this change")
t("Agronomist cannot activate cycles",             "app_api", AGR1, rows_affected_is(f"UPDATE app.crop_cycles SET status='PENDING_ACTIVATION' WHERE id='{CYC_A2_DRAFT}';", 0))
t("Farm owner cannot change a cycle",              "app_api", OWNER_A, rows_affected_is(f"UPDATE app.crop_cycles SET status='TERMINATED' WHERE id='{CYC_A1}';", 0))
t("Farm manager cannot change a cycle",            "app_api", MGR_A1, rows_affected_is(f"UPDATE app.crop_cycles SET status='TERMINATED' WHERE id='{CYC_A1}';", 0))
t("Cannot skip straight from DRAFT to ACTIVE",     "postgres", None, f"UPDATE app.crop_cycles SET status='ACTIVE', approved_by='{OPS2}' WHERE id='{CYC_A2_DRAFT}';", "illegal cycle status change")
t("Suspending needs a reason",                     "postgres", None, f"UPDATE app.crop_cycles SET status='SUSPENDED' WHERE id='{CYC_A1}';", "reason is required")
t("A cycle cannot use a DRAFT program version",    "app_api", OPS1,
  f"INSERT INTO app.crop_cycles(farm_id,block_id,supply_batch_id,program_version_id,created_by) VALUES ('{FARM_A}','{BLK_A2}','{BATCH_A2}','{PV_DRAFT}','{OPS1}');",
  "only APPROVED program versions")
t("Program snapshot is frozen",                    "postgres", None, f"UPDATE app.crop_cycles SET program_snapshot='{{}}' WHERE id='{CYC_A1}';", "fixed for the life of a cycle")
t("Single-approver mode works when switched on",   "postgres", None,
  "UPDATE app.system_settings SET value='false'::jsonb WHERE key='require_two_person_activation';" +
  f"SET LOCAL app.user_id='{OPS1}';" + REQUEST +
  f"UPDATE app.crop_cycles SET status='ACTIVE', approved_by='{OPS1}' WHERE id='{CYC_A2_DRAFT}';")

# ───────── Program authoring: maker-checker ─────────
NEWV = f"INSERT INTO app.program_versions(id,program_id,version_no,content,authored_by) VALUES ('00000000-0000-0000-0000-0000000000d9','{PROGRAM}',3,'{{}}','{AGR1}');" \
       f"UPDATE app.program_versions SET status='IN_REVIEW' WHERE id='00000000-0000-0000-0000-0000000000d9';"
t("Agronomist cannot approve their own program",   "postgres", None, NEWV + f"SET LOCAL app.user_id='{AGR1}';UPDATE app.program_versions SET status='APPROVED', reviewed_by='{AGR1}' WHERE id='00000000-0000-0000-0000-0000000000d9';", "maker-checker")
t("A second agronomist can approve",               "postgres", None, NEWV + f"SET LOCAL app.user_id='{AGR2}';UPDATE app.program_versions SET status='APPROVED', reviewed_by='{AGR2}' WHERE id='00000000-0000-0000-0000-0000000000d9';")
t("Operations cannot approve programs",            "app_api", OPS1, rows_affected_is(f"UPDATE app.program_versions SET status='IN_REVIEW' WHERE id='{PV_DRAFT}';", 0))
t("Approved program versions are immutable",       "postgres", None, f"UPDATE app.program_versions SET content='{{}}' WHERE id='{PV_APPROVED}';", "immutable")
t("A new version cannot be created pre-approved",  "postgres", None, f"INSERT INTO app.program_versions(program_id,version_no,status,content,authored_by) VALUES ('{PROGRAM}',9,'APPROVED','{{}}','{AGR1}');", "must start as DRAFT")

# ───────── Farm membership ─────────
INVITE = lambda farm, role: f"INSERT INTO app.farm_memberships(farm_id,user_id,farm_role) VALUES ('{farm}','{SPARE}','{role}');"
t("Owner can invite a manager to their farm",      "app_api", OWNER_A, INVITE(FARM_A, "manager"))
t("Owner cannot create another owner",             "app_api", OWNER_A, INVITE(FARM_A, "owner"), "row-level security")
t("Owner cannot invite into someone else's farm",  "app_api", OWNER_A, INVITE(FARM_B, "manager"), "row-level security")
t("Manager cannot invite anyone",                  "app_api", MGR_A1, INVITE(FARM_A, "manager"), "row-level security")
t("Only one active owner per farm",                "postgres", None, INVITE(FARM_A, "owner"), "one_active_owner_per_farm")

# ───────── Sensors ─────────
OBS = lambda dev, v: f"INSERT INTO app.observations(device_id,metric,value,unit,observed_at) VALUES ('{dev}','ph',{v},'pH',now());"
t("Ingest service can store a reading",            "app_ingest", None, OBS(DEVICE, 6.5))
t("Reading from an unknown device is refused",     "app_ingest", None, OBS("99999999-9999-9999-9999-999999999999", 6.5), "unknown or inactive device")
t("Reading from a disabled device is refused",     "app_ingest", None, OBS(DEVICE, 6.5), "unknown or inactive device",
  pre=f"UPDATE app.devices SET status='DISABLED' WHERE id='{DEVICE}';")
t("Ingest service cannot read events",             "app_ingest", None, "SELECT * FROM app.events;", "permission denied")
t("API role cannot write sensor readings",         "app_api", MGR_A1, OBS(DEVICE, 6.5), "permission denied")
t("Readings are visible to the owning farm only",  "app_api", MGR_A1, count_is("SELECT 1 FROM app.observations", 1))
t("Another farm cannot see those readings",        "app_api", MGR_B, count_is("SELECT 1 FROM app.observations", 0))
t("Readings cannot be edited",                     "postgres", None, "UPDATE app.observations SET value = 0;", "append-only")

# ───────── Audit, alerts, engine ─────────
t("Users can write audit entries via the function","app_api", MGR_A1, f"SELECT app.write_audit('read','cycle',  '{FARM_A}', 'allowed');")
t("Users cannot write the audit table directly",   "app_api", MGR_A1, "INSERT INTO app.audit_log(action,resource,result) VALUES ('x','y','allowed');", "permission denied")
t("Managers cannot read the audit log",            "app_api", MGR_A1, count_is("SELECT 1 FROM app.audit_log", 0),
  pre=f"SELECT app.write_audit('seed','x',NULL,'allowed');")
t("Super admin can read the audit log",            "app_api", SUPER, count_is("SELECT 1 FROM app.audit_log", 1),
  pre=f"SELECT app.write_audit('seed','x',NULL,'allowed');")
ALERT = lambda: (f"INSERT INTO app.alerts(cycle_id,farm_id,source,priority,title,dedupe_key) VALUES ('{CYC_A1}','{FARM_A}','sensor','HIGH','EC high','ec_high');")
t("Engine can raise an alert",                     "app_engine", None, ALERT())
t("Duplicate live alert is suppressed",            "app_engine", None, ALERT() + ALERT(), "one_live_alert_per_condition")
t("API role cannot create alerts",                 "app_api", MGR_A1, ALERT(), "permission denied")
t("Manager cannot edit expected steps",            "app_api", MGR_A1, "UPDATE app.expected_steps SET status='COMPLETED_ON_TIME';", "permission denied")
t("Engine cannot touch events",                    "app_engine", None, ev(CYC_A1, MGR_A1), "permission denied")

# ───────── Consent, invitations, devices, demo guard ─────────
CONSENT = lambda uid: f"INSERT INTO app.consents(user_id,purpose,granted,policy_version) VALUES ('{uid}','location',true,'v1');"
t("A person can record their own consent",         "app_api", MGR_A1, CONSENT(MGR_A1))
t("A person cannot record consent for someone else","app_api", MGR_A1, CONSENT(MGR_A2), "row-level security")
t("Consent records cannot be rewritten",           "postgres", None, "UPDATE app.consents SET granted=false;", "append-only",
  pre=CONSENT(MGR_A1))
t("Others cannot read my consent record",          "app_api", MGR_A2, count_is("SELECT 1 FROM app.consents", 0), pre=CONSENT(MGR_A1))
INV = lambda farm, role: (f"INSERT INTO app.farm_invites(farm_id,farm_role,email,token_hash,invited_by,expires_at) "
                          f"VALUES ('{farm}','{role}','new@farm.test',decode('00ff','hex'),'%s',now()+interval '7 days');")
t("Owner can invite a manager to their own farm",  "app_api", OWNER_A, INV(FARM_A, "manager") % OWNER_A)
t("Owner cannot invite another owner",             "app_api", OWNER_A, INV(FARM_A, "owner") % OWNER_A, "row-level security")
t("Owner cannot invite into another farm",         "app_api", OWNER_A, INV(FARM_B, "manager") % OWNER_A, "row-level security")
t("Manager cannot invite anyone",                  "app_api", MGR_A1, INV(FARM_A, "manager") % MGR_A1, "row-level security")
t("Operations can invite a farm owner",            "app_api", OPS1, INV(FARM_A, "owner") % OPS1)
t("Push devices are private to their user",        "app_api", MGR_A2, count_is("SELECT 1 FROM app.user_devices", 0),
  pre=f"INSERT INTO app.user_devices(user_id,platform,push_token) VALUES ('{MGR_A1}','android','tok1');")
t("Demo crops cannot be activated in production",  "postgres", None,
  f"SET LOCAL app.user_id='{OPS1}';UPDATE app.crop_cycles SET status='PENDING_ACTIVATION' WHERE id='{CYC_A2_DRAFT}';"
  f"SET LOCAL app.user_id='{OPS2}';UPDATE app.crop_cycles SET status='ACTIVE', approved_by='{OPS2}' WHERE id='{CYC_A2_DRAFT}';",
  "demo crops", pre=f"UPDATE app.crops SET is_demo=true WHERE id='{CROP}';")

# ───────── Winfield role limits ─────────
t("Analyst is read-only",                          "app_api", ANALYST, "INSERT INTO app.crops(name,cycle_type) VALUES ('Nope','SHORT_CYCLE');", "row-level security")
t("Operations cannot create crops",                "app_api", OPS1, "INSERT INTO app.crops(name,cycle_type) VALUES ('Nope','SHORT_CYCLE');", "row-level security")
t("Agronomist can create crops",                   "app_api", AGR1, "INSERT INTO app.crops(name,cycle_type) VALUES ('Okra','SHORT_CYCLE');")
t("Only super admin can change system settings",   "app_api", OPS1, rows_affected_is("UPDATE app.system_settings SET value='false'::jsonb WHERE key='require_two_person_activation';", 0))
t("Deactivated user loses access immediately",     "app_api", MGR_A1, count_is("SELECT 1 FROM app.events", 0),
  pre=f"UPDATE app.users SET is_active=false WHERE id='{MGR_A1}';")
t("Removed manager loses access immediately",      "app_api", MGR_A1, count_is("SELECT 1 FROM app.events", 0),
  pre=f"UPDATE app.farm_memberships SET active=false WHERE user_id='{MGR_A1}';")


def run(name, pre, role, user, sql, expect):
    parts = ["BEGIN;"]
    if pre: parts.append(pre)
    if role != "postgres":
        parts.append(f"SET LOCAL ROLE {role};")
    if user:
        parts.append(f"SELECT set_config('app.user_id','{user}',true);")
    parts.append(sql)
    parts.append("ROLLBACK;")
    script = "\n".join(parts)
    p = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", "-"], input=script, capture_output=True, text=True)
    err = (p.stderr or "").strip()
    if expect == "ok":
        return p.returncode == 0, err.splitlines()[-1] if err else ""
    return (p.returncode != 0 and expect.lower() in err.lower()), (err.splitlines()[-1] if err else "(no error raised!)")


def main():
    fails = 0
    for i, (name, pre, role, user, sql, expect) in enumerate(T, 1):
        ok, msg = run(name, pre, role, user, sql, expect)
        print(f"{'PASS' if ok else 'FAIL'}  {i:02d}  {name}")
        if not ok:
            fails += 1
            print(f"        expected: {expect!r}\n        got:      {msg}")
    print(f"\n{len(T) - fails}/{len(T)} passed")
    sys.exit(1 if fails else 0)

main()
