> Cross-model review by **codex (gpt-5.5)**, 2026-07-23 — a skeptical second opinion on `socboard-portal.md`.

## Review

### 1. Biggest Risks / Wrong Calls

1. **The scope is far too large for a rewrite MVP.**  
   This is not one app rewrite. It is a docs platform, LMS-lite, grading engine, Proxmox control plane, scenario orchestrator, Wazuh integration layer, AI proxy, and activity analytics system. For a solo instructor, that is a maintenance product, not a course tool.

2. **Auto-grading is treated as a feature, but it is really a second curriculum.**  
   Wazuh SCA policies, Ansible verify playbooks, rubric mappings, check freshness, false positives, per-cohort targeting, and grade disputes will require constant care. The proposal underestimates the authoring and debugging workload.

3. **Django 6 is an avoidable bet.**  
   Basing orchestration on a new Django 6 Tasks framework is risky for a self-hosted teaching lab. Use Django 5.2 LTS unless Django 6 Tasks are already proven in this environment. Background jobs are not where you want novelty.

4. **The admin control plane raises the blast radius substantially.**  
   Putting Proxmox rollback, scenario execution, AD provisioning, and grading inside one web app means auth/session bugs become infrastructure bugs. The proposal says MFA and scoped tokens, but it needs a much harder separation between “teaching portal” and “dangerous lab operations.”

5. **BlockNote + custom SOC blocks is a product bet, not a small editor choice.**  
   A rich block editor with images, revisions, comments, custom blocks, Mermaid, Excalidraw, diff/restore, and submit-pinned revisions will dominate Wave 1. This is the highest-risk part of the student-facing MVP.

### 2. Over-Engineered for a Solo Maintainer

- **Custom Notion clone behavior.** A simpler Markdown/ProseMirror editor with attachments and immutable submissions may be enough.
- **Activity-based participation scoring.** Useful, but easy to make both noisy and politically fragile. Start with visible activity timelines, not computed participation grades.
- **Rubric-as-code plus in-app rubric builder.** Pick one. Maintaining both YAML and UI editing creates drift unless carefully designed.
- **Threaded anchored comments with SSE.** Nice, not necessary early. Plain submission comments are enough for MVP.
- **AI assist as first-class participation signal.** This adds privacy, reliability, grading, and network complexity before the core portal exists.
- **Live scenario scoring.** This is a separate scoring engine project. Do not put it in v1 unless the course already depends on it.
- **Docmost plan-B.** If Docmost is credible, seriously consider using it first. If it is not credible, remove it. As written, it is a late escape hatch after the hardest work has already been attempted.

### 3. Missing / Underspecified

- **Threat model.** The app controls lab infrastructure. The proposal needs explicit network placement, admin-only routes, CSRF/session hardening, audit retention, backup/restore, and emergency lockout.
- **Failure modes.** What happens when Wazuh is down, Semaphore is down, Proxmox API fails, a scenario reset half-completes, or evidence collection disagrees with student-visible state?
- **Data retention and privacy.** AI logs, edit histories, activity scoring, screenshots, and grading evidence are sensitive educational records. Define retention, export, deletion, and instructor override policy.
- **Grade dispute workflow.** If automated evidence affects grades, students need to see exactly what was checked, when, against which VM, and how to contest it.
- **Operational backup story.** Postgres, uploaded media, rubric definitions, lab mappings, and scenario/audit history all need tested backup/restore.
- **Permission model details.** “Role enum + row ownership” is directionally right but underspecified for teams, class-visible docs, instructor guides, service accounts, and admin actions.
- **Import/export boundaries.** Canvas CSV is mentioned, but roster import format, user lifecycle, semester reset, archive/export, and reusing the app next term need firmer treatment.

### 4. Bottom-Line Verdict

Good product instincts, but the proposal is trying to build a small LMS, SIEM-backed grading platform, and infrastructure control plane in one pass. The architecture is mostly plausible, but the MVP boundary is not credible for a solo maintainer using Claude Code.

I would approve a much smaller rewrite, not this plan as written.

### Top 3 Changes Before Building

1. **Cut MVP to portal + docs + submissions + basic instructor review.**  
   Local auth, teams, dashboard links, simple editor with attachments, immutable submitted revision, rubric grading, Canvas CSV. Nothing Proxmox-controlling yet.

2. **Move dangerous infrastructure actions behind a separate narrow service or CLI wrapper.**  
   The Django app can request scenario actions, but Proxmox rollback and Ansible execution should have a small audited boundary with hard allowlists and minimal credentials.

3. **Defer auto-grading until manual grading is solid.**  
   First ship `Evidence` as instructor-attached/manual or imported check results. Then add Wazuh/Ansible collectors one criterion at a time after the rubric and dispute model are proven.
tokens used
## Review

### 1. Biggest Risks / Wrong Calls

1. **The scope is far too large for a rewrite MVP.**  
   This is not one app rewrite. It is a docs platform, LMS-lite, grading engine, Proxmox control plane, scenario orchestrator, Wazuh integration layer, AI proxy, and activity analytics system. For a solo instructor, that is a maintenance product, not a course tool.

2. **Auto-grading is treated as a feature, but it is really a second curriculum.**  
   Wazuh SCA policies, Ansible verify playbooks, rubric mappings, check freshness, false positives, per-cohort targeting, and grade disputes will require constant care. The proposal underestimates the authoring and debugging workload.

3. **Django 6 is an avoidable bet.**  
   Basing orchestration on a new Django 6 Tasks framework is risky for a self-hosted teaching lab. Use Django 5.2 LTS unless Django 6 Tasks are already proven in this environment. Background jobs are not where you want novelty.

4. **The admin control plane raises the blast radius substantially.**  
   Putting Proxmox rollback, scenario execution, AD provisioning, and grading inside one web app means auth/session bugs become infrastructure bugs. The proposal says MFA and scoped tokens, but it needs a much harder separation between “teaching portal” and “dangerous lab operations.”

5. **BlockNote + custom SOC blocks is a product bet, not a small editor choice.**  
   A rich block editor with images, revisions, comments, custom blocks, Mermaid, Excalidraw, diff/restore, and submit-pinned revisions will dominate Wave 1. This is the highest-risk part of the student-facing MVP.

### 2. Over-Engineered for a Solo Maintainer

- **Custom Notion clone behavior.** A simpler Markdown/ProseMirror editor with attachments and immutable submissions may be enough.
- **Activity-based participation scoring.** Useful, but easy to make both noisy and politically fragile. Start with visible activity timelines, not computed participation grades.
- **Rubric-as-code plus in-app rubric builder.** Pick one. Maintaining both YAML and UI editing creates drift unless carefully designed.
- **Threaded anchored comments with SSE.** Nice, not necessary early. Plain submission comments are enough for MVP.
- **AI assist as first-class participation signal.** This adds privacy, reliability, grading, and network complexity before the core portal exists.
- **Live scenario scoring.** This is a separate scoring engine project. Do not put it in v1 unless the course already depends on it.
- **Docmost plan-B.** If Docmost is credible, seriously consider using it first. If it is not credible, remove it. As written, it is a late escape hatch after the hardest work has already been attempted.

### 3. Missing / Underspecified

- **Threat model.** The app controls lab infrastructure. The proposal needs explicit network placement, admin-only routes, CSRF/session hardening, audit retention, backup/restore, and emergency lockout.
- **Failure modes.** What happens when Wazuh is down, Semaphore is down, Proxmox API fails, a scenario reset half-completes, or evidence collection disagrees with student-visible state?
- **Data retention and privacy.** AI logs, edit histories, activity scoring, screenshots, and grading evidence are sensitive educational records. Define retention, export, deletion, and instructor override policy.
- **Grade dispute workflow.** If automated evidence affects grades, students need to see exactly what was checked, when, against which VM, and how to contest it.
- **Operational backup story.** Postgres, uploaded media, rubric definitions, lab mappings, and scenario/audit history all need tested backup/restore.
- **Permission model details.** “Role enum + row ownership” is directionally right but underspecified for teams, class-visible docs, instructor guides, service accounts, and admin actions.
- **Import/export boundaries.** Canvas CSV is mentioned, but roster import format, user lifecycle, semester reset, archive/export, and reusing the app next term need firmer treatment.

### 4. Bottom-Line Verdict

Good product instincts, but the proposal is trying to build a small LMS, SIEM-backed grading platform, and infrastructure control plane in one pass. The architecture is mostly plausible, but the MVP boundary is not credible for a solo maintainer using Claude Code.

I would approve a much smaller rewrite, not this plan as written.

### Top 3 Changes Before Building

1. **Cut MVP to portal + docs + submissions + basic instructor review.**  
   Local auth, teams, dashboard links, simple editor with attachments, immutable submitted revision, rubric grading, Canvas CSV. Nothing Proxmox-controlling yet.

2. **Move dangerous infrastructure actions behind a separate narrow service or CLI wrapper.**  
   The Django app can request scenario actions, but Proxmox rollback and Ansible execution should have a small audited boundary with hard allowlists and minimal credentials.

3. **Defer auto-grading until manual grading is solid.**  
   First ship `Evidence` as instructor-attached/manual or imported check results. Then add Wazuh/Ansible collectors one criterion at a time after the rubric and dispute model are proven.
