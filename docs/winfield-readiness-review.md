# Winfield Farmer App — Readiness Review

**Question asked:** Is the build spec ready to be implemented in Claude and will it produce apps that are ready to deploy?

## Verdict

**Ready to start building: yes. Guaranteed to produce deployable apps without further work: no, and nobody can honestly promise that.**

- The specification, the backend and security addendum, and the database layer are complete enough that Claude Code can build the system milestone by milestone without guessing the architecture.
- "Ready to deploy" is earned by passing the gates in the addendum (§K) and Part 8 of the setup guide: real-device testing, an independent security test, a restore drill, store approval and a Winfield-approved first crop program. Those cannot be done inside a chat.

## What was verified, and what was not

| Area | Status | Evidence |
|---|---|---|
| Database layer (34 tables, 6 migration files) | **Verified** | 99/99 tests pass from a clean database |
| Tenant isolation, role limits, instant access revocation | **Verified** | Tests run as each database role and test user |
| Winfield activation gate (no activation, no recording) | **Verified** | Gate tests including time-aware offline replay |
| Two-person activation, maker-checker on programs | **Verified** | Tests |
| Immutability and hash-chain tamper detection | **Verified** | Edit, delete, truncate and tamper tests; concurrency test |
| Spec, addendum and guide consistency | **Reviewed by reading** | Contradictions found and fixed (below); not machine-checked |
| API, worker, ingest, mobile app, web console | **Not built, not tested** | No code exists yet |
| Mobile builds, store approval | **Not done** | Needs real accounts and a network |
| Sensor vendor integrations | **Not done** | Depends on which devices you choose |
| Load, penetration, usability testing | **Not done** | Needs a running system |
| Agronomy content | **Not authored** | The app ships with no real crop program; Winfield agronomists must write and approve one |

The sandbox had no network access for package installs, so the database was tested directly but no application code could be built here. Real builds happen in Claude Code in a repository with network access.

## Scorecard

| Dimension | Readiness | Comment |
|---|---|---|
| Product definition | High | Roles, cycle lifecycle, activation, traceability, scoring and alerts are specified |
| Data model | High | Built and tested |
| Security design | High on design, untested in practice | Controls specified; needs an independent test |
| Build instructions | High | Master prompt with milestones and acceptance tests |
| Deployment instructions | Medium-high | Provider-neutral; screens and prices change |
| Agronomic content | Low | Intentionally empty until Winfield approves a program |
| Operational readiness | Low | Staffing, support, legal review and SMS budgets are human work |

## Gaps found, and how each was resolved

| # | Gap or contradiction | Resolution |
|---|---|---|
| A1 | Spec put "receipt confirmed" before activation | Activation first, then receipt confirmation, in spec and addendum |
| A2 | Offline work logged during an active period would be rejected if synced after a suspension | `cycle_status_history` and a time-aware gate, with tests; late-sync rule added to spec §3.4 |
| A3 | Hash-chain order depended on timestamps | Per-cycle `seq` assigned under an advisory lock |
| A4 | No consent records | `consents` table, append-only |
| A5 | No invitation mechanism | `farm_invites` with token hash and expiry |
| A6 | No push device registry | `user_devices` |
| A7 | Demo crops could reach real farms | `crops.is_demo` guard and `allow_demo_cycles` setting (off by default) |
| A8 | Roles unclear | Five database roles plus a migration owner that never runs services |
| A9 | Scoring weights were proposals | Marked as proposals pending Winfield sign-off; the formula is versioned |

## Decisions that are still proposals (need your sign-off)

1. Score weights: 40% protocol adherence, 20% scouting and health checks, 15% data compliance, 15% sensor-range compliance, 10% issue response.
2. 14-day offline grace period for entitlements.
3. Two-person activation (supported by a setting; recommended).
4. Pilot crop and pilot country.
5. Alert escalation timers T1/T2.
6. Avocado deferred until after the short-cycle pilot.

## Human-only steps and residual risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Program content is wrong | Alerts and scores would mislead farmers | Two agronomists approve; pilot cycle reviewed before AI agents go live |
| Store rejection | The app does nothing without activation | Review farm with a demo cycle (setup guide Part 7.2) |
| Data-protection law differs by country | Fines, blocked launch | Legal review per country before go-live |
| SMS costs and delivery | Surprise bills, missed alerts | Spend cap; test on real phones |
| Sensor data quality | False alarms or missed problems | Quality gating; NPK probes treated as indicative only |
| Scope creep during build | Delays | Milestones with acceptance tests; V2 list kept separate |
| Single points of failure in the team | Access lost if one person leaves | Company-owned accounts and a shared password manager |

## Recommended order

1. Sign off the proposals above.
2. Start account sign-ups (Apple, Google, SMS) on day one; they take longest.
3. Run the master build prompt, one milestone at a time.
4. Have agronomists author the pilot program while the build runs.
5. Pilot with one farm, then fix, then widen.
