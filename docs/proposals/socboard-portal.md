# MutaSpace SOC Portal — Product Design & Rewrite Proposal

**Working name:** `socboard` (replacing `socdoc`)
**Author:** Lead product engineering
**Date:** 2026-07-23
**Status:** Proposal for approval — precedes any `/plan`

---

## 1. Vision

`socboard` is the single place a SOC-class student logs into for the entire course: their **home base** for documenting everything they build (Wazuh standups, AD policies, network diagrams, live investigations), their **launchpad** into the running lab (Wazuh dashboard, their own VM consoles, guides, AI assist), and the channel through which they see announcements and get feedback — all in one authenticated app that works from inside the SOC LAN with no internet. The same application, behind role gates, is the **instructor's control plane**: a frontend to the attack/scenario VM (start / stop / reset a scenario), least-privilege Proxmox control over the lab VMs, and a grading system that computes participation and competency **automatically** from what students actually did — doc revisions, in-app activity, and machine-verified VM state pulled from the Wazuh agents and Ansible the lab already runs — instead of the old workflow of reading Discord and hand-checking machines. One Django deployment on `jumpbox-01`, outside the snapshot-reset plane, owned end to end by a solo instructor building it with Claude Code.

---

## 2. Personas & Top User Journeys

### Student — "Maya", learning to run a SOC
1. **Log in & orient.** Opens `socboard`, lands on a dashboard showing her team, her current milestone progress ("Wazuh standup: 6/9 checks passing"), unread announcements, and live status tiles for her VMs and the Wazuh SIEM.
2. **Document what she builds.** Opens a Notion-style block editor, writes a runbook for enrolling a Wazuh agent, pastes screenshots inline as evidence, drops in a Mermaid data-flow diagram and an Excalidraw attack-path sketch — autosaved with full revision history.
3. **Navigate the lab.** From the launchpad, one click opens her `analyst-01` console (Proxmox noVNC), the Wazuh dashboard (deep link into a saved search scoped to her host), and the course guides.
4. **Get AI help mid-incident.** Opens the AI-assist pane, asks "why isn't my Sysmon config loading" — the query is answered by the local Ollama LLM with her current doc and scenario as context, and the interaction is logged.
5. **Submit & communicate.** Clicks "Submit for milestone" on a finished doc; it snapshots that revision as the graded artifact. Reads the instructor's threaded comment asking her to expand the escalation section; replies in-thread. No Discord.

### Instructor / Admin — "Prof. Zeller", running the class solo
1. **Pre-class health check.** Opens the admin dashboard: all lab VMs green, backups current, no agent offline.
2. **Run a scenario.** Clicks "Start scenario: Kerberoasting on dc-01" — the platform triggers the Ansible playbook via Semaphore, streams live output, powers on the isolated attack plane, and flips the scenario to "running."
3. **Watch & score live.** Sees per-team service-check / detection status update each round while the scenario runs; resets it to a clean snapshot between sections with one button.
4. **Grade with evidence, not guesswork.** Opens a milestone: each criterion already shows an auto-verdict (Wazuh SCA "Sysmon installed & config loaded: PASS on `win-client-01`", Ansible "auditd rules present: PASS") plus the student's submitted doc revision. He adjusts a few rubric scores by hand, leaves comments, exports a Canvas-format CSV.
5. **Track participation objectively.** Opens the participation view: an activity timeline per student (doc edits with word-count deltas, submissions, comments, AI queries, scenario participation) rolled into a tunable participation score — defensible, auditable, no Discord scraping.
6. **Manage the class.** Rotates the enrollment code, imports next semester's roster CSV, provisions per-student lab AD accounts from the admin side, toggles "students can create teams."

---

## 3. What to Salvage vs Rewrite

The old `socdoc` is ~1,500 lines of views + ~400 lines of models — small enough that we **rewrite the framework layer wholesale and carry forward only designs, not code.** The two capabilities the instructor most wants to replace — Discord-derived participation grades and manual VM software checks — **never existed in code**; `discord_id` was captured and read nowhere, and VM checks were entirely out-of-band. So we are not porting integrations, we are building them fresh, which is liberating.

| Area | Old `socdoc` | Verdict | What replaces it in `socboard` |
|---|---|---|---|
| **Team + join-code model** | `accounts.Team` with `secrets.token_urlsafe` join code, owner + self-join | **KEEP (concept)** | One canonical `Team` model, shared by all apps. Kill the duplicate `grading.Team`. |
| **Per-artifact visibility** | team / class / global tiers on docs, policies, diagrams (inconsistent: 2 vs 3 states) | **KEEP (concept), unify** | One `visibility` + review lifecycle shared by every artifact type. |
| **Class-enrollment-code gate** | Code gates signup only, validated then discarded; DB rows + env fallback | **KEEP** | Same idea, moved out of allauth-URL-coupled middleware into the signup flow itself. |
| **Singleton `ClassConfig` toggles** | `students_can_create_teams` | **KEEP** | Generalize to a course-settings model with instructor kill-switches. |
| **Rubric grading model** | `Milestone → Criterion → Submission → CriterionScore` + `Evidence` + CSV export + team matrix | **KEEP (best bones in the app)** | Carry forward with fixes: single Team, real `doc_revision` FK snapshot, score-bound validation, attempt history, one aggregated matrix query, **auto-populated `Evidence` from Wazuh/Ansible.** |
| **Submit-from-doc** | Doc page becomes the graded submission (stored as an absolute URL string) | **KEEP (strongest idea)** | The doc **revision** FK is the source of truth, snapshotted immutable at submit time. |
| **Markdown docs** | One flat `MarkdownxField` blob, no images, no history, half-wired editor | **REWRITE** | BlockNote structured block editor, inline screenshots, server-side revisions, custom SOC blocks. |
| **Diagrams** | Fossflow container, PNG-export-only, no re-editable source, `pk`-vs-slug 404s | **REWRITE** | Embedded Excalidraw (scene JSON persisted) + Mermaid blocks; source is versioned, not raster. |
| **Discord OAuth (identity)** | allauth Discord provider; `discord_id` write-only, read nowhere | **KILL** | Local accounts + roster import; optional OIDC later. Nothing is lost. |
| **Discord (comms + participation)** | Not in code — manual instructor workflow | **KILL / BUILD FRESH** | In-app announcements + doc-anchored threaded comments; participation from an **activity event log**. |
| **Manual VM software checks** | Not in code — instructor inspected VMs by hand | **KILL / BUILD FRESH** | **Wazuh SCA custom policies + syscollector API + Ansible verify-playbooks**, mapped to rubric criteria. |
| **`moderation` app** | Empty stub, crashes on a deleted field, CSRF-less GET approvals | **KILL** | One unified review queue over all artifact types with a real state machine + comments. |
| **`policies` app** | Near-clone of docs; dead `forms.py` importing nonexistent models | **MERGE into docs** | Policies are just docs with a policy template + category; one content system. |
| **Settings / secrets / compose** | `SECRET_KEY='dev'`, `DEBUG` bool/str bug → `ALLOWED_HOSTS='*'`, hardcoded creds + hostname | **KILL** | Typed settings (django-environ / pydantic-settings), fail-closed defaults, secrets from env. |
| **Media serving** | `django.static()` helper (DEBUG-only) + bind mount | **KILL** | Proper media via reverse proxy volume; inline images stored as real attachments. |
| **Frontend** | Server templates + one CSS + duplicated inline JS, CDN `marked.js` | **REWRITE** | HTMX 2 + Alpine + Django templates for 90%; two Vite-built React islands (editor, canvas). |
| **Tests / CI / README** | Zero tests, empty README, no CI | **BUILD FRESH** | Tests from day one, CI running them + `packer validate` / `tofu test` where relevant. |

---

## 4. Recommended Architecture & Tech Stack

**Decisive call: stay Django. Do not migrate to Next.js/FastAPI+React.** The portal is overwhelmingly forms, tables, dashboards, links, admin actions and grading — the exact shape where server-rendered Django + HTMX ships faster and runs cheaper for a solo maintainer than a two-codebase split. The only two genuinely rich widgets are self-contained React components that embed fine as islands. Migrating would forfeit Django admin, ORM, auth and permissions — which are the backbone of the grading and Proxmox-admin side — and double the deployable surface.

### 4.1 Stack

| Layer | Choice | Why |
|---|---|---|
| **Framework** | **Django 6.0** | Built-in background **Tasks** framework (Dec 2025) is purpose-built for "start/reset scenario" jobs — no Celery/Redis at this scale. Template partials pair with HTMX. Built-in CSP. (5.2 LTS is the fallback if quiet-maximalism is preferred; identical app design.) |
| **Interactivity** | **HTMX 2 + Alpine.js** | Navigation, forms, CRUD, live status tiles via polling/SSE. HTMX 2 is feature-complete, supported in perpetuity. |
| **Rich islands** | **React via django-vite**, one Vite bundle | Only two mount points: the doc editor and the diagram canvas. Everything else is server-rendered. |
| **Doc editor** | **BlockNote** (MPL-2.0, ProseMirror/Tiptap) | Notion-style blocks, slash commands, inline images, tables, code — JSON persisted in Postgres. Custom blocks give us `evidence`, `wazuh-rule`, `investigation-step`, `mermaid`, `excalidraw`. Avoid the AGPL/commercial `xl-` packages. BlockNote JSON is canonical; markdown is a lossy export. |
| **Diagrams** | **Excalidraw** (MIT, embedded) + **Mermaid** blocks | Scene JSON stored per-doc; Mermaid as diffable text. draw.io embed-mode is a documented *later* option for formal network diagrams. |
| **Collab (deferred)** | **Hocuspocus 4** (MIT Yjs server) | The one optional Node sidecar. BlockNote v0.52 decoupled Yjs, so **v1 ships single-user + autosave revisions** and real-time co-editing bolts on later without schema change. Do not make it load-bearing. |
| **Versioning** | Server-side `Revision` snapshots + **django-simple-history** for ordinary models | Immutable revision on save/submit → history/diff/restore UI, grade-a-pinned-revision, participation evidence, anti-plagiarism. |
| **API (as needed)** | **django-ninja** | FastAPI-style typed endpoints *inside* the same project for AI-assist and in-VM check agents — removes the last reason to run a separate FastAPI service. |
| **Proxmox** | **proxmoxer 2.3** | De-facto PVE Python client (what Ansible uses underneath). Allowlisted verb layer, never raw passthrough. |
| **Scenario execution** | **Semaphore UI** REST API on `jumpbox-01` | One task template per scenario runs the existing Ansible; the admin page POSTs a template and streams logs. Every run audited for free. (Alternative: embed `ansible-runner` directly — fewer services, but you own job state.) |
| **DB** | **Postgres 16** | Unchanged; the one durable store. |
| **Deploy** | **docker-compose on `jumpbox-01`**, behind nginx (TLS) | Django + Postgres + a static Vite bundle + (later) one Hocuspocus container + (external) Semaphore. |

### 4.2 Authentication & identity — the hard architectural rules

- **Baseline: portal-local accounts** (custom `User` model **on day one**), app-level role enum, **CSV roster import** with generated first-login credentials or magic links. For ~10–40 students and one instructor this is the lowest-maintenance option and requires zero extra services.
- **Three explicit roles: `student`, `instructor`, `service`** (the automation identity for scenario/agent APIs). Kill the ~20 scattered `is_staff` checks. Row-level ownership (`owner`/`team` FK on every workspace object) + instructor read-all gives per-student isolation for free.
- **MFA / passkeys mandatory for instructor/admin** — the admin side drives Proxmox; a leaked admin session must not be a bare password away.
- **Do NOT bind portal auth to the lab AD (`mutaspace.local`).** This is non-negotiable and specific to this lab:
  1. `dc-01` is *curriculum* — attacked from `kali-01`, broken by students, reset by snapshots. Portal auth would die exactly mid-incident and snapshot rollback would silently revert accounts.
  2. The attack plane targets AD; a student who DCSyncs `dc-01` would hold credentials that also open the **admin side that controls Proxmox** — a privilege-escalation path out of the sandbox.
  3. AD's user population should be scenario-driven fake employees, not the class roster.
  **Invert the relationship: portal → lab.** The admin side *provisions* per-student lab AD accounts via Ansible and shows them on the student dashboard. The lab is a provisioning **target**, never an auth **source**.
- **Identity lives outside the snapshot-reset plane** — the portal (and its Postgres) run on `jumpbox-01` / management side, never on `vmbr1`/`vmbr2`.
- **OIDC is a no-regret later add.** If single-sign-on across services becomes a felt need, **Pocket ID** (single Go container, passkey-first, OIDC-certified) is the pick — the portal's own users/roles schema is identical either way. Wazuh dashboard SSO stays optional; put its URL + credentials on the dashboard instead.

### 4.3 Data model sketch

```
User (custom) ── role {student|instructor|service}, team FK, role_in_soc, lab_ad_username
Team ── name, join_code, owner FK
CourseConfig (singleton) ── enroll_code, students_can_create_teams, participation_weights (JSON)
EnrollmentCode ── code, active, expires        # rotating codes + env fallback

# Documentation workspace (docs, policies, diagrams unified)
Doc ── title, team FK, author FK, doc_type {runbook|policy|investigation|diagram|guide},
       tags (M2M), visibility {team|class}, review_state {draft|submitted|changes|published}
DocRevision ── doc FK, blocknote_json, author FK, created_at   # immutable snapshots
Attachment ── doc FK, file, kind {screenshot|excalidraw_scene|file}
Comment ── doc FK, author FK, anchor (block id | null), body, thread parent FK

# Grading (rubric carried forward, fixed)
Milestone ── title, max_points, agent_group        # Wazuh group this milestone's checks target
Criterion ── milestone FK, label, max_points, weight, evidence_source {manual|wazuh_sca|wazuh_pkg|ansible|activity}, evidence_ref
Submission ── milestone FK, student FK, doc_revision FK (snapshot), attempt_no, submitted_at
CriterionScore ── submission FK, criterion FK, points (≤ max), comment, auto {bool}
Evidence ── submission FK / criterion FK, source, payload (JSON), collected_at   # auto or manual

# Participation & audit (net-new — replaces Discord)
ActivityEvent (append-only) ── user FK, kind {login|doc_edit|submit|comment|ai_query|scenario|check_pass},
       payload (JSON, e.g. word-count delta), ts
Announcement ── author FK, body, created_at ; AnnouncementRead ── announcement FK, user FK

# Admin / infrastructure
ScenarioRun ── scenario_id, triggered_by FK, semaphore_task_id, state, started/ended_at, log_ref
VMActionAudit ── actor FK, vmid, verb {start|stop|snapshot|rollback}, result, ts
LabCheck ── milestone/criterion linkage, source, target_vm, last_result, last_run   # cached check state
```

### 4.4 Why this stays low-maintenance
One Django project, one deployment, one auth system, Django admin for free instructor CRUD. All egress-free/offline (assets vendored, no CDN) — essential for students on the SOC LAN. Background jobs in Django 6 Tasks (no broker). The only "extra moving parts" are optional (Hocuspocus) or reuse existing lab infra (Semaphore + Ansible on `jumpbox-01`, Wazuh on `wazuh-01`). Grading needs **no new heavyweight service** — evidence flows from three collectors the lab already has.

---

## 5. Feature Set (MVP-first)

Legend: **MVP** = a student can log in, see a dashboard, and document work; instructor can run the class. **v1** = the differentiators. **later** = nice-to-have / scope valves.

### Student portal (identity, comms)
- **MVP** — Local login, class-code-gated signup, team create/join, profile with `role_in_soc`.
- **MVP** — Dashboard shell: team pill, milestone progress summary, announcements feed, dark/light theme.
- **v1** — Announcements with read receipts; threaded comments anchored to docs (SSE).
- **v1** — AI-assist chat pane (Ollama proxy) with lab context injection.
- **later** — Real-time presence/co-editing (Hocuspocus); optional Mattermost bridge only if synchronous chat is genuinely needed.

### Documentation workspace
- **MVP** — BlockNote editor, inline screenshot paste, server-side autosave + `DocRevision` history, tags, team→class publish step.
- **MVP** — Instructor/global guides live in the same system (team=None, class visibility).
- **v1** — Custom SOC blocks (evidence, wazuh-rule, investigation-step, mermaid), Excalidraw diagram block with persisted scene JSON, per-category doc templates (IR / access control / log mgmt policy scaffolds).
- **v1** — Revision diff & restore; submit a pinned revision.
- **later** — draw.io embed for formal network diagrams; CRDT co-editing; markdown export.

### Dashboard / launchpad
- **MVP** — Per-student link cards driven by `lab.yaml` + roster: their VM consoles (Proxmox noVNC URLs), Wazuh dashboard deep link, guides, AI assist.
- **v1** — Live status tiles: agent green/red + recent alert count per their VM (Wazuh API), VM power state (Proxmox API), "requirements met: 7/9" from check results.
- **later** — Personal instructor ops board (or drop in Homepage on `jumpbox-01` as a 30-min separate win).

### Admin control plane
- **MVP** — Roster CSV import, enroll-code rotation, `CourseConfig` toggles, unified review queue (approve / request-changes with comments), rubric builder (Milestone/Criterion in-app, not Django admin).
- **v1** — Proxmox VM control: per-VM start/stop/snapshot/**rollback** buttons (pool-scoped token), audited.
- **v1** — Scenario control: start/stop/reset buttons → Semaphore task templates → Ansible, with streamed logs and `ScenarioRun` history.
- **v1** — Auto-grading: Wazuh SCA + syscollector + Ansible verify-playbooks feed `Evidence`/`CriterionScore`; participation view + Canvas CSV export.
- **v1** — Provision per-student lab AD accounts via Ansible; show credentials on student dashboards.
- **v1** — Live scenario scoring (CCDC-style service/detection checks per round).
- **later** — Pulse as a read-only health pane; xAPI/Ralph LRS only if standards interop is demanded.

---

## 6. Integration with the MutaSpace Lab

Four thin integration **seams**, not one monolith of glue. All actions land in one audit/event table shared with grading.

### 6.1 Proxmox — VM control
- **`proxmoxer`** with a **privilege-separated, pool-scoped API token** — never `root@pam`. Put all lab VMs in a resource pool (OpenTofu sets membership); grant a custom role with only `VM.Audit`, `VM.PowerMgmt`, `VM.Snapshot`, `VM.Snapshot.Rollback` on `/pool/<lab-pool>`. `VM.Snapshot.Rollback` is a distinct privilege precisely so "reset scenario" is grantable without delete/config rights.
- **This token setup belongs in `scripts/bootstrap-host.sh`** alongside the existing privilege fixes — "fix the script, not just the host," so the next operator inherits it.
- Backend exposes **allowlisted verbs** (`start_vm`, `stop_vm`, `snapshot`, `rollback_to`, `lab_status`) reading VMIDs **from `lab.yaml`** so the UI and IaC never drift.

### 6.2 Attack / scenario VM — the interface this platform needs
The scenario VM is a **parallel effort**. `socboard`'s admin side fronts it via Semaphore + Ansible. The **contract we require from the scenario work**:

- **A declarative scenario registry** (a YAML file in the repo, `lab.yaml`-style) listing each scenario: `id`, human name, description, the Ansible playbook/tags that **start**, **stop**, and **reset** it, which VMs it touches, and which snapshot is its clean baseline.
- **Idempotent playbooks** for start/stop/reset, invokable non-interactively by Semaphore's API (one task template per verb per scenario).
- **A clean-baseline snapshot** per scenario the platform can roll back to (maps to the Proxmox rollback verb).
- **Optional: a machine-readable "expected detections/services" descriptor** per scenario so live scoring knows what to check each round (feeds §7).
- **State the platform tracks:** `ScenarioRun` (which scenario, who triggered, Semaphore task id, running/stopped, log ref). The platform owns orchestration state; the scenario VM owns the attack logic.

### 6.3 Wazuh — links, tiles, no iframe fight
- **Do not iframe Wazuh.** The Wazuh dashboard plugin sets `X-Frame-Options: sameorigin` itself and the plugin-patch workaround is lost on every upgrade (lab is on 4.14.6 and will upgrade).
- **Render our own status tiles** from small cacheable Wazuh REST/indexer queries (agent status, recent alert counts per student VM) and **deep-link every tile** into the full Wazuh dashboard in a new tab (saved-search URL scoped to the student's host). Students get "your agent is green, 3 new alerts" context and click through into the real SIEM — which is the teaching goal.
- If true embedding is ever demanded, the maintainable route is a **same-origin reverse proxy** (portal + Wazuh under one origin behind nginx), never patching `plugin.ts`.

### 6.4 AI-assist — Ollama through the backend
- **Proxy Ollama's OpenAI-compatible endpoint** (`nlp-01:11434 /v1/chat/completions`) through a backend django-ninja route; stream tokens back via SSE. **Do not** stand up Open WebUI (another login/service).
- The proxy is where value is added: **inject lab context** (which VM, current scenario, links into the student's own docs), enforce per-student rate limits, and **log every Q&A as an `ActivityEvent`** — routing AI through the platform is precisely what lets AI usage feed participation tracking. The existing `ai/` tooling (detection copilot, lab assistant) slots behind the same routes.
- **Network caveat to resolve:** `nlp-01` sits on the normally-off isolated plane (`10.10.20.0/24`). AI assist as a first-class student feature needs either a routed path through `fw-01` or the Ollama host mirrored onto the SOC LAN. Flag for the infra owner.

### 6.5 Student identity → lab resources
Portal `User` carries `lab_ad_username`. The admin side runs an Ansible playbook (same pattern as scenario control) to **create/rotate** that student's lab AD account and DHCP-stable VM assignments, recording the mapping. The dashboard renders "your lab credentials" and per-student console links from `lab.yaml` + roster. The portal never trusts the lab for auth (§4.2).

---

## 7. Automated Grading / Participation — Replacing Discord

The pipeline needs **no new heavyweight service**. Evidence flows from three collectors the lab already has or the app already is, aggregated by a **rubric-as-code** layer into scores with an evidence trail, exported as Canvas CSV. Students must **never** reach the Wazuh API or `jumpbox-01` directly — everything fronts through the backend with a read-only Wazuh user and a scoped Ansible credential.

### 7.1 Collector A — Wazuh SCA + syscollector (state on VMs)
The killer insight: **the lab already runs Wazuh with agents on every graded VM**, and Wazuh's Security Configuration Assessment module is a per-host pass/fail engine driven by YAML policies.
- Write **one custom SCA policy per assignment** ("Sysmon installed and config loaded", "auditd rules present", "nginx hardened", "agent enrolled"). Checks test files, registry keys, processes, command output. Each failed check carries a **remediation string** we surface to students as a hint.
- Distribute centrally from the manager via `agent.conf` per **Wazuh agent group** — put each cohort in its own group so policies target only student VMs. No per-VM touch.
- Poll results per agent: `GET /sca/{agent_id}` (summary + score), `GET /sca/{agent_id}/checks/{policy_id}?result=failed` (per-check detail). For plain "is package X installed": `GET /syscollector/{agent_id}/packages?name=<pkg>`.
- The grading service maps SCA check IDs → rubric criteria; the SIEM the students stood up becomes its own compliance checker (pedagogically elegant). **Note:** SCA rescans on interval, so dashboard "live" status is really interval-fresh (configurable).

### 7.2 Collector B — Ansible verify-playbooks via `ansible-runner` on `jumpbox-01` (behavior / domain checks)
For the ~20% SCA can't express — AD objects exist (GPOs, OUs, users), a Wazuh **rule actually fires**, a service answers correctly.
- A library of small `verify_*` playbooks (`package_facts` / `win_shell` / `assert`) run per-student on demand or on schedule via **`ansible-runner`** (Red Hat's programmatic interface behind AWX) — structured JSON event streams stored as graded `Evidence`, not scraped stdout. These live beside the config playbooks in `ansible/`.
- **`goss`** (single Go binary, JSON/JUnit output) is the fast declarative option for Linux checks. Skip InSpec (Chef/Ruby weight + licensing).

### 7.3 Collector C — the platform's own activity event log (participation)
One append-only `ActivityEvent` table records logins, **doc edits with word-count deltas**, submissions, comments, AI-assist queries, scenario participation, and check pass/fail transitions. **This replaces "count Discord messages" with defensible, in-platform signals** — and because messages/edits land in our own DB, participation is *integrated*, not scraped. A tunable-weight rollup (`CourseConfig.participation_weights`) produces a participation score with a visible timeline for dispute resolution.

### 7.4 Live scenario scoring (the CCDC pattern)
For "is the student's SOC keeping services alive / detecting the attack while scenario X runs" — implement the CCDC scoring-engine **pattern inside the scenario module** (periodic protocol checks per team + score-over-time table), rather than deploying a whole second webapp. `scoringengine/scoringengine` (MIT) and `DWAYNE-INATOR-5000` (single Go binary, built for this class size) are the reference implementations to mine; CTFd only if flag-submission challenges are also wanted (it brings its own user DB — keep it an optional side service).

### 7.5 Rubric-as-code + export
- **YAML rubric per milestone** mapping criteria → evidence sources (SCA check IDs, verify-playbook results, service-check uptime, doc-submitted flags) with weights — versioned alongside the IaC, auditable when a student disputes a grade.
- A grading job aggregates all three collectors into per-student scores with an evidence trail; instructor adjusts/overrides in-app.
- **Export: Canvas gradebook CSV** (the 5 case-sensitive required columns) — zero-dependency, officially documented. **Skip LTI 1.3** (the reference `pylti1p3` lib is ~2 years stale and institutional registration is real overhead). Ralph LRS (xAPI) only if standards interop is ever demanded.
- **Fix the old grading bugs:** enforce `points ≤ criterion.max_points` and reconcile weighted sums against `milestone.max_points`; attempt history instead of silent `update_or_create` clobber; one `values().annotate()` query for the team matrix.

---

## 8. Migration Plan from Old `socdoc`

**This is a rewrite, not a port.** Almost nothing operational should survive. What carries:

- **Ideas/designs carry (not code):** team + join-code mechanics, class-code gate, visibility/publish workflow, rubric schema shape, submit-from-doc, `role_in_soc`, `CourseConfig` toggle pattern, dark mode + team-pill chrome.
- **Data:** the old app ran at `socdocs.fhsucyber.com` and real student diagrams exist in `media/`. If any old cohort data must survive (likely **not** — clean start per semester is the norm), write a **one-shot import script**: old `DocPage` markdown → a single BlockNote paragraph-import per doc; old `Diagram` PNGs → `Attachment`. Old grading identifies students by stock Django `User` FK, so map by email into the new custom `User`. **Recommendation: start clean**; keep the import script as a scope valve only.
- **Do not migrate:** settings, compose, media wiring, secrets, the `moderation`/`policies` apps, any template or inline JS, the duplicate Team model, Discord config.

**Order of the rewrite** = §9.

---

## 9. Phased Build Plan

Each wave ends usable and is built with `/plan → /ship → verify`. Tests + CI from Wave 0.

### Wave 0 — Skeleton & identity (foundation)
Django 6 project, custom `User` + roles, typed settings (fail-closed), Postgres, docker-compose on `jumpbox-01` behind nginx, CI running tests. Local login, class-code-gated signup, team create/join, profile. **Exit:** a student can log in; an instructor exists.

### Wave 1 — Documentation MVP + dashboard shell (the "usable MVP")
BlockNote island via django-vite, inline screenshots, `DocRevision` autosave/history, tags, team→class publish. Dashboard shell with launchpad link cards driven by `lab.yaml` + roster (VM consoles, Wazuh link, guides). **Exit:** *a student can log in, see a dashboard, and write a documented runbook with screenshots* — the headline MVP.

### Wave 2 — Comms + AI assist
Announcements (read receipts), doc-anchored threaded comments, `ActivityEvent` logging wired into edits/comments/logins. AI-assist pane proxying Ollama with context injection + logging. **Exit:** Discord's comms role is replaced in-app; participation signals start accumulating.

### Wave 3 — Admin control plane: Proxmox + scenarios
Pool-scoped Proxmox token (in `bootstrap-host.sh`), allowlisted VM verbs with per-VM buttons + audit, live power/agent/alert status tiles. Semaphore integration: scenario start/stop/reset buttons → Ansible, streamed logs, `ScenarioRun` history. Roster CSV import, enroll-code rotation, unified review queue, in-app rubric builder. **Exit:** instructor runs and resets scenarios and controls VMs from the browser.

### Wave 4 — Auto-grading & participation
Wazuh SCA custom policies (per-cohort agent group) + syscollector polling; `verify_*` Ansible playbooks via `ansible-runner`; rubric-as-code aggregation into `Evidence`/`CriterionScore` with the math-validation fixes; participation rollup view; Canvas CSV export; per-student lab AD provisioning. **Exit:** grades and participation are computed from evidence, not Discord.

### Wave 5 — Differentiators & polish (v1→later)
Custom SOC blocks, Excalidraw + Mermaid, doc templates, revision diff/restore, live scenario scoring, then optional Hocuspocus co-editing / Pulse / draw.io as pull-based scope valves.

**Scope valve:** if Wave 1's editor overruns, **Docmost** (self-hosted Notion-style wiki with built-in Excalidraw/Mermaid, OIDC, API) behind portal SSO is the documented plan-B — but building in-app is ~2–3 weeks of Claude-assisted work and owns the grading integration Docmost's API can't.

---

## 10. Risks & Open Questions

**Risks**
1. **BlockNote is pre-1.0, monthly minors.** Pin versions, budget occasional upgrade friction. Treat BlockNote JSON as canonical (its markdown export is intentionally lossy). — *Mitigation:* Docmost plan-B (Wave 1 valve).
2. **Hocuspocus/Yjs is the one architecturally "extra" service.** — *Mitigation:* keep it strictly optional; ship single-user + revisions first (v0.52 decoupled Yjs).
3. **`nlp-01` is on the usually-off isolated plane.** AI assist as a first-class feature needs a routed path through `fw-01` or the LLM mirrored onto the SOC LAN. — *Open, owned by infra.*
4. **Wazuh SCA is interval-fresh, not real-time.** "Live" dashboard status lags the scan interval. — *Mitigation:* show "last checked" timestamps; tune interval per cohort; allow on-demand rescan trigger.
5. **Admin side controls Proxmox** — a compromised admin session is serious. — *Mitigation:* mandatory MFA/passkeys, pool-scoped token (blast radius = "someone rebooted lab VMs"), admin API reachable only from the backend.
6. **Solo maintainer upgrade treadmill.** — *Mitigation:* Django 6 (or 5.2 LTS), boring-mature deps, everything self-hosted/offline, no broker, minimal sidecars.

**Open questions**
1. **Scenario VM contract (§6.2):** who owns the scenario registry format, and is the parallel scenario effort willing to expose idempotent start/stop/reset playbooks + a clean-baseline snapshot per scenario? This platform's admin side depends on that interface.
2. **Cohort data:** clean start each semester (recommended) or must old `socdocs.fhsucyber.com` data survive? Determines whether the import script ships.
3. **Django 6.0 vs 5.2 LTS:** take 6.0 for built-in Tasks (scenario orchestration), or 5.2 LTS for maximum quiet? (Design is identical; leaning **6.0**.)
4. **Real-time co-editing:** is concurrent team doc editing a v1 need or a "later"? Drives whether Hocuspocus lands in Wave 5 or is deferred indefinitely.
5. **Lab AD provisioning scope:** should the platform create per-student AD accounts at all, or only display credentials the scenario/infra layer creates? Confirms the direction of the portal→lab boundary.
6. **Wazuh SSO:** leave students on Wazuh's internal users with credentials on the dashboard (recommended v1), or invest in OIDC/SAML later once Pocket ID exists?

---

*Full document also written to `/tmp/socboard-proposal.md`.*
