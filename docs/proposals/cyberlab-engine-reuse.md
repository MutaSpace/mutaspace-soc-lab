# Reusing CyberLab Engine in the MutaSpace Student Platform — Architecture Proposal

**Author:** Lead architect
**Date:** 2026-07-23
**Status:** Proposal for approval — precedes any `/plan`
**Inputs reconciled:** `docs/proposals/socboard-portal.md` (+ codex review), `docs/proposals/scenario-generation-vm.md` (+ codex review), and a five-subsystem source read of `/home/profz/projects/cyberlab-engine` (Apache-2.0).

---

## 1. Bottom line up front

**Keep the Django `socboard` rewrite as the platform. Treat `cyberlab-engine` as an Apache-2.0 parts donor — port its schemas, its scoring algorithms, its tutor prompts, and one small console pattern — and run none of its Go/Next.js services.** A fork or a hybrid (Go grading backend behind a thin Django portal) both force a solo instructor to operate a second web stack, a second auth system, and a second Postgres schema whose central abstraction — the ephemeral per‑student "pod" with no snapshot support — is the *opposite* of the mutaspace one‑persistent‑lab, `qm rollback` design. That is a rewrite wearing a fork's clothes, and it is exactly the "maintenance product, not a course tool" the socboard codex review warned against.

This **revises the socboard proposal in three concrete ways** rather than replacing it: (1) it supplies a proven, battle‑tested field set for socboard's `Milestone → Criterion → Submission → CriterionScore → Evidence` rubric (§4.3 of socboard) — cyberlab already shipped the fields socboard would discover the hard way: `verify_attempts`, `evidence` JSON, `hint_penalty`, `paused_seconds`, `is_bonus/is_hidden`, and a manual‑adjustment audit trail; (2) it hands the scenario‑runner a **more mature version of its own `scenarios.yml`** — cyberlab's `ScenarioDefinition` is `scenarios.yml` at the next maturity level, so the two threads merge instead of competing; and (3) it adds a **gamification layer** (points, streaks, badges, leaderboard) that socboard did not scope, ported clean because it is DB‑only. Everything reused is language‑independent; nothing reused requires the Go engine to be running.

---

## 2. What CyberLab Engine already gives us

Maturity = how real/complete the code is (verified by source read, not README — the README overpromises). Reuse value = for *this* mutaspace build under the two approved proposals.

| Capability | In cyberlab today | Stack | Maturity | Reuse value for mutaspace |
|---|---|---|---|---|
| **Student dashboard** | `frontend/app/student/page.tsx` (960 ln) bento stats bar (points/streak/badges/progress), streak‑at‑risk banner, "continue where you left off", badge showcase; `components/student/Leaderboard.tsx` (self‑contained) | Next.js 15 / React 19 / Tailwind | Working, but 500–1500‑ln monolith pages; badge icon map duplicated in 3 files | **MEDIUM** — crib the information architecture + Tailwind theme into Django templates; discard React state |
| **Auto‑grading / verification** | `internal/services/grading.go` (`GradeScenario`, Canvas CSV export), `scenario.go` (`HandleAlert`/`RecordDetection`), `checkpoint_poller.go`, `exam_expiration_poller.go`; models in `internal/models/{exam,lab,scenario}.go` | Go / GORM / Postgres JSONB | Real, working, cohesive — the strongest subsystem | **HIGH** — port the data model + scoring math; leave the transport |
| **Gamification** | `internal/services/badge.go` (711 ln) + `Badge/UserBadge` in `internal/models/scenario.go`; streak + section‑filtered leaderboard; seed catalog in `cmd/cyberlab-bootstrap/cmd/seed.go` | Go / GORM (DB‑only, zero infra coupling) | Clean, self‑contained | **HIGH** — straightest port; the cleanest piece in the whole repo |
| **AI tutor** | `packages/network-defense/tutor/system-prompt.md` (119 ln Socratic) + 13 hint files (`ids-ips`, `siem`, `threat-hunting`, `incident-response`, `suricata-rules`, …); `internal/services/tutor.go` (Ollama + OpenAI chat) | Markdown + Go net/http | Prompt content excellent; Go wiring **incomplete** (the packaged prompt is dead‑wired — `TutorService` never calls `GetTutorSystemPrompt`) | **HIGH for prompts, LOW for code** — lift the markdown verbatim, reimplement ~120 ln of chat in Python |
| **Browser console ("via Guacamole")** | `internal/api/vnc_proxy.go` (237 ln) + `console.go` → Proxmox `vncwebsocket`; `frontend/components/console/VNCConsole.tsx` (@novnc). **Guacamole is declared in compose but has ZERO client code.** | Go WS proxy + noVNC | The noVNC path works; Guacamole is dead deployment weight | **LOW now / MEDIUM later** — the lesson is "skip Guacamole." socboard uses Proxmox noVNC deep‑links |
| **Proxmox integration** | `pkg/proxmox/{client,provider,guest_agent}.go` — REST + QEMU guest agent, token auth, task polling. **No snapshot/rollback anywhere** (reset = destroy + re‑clone) | Go REST client | Solid, but pod‑lifecycle shaped and snapshot‑less | **LOW** — mutaspace uses `proxmoxer` + `qm rollback`, which is strictly better here |
| **Course packages** | `internal/models/package.go` contract + `package_loader.go`/`package_validator.go`; `packages/network-defense/` (manifest + labs + scenarios + exams) | Go + YAML | Real, validated, a good convention | **MEDIUM** — reuse the YAML *shape* as scenarios.yml schema, port loader/validator idea to Python |

---

## 3. The stack decision — Django socboard, cyberlab as donor

**Decision: option (b). Build socboard as a single Django 5.2 LTS app (not Django 6 — background jobs are not where a teaching lab wants novelty, per the socboard codex review). Mine cyberlab as an Apache‑2.0 parts donor. Do not fork it; do not run its Go backend or Next.js SPA; do not inherit its pod/VLAN orchestrator, its in‑VM agent fleet, Guacamole, Redis, or `docker-compose.prod.yml`.**

Five reasons, decisive for a solo maintainer using Claude Code:

1. **The lifecycle mismatch is structural, not cosmetic.** cyberlab's spine is ephemeral per‑student pods: clone‑per‑role → DB‑allocated VLAN → destroy; `ResetPod` (in `internal/services/orchestrator.go`) is a full re‑clone, and there is **no snapshot/rollback anywhere in `pkg/proxmox`**. A `PodID` FK threads through `ExamAttempt`, `LabProgress`, `ScenarioResult`, console, and agent paths. mutaspace is the inverse: one persistent shared lab, fixed VMIDs in `lab.yaml`, reset by `qm rollback`. Forking means surgically excising the framework's central abstraction from every subsystem and grafting on a reset model it never had.

2. **The detection source does not transfer.** cyberlab grades on Suricata SIDs pulled from `eve.json` by an in‑VM Go agent WebSocket fleet baked into every template. mutaspace grades on **Wazuh rule IDs via the Wazuh Indexer**, with Wazuh agents + Ansible already deployed. The verification *execution* layer (agent, collectors, transport) is a full rewrite regardless of fork‑vs‑port — only the *schema* and the *scoring math* survive. So even a fork buys you nothing on the hardest part.

3. **Solo‑maintainer economics + both codex reviews.** cyberlab is ~35k lines of Go/Fiber/GORM plus a Next.js 15/React 19 SPA, and its README overpromises: Guacamole is declared in compose but never integrated (zero client code), `docker-compose.prod.yml` deploys a Python/FastAPI backend deleted in the Go rewrite, and Redis is in every compose file but used by nothing. Options (a) and (c) both make the instructor run and maintain a second full web stack and a second auth system (its HS256 JWT vs Django sessions) — the reverse of socboard's deliberate "one Django deployment, boring deps, no broker" call. The portal is 90% forms/tables/dashboards/admin/grading: Django's home turf, and where Claude‑Code‑assisted solo dev is fastest.

4. **The instructor's own constraint.** "Reuse code where it makes sense; do NOT copy the whole project." Option (a) violates that outright. Option (c) keeps the Go engine alive as a live grading service whose pod assumptions *and* Suricata detectors both must be reworked anyway — you pay a fork's maintenance cost for logic you must rewrite. Only (b) honors the constraint.

5. **What actually transfers is portable, not runnable.** The high‑value reuse is YAML contracts, a data‑model field taxonomy, two scoring formulas, ~13 markdown prompt files, a badge/streak/leaderboard service, and one ~400‑line VNC‑proxy pattern. All language‑independent, all Apache‑2.0, same author (attribution is a formality). None of it needs the Go engine running.

**Rejected explicitly:** (a) fork/extend cyberlab — violates "don't copy the whole project," inherits pod/VLAN/snapshot‑less lifecycle, doubles the maintenance surface. (c) hybrid Go‑grading‑backend — keeps a second stack and second DB alive while *still* requiring the Suricata→Wazuh and pod→persistent‑lab rewrites; worst of both.

---

## 4. Concrete reuse inventory

Legend: **REUSE** = copy near‑verbatim (markup / prompt / YAML). **PORT** = re‑express Go→Python/Django, keeping fields & algorithm. **REBUILD** = new code, cyberlab as design reference only. **LEAVE** = do not touch.

### 4.1 Student dashboard

| Piece (cyberlab path) | Verdict | What to do |
|---|---|---|
| `frontend/tailwind.config.ts` + `frontend/app/providers.tsx` | **REUSE** | Adopt the gunmetal/accent palette + light/dark `ThemeProvider` as socboard's visual identity. Tailwind classes are framework‑agnostic. |
| `frontend/app/student/page.tsx` (bento stats bar, streak‑at‑risk banner, "continue where you left off", tutorial modal) | **REBUILD** in Django templates, **REUSE** the markup | Port the Tailwind markup ~1:1 into a Django template; throw away all React state / TanStack / JWT‑in‑localStorage. This is socboard Wave 1's dashboard shell (socboard §5, "Dashboard shell"). |
| `frontend/components/student/Leaderboard.tsx` | **PORT** | Self‑contained (rank medals, section filter, your‑rank‑when‑outside‑top‑N, badge chips). Re‑render as a Django template; keep the entry JSON shape `{rank, points, current_streak, recent_badges[]}`. Backing logic is the ported `badge.go GetLeaderboard`. |
| `frontend/components/common/Toast.tsx` (has a dedicated `showBadge` variant) | **REUSE** as UX spec | Copy the badge‑award celebration cue; implement with Alpine + a small toast. |
| `frontend/hooks/usePodWebSocket.ts` | **REUSE the CONTRACT only** | Take its typed message union (`checkpoint / scenario / score / lab_task / pod_status`) as the JSON envelope for one live "verify result" push. Implement as a single HTMX SSE / Alpine poll, **not** a reconnecting React WS. Re‑key from `pod_id` → `student+scenario`. |
| `frontend/app/student/labs/[slug]/page.tsx` | **REUSE** as interaction spec | Defines the exact loop mutaspace wants — *task list → Verify → server check → points + badge toast → auto‑advance*. Copy the `TaskVerificationResult {passed, points_earned, awarded_badges[], evidence}` shape into socboard's verify endpoint. **LEAVE** the embedded VM console + pod‑reset button. |

### 4.2 Gamification (the cleanest, earliest, safest reuse — DB‑only)

| Piece | Verdict | What to do |
|---|---|---|
| `internal/models/scenario.go` → `Badge` + `UserBadge` (slug, name, icon, color, category, `requirements` JSONB, points, rarity, is_hidden; `UserBadge.earned_at`, context) and `User` counters `total_points / current_streak / longest_streak / last_activity_at` (`internal/models/user.go`) | **PORT** to Django ORM | Zero infra coupling. Add these models to socboard. |
| `internal/services/badge.go` (711 ln) | **PORT** to a Django `BadgeService` | Keep the requirement vocabulary **exactly**: `type ∈ {lab_complete, exam_pass, points_total, streak_days, scenario_detection}` with params `count/min_score/points/days/min_rate`. Keep `CheckAndAwardBadges`, fractional `GetBadgeProgress`, `UpdateStreak`/`GetStreakStatus` (StreakAtRisk = last activity yesterday, not today), `GetLeaderboard(section, out‑of‑top‑N)`. |
| `cmd/cyberlab-bootstrap/cmd/seed.go` (seed badge catalog) | **REUSE** as content | Starter badge set; translate to a Django data migration / fixture. |

**Hard rule (honors the socboard codex review):** gamification points/badges stay **motivational and decoupled from the graded rubric**. The review flagged computed participation as "noisy and politically fragile." Points motivate; the `Milestone/Criterion` rubric grades. Wire `CheckAndAwardBadges` off socboard's planned `ActivityEvent` table and submit/scenario‑complete signals — never into `CriterionScore`.

### 4.3 Auto‑grading of scenarios

| Piece | Verdict | What to do |
|---|---|---|
| `internal/models/{exam,lab,scenario}.go` — `Exam/Checkpoint/ExamAttempt/CheckpointProgress`, `Lab/LabTask/LabProgress`, `Scenario/ScenarioResult` | **PORT** to Django models | This is the rubric backbone socboard §4.3 already sketched, upgraded. Keep the battle‑chosen fields socboard would miss: `verification_type` (incl. `manual`), `verification_config` JSON, `target_vm`, `verify_attempts`, `evidence` JSONB, `is_bonus/is_hidden`, `hint_penalty`, `paused_seconds`, the attempt status machine (`not_started/in_progress/paused/submitted/graded/expired`), and the manual‑adjustment audit (`adjusted_by/note/at`). **Adapt:** rename `Checkpoint → Criterion` to match socboard; add `verification_type` values `wazuh_sca / wazuh_indexer / ansible`; drop or reinterpret `PodID` as the student's fixed learner VM. |
| `internal/models/package.go` `ScenarioDefinition` / `ExpectedDetection` (`slug`, `difficulty`, `detection_window_seconds`, `expected_detections[{sid,name,points,required}]`, `passing_threshold`, `hints`, `prerequisites`) + the 10 worked `packages/network-defense/scenarios/*/scenario.yaml` | **REUSE** as schema template for `ansible/scenarios.yml` | Merge field‑for‑field into the scenario‑runner's `scenarios.yml`. **Swap `sid` (int) → Wazuh `rule_id`; add a `fields{}` map and `max_latency_seconds`** — which is precisely the scenario codex's demand for "exact log source, rule, expected fields, expected latency." Note the overlap is uncanny: cyberlab ships `scenarios/beginner/ssh-bruteforce/scenario.yaml` and the scenario‑VM proposal names `ssh-bruteforce` as its Wave 1 (`fires: ["wazuh:5712","wazuh:5720"]`). **LEAVE** `replay:{pcap_file,interface,speed}` — mutaspace uses ART/kali one‑liners + offline `suricata -r`. |
| `internal/services/grading.go` `GradeScenario` (`grading.go:268` `pointsEarned = int(scenario.Points × detectionRate)`; `:292` `− HintPenalty`; `:332` pass if `rate ≥ threshold`) and `scenario.go:305` `DetectionRate = DetectionCount / ExpectedCount` | **PORT the math** (~150 ln Python), **LEAVE the plumbing** | Reimplement inside the scenario‑runner harness. The `detected/expected` sets become **Wazuh `rule.id` hits, not Suricata SIDs**; "expected" comes from `scenarios.yml`'s `fires:`. |
| `internal/services/scenario.go` `HandleAlert`/`RecordDetection` + `scenario_poller.go` (dedup by rule within `detection_window_seconds`, auto‑complete past window, then grade) | **PORT the pattern** | Reimplement as a Python poller that queries the Wazuh Indexer (`wazuh-alerts-4.x-*`) for `rule.id in [expected] AND agent.name in scope AND @timestamp ≥ run_start`. This *is* the scenario codex's mandated `verify` step. **LEAVE** the WebSocket agent‑fleet ingest (`internal/agent/`, `agent_manager.go`, `hybrid_comm.go`). |
| `internal/services/{checkpoint_poller,exam_expiration_poller}.go` | **REBUILD** as reference | Small idempotent, race‑guarded poll loops (auto‑verify open attempts; auto‑submit expired timed attempts). Model a Django management command / cron on them. |
| `internal/services/grading.go` `ExportStudentGradesCSV` / `ExportCanvasCSV` (Canvas columns, 30/70 lab/exam weighting) | **REUSE** the column choices | socboard §7.5 already commits to Canvas CSV — copy the exact columns, reimplement in Python. **LEAVE** `lti_grades.go` (both proposals skip LTI). |
| `internal/agent/collectors.go` (6 collectors: file_exists / file_contains / service_active / command_exit / suricata / replay) + `protocol.go` | **REBUILD** as an Ansible verify‑playbook, do **not** deploy the daemon | Re‑express the `verification_config` vocabulary as an `ansible-runner`/`goss` verify‑playbook (socboard §7.2 already plans this). The lab already runs Ansible; don't add an always‑on Go agent. |

**Sequence (obeys both codex reviews):** ship `verification_type = "manual"` (auto‑pass) on **day one** — it is a first‑class value in cyberlab's schema, so adopting the shape now does not force auto‑grading forward. Switch machine collectors on **one criterion at a time** after the rubric and dispute model are proven.

### 4.4 AI‑assist (wire LAST, per both reviews)

| Piece | Verdict | What to do |
|---|---|---|
| `packages/network-defense/tutor/system-prompt.md` + `tutor/hints/*.md` (13 files: `ids-ips`, `siem`, `threat-hunting`, `incident-response`, `suricata-rules`, `malware`, …) | **REUSE verbatim** | The single best artifact in the repo. Already matches scenario‑VM §6's "SOC mentor, never reveal, only nudge." Copy into the mutaspace `ai/` layer; feed per‑scenario `objective` + `answer_key` as context with the hard no‑leak constraint. |
| `internal/services/tutor.go` `getSystemPrompt` / `callOllama` structs | **REBUILD thin** | Reimplement ~120 ln as a `django-ninja` route proxying `nlp-01:11434` (socboard §6.4). |
| `internal/services/tutor.go` `isDangerousCommand` / `dangerousCommands` denylist | **REUSE** as safety reference only | Keep the denylist **only if** any command surfacing is ever added. **DROP** the click‑to‑run‑in‑VM executor entirely (`internal/api/command.go` + agent `injectKeys`) — both reviews: the copilot nudges, never executes. |

### 4.5 Leave entirely (do not mine)

`internal/services/{orchestrator,pod}.go` + `VLANAllocation` + `ResetPod` (pod lifecycle — mutaspace uses snapshot rollback); the whole `internal/agent/` in‑VM Go fleet; **Guacamole** (dead in cyberlab too — compose + two dead model columns, zero client code); `internal/api/lti*.go`; multi‑tenant `Tenant/Organization`; `docker-compose.prod.yml` (deploys a deleted Python backend); Redis (declared, never used); the Next.js runtime; and all `tmpclaude-*-cwd`, `dist;C`, `packages;C`, and prebuilt `cyberlab-api-*` binaries (build accidents — treat only `cmd/`, `internal/`, `pkg/`, `frontend/`, `packages/`, `docs/`, `docker-compose.go.yml` as authoritative).

**Console note:** for MVP use Proxmox's own noVNC deep‑link (socboard §5 already chose this). *Only if* an authenticated in‑portal console is later wanted, port `internal/api/vnc_proxy.go` + `console.go` (~400 ln) to Django Channels, replacing the pod lookup with a static `vm_role → VMID` map from `lab.yaml`. Note the two security shortcuts to fix on the way in: JWT in the WebSocket query string (logged by proxies) and Proxmox `InsecureSkipVerify` TLS.

---

## 5. Integration with the mutaspace lab — the CheckResult seam

The whole integration reduces to **one contract**: a normalized `CheckResult` evidence envelope that every collector emits and the Django grader ingests. It is modeled on cyberlab's `CheckpointProgress.Evidence` + `ScenarioResult`, and it is what lets "grading be driven by what students detect in Wazuh."

```jsonc
// CheckResult — lives in the repo next to scenarios.yml; the one seam.
{
  "scenario_id": "ssh-bruteforce",
  "run_id": "2026-07-23T14:02:11Z-a1b2",
  "check_id": "wazuh:5712",                    // rule id | sca-check-id | ansible-task
  "source": "wazuh_indexer",                   // wazuh_indexer | wazuh_sca | ansible | manual
  "target": "ubuntu-app-01",
  "status": "pass",                            // pass | fail | error
  "detected": true,
  "latency_seconds": 37,
  "expected_within_seconds": 120,
  "evidence": { "hits": 9, "srcip": "10.10.20.10", "query": "...", "sample_doc": {...} },
  "collected_at": "2026-07-23T14:02:48Z"
}
```

`scenarios.yml`'s `fires: ["wazuh:5712","wazuh:5720"]` is promoted to cyberlab's richer `expected_detections`:

```yaml
expected_detections:
  - rule_id: 5712
    name: "sshd multiple failed logins"
    points: 20
    required: true
    fields:  { agent.name: ubuntu-app-01, data.srcip: 10.10.20.10 }
    max_latency_seconds: 120
```

**How the reused grading engine consumes the scenario‑runner's Wazuh verify + Ansible checks (the two‑layer model):**

- **Layer 1 — scenario liveness (the runner's `verify` step).** A Python `wazuh_verify` collector queries the Wazuh Indexer for `rule.id ∈ expected` scoped to the run window, applying cyberlab's `HandleAlert` elapsed‑vs‑`detection_window` logic (ported from `scenario.go:305`+). It emits `CheckResult` rows and *gates the scenario before students touch it* — this is the codex‑mandated `task scenario:verify -- ssh-bruteforce → pass/fail`. cyberlab's per‑detection scorer gives a liveness score.
- **Layer 2 — student grading (deferred; additive because of the seam).** Ship socboard's rubric with `Evidence.source = manual` first: the instructor scores the submitted doc revision against the `answer_key`. Machine evidence then arrives through the **same** `CheckResult` envelope from two more collectors added one criterion at a time — **Wazuh SCA/syscollector** (socboard §7.1) and **Ansible/goss verify‑playbooks** (socboard §7.2) — each mapping cyberlab's detector taxonomy (file/service/command → SCA check / goss assert / ansible task). The Django grader treats every `CheckResult` as an auto‑populated `Evidence` row on a `CriterionScore`; the instructor always adjudicates.

**The one trap to force a decision on:** cyberlab's `detected/expected` scoring assumes *the student authored the detection* (a detection‑engineering course — grade = did their rules catch the replay). The mutaspace `scenarios.yml` + `answer_key` + "SOC mentor" describe a **SOC‑analyst / diagnosis** course: the detection content is instructor‑authored and *always* fires, and the student's graded artifact is their *written findings*. So the attacker alert (`rule 5712`) verifies **scenario liveness**, not student competency — a naive `detected/expected` grade would give every student full marks. The seam supports both course models unchanged; the scoping differs (analyst = grade the doc, evidence auto‑populates the rubric; detection‑engineering = scope the Wazuh query to the student's own `rule.id` band). **This is the single decision to make before wiring any auto‑grade.**

**Evidence lifecycle (solves what both codex reviews raised).** `CheckResult` rows persist to socboard's Postgres on `jumpbox-01` — *outside* the `vmbr1/vmbr2` snapshot plane. Order of operations: **run → verify → write evidence → THEN roll back targets.** `wazuh-01` stays *out* of the rollback set during investigation (scenario codex #2). The durable grade record cannot be erased by a `qm rollback` — the gap cyberlab never had to engineer, because its grading DB was always separate from the ephemeral pod, and the same property protects us here.

**Wazuh in place of Security Onion.** Only the schema and math transfer; the detector plumbing is a full rewrite. cyberlab's `ExpectedSIDs`/`AlertCollector` are Suricata `signature_id` from `eve.json`; mutaspace's are Wazuh `rule.id` from the Indexer API. Budget the Wazuh Indexer harness as **net‑new work owned by the scenario‑runner effort** — cyberlab saves the design iteration, not the implementation.

**Guacamole / console.** cyberlab's own lesson is decisive: it *declared* Guacamole and never wrote a line of client code, running its noVNC/WS proxy instead. mutaspace should skip Guacamole entirely and use Proxmox noVNC deep‑links (socboard §6.x), keeping `vnc_proxy.go` as a reference for a later Django‑Channels console if ever wanted.

**Ollama AI‑assist.** The local Ollama on `nlp-01` *replaces* cyberlab's LLM provider layer wholesale; only the prompt content is fed forward. cyberlab's `tutor.go` is a competent multi‑provider chat wrapper but is Go, and its packaged Socratic prompt is dead‑wired anyway — so "reuse the tutor" means copy the markdown and reimplement the ~120 ln proxy in `django-ninja`, routed so `nlp-01` (on the usually‑off `vmbr2`) is reached via `jumpbox-01`, never by opening `vmbr1→vmbr2` broadly (socboard §6.4 open item).

---

## 6. Reconciling the three research threads into one buildable platform

The three documents are one system at three altitudes, and cyberlab is the connective tissue that makes them fit:

- **socboard** owns the *product*: the Django app, identity, docs workspace, dashboard, rubric, instructor plane, Canvas export. Its codex review already cut it to "portal + docs + submissions + manual review first; dangerous infra behind a narrow boundary; defer auto‑grading." cyberlab does not change that scope — it **furnishes the interior**: the dashboard IA + theme, the gamification layer socboard didn't scope, and the exact rubric field set socboard's §4.3 was reaching for.
- **scenario‑VM** owns the *execution*: the Ansible `75-scenario-run.yml`, `scenarios.yml`, snapshot‑bracketed reset, Wazuh Indexer verify. Its codex review demanded "a scenario contract + verification harness first, with per‑scenario run/verify/cleanup and pass/fail." cyberlab's `ScenarioDefinition` + `GradeScenario` + detection‑window poller **is that contract and harness, one maturity level up** — adopt its fields (swap SID→rule_id), port its math, reimplement its poller against Wazuh.
- **this thread** owns the *seam*: the `CheckResult` envelope and the ported grading/badge/scoring models that let scenario‑runner output flow into socboard's gradebook and dashboard without either side taking a dependency on the Go engine.

Concretely, they meet at three files/objects: (1) `ansible/scenarios.yml` gains cyberlab's `expected_detections`/`detection_window`/`passing_threshold`/`hints` fields → consumed by both the scenario‑runner (to `run`/`verify`) and socboard (to define `Criterion` rows and expected evidence); (2) the `CheckResult` envelope emitted by the runner's `wazuh_verify` collector → ingested by socboard's grader as `Evidence`; (3) the ported `BadgeService` + dashboard, fed by socboard's `ActivityEvent` + scenario completions → the student‑facing motivation layer none of the three threads had on its own. One Django deployment on `jumpbox-01`; one Ansible runner; one Wazuh; one Postgres of record outside the snapshot plane.

---

## 7. Licensing & attribution

`cyberlab-engine` is **Apache‑2.0** (`LICENSE` at repo root, verified), authored by the same instructor. mutaspace is a **public** repo, which is fine. Requirements when porting:

- For any file copied substantially verbatim (the tutor `system-prompt.md` + `hints/*.md`, `Leaderboard.tsx` markup, a `scenario.yaml`), retain the Apache‑2.0 header and note modifications, and add a `NOTICE` entry crediting `cyberlab-engine`.
- For ported logic re‑expressed in Python/Django (badge service, grading math, models), a `NOTICE` line and a source‑attribution comment at the top of the module (`# Ported from cyberlab-engine internal/services/badge.go (Apache-2.0)`) is sufficient and honest.
- Add one `THIRD_PARTY_NOTICES` / `ATTRIBUTION.md` in the mutaspace repo listing cyberlab‑engine (Apache‑2.0) and the assets drawn from it. Same‑author makes this a formality, but the public repo should carry it correctly.
- No secrets or real hostnames travel with any ported file — cyberlab's `.env.example` and compose files are **not** copied (mutaspace §Secrets policy).

---

## 8. Phased build plan (MVP‑first) & top risks

This threads cyberlab's reuse into socboard's existing wave structure without expanding its scope. Each wave ends usable; tests + CI from Wave 0 (`/plan → /ship → verify`).

- **Wave 0 — Skeleton & identity (socboard as written).** Django 5.2 LTS, custom `User` + roles, typed fail‑closed settings, Postgres on `jumpbox-01` behind nginx, CI. **cyberlab reuse:** adopt `tailwind.config.ts` palette. *Exit: a student logs in; an instructor exists.*
- **Wave 1 — Docs MVP + dashboard shell + gamification models.** BlockNote island, `DocRevision` autosave, launchpad link cards from `lab.yaml`. **cyberlab reuse (high‑ratio, safe):** rebuild the student bento dashboard from `app/student/page.tsx` markup; **port `badge.go` + `Badge/UserBadge` + streak/leaderboard** (DB‑only, no infra) and the seed catalog. Points/badges are decorative here — no rubric coupling. *Exit: student sees a themed dashboard with points/streak/badges and writes a documented runbook.*
- **Wave 2 — Comms + AI‑assist prompt (not executor).** Announcements, submission comments, `ActivityEvent` logging (feeds `CheckAndAwardBadges`). **cyberlab reuse:** lift `tutor/system-prompt.md` + `hints/*.md` verbatim into a `django-ninja` Ollama proxy; keep the `isDangerousCommand` denylist, drop the executor. *Exit: comms replaced in‑app; copilot nudges.*
- **Wave 3 — Scenario contract + manual grading.** Merge cyberlab's `ScenarioDefinition` fields into `ansible/scenarios.yml` (SID→rule_id + `fields`/`max_latency_seconds`). **cyberlab reuse:** port `Exam/Checkpoint→Milestone/Criterion`, `Submission`, `CriterionScore`, `Evidence`, `ScenarioResult` models with all battle‑chosen fields; ship `verification_type="manual"`; port `ExportCanvasCSV` columns. Dangerous infra (Proxmox rollback, Semaphore/Ansible run) behind the socboard‑review's narrow audited allowlist boundary — **not** inside the grader. *Exit: instructor grades submissions with a real rubric + Canvas export; scenarios defined.*
- **Wave 4 — Wazuh‑Indexer auto‑grading (the payoff).** Build the `wazuh_verify` collector + `CheckResult` seam; port `GradeScenario` math and the detection‑window poller against the Wazuh Indexer, one criterion at a time. Add Wazuh SCA + Ansible/goss collectors behind the same envelope. Persist evidence to `jumpbox-01` Postgres before any target rollback; keep `wazuh-01` out of the rollback set. *Exit: scenario detection auto‑populates evidence on the rubric; instructor adjudicates.*
- **Wave 5 — Differentiators.** Live scenario scoring, custom SOC blocks, optional in‑portal noVNC console (port `vnc_proxy.go` only if wanted). Pull‑based scope valves.

**Top risks**

1. **Conflating scenario liveness with student competency.** The attacker always trips the alert; a naive `detected/expected` grade gives everyone full marks. *Mitigation:* decide analyst‑vs‑detection‑engineering course model before Wave 4; the seam supports both, the scoping differs.
2. **Go→Django is a re‑model, not an import.** Every ported schema is re‑expressed in Django ORM; every algorithm reimplemented in Python. *Mitigation:* budget porting time; the value is design‑iteration saved (battle‑chosen fields), not lines saved.
3. **Detector plumbing does not transfer (Suricata SID → Wazuh rule.id).** Only schema + math port; the Wazuh Indexer harness is net‑new. *Mitigation:* own it in the scenario‑runner effort; ship 2 scenarios end‑to‑end (`ssh-bruteforce`, `web-sqli`) before adding more (scenario codex #3).
4. **Evidence lifecycle vs snapshot reset.** Rolling back `wazuh-01` with targets erases the alerts students investigate. *Mitigation:* run→verify→write evidence→then roll back; `wazuh-01` outside the rollback set; durable grade record on `jumpbox-01`.
5. **Wazuh SCA/indexer is interval‑fresh, not real‑time.** A live scenario can read as "failed" if latency budgets are too tight. *Mitigation:* `max_latency_seconds` per detection exceeds scan/index lag; show "last checked"; allow on‑demand re‑verify.
6. **Rule‑ID band collision.** `scenarios.yml` expected rule IDs vs imported Wazuh rule packs vs `local_rules.xml` can make `wazuh-manager` fail to restart mid‑class. *Mitigation:* reserve a lab rule‑ID band; gate on manager health before class (scenario codex).
7. **Scope creep back into the engine.** The moment you want cyberlab's poller/hub/agent "for free," you inherit GORM + pod + Proxmox coupling and a second web stack. *Mitigation:* hold the line at schema+algorithm port + the `CheckResult` envelope; nothing runs but Django, Ansible, Wazuh, Postgres.
8. **Crib patterns, not modules.** cyberlab's pages are 500–1500‑ln monoliths with the badge icon/color map duplicated across three files. *Mitigation:* port the badge map once into a shared Django template tag; don't inherit the duplication.

---

*Recommended home for this document: `docs/proposals/cyberlab-reuse.md` (sibling to the two proposals it reconciles).*
