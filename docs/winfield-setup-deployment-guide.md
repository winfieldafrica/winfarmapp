# Winfield Farmer App — Setup and Deployment Guide

**For:** the Winfield person responsible for getting the app live, even if you have never deployed software before.
**Use it after:** the build milestones in `winfield-master-build-prompt.md` are finished and their checks have passed.
**How it works:** every step says *what to do*, then *what you should see*. If you do not see it, **stop** and use the troubleshooting table in Part 10. Do not skip ahead.

> **Honest note on screens and prices.** Hosting companies, Apple and Google change their screens, names and prices. This guide tells you the *settings that matter* and why; the buttons may be labelled differently when you get there. Where a step names a product, an equivalent is fine as long as it meets the stated requirement.

---

## Part 0 — What you will end up with, and who does what

You will have: a production system (database, API, background worker, sensor intake, web console), a **Winfield console** for your staff, an **Owner web view**, and **iPhone and Android apps** published to the stores, plus a first pilot farm running on a real supply batch.

| Person | Does | Needs |
|---|---|---|
| **Project owner** (you) | Makes decisions, owns accounts, approves releases | Company email, company card, authority to sign up |
| **Developer or Claude Code session** | Builds, deploys, fixes | Access to the code repository and the cloud accounts |
| **Two Winfield agronomists** | Write and approve the first crop program | Login to the Winfield console |
| **Two Winfield operations staff** | Record supply and activate cycles (the two-person rule) | Login to the Winfield console |
| **Lawyer / data-protection adviser** | Reviews privacy policy and terms | The draft documents |
| **Pilot farm owner and manager** | Test the apps for real | A phone each |

**Realistic timeline:** account sign-ups can take **days to weeks** (Apple and Google business verification, SMS provider approval). **Start Part 2 on day one**, in parallel with the build.

---

## Part 1 — Decisions to make before you start

Write the answers in one shared document. The build and the setup depend on them.

| # | Decision | Suggested default |
|---|---|---|
| 1 | Countries where the app will operate | *Required, no default.* Drives legal, hosting region, languages, SMS provider |
| 2 | Pilot crop (short-cycle) and who writes its program | A crop that finishes within 8–12 weeks |
| 3 | Activation approval | Two people (recommended) |
| 4 | Manager sign-in | Email/password; SMS code is an option |
| 5 | Languages in the app | English first; add others once the country list is known |
| 6 | Hosting region | Closest to your farms that your legal adviser accepts |
| 7 | Cycle clock starts on | Supply date |
| 8 | App name, icon, and the **bundle identifier** (e.g. `com.winfield.farm`) | **Cannot be changed after publishing — decide carefully** |
| 9 | Support email and phone shown in the app | A shared mailbox, not a person |

---

## Part 2 — Create the accounts (start now)

**Rule:** every account is owned by the **company**, using a **shared company mailbox** (for example `devops@yourcompany.com`), never a personal email. Turn on two-step sign-in everywhere and store recovery codes in the company password manager.

| Account | What it is for | Notes |
|---|---|---|
| **Password manager** (company) | Stores every secret and recovery code | Do this first |
| **GitHub** (organisation) | Holds the code | Turn on required two-step sign-in for all members |
| **Cloud / hosting provider** | Runs the services | One **separate project or account per environment**: staging and production |
| **Managed PostgreSQL 16** | The database | Must offer: version 16, private networking, daily backups **with point-in-time recovery**, ability to create roles, SSL |
| **Managed Redis** | Job queue | Private networking |
| **Object storage** (S3-compatible bucket) | Photos | Private bucket, versioning on |
| **Domain name and DNS** | e.g. `app.yourcompany.com`, `api.…`, `console.…` | Company-owned registrar account |
| **Expo / EAS** | Builds the mobile apps | Create an organisation account |
| **Apple Developer Program (organisation)** | Publish on the App Store | Needs a legal entity and a **D-U-N-S number**; can take days to weeks |
| **Google Play Console (organisation)** | Publish on Google Play | Organisation verification required; new accounts may need a closed test period before production |
| **SMS / WhatsApp provider** | Alerts where there is no data signal | Pick one that covers your countries; **set a monthly spend cap** |
| **Transactional email provider** | Invitations, password resets | Verify your sending domain |
| **Error tracking** | See crashes and errors | Scrub personal data |
| **Uptime monitoring** | Pages you when the system is down | Point at the API health URL |

**You should see:** a spreadsheet listing each account, who owns it, where the recovery codes are stored. If any account is in one person's name only, fix that now.

---

## Part 3 — Prepare the computer used for building (skip if a hosted build environment does this for you)

1. Install **Git**, **Node.js 22 (LTS)**, **pnpm**, **Docker Desktop**, and the **PostgreSQL 16 client tools** (`psql`).
2. Open a terminal and check each one:

| Run | You should see |
|---|---|
| `git --version` | a version number |
| `node --version` | starts with `v22` |
| `pnpm --version` | a version number |
| `docker --version` | a version number |
| `psql --version` | `psql (PostgreSQL) 16…` |

If any command says "not found", reinstall that tool before continuing.

---

## Part 4 — Build the app from the specification

1. Create an **empty private repository** on GitHub named `winfield`.
2. Put these files in a `docs/` folder in it: the build spec, the addendum, the readiness review, this guide, the master build prompt, and the `winfield-database` folder (put that at the repository top level as `database/`).
3. Open Claude Code in the repository and give it the contents of **`winfield-master-build-prompt.md`**.
4. The prompt builds in **numbered milestones (M0–M12)**. After each one, Claude stops and reports. **Do not tell it to continue until you have checked the milestone's "You should see" line.** The most important checkpoint is below.

**Checkpoint after M1 — run the database tests yourself:**

```
cd database
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=yourpassword ./run_all.sh
```

**You should see** a long list of `PASS` lines ending with **`99/99 passed`** (the number may be higher if more tests were added, but it must say *all* passed). Any `FAIL` means **stop**.

5. When M12 is reported finished, the repository must contain these commands (if one is missing, the build is not finished):

| Command | What it does |
|---|---|
| `pnpm install` | installs everything |
| `docker compose up -d` | starts a local database, Redis and storage |
| `pnpm db:migrate` | applies the database files |
| `pnpm db:test` | runs the database tests |
| `pnpm test` | runs all automated tests |
| `pnpm e2e` | runs the end-to-end scenario |
| `pnpm bootstrap:admin` | creates the first Winfield super admin |
| `pnpm dev` | starts everything locally |

---

## Part 5 — Run it on your own computer first

1. `pnpm install` → **you should see** it finish with no red errors.
2. `docker compose up -d` → `docker ps` should list a database, Redis and a storage container, all "healthy" or "up".
3. `pnpm db:migrate` → **you should see** each of the six database files applied in order.
4. `pnpm db:test` → **`all passed`**.
5. `pnpm bootstrap:admin` → it asks for an email and a strong password; **you should see** "super admin created".
6. `pnpm dev`, then open the console address it prints (usually `http://localhost:3000`) and **log in**.
7. `pnpm test` and `pnpm e2e` → **both pass**.

If steps 1–7 work, the software itself is sound. Everything after this is about putting it on the internet safely.

---

## Part 6 — Create the production environment

> **Golden rules for production.** Never connect any running service as the database *owner*. Never edit production data by hand in a database tool. Never copy production data into staging. Never share logins. Do everything for **staging first**, repeat for **production**.

### 6.1 Database

1. In your database provider, create a **PostgreSQL 16** instance in your chosen region. Turn on: **automatic daily backups**, **point-in-time recovery** (keep at least 14 days), **encryption at rest**, **private network access only**, **deletion protection**.
2. Create the **migration owner** account (the provider usually creates an admin user; use it only for migrations).
3. Run the database files **in order** as that owner: `001` through `006` (your pipeline's `pnpm db:migrate` does this).
4. Give the five application roles a way to log in. In a database console, run once per role, using a **different long random password for each** (generate in the password manager; store them there):

```sql
ALTER ROLE app_api      LOGIN PASSWORD '<random-1>';
ALTER ROLE app_engine   LOGIN PASSWORD '<random-2>';
ALTER ROLE app_ingest   LOGIN PASSWORD '<random-3>';
ALTER ROLE app_auth     LOGIN PASSWORD '<random-4>';
ALTER ROLE app_readonly LOGIN PASSWORD '<random-5>';

-- safety limits
ALTER ROLE app_api      SET statement_timeout = '15s';
ALTER ROLE app_api      SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE app_engine   SET statement_timeout = '60s';
ALTER ROLE app_ingest   SET statement_timeout = '10s';
ALTER ROLE app_auth     SET statement_timeout = '10s';
ALTER ROLE app_readonly SET statement_timeout = '30s';
ALTER ROLE app_api CONNECTION LIMIT 40;   -- adjust to your plan
```

5. **Verify** (you should see `0` rows from the first query and an error from the second):

```sql
-- as app_api: should return nothing, because no user is set
SELECT count(*) FROM app.farms;
-- as app_api: must fail with "permission denied"
SELECT * FROM app.user_credentials;
```

### 6.2 Redis and storage

- Create Redis on the private network; note its connection address.
- Create a **private** bucket named for the environment (for example `winfield-prod-media`), turn on **versioning**, block all public access, and allow cross-origin uploads only from your app domains.

### 6.3 Secrets

Store all of the following in the **host's secret manager** (not in the repository, not in chat, not in the app). Use these exact names so the services find them:

| Name | What it is |
|---|---|
| `DATABASE_URL_API`, `DATABASE_URL_ENGINE`, `DATABASE_URL_INGEST`, `DATABASE_URL_AUTH`, `DATABASE_URL_MIGRATE` | Connection strings for each role (the last is the owner, used only by deploy migrations) |
| `REDIS_URL` | Redis address |
| `JWT_ACCESS_PRIVATE_KEY`, `JWT_ACCESS_PUBLIC_KEY` | Signs login tokens |
| `ENTITLEMENT_PRIVATE_KEY` (public key is built into the app) | Signs offline entitlements |
| `FIELD_ENCRYPTION_KEY` | Encrypts MFA secrets (ideally held in the provider's key service) |
| `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_REGION` | Photo storage |
| `SMS_PROVIDER`, `SMS_API_KEY`, `SMS_SENDER_ID` | Alerts |
| `EMAIL_API_KEY`, `EMAIL_FROM` | Invitations and resets |
| `EXPO_ACCESS_TOKEN` | Push notifications |
| `ERROR_TRACKING_DSN` | Error tracking |
| `APP_BASE_URL`, `API_BASE_URL`, `CONSOLE_BASE_URL`, `ALLOWED_ORIGINS` | Addresses |

The build also provides a `.env.example` listing every name. **Use a different value for every secret in staging and production.**

### 6.4 Deploy the services

Create **four services** from the repository's Docker files: **api**, **worker**, **ingest**, **console**. For each: set the secrets above, set a health-check path (`/health`), set at least **two instances** for the API in production, and turn on automatic restart.

**You should see:** each service reporting "healthy"; opening `https://api.<your-domain>/health` returns "ok".

### 6.5 Domain and HTTPS

Point your domains at the services; turn on automatic HTTPS certificates; confirm that `http://` redirects to `https://`.

### 6.6 First admin and smoke test

1. Run the bootstrap command **once** against production to create the first super admin; use a strong password and set up two-step sign-in immediately.
2. Log in to the console. **Smoke test:** create a test farm, check the audit log shows your actions, then log out.

---

## Part 7 — Build and publish the mobile apps

### 7.1 Internal test builds first

1. In Expo/EAS, link the project and set the **bundle identifier** (Part 1, decision 8) for iOS and Android.
2. Add the app icon, splash screen and name.
3. Point the staging build at the **staging API**. Run the build for iOS and Android.
4. Install on **real phones**: iPhone via TestFlight, Android via internal testing. Include one **cheap, older Android phone**.
5. Run the **field test checklist** with a real manager, in their language:

| Test | Pass if |
|---|---|
| Sign in, accept an invitation | works first time |
| Switch the phone to airplane mode, log work and a photo, switch back | everything syncs, each entry shows "synced" |
| Close the app mid-sync | nothing is lost or duplicated |
| Log in on a cycle that is not active | "Awaiting Winfield activation" appears |
| Receive an alert | push arrives; critical alert also by SMS |
| Slow or no signal for a full day | app stays usable |

### 7.2 Store submission

**Both stores need:** privacy policy web address, support address, screenshots, age rating, a description, and a clear **in-app way to delete an account** (a store requirement).

**Reviewers must be able to log in and see the app working.** Because this app does nothing without Winfield activation, prepare a **review farm**:

1. In production, set `allow_demo_cycles` to **on** (console → settings, super admin only).
2. Create a farm called "App Review", a demo crop (flagged *demo*), a demo program approved by two agronomists, and activate one demo cycle with the normal two-person process.
3. **Immediately set `allow_demo_cycles` back to off.** (The already-active demo cycle keeps working; the switch only matters at activation.)
4. Put the review login (email and password) and a one-paragraph explanation in the store's review notes: *"This app is used by farms supplied by Winfield. It works only for farms activated by Winfield. Use this demo account to see all features."*

**Apple:** create the app record, answer the privacy "data collection" questions to match the privacy policy exactly, upload the build, submit for review. **Google:** complete the data-safety form, upload the build to a closed test, then promote to production.

**You should see:** both apps "approved" and available. Expect at least one round of review questions; answer them promptly and honestly.

---

## Part 8 — Go-live checklist

Do not announce launch until **every** box is ticked. This is the same list as "Definition of ready to deploy" in the addendum (§K).

- [ ] Database tests pass on staging; automated and end-to-end tests pass
- [ ] Tested on real iPhone and Android phones, **including a low-end one**, online and offline
- [ ] Independent security test done; **no open critical or high findings**
- [ ] A backup has been **restored** into a test database and checked
- [ ] The first crop program is **approved by two agronomists** through the console
- [ ] Privacy policy, terms and data agreements reviewed by your adviser for each country
- [ ] Both apps approved in the stores; in-app account deletion works
- [ ] Alerts reach a real phone by push **and** SMS; SMS spending cap is set
- [ ] Uptime monitoring pages a named person; a support mailbox is staffed
- [ ] Every open decision in Part 1 is written down
- [ ] Secrets are in the secret manager only; nobody uses a shared login

---

## Part 9 — Onboard the pilot farm (the first real use)

All steps happen in the **Winfield console** unless noted.

| # | Who | Step | You should see |
|---|---|---|---|
| 1 | Operations A | **Farms → New farm.** Enter name, country, region | Farm appears as *Active* |
| 2 | Operations A | **Invite the farm owner** by email | Owner receives an invitation |
| 3 | Operations A | **Add blocks** with names, area, and the map boundary | Blocks listed on the farm |
| 4 | Operations A | **Supply → Record supply batch**: crop, variety, nursery lot code, quantity, supply date, delivery note, block | Batch listed |
| 5 | Operations A | **Cycles → New cycle** from the batch, choosing the **approved** program version | Cycle shows *Draft*; the program is now frozen onto it |
| 6 | Operations A | **Request activation** | Cycle shows *Pending activation* |
| 7 | **Operations B** (a different person) | **Activation queue → Approve** | Cycle shows **Active**; expected steps and stage calendar appear |
| 8 | Farm owner | Accepts the invite, sets up two-step sign-in, **invites the farm manager** (in the app or web) | Manager appears in the team list |
| 9 | Operations | **Assign the manager to blocks** | Manager sees the block |
| 10 | Farm manager | Installs the app, signs in, gives consent choices, **confirms receipt** (quantity and planting date) | Today screen lists the first steps |

**Two-person rule:** if Operations A tries to approve their own request the system refuses. That is correct, not a bug.

---

## Part 10 — Troubleshooting

| What you see | Likely cause | What to do |
|---|---|---|
| Manager sees **"Awaiting Winfield activation"** | Cycle is not Active | Console → Activation queue; if *Pending*, a *different* operations person must approve |
| Operations cannot approve their own request | Two-person rule | Ask a second authorised person |
| Activation refused: "only APPROVED program versions" | Program still in draft/review | A second agronomist must approve the version |
| Activation refused: "demo crops cannot be activated" | Crop is a demo | Use a real crop, or see Part 7.2 for the review farm |
| Phone shows entries in **"needs attention"** | Work dated inside a suspension, or cycle is closed | Read the reason shown; contact Winfield; **do not delete** |
| Manager cannot sign in | Account locked after failed attempts, or deactivated | Wait 15 minutes, or reset password; check the user is active |
| Owner sees no data | Not assigned/invited correctly | Check farm membership and the farm's status |
| No push notifications | Notifications permission off, or no registered device | Check phone settings and the user's device list |
| Alerts by SMS missing | Spend cap reached or sender not approved | Check the provider dashboard |
| Sensor shows **"Check sensor"** | Poor-quality, silent or flat-lining device | Inspect or recalibrate the device; this is not a crop problem |
| Database tests show **fewer than all passing** | Something changed in the database files | **Stop. Do not deploy.** Revert the last change |
| A deployment fails during migration | A database file did not apply | **Do not run it again by hand.** Restore the last backup if data changed, or ask the developer; fix forward in a new migration file |
| API slow or erroring | Database connections exhausted, or a service down | Check service health and the error tracker; scale up temporarily |
| Score looks wrong | Check missed or late steps listed in the score breakdown | The formula and every contributing event are shown; scores are recomputed from events |

---

## Part 11 — Running it day to day

**Daily:** check the uptime and error dashboards; skim open escalations in the console; confirm alerts are being delivered.
**Weekly:** review the audit log for unusual denied attempts; check the SMS spend; check backups succeeded.
**Monthly:** review farm compliance and at-risk list; confirm sensor devices are reporting; apply dependency updates (staging first).
**Quarterly:** **restore-test a backup**; rotate secrets; review who has access to what; re-run the security scan; review the program's tolerances against pilot results.

**Add a new crop:** Console → Catalog → New crop → create the program in the authoring tool → a second agronomist reviews and approves → it can now be attached to supply batches. No code change is needed.
**Add a Winfield staff member:** Console → Users → New → choose the *narrowest* role that does the job → they set up two-step sign-in on first login.
**Suspend a farm or cycle:** Console → Cycles → Suspend → a written reason is required; the farm app becomes read-only at next sync.
**Deploy an update:** merge → staging deploys automatically → test → approve production deploy; the pipeline runs migrations first.
**Roll back a bad release:** redeploy the previous version of the service; migrations are written so older code keeps working.
**Rotate a secret:** create a new value in the secret manager, redeploy the service, then revoke the old one.

---

## Part 12 — Things never to do

- Never use the database owner login from a running service or from your laptop for routine work.
- Never edit, delete or "fix" rows directly in production. Corrections are made through the app (annotations, amendments).
- Never copy production data into staging or onto a laptop.
- Never leave `allow_demo_cycles` on.
- Never share one login between people; create a user for each person.
- Never put secrets in the repository, in screenshots, in chat or in email.
- Never skip the second approver "just this once".
- Never go live with a failing test, an unreviewed program, or an unrestored backup.

---

## Glossary

**Cycle** one planting from supply to harvest. **Supply batch** a delivery of plants from the nursery. **Activation** Winfield switching a cycle on. **Program** the stage-by-stage growing instructions for a crop. **Protocol** what the program tells the farm to do. **Expected step** one thing that should happen by a deadline. **Event** one recorded action, which can never be edited. **Hash chain** the tamper-evident link between events. **RLS** database rules that stop one farm seeing another's data. **Staging** a safe copy of the system for testing. **Migration** a change to the database structure.
