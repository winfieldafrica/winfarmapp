# Winfield Farmer App — Build Specification (Multi-Crop, Winfield-Activated)

Supersedes the avocado-specific *Orchard Ops* build spec. Avocado becomes one **crop program** inside this system (a perennial one); nothing from the earlier design is thrown away. Section 1 lists what carries over and what changes.

**Companion documents (read together; where they conflict, the Addendum wins):**
- `winfield-backend-security-addendum.md` — final stack decisions, database, security controls, API and sync rules, environments, testing
- `winfield-database/` (`winfield-database-schema.sql` + tests) — the executable, tested database layer
- `winfield-readiness-review.md` — what is and is not ready, and what only humans can supply
- `winfield-setup-deployment-guide.md` — step-by-step setup and go-live
- `winfield-master-build-prompt.md` — the prompt that drives the build

This document is written to hand to a development team or an AI coding agent. Values shown in examples are **illustrative placeholders, not agronomic recommendations**. All real protocol content comes from Winfield agronomists through the program authoring workflow (§4).

---

## 0. Concept in one paragraph

Winfield supplies plants from its nursery. Each supply is recorded as a **Supply Batch**. A Winfield-authorised person **activates a Crop Cycle** for that batch, which attaches an approved, versioned **Crop Program** (stage-by-stage growing conditions, irrigation and feeding programs, scouting frequencies, health checks, pest and disease vulnerability). Only then does the farm's app become functional for that crop. The app tells the farm manager and owner what must be done and checked at each stage, collects what was actually done (inputs, scouting, readings, sensor data), compares it against the protocol, flags missed or deviating steps, and produces a compliance and health score and a full traceability record from plant supply to projected cycle end.

---

## 1. What carries over from the avocado design, and what changes

| Area | Carried over unchanged | New or changed |
|---|---|---|
| Architecture | Offline-first mobile app, immutable event log, server-side RBAC with row-level security, audit log, formula transparency | Crop-agnostic data model; Winfield back office becomes the control plane |
| Roles | Farm Owner, multiple Supervisors per farm | Supervisor renamed **Farm Manager** (same permissions); Winfield roles split into Admin, Agronomist, Operations, Analyst (§2) |
| Rules engine | Provenance, versioning, `UNVALIDATED` gating, agronomist sign-off | One program per crop, authored and approved in-app (§4), not a spreadsheet handoff |
| Thresholds | Soil-based tensiometer and EC targets by soil, age, stage | Targets are **stage-wise per crop**, extended to pH, soil moisture, NPK ratio, with sensor evaluation (§10) |
| Health score | Deviation-based, transparent, gaming-resistant | New component weights; adds protocol adherence and sensor compliance (§9) |
| Platform analytics | Fixed at-risk threshold, benchmarking deferred | Cohorts are now natural (same crop, same stage), still deferred to Phase 8 |
| AI advisory | Grounded, rules-engine-consistent, hard validation gate | Scoped per crop; a crop's agents go live only once its program is approved (§13) |
| **Activation** | n/a | **Nothing works without Winfield activation** (§3) |
| **Traceability** | Event log | Supply Batch → Crop Cycle → every step, input and reading (§5) |

The earlier avocado work becomes the first **perennial** program: an establishment phase followed by repeating seasonal cycles (§4.4).

---

## 2. Actors and permissions

Permissions are enforced in the API and database (row-level security keyed on `org`, `farm_id`, `role`, `cycle_id`), never only in the UI.

### Winfield (control plane, web console)

| Role | Can do | Cannot do |
|---|---|---|
| **Super Admin** | Manage Winfield users and roles, system configuration, entitlements policy | Edit or delete farm-submitted events |
| **Agronomist** | Author, review and publish crop programs; amend active cycles; respond to escalations; read all farm data | Activate cycles (separation of duties) |
| **Operations** | Create farms, record supply batches, raise activation requests, register devices, suspend or resume cycles | Publish programs; approve their own activation requests |
| **Analyst** | Read-only cross-farm analytics | Any write |
| **Field Officer** (optional) | Add on-site verification events (e.g. verify scouting) | Edit farm events |

**Integrity rule:** no Winfield role can edit or delete a farm-submitted event. Corrections are separate annotation events that reference the original. This protects accountability in both directions.

### Farm (mobile app and web)

| Role | Can do | Cannot do |
|---|---|---|
| **Farm Owner** | Read dashboards, alerts, compliance, protocol and traceability for their farm; invite or remove Farm Managers; export own data | Edit operational logs; edit protocols |
| **Farm Manager** (multiple per farm, each assigned blocks) | Execute and log steps, scouting, readings; acknowledge alerts; confirm stage transitions and planting date; view own score and the full formula | Create crops, edit programs, activate cycles, see other farms |

---

## 3. Winfield authority and activation model

This is the core commercial control. The app is not usable for crop management without a Winfield-activated cycle.

### 3.1 Rules

1. Farm accounts are **created by Winfield Operations only**. No self-registration to a working state.
2. Farms cannot create crops, programs or protocols. They can only run what Winfield has activated.
3. A cycle moves to `ACTIVE` only through Winfield activation tied to a recorded Supply Batch.
4. Every operational API call checks the cycle's state and entitlement server-side. The mobile app mirrors this for UX but is never the authority.
5. With no active cycle, the app shows "Awaiting Winfield activation" plus contact details, and historical closed cycles remain readable.

### 3.2 Cycle state machine

```
DRAFT → PENDING_ACTIVATION → ACTIVE → COMPLETED → CLOSED
                                ↕
                             SUSPENDED          (also: ACTIVE → TERMINATED early, with reason code)
```

| State | Meaning | Farm app behaviour |
|---|---|---|
| `DRAFT` | Operations is preparing the batch and selecting the program version | Invisible to farm |
| `PENDING_ACTIVATION` | Activation request awaiting approval | "Awaiting activation" |
| `ACTIVE` | Approved; protocol clock running | Fully functional |
| `SUSPENDED` | Paused by Winfield (e.g. contract or compliance issue) | Read-only; alerts muted except safety-critical |
| `COMPLETED` | Projected end reached or harvest closed out | Read-only, summary report |
| `TERMINATED` | Ended early (crop failure, write-off), reason code required | Read-only, closure report |
| `CLOSED` | Reconciled and archived | Read-only |

### 3.3 Activation requirements

- Farm account verified; block(s) assigned and geo-bounded.
- Supply Batch recorded: nursery batch and lot code, crop, variety, quantity, plant specification at supply, supply date, delivery note reference.
- A **published** program version selected (never a draft). The chosen version is **frozen as a snapshot** onto the cycle so later program edits do not silently change in-flight cycles.
- **Maker-checker:** Operations raises the request, a different authorised person approves. Single-approver mode can be configured (open decision, §17).
- Optional per-supply overrides (§4.3) applied by an Agronomist, recorded and versioned.

### 3.4 Offline entitlement

The server is authoritative. The app caches a signed entitlement with an expiry and works offline within a **grace period** (proposed 14 days, configurable). After expiry, new writes queue locally but cannot sync until the entitlement is refreshed. Suspension takes effect at next sync, and the device receives a revocation on reconnect.

**Late-synced offline work is judged by when it happened, not when it arrived.** The database gate accepts an event if the cycle was `ACTIVE` at the event's `occurred_at` time, even if the cycle has since been suspended or completed; it refuses work dated inside a suspended period or before activation, and everything once a cycle is `CLOSED`. Without this rule, a manager who worked offline for three days while Winfield suspended the cycle would silently lose that legitimate work. Implemented and tested in the database layer (`cycle_status_history`).

### 3.5 Cycle amendments

An Agronomist can amend an active cycle (for example after a weather event or disease outbreak). Amendments are versioned, require a reason, notify the Farm Manager and Owner, and are shown in the traceability record, so adherence is always judged against the protocol in force at the time.

---

## 4. Crop catalog and program model

### 4.1 Hierarchy

```
Crop (catalog)
  └── Variety
        └── CropProgram (template, per crop/variety/region)
              └── ProgramVersion (immutable once published)
                    └── Stage[ ]   (ordered)
                          └── stage content (§4.2)
```

**Customisation layers** (later layers override earlier ones, field by field):

1. Crop default
2. Variety override
3. Region / climate-zone override
4. Supply-batch override (Agronomist only, tied to one cycle)

Every override is versioned and attributed. Farms never customise.

### 4.2 Stage definition (what each stage must carry)

| Block | Content |
|---|---|
| **Timing** | Target, minimum and maximum duration in days (optionally degree-days later); entry marker (how a stage transition is confirmed); tolerance before variance is flagged |
| **Growing conditions** | Target bands for temperature, humidity and others the crop needs (min / max / warn / critical) |
| **Irrigation program** | Moisture or tension band, frequency, volume or duration guidance, method |
| **Feeding program** | Scheduled steps: nutrient spec or product, rate, method, interval, allowed timing window, rate tolerance |
| **Target bands for sensors and checks** | EC, pH, soil moisture, NPK ratio (min / max / warn / critical, persistence window) |
| **Scouting plan** | Frequency, sample plan (plants or points per block or hectare), checklist drawn from the stage's vulnerability list, severity scale, mandatory photo rules |
| **Health checks** | Scheduled inspections (e.g. root, canopy, fruit, tissue or lab sample) with pass/fail criteria |
| **Pest and disease vulnerability** | Per threat: stage susceptibility, likelihood conditions, action thresholds (§7) |
| **Critical control points** | Steps flagged as critical; they carry more weight in compliance and escalate faster when missed |
| **Provenance** | Source, author, approver, version, effective date, `status` (`UNVALIDATED` / `APPROVED`) |

### 4.3 Authoring and publishing workflow (Winfield web console)

1. Agronomist drafts a program (or clones an existing one for a new variety).
2. Validation checks run automatically: every stage has timing, at least one scouting plan, targets are min < max, no overlapping stages, every referenced pest/disease exists in the threat library.
3. A **second Agronomist reviews and approves** (maker-checker). Self-approval is blocked.
4. Publishing creates an immutable `ProgramVersion`. Edits after that create a new version.
5. Only `APPROVED` versions can be attached to a cycle. Anything marked `UNVALIDATED` can be previewed but never activated.

New crops from the nursery are introduced by creating a Crop and Program through this workflow with prefilled protocols and checks, so onboarding a crop is configuration, not code.

### 4.4 Cycle types

| Type | Shape | Example |
|---|---|---|
| `SHORT_CYCLE` | Transplant to harvest, one pass | Many vegetable and leaf crops |
| `CONTINUOUS_HARVEST` | Establishment, then a long harvest period with recurring routines | Fruiting vegetables |
| `PERENNIAL` | Establishment years, then repeating **seasonal sub-cycles** each with its own stage set | Avocado |

The data model treats all three as ordered phases containing stages, so one engine serves them all. Perennial seasonal sub-cycles are activated by Winfield per season.

### 4.5 Sample program fragment (illustrative only)

```yaml
program: Example Crop (illustrative, do not use)
version: 0.1
status: UNVALIDATED
cycle_type: SHORT_CYCLE
stages:
  - id: S2
    name: Vegetative growth
    duration_days: { min: 20, target: 28, max: 35 }
    entry_marker: "<<defined by Winfield agronomy>>"
    targets:
      soil_moisture: { min: <n>, max: <n>, warn: <n>, critical: <n>, persist_hours: 6 }
      ec_dS_m:       { min: <n>, max: <n> }
      ph:            { min: <n>, max: <n> }
      npk_ratio:     { n: <n>, p: <n>, k: <n>, tolerance_pct: <n>, indicative_only: true }
    feeding_steps:
      - { id: F2.1, product_spec: "<<TBD>>", rate: <n>, rate_tolerance_pct: 10,
          window_days: [5, 9], critical: true }
    scouting: { every_days: 3, sample: "<<plan>>", checklist: [threat_ids...], photo_required_if_severity_gte: 2 }
    health_checks: [ { id: H2.1, at_day: 14, criteria: "<<TBD>>" } ]
    vulnerabilities:
      - { threat: threat_id, susceptibility: HIGH, conditions: "<<rule ref>>" }
```

---

## 5. Supply batch, crop cycle and traceability

### 5.1 Lifecycle

1. **Supply Batch recorded** by Winfield Operations (nursery lot, crop, variety, quantity, plant spec, supply date, delivery note, destination farm and block).
2. **Activation** (Winfield, two-person) turns the prepared cycle `ACTIVE`: program snapshot frozen, projected stage calendar and the full set of **Expected Steps** generated (scheduled feeding, irrigation checks, scouting rounds, health checks). Nothing on the farm side works before this point.
3. **Receipt confirmation** is the Farm Manager's first step in the now-active cycle: confirm quantity received (scan batch QR or enter code), note condition, confirm actual planting date. Variance against the supply date and quantity is flagged to Winfield. *(Corrected in the readiness review: an earlier draft placed receipt before activation, which contradicted the rule that the app does nothing without Winfield activation.)*
4. **Execution:** the manager works through expected steps; each completion links to an event.
5. **Stage transitions:** the system proposes a transition at the expected date. The manager confirms against the entry marker (photo optional or required per stage). Early or late beyond tolerance flags variance and **recalculates the projected end date**.
6. **Completion or termination** produces a closure report.

### 5.2 Traceability record

For every cycle, one ordered, tamper-evident chain:

`Supply Batch → Activation (who, when, program version) → each Expected Step → Actual Event (who, when, GPS, photo, product, lot, rate, area) → Readings and sensor observations → Alerts and acknowledgements → Amendments → Stage transitions → Closure`

- Events are immutable and append-only; corrections are new annotation events.
- The chain is exportable as a PDF or CSV per cycle (Owner for own farm, Winfield for all).
- **Cycle clock start** is the Winfield-recorded supply date by default, with the manager-confirmed planting date shown beside it (open decision, §17).

---

## 6. Protocol execution

### 6.1 Expected steps

Generated at activation, per step: `earliest`, `due`, `latest`, `grace`, `critical` flag, prescribed product and rate (for feeding and spraying), required evidence (photo, reading).

### 6.2 Step status (deviation-based, as in the avocado design)

| Status | Definition |
|---|---|
| `COMPLETED_ON_TIME` | Done inside the allowed window, product and rate within tolerance |
| `COMPLETED_LATE(n days)` | Done after `due`, before `latest` |
| `COMPLETED_WITH_DEVIATION` | Wrong product, or rate outside tolerance, or wrong method; deviation recorded numerically |
| `SKIPPED_APPROVED` | Skipped with a reason that the Agronomist accepted |
| `MISSED` | `latest` + grace passed with no completion |
| `PENDING` / `DUE` / `OVERDUE` | Live states used for alerts |

### 6.3 Scouting

- Scouting rounds follow the stage's frequency and sample plan.
- The form is generated from the stage's vulnerability list: per threat, incidence or severity on the stage's scale, location in block, photo where required.
- Results above action thresholds generate a recommended action or an escalation to a Winfield Agronomist.
- Scouting findings feed the risk engine (§7) as observed pressure.
- Missed scouting rounds count against compliance exactly like missed feeding steps.

### 6.4 Health checks

Scheduled, pass/fail against criteria in the program. A failed check opens an issue with a due date, tracked into the **issue response** score component.

### 6.5 Inputs

Every feeding or spraying record captures product, batch or lot where available, rate, area or plant count, method, and operator, so applied inputs can be compared with the prescription and traced later.

---

## 7. Pest and disease vulnerability and risk engine

### 7.1 Threat library (Winfield-maintained)

Per threat: name, crop(s), symptoms and visual cues, favourable conditions (weather and sensor rules), scouting method, severity scale, action thresholds, recommended first action, escalation criteria, source.

### 7.2 Risk model (transparent, configurable)

- **Susceptibility** (from the stage definition): Low / Medium / High.
- **Likelihood** (computed): Unlikely / Possible / Likely / Imminent. Inputs: favourable-condition rules evaluated on weather and sensor data, recent scouting findings, active alerts in the same cycle, history on the farm.
- **Risk category** = matrix lookup:

| Susceptibility ↓ / Likelihood → | Unlikely | Possible | Likely | Imminent |
|---|---|---|---|---|
| **Low** | Low | Low | Moderate | Moderate |
| **Medium** | Low | Moderate | High | High |
| **High** | Moderate | High | Critical | Critical |

The default matrix is editable by Winfield Agronomists, versioned like any rule. Risk categories drive alert priority, scouting intensification (for example "scout every 2 days instead of 4 while High") and recommended preventive steps. Every category shown to a user lists the inputs that produced it.

---

## 8. Alerts and notifications

### 8.1 Alert sources

| Source | Examples |
|---|---|
| Protocol schedule | Step due soon, due today, overdue, missed; scouting round due; health check due; stage transition due |
| Risk engine | Risk category rises for a threat in this stage |
| Readings and sensors | Value outside stage target band; sustained out-of-range; sensor offline or implausible |
| Compliance | Score drops below threshold; critical step missed |
| Winfield | Amendments, advisories, activation or suspension notices |

### 8.2 Priority and escalation

| Priority | Channel | Escalation |
|---|---|---|
| Info | In-app | None |
| Action | Push; in-app badge | Reminder at due, again at overdue |
| High | Push; SMS or WhatsApp fallback | Unacknowledged after T1 → Farm Owner |
| Critical | Push plus SMS or WhatsApp | Unacknowledged after T1 → Owner; after T2 → Winfield Agronomist |

Timers T1 and T2 are configurable per priority. Critical alerts require **acknowledgement**, and every ack is an event. Deduplication and rate limiting prevent alert storms (one alert per condition until resolved or re-armed). Quiet hours apply except Critical. Rural connectivity is assumed poor, so SMS or WhatsApp fallback and a once-daily digest are first-class, not extras.

### 8.3 What users see

- **Farm Manager:** "What must I do and check today, by block and stage", plus overdue items.
- **Farm Owner:** stage progress, what is being monitored, compliance, escalations, projected cycle end, weekly digest.

---

## 9. Compliance and health score

### 9.1 Components and proposed weights

| Component | What it measures | Weight |
|---|---|---|
| **Protocol adherence** | On-time execution of scheduled irrigation, feeding, spraying and cultural steps, with partial credit for late, and deviation penalties for wrong product or rate | 40% |
| **Scouting and health checks** | Rounds completed on schedule, required fields and photos present | 20% |
| **Data compliance** | Manual readings (irrigation, moisture, EC, pH) submitted on schedule | 15% |
| **Sensor-range compliance** | Share of time EC, pH, moisture and NPK ratio sat inside stage bands (only when sensors are linked) | 15% |
| **Issue response** | Time from alert or flagged finding to logged action | 10% |

If no sensors are linked, the sensor component's weight is redistributed pro rata across the others and the score is labelled "no sensor data". **These weights are a proposal** (the avocado design used 60/20/20 on different components) and need a Winfield decision (§17).

### 9.2 Rules carried over

- **Critical control points** weigh more than ordinary steps.
- **Confidence interval** shown for short cycles or small blocks (few data points means a wide band, not false precision).
- **Formula is fully visible** to Farm Managers and Owners, with each component and the events behind it.
- **Every score is recomputable from raw events.** If a stored score disagrees with a recomputation, that is a defect.
- Scores are per **cycle** and per **block**, with a rolling view per farm.
- **Missed-step detection** is automatic from the Expected Steps table: nothing relies on a person remembering to report that they forgot.

### 9.3 Anti-gaming

Immutable events; deviation-based status; photo EXIF time and GPS cross-checks against claimed time and block; sensor-versus-manual cross-checks; compliance from sensors cannot be entered by the farm; no role can edit farm events.

---

## 10. Sensor and weather integration

### 10.1 Pipeline

```
Device or gateway → Ingestion adapter → Normalise → Quality checks → Time-series store → Rule evaluation → Alerts and compliance
```

- **Ingestion options:** vendor cloud APIs (adapter per vendor), direct MQTT or HTTPS from gateways, CSV or manual import as a fallback.
- **Normalised observation:** `device_id, block_id, metric, value, unit, timestamp, quality_flag`.
- **Metrics:** soil moisture (VWC % or tension), EC, pH, N/P/K (as the sensor reports), temperature, humidity, rainfall, others as added.

### 10.2 Device registry

Each device is registered to a farm and block with position and depth, install date and calibration date. **Winfield registers or approves devices**, and device credentials are device-scoped and issued by Winfield, which prevents spoofed data.

### 10.3 Rule evaluation

Per stage and metric: `min / max / warn / critical`, plus a **persistence window** so a momentary spike does not alert. Also:

- Rate-of-change checks (sudden drops suggest probe failure).
- Offline detection (no data for X hours).
- Flatline detection (identical values for too long).
- Implausible-value filters.

**Data quality gating:** alerts triggered by low-quality data are labelled "Check sensor", not "Crop problem", so managers are not sent to fix a plant that is fine.

### 10.4 Escalation of "way off" readings

Critical-band reading with good data quality → Critical alert to the Manager immediately, to the Owner if unacknowledged within T1, to the Winfield Agronomist after T2.

### 10.5 Cross-validation and drift

Periodic manual reading versus sensor reading per device. Divergence beyond tolerance raises a calibration task and lowers that device's confidence weight.

### 10.6 NPK sensors: be explicit

In-soil NPK probes are generally **indicative rather than lab-accurate**, and readings vary with moisture and salinity. The spec therefore treats NPK ratio as a **trend and ratio signal with wider tolerance bands**, flagged `indicative_only`, and requires lab or tissue confirmation before a feeding program is changed on NPK data alone. Which sensor models are supported and how much NPK data may influence compliance is a Winfield agronomy decision (§17). EC, pH and moisture are the primary compliance drivers.

### 10.7 Weather

Use a linked on-farm station where present, otherwise a weather API for the block's coordinates. Weather feeds the risk engine, irrigation advice and spray-hold rules (the earlier "rain forecast: hold spray" behaviour generalises to every crop).

---

## 11. Data model

```
Organisation (Winfield)
  ├── WinfieldUser (role: super_admin | agronomist | operations | analyst | field_officer)
  └── Catalog
        ├── Crop ── Variety
        ├── ThreatLibrary (pest/disease) ── ThreatRule (favourable conditions, thresholds)
        ├── ProductReference (feeds, sprays: spec, method, rate range, safety/PHI, cost)
        ├── CropProgram ── ProgramVersion (immutable) ── Stage ── { StageTargets, FeedingStep,
        │                   IrrigationRule, ScoutingPlan, HealthCheck, VulnerabilityRule, CriticalFlag }
        └── RiskMatrix (versioned)

Farm
  ├── Owner (user)            └── FarmManager[ ] (users, block assignments)
  ├── Block (geo boundary, soil profile, elevation, region)
  ├── Device ── Observation (time-series)
  └── Entitlement (derived from active cycles; signed; expiry)

SupplyBatch (nursery_lot, crop, variety, qty, plant_spec, supply_date, delivery_note, farm, block)
  └── CropCycle
        ├── cycle_type, status (state machine §3.2), program_version_snapshot, overrides[ ], amendments[ ]
        ├── activation (requested_by, approved_by, timestamps)
        ├── CycleStage[ ] (planned vs actual dates, confirmation event, variance)
        ├── ExpectedStep[ ] (window, critical, prescription, status)
        ├── Event (immutable)  ← work_log | input_application | scouting | health_check | reading |
        │                        receipt_confirmation | stage_confirmation | ack | annotation
        ├── ScoutingRecord (per threat: severity, location, photo)
        ├── Alert ── Notification ── Acknowledgement
        ├── ComplianceSnapshot (components, weights, formula_version, confidence_interval)
        └── ProjectedEnd (recomputed on stage transitions)

AuditLog (immutable): viewer, role, resource, farm, timestamp, result (allowed | denied)
```

**Soil and tissue nutrition loop:** the avocado soil-weighted recommendation design (§3.5–3.6 of the earlier spec) generalises. `Block.SoilProfile` plus per-crop, per-stage `SufficiencyRange` tables for soil and tissue analysis, block-averaged, soil-weighted, with agronomist review before auto-apply. It is configuration per crop, not separate code.

---

## 12. Reused platform decisions (unchanged)

Offline-first with a sync queue and per-entry sync status; last-write-wins at field level with the event log preserving both writes; short-lived JWTs with role, farm and entitlement claims; PostgreSQL with row-level security; object storage with signed, farm-scoped URLs; audit log of every Owner or Winfield read; Spanish and English at minimum with externalised strings; read replicas for analytics.

New infrastructure: a **time-series store** for sensor observations (TimescaleDB or equivalent), a **scheduler** for Expected Step windows and alert timers, an **SMS/WhatsApp provider** integration, and a **device ingestion service** isolated from the main API.

---

## 13. AI advisory layer (beta, carried over)

- One grounded LLM; each domain "agent" is a system prompt plus a retrieval scope plus tool access. Domains: Water, Feeding and Deficiencies, Pests and Diseases, then Cultural, Fruit or Produce Management and Post-harvest.
- **New scoping:** retrieval and tools are limited to the **active cycle's program version and stage**, so answers are about this crop at this stage.
- The agent explains computed values and the protocol, and never generates doses, products or thresholds from memory.
- It must agree with the deterministic engines (protocol, risk, sensor rules): tested directly against identical inputs.
- **Hard gate:** a crop's agents go live only when that crop's program is `APPROVED` and has completed at least one reviewed pilot cycle.
- Low-confidence answers escalate to a Winfield Agronomist; all interactions are audit-logged.
- Ask is Farm Manager only, online only, with the protocol task list as offline fallback.

---

## 14. Screens by module

### Winfield console (web)
1. **Crop catalog and threat library**
2. **Program authoring:** stage editor, validation results, review and publish
3. **Farms and users**
4. **Supply batches:** record, receipt variance
5. **Activation queue:** pending requests, approve or reject, suspend or resume, terminate
6. **Active cycles board:** stage, compliance, open escalations, projected end
7. **Escalations inbox** (Agronomist)
8. **Devices:** register, approve, health
9. **Analytics:** compliance by crop, farm, stage; audit log
10. **Amendments:** create, notify, track

### Farm Manager app (mobile)
1. Activation state or **Today** (what to do and check, by block and stage)
2. Cycle timeline (stages, projected end, variance)
3. Receipt confirmation (batch scan, quantity, planting date)
4. Log work, inputs and irrigation (prescription shown beside what was applied)
5. Scouting (generated checklist, photos)
6. Health checks
7. Readings (moisture, EC, pH; target band shown for the current stage)
8. Alerts (acknowledge)
9. My score (full formula, missed or deviating steps)
10. Ask (beta)

### Farm Owner (mobile and web)
1. Summary: stage progress, compliance, projected end
2. What is being monitored and checked, by stage (protocol view)
3. Alerts and escalations
4. Traceability and exports
5. Team management (invite or remove Managers)

---

## 15. Security and integrity

Server-enforced RBAC and RLS; separation of duties (Operations activates requests but cannot approve them; Agronomists approve programs but cannot activate); maker-checker on program publishing; immutable events and audit log; device-scoped credentials; signed entitlements; encryption in transit and at rest; MFA for all Winfield roles and Farm Owners; no Winfield role can edit farm events; penetration test before pilot.

---

## 16. Build order and acceptance criteria

### Order
1. Multi-tenant accounts, RBAC and RLS, audit, immutable events
2. Crop catalog, program model, authoring and maker-checker publishing
3. Supply batch, activation, entitlement gating, traceability chain
4. Farm Manager app: Today, execution, scouting, readings, offline sync, alerts
5. Compliance engine and health score; Owner views
6. **Pilot A** (manual data, one short-cycle crop)
7. Sensor integration and sensor-range compliance
8. AI advisory beta
9. Scale: new-crop onboarding playbook, benchmarking, outcome validation

### Acceptance criteria
- A farm account with no `ACTIVE` cycle cannot write operational data, even by calling the API directly (tested, not reviewed by eye).
- No single Winfield person can both request and approve an activation (when two-person mode is on), or author and approve a program.
- A cycle always runs against its frozen program snapshot; publishing a new program version never changes an in-flight cycle without an explicit, logged amendment.
- Every cycle has a complete chain from Supply Batch to closure, exportable, with no gaps.
- Missed steps are detected automatically with no user report, and each produces an alert and a score effect.
- Every score and every risk category can be recomputed from stored events and shows its inputs.
- A sensor reading in a critical band with good data quality produces a Critical alert within the agreed latency, and a faulty probe produces "Check sensor", not a crop alert.
- A new crop can be introduced entirely through the authoring workflow with no code change.
- A Manager can log a full day offline and sync with no loss.
- An AI answer always matches the deterministic engines for identical inputs.

---

## 17. Open decisions for Winfield

1. **Pilot crop and first programs:** which crops, and who writes the protocols? A **short-cycle crop** is strongly recommended for Pilot A so a full cycle completes during the pilot.
2. **Health-score weights** (§9.1 proposal) and the at-risk threshold number.
3. **Activation approval:** two-person (recommended) or single approver.
4. **Offline grace period** (proposed 14 days) and what happens to queued data on expiry.
5. **Cycle clock start:** Winfield supply date or manager-confirmed planting date.
6. **Sensor vendors and models** to support first, and how far NPK data may influence compliance (§10.6).
7. **Notification channels:** SMS versus WhatsApp, cost per message, languages.
8. **Owner visibility of the protocol:** recommended yes (transparency), but it is a commercial call.
9. **Contract end:** data retention and what the farm keeps access to.
10. **Field Officer role:** include in v1 for scouting verification, or later?
11. **Perennials:** confirm avocado migrates in as the first `PERENNIAL` program.
12. **Regulatory and data-residency** requirements for the countries in scope.
