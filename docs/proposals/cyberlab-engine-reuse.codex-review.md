> Cross-model review by **codex (gpt-5.5)**, 2026-07-23 — second opinion on `cyberlab-engine-reuse.md`.

## Review

### Biggest Risks / Wrong Calls

1. **The proposal overstates “porting” as low-risk reuse.**  
   The valuable parts are not just fields and formulas; they encode assumptions about attempts, timing, evidence ownership, detector authorship, and course model. Re-expressing those in Django is product design work, not mechanical translation.

2. **Gamification is being pulled in too early.**  
   Badge/streak/leaderboard logic may be technically clean, but it adds behavioral complexity before the core grading loop is proven. For a solo-instructor SOC lab, dashboard polish should not outrank durable submissions, rubric adjudication, evidence provenance, and Canvas export.

3. **The CheckResult seam is promising but underspecified.**  
   It names the envelope, but not the trust model, idempotency model, deduplication key, retry behavior, partial failure semantics, or who is allowed to write evidence. Without that, it becomes a JSON junk drawer.

4. **The “manual first, auto later” story is correct, but the model still smells auto-grader-shaped.**  
   If this is primarily SOC analyst training, the central artifact is the student’s reasoning. Wazuh hits are supporting evidence, not grades. The data model should make that hard to confuse.

5. **Licensing is treated too casually.**  
   “Same author” does not remove Apache-2.0 obligations once code/content moves into a public repo. Attribution, NOTICE preservation, modified-file notices, and provenance records need to be explicit from the first copied artifact.

### Port vs Fork

The **port-not-fork decision is directionally correct**.

A fork would inherit the wrong lifecycle abstraction: pods, VLAN allocation, Suricata-centric detection, in-VM agents, JWT auth, Go services, Next.js, and a second operational surface. For this lab, that is almost certainly worse than a Django-native rebuild.

But the proposal risks **underestimating porting cost**. The reusable value is not “copy code, save time.” It is “avoid first-draft schema mistakes.” Badge logic, grading math, evidence models, scenario definitions, and dashboards all need semantic review before they land. Budget this as selective reimplementation with tests, not as code reuse.

The one possible value left on the table is **running cyberlab temporarily as a reference oracle** during porting: use it to compare expected scoring outputs from known fixtures. Do not run it in production, but consider keeping fixture-level parity tests against extracted examples.

### Missing / Underspecified

The **CheckResult contract** needs a real spec:

- Stable primary key: probably `(run_id, check_id, source, target)` plus collector attempt/version.
- Idempotency and dedup behavior.
- Evidence retention limits and redaction rules.
- Trust boundary: which process can write results, with what credential.
- Timestamp semantics: event time vs collected time vs ingested time.
- Error states: collector failure, Wazuh unavailable, stale index, rule missing, target unreachable.
- Mapping from `CheckResult` to `Evidence` and from `Evidence` to `CriterionScore`.
- Whether machine evidence can ever change score automatically, or only recommend.

The **grading seam** needs sharper language:

- Analyst course: Wazuh detections prove scenario liveness and support the instructor’s review.
- Detection-engineering course: Wazuh detections may grade student-authored rule coverage.
- These should be separate `grading_mode` values, not tribal knowledge.

The **license plan** needs to be operationalized:

- Add `NOTICE` / `THIRD_PARTY_NOTICES` before copying anything.
- Preserve Apache headers where present.
- Add modified-source notes to copied markdown/YAML/code-derived files.
- Track copied vs ported assets in a small attribution table.
- Avoid “verbatim” language for prompts unless headers and provenance are clean.

Also missing:

- A migration strategy from `scenarios.yml` to database records.
- A test plan for scoring math and evidence ingestion.
- Wazuh Indexer query examples and failure handling.
- Security model for Proxmox/noVNC links.
- Explicit decision on whether badges are enabled in MVP or deferred.

### Verdict

Approve the strategic direction: **Django socboard as the product, cyberlab-engine as a reference and parts donor, no live Go/Next stack.**

Do not approve the proposal as build-ready. It is too optimistic about porting cost and too loose around the evidence/grading boundary.

### Top 3 Changes Before Building

1. **Write a formal `CheckResult` and `Evidence` spec** with idempotency, trust, lifecycle, failure states, and exact Django model mappings.

2. **Declare the course grading mode explicitly**: analyst-first/manual-adjudicated, with Wazuh evidence supporting but not determining grades. Keep detection-engineering scoring as a later optional mode.

3. **Create the attribution/licensing file first**, then copy or port assets through that process. Treat provenance as part of the implementation, not cleanup.
## Review

### Biggest Risks / Wrong Calls

1. **The proposal overstates “porting” as low-risk reuse.**  
   The valuable parts are not just fields and formulas; they encode assumptions about attempts, timing, evidence ownership, detector authorship, and course model. Re-expressing those in Django is product design work, not mechanical translation.

2. **Gamification is being pulled in too early.**  
   Badge/streak/leaderboard logic may be technically clean, but it adds behavioral complexity before the core grading loop is proven. For a solo-instructor SOC lab, dashboard polish should not outrank durable submissions, rubric adjudication, evidence provenance, and Canvas export.

3. **The CheckResult seam is promising but underspecified.**  
   It names the envelope, but not the trust model, idempotency model, deduplication key, retry behavior, partial failure semantics, or who is allowed to write evidence. Without that, it becomes a JSON junk drawer.

4. **The “manual first, auto later” story is correct, but the model still smells auto-grader-shaped.**  
   If this is primarily SOC analyst training, the central artifact is the student’s reasoning. Wazuh hits are supporting evidence, not grades. The data model should make that hard to confuse.

5. **Licensing is treated too casually.**  
   “Same author” does not remove Apache-2.0 obligations once code/content moves into a public repo. Attribution, NOTICE preservation, modified-file notices, and provenance records need to be explicit from the first copied artifact.

### Port vs Fork

The **port-not-fork decision is directionally correct**.

A fork would inherit the wrong lifecycle abstraction: pods, VLAN allocation, Suricata-centric detection, in-VM agents, JWT auth, Go services, Next.js, and a second operational surface. For this lab, that is almost certainly worse than a Django-native rebuild.

But the proposal risks **underestimating porting cost**. The reusable value is not “copy code, save time.” It is “avoid first-draft schema mistakes.” Badge logic, grading math, evidence models, scenario definitions, and dashboards all need semantic review before they land. Budget this as selective reimplementation with tests, not as code reuse.

The one possible value left on the table is **running cyberlab temporarily as a reference oracle** during porting: use it to compare expected scoring outputs from known fixtures. Do not run it in production, but consider keeping fixture-level parity tests against extracted examples.

### Missing / Underspecified

The **CheckResult contract** needs a real spec:

- Stable primary key: probably `(run_id, check_id, source, target)` plus collector attempt/version.
- Idempotency and dedup behavior.
- Evidence retention limits and redaction rules.
- Trust boundary: which process can write results, with what credential.
- Timestamp semantics: event time vs collected time vs ingested time.
- Error states: collector failure, Wazuh unavailable, stale index, rule missing, target unreachable.
- Mapping from `CheckResult` to `Evidence` and from `Evidence` to `CriterionScore`.
- Whether machine evidence can ever change score automatically, or only recommend.

The **grading seam** needs sharper language:

- Analyst course: Wazuh detections prove scenario liveness and support the instructor’s review.
- Detection-engineering course: Wazuh detections may grade student-authored rule coverage.
- These should be separate `grading_mode` values, not tribal knowledge.

The **license plan** needs to be operationalized:

- Add `NOTICE` / `THIRD_PARTY_NOTICES` before copying anything.
- Preserve Apache headers where present.
- Add modified-source notes to copied markdown/YAML/code-derived files.
- Track copied vs ported assets in a small attribution table.
- Avoid “verbatim” language for prompts unless headers and provenance are clean.

Also missing:

- A migration strategy from `scenarios.yml` to database records.
- A test plan for scoring math and evidence ingestion.
- Wazuh Indexer query examples and failure handling.
- Security model for Proxmox/noVNC links.
- Explicit decision on whether badges are enabled in MVP or deferred.

### Verdict

Approve the strategic direction: **Django socboard as the product, cyberlab-engine as a reference and parts donor, no live Go/Next stack.**

Do not approve the proposal as build-ready. It is too optimistic about porting cost and too loose around the evidence/grading boundary.

### Top 3 Changes Before Building

1. **Write a formal `CheckResult` and `Evidence` spec** with idempotency, trust, lifecycle, failure states, and exact Django model mappings.

2. **Declare the course grading mode explicitly**: analyst-first/manual-adjudicated, with Wazuh evidence supporting but not determining grades. Keep detection-engineering scoring as a later optional mode.

3. **Create the attribution/licensing file first**, then copy or port assets through that process. Treat provenance as part of the implementation, not cleanup.
