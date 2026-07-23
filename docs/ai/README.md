# AI-assisted SOC work in this lab

This lab teaches security operations. This document describes how a **local, offline AI model**
is being wired into it as a force-multiplier for the analyst — and, just as importantly, where it
is deliberately *not* trusted. It is the design record for the `ai/` work the way `docs/iac/`
is for the infrastructure: read it before changing how the model is deployed or used.

The guiding rule is the one the SecAI+ course Day 4 lesson is built on, and it is worth stating
before anything else:

> **AI drafts, the human decides.** Every artifact the model produces — a triaged alert, a
> detection rule, an incident summary — is a *proposal*. A validator checks it where a validator
> exists, and an analyst confirms it before it is trusted. That discipline is the whole difference
> between a force-multiplier and an automation liability.

---

## The model: one local endpoint, on CPU, offline

There is exactly one model in the lab, and everything else calls it:

- **Runtime:** [Ollama](https://ollama.com), serving on CPU. No GPU, no API key, no data leaving
  the host.
- **Chat model:** `qwen2.5:3b`. Three billion parameters is not arbitrary — it is the *floor* for
  emitting well-formed tool-call JSON on CPU. Sub-2B models (the `qwen2.5:1.5b` used elsewhere in
  the course) produce malformed tool arguments often enough to break an agent loop. This is the
  "right-size the model to the task" judgment made concrete: 3B for tool-calling, no larger.
- **Embedder:** `nomic-embed-text`, for retrieval over the lab's own documents (the assistant).
- **Where it runs:** `nlp-01` (10.10.20.30), the pre-existing *"Analysis/NLP workload"* node.

Stand it up with:

```bash
ansible-playbook ansible/playbooks/80-ai-assist.yml
```

That playbook installs Ollama, pins the two models, binds the API, and asserts the endpoint
answers. Its header explains the one wrinkle: **installing and pulling models needs outbound
internet, but the box that runs them sits on the isolated segment that has none.** The same
build-plane-vs-run-plane tension as the Wazuh install — the long-term fix is to bake Ollama and
the model weights into the `nlp-01` Packer template so a rebuilt lab is offline from first boot.

### Where the model lives is a real decision, not a default

`nlp-01` is on the isolated segment. That keeps a CPU-heavy inference workload off the SOC LAN and
puts a model next to the attack plane (useful for the *offensive* AI demos below). But it also
means the analyst tooling on `analyst-01` (SOC LAN) can only reach it through a **deliberate
firewall rule** on fw-01. Two honest options, and the lab should pick per-cohort rather than
pretend the choice isn't there:

| Placement (`ai_host` →) | Reachable by | Cost |
|---|---|---|
| `nlp-01` (default) | isolated segment; SOC LAN only via an fw-01 rule | keeps inference off the SOC LAN; models the cross-segment access-control decision explicitly |
| `analyst-01` | SOC LAN directly, no firewall change | simplest for analyst-facing features; puts inference load on the analyst desktop |

The placement is one line — the `ai_host` group in `ansible/inventory/hosts.yml` — precisely so
this stays a conscious choice. The bind address (`ai_ollama_bind` in `group_vars/all.yml`) and the
firewall rule are set together or not at all; binding to the segment IP without the rule just makes
the model unreachable, and opening the rule without rebinding leaves it on loopback.

---

## The four integrations

Each maps to a Day 4 theme and reuses the same local endpoint. They are built **against sample
data first** so they are ready and reviewable before the live environment is fully deployed, then
pointed at the real services as the lab comes up. Status is tracked here.

### 1. Wazuh alert triage — *AI drafts, human decides*
A tool (exposed over MCP, so it drops into the Day 4 MCP SOC-tool lab) that reads real Wazuh alerts
from the manager's API and asks the model to **summarize and prioritize** them — *Investigate now /
Watch / Likely benign* — with a one-line rationale grounded in the alert fields. The model never
closes or actions an alert; it ranks a queue an analyst then works. Grounding triage on the actual
alert data (not the model's memory) is what keeps it from inventing severities.
**Status:** planned — build against exported sample alerts, then point at the `wazuh_api` on
`wazuh-01`.

### 2. Detection-rule copilot — *generate → validate → repair*
The Day 4 detection loop, wired to the lab's real validators. The model drafts a **Sigma** rule
(log events) or a **Suricata** rule (network — Suricata uses Snort-family syntax); the draft is
validated *statically and offline* with `sigma check` and `suricata -T`; failures feed back into a
repair prompt; the human reviews the survivor before it is deployed into the lab's ruleset (the
Wazuh `local_rules.xml` / the Suricata rules dir via IaC). The loop only works because both
artifact types have a mechanical validator — that is the load-bearing point.
**Status:** **built** — `ai/detection_copilot.py` (+ `validators.py`, `prompts/`, sample incidents
in `ai/samples/`). Runs against sample data now; `sigma check` / `suricata -T` gate the rule when
installed and degrade to a clearly-marked ungated draft when not. The live model round-trip and the
repair loop are smoke-tested; not yet run against `nlp-01`'s `qwen2.5:3b`.

### 3. Lab-grounded analyst assistant — *retrieval over your own docs*
An assistant (AnythingLLM or the course's small Python chat starter, both on Ollama) grounded on
**this repository's `docs/`** — the runbooks, the build notes, the incident scenarios. A learner
asks "how is the isolated segment supposed to route?" and gets an answer *from the lab's own
documentation*, with the source, rather than a generic web answer. This is the classroom-assistant
pattern pointed at the SOC lab's corpus.
**Status:** **built** — `ai/assistant.py` embeds `docs/` with `nomic-embed-text` and answers from
it with citations; the corpus is read-only (an editable corpus is an indirect-injection surface —
the Day 2/Day 3 lesson). Retrieval/chunking/citation logic is unit-tested; the live embed+answer
pass is not yet run against `nlp-01`.

### 4. Incident-scenario copilot — *coach and generate*
Two uses over `docs/incident-scenarios/`: a **Socratic coach** that walks a learner through an
investigation with guiding questions instead of answers (a system-prompt persona, like the course's
`socratic.txt`), and a **generator** that drafts a *new* scenario plus the matching detection —
which then goes through integration 2's validate loop before it is ever used. Generated scenarios
are drafts a human reviews, same rule as everything else.
**Status:** planned.

---

## Security posture — the model is inside the threat model, not above it

This is a security lab; the AI is treated as an attackable component, not a trusted oracle.

- **No secrets to the model.** Never place credentials, real PII, or the answer key to a scenario
  in a system prompt or a document the assistant can retrieve. You cannot leak what is not there
  (the Day 3 lesson).
- **Read-only corpus.** Only the maintainer adds documents the assistant retrieves. A corpus
  learners can edit is an indirect-injection channel.
- **Least privilege for tools.** The triage and rule tools get read access to what they need and
  nothing else; nothing the model drives can close an alert, deploy a rule, or touch a host without
  a human step in between.
- **Offline by default.** Once the models are pulled, inference needs no network. Keep the isolated
  segment isolated; open fw-01 only for the deliberate, documented cases above.
- **The model is also an attacker's tool.** The isolated placement is partly so the attack-plane
  demos (AI-assisted phishing, evasion drafting — Day 4's "symmetry of capability") have a model to
  use. Teaching the offense is a feature; letting it reach the SOC LAN is not.

---

## Build order

1. **Foundation — done here.** `80-ai-assist.yml` + the `ai_host` group + the `ai_*` vars in
   `group_vars/all.yml`. One local endpoint, validated.
2. **Assistant (3) and rule copilot (2) — done.** Both live under `ai/` (see `ai/README.md`), built
   against `docs/` and sample incidents, neither needing live alerts. Host verification pending.
3. **Wazuh triage (1)** next — once the SIEM is up and producing alerts to ground on.
4. **Scenario copilot (4)** last — it leans on the rule copilot's validate loop.

> **Not verified on a host yet.** Per the repo's hard rule, this foundation has been written and
> statically checked but not yet run against `nlp-01` — the node is not built at the time of
> writing. Run `80-ai-assist.yml` on it, confirm `ollama list` shows both models, and update this
> line when it has actually served a completion.
