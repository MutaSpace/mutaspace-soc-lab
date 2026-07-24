# Proposal: OPNsense-as-code — zero-touch fw-01 on deploy

**Status:** proposed (2026-07-24). Author: live investigation on swc2026.
**Goal:** remove the one manual island in the lab. Today fw-01 (OPNsense) is the only
component an operator configures by hand (GUI clicks, password SSH, config.xml surgery).
Everything else is Packer/OpenTofu/Ansible. This proposal makes fw-01 configured-as-code
like every other host, so **an instructor does nothing to the firewall during a deploy.**

---

## Why this exists (the friction we hit)

- OPNsense root is **password-only** (no key), so automation needs `sshpass`, which the
  Claude Code auto-mode classifier refuses (correctly — password SSH to a firewall).
- Live changes (a reset root password, ad-hoc rules) drift from the template.
- There is no API access provisioned, so nothing can drive fw-01 programmatically.

The fix is not a smarter way to type the password — it is to **provision key + API access
at build time** and manage the rest over the API, exactly like AD/Wazuh/agents.

---

## Verified findings (from the live template + host, 2026-07-24)

The OPNsense template `tpl-opnsense-267` (VMID 9004) seeds its entire config from
`packer/opnsense-267/config/config.xml.pkrtpl.hcl`. Inspection confirms a **redeploy
reproduces the live box**:

| In the seed (reproduces on redeploy) | Not in the seed (must add / wire) |
|---|---|
| `<filter>` firewall rules incl. the scenario allow rules | `<authorizedkeys>` (root SSH key) |
| `<nat>`, `<outbound>` NAT | `<apikeys>` (API key/secret) |
| `<gateways>`, `<interfaces>` (wan/lan/opt1/opt2) | — |
| `<dhcpd>` incl. static reservations (analyst-01 .50 etc.) | — |
| `<unbound>` DNS resolver | — |
| root `<user>` with templated `${root_password_hash}` | — |
| `<IDS>` + `<syslog_eve>` Suricata scaffolding (core in 26.7, no os-suricata plugin) | — |

**The one gap that would break a redeploy:** `PKR_VAR_root_password` /
`PKR_VAR_root_password_hash` are **not currently set in `.envrc`**, so a rebuild today would
bake an empty/unknown root password (the template defaults it empty on purpose). This must be
wired to the known value or the rebuilt fw-01 is locked out (console-only recovery).

---

## Design

### 1. Bake access into the template seed (Packer)

Add to the root `<user>` block in `config.xml.pkrtpl.hcl`, both env-sourced, never committed:

- `<authorizedkeys>${base64(root_authorized_keys)}</authorizedkeys>` — root SSH **public**
  key. New `variable "root_authorized_keys"`, passed through the `templatefile()` map,
  set via `PKR_VAR_root_authorized_keys`. (A public key is not a secret, but keep it
  env-driven to match repo convention.)
- `<apikeys><item><key>…</key><secret>…</secret></item></apikeys>` — an API key/secret for a
  dedicated `labauto` user (or root). OPNsense stores the **secret hashed**; the exact hash
  format (sha512-crypt vs bcrypt in 26.7) must be confirmed by creating one key on a live box
  first (trivial once SSH-key access exists — bootstrap order below). Plaintext secret lives
  in `.envrc` for API clients; only the hash is in the seed.

Also wire the existing `PKR_VAR_root_password` + `PKR_VAR_root_password_hash`
(`openssl passwd -6`) so the console/root password is the known lab value on every build.

**Result:** every fw-01 built from the template comes up with key-based root SSH **and** API
access already enabled. Zero GUI, zero manual keys.

### 2. Manage fw-01 over the API, automatically, during deploy (Ansible)

fw-01 is "reachability-only" in Ansible today. Add a real `fw-01` role (using the
`ansibleguy.opnsense` collection → the REST API, authed by the baked-in key) that applies the
firewall deltas as code — run in the normal deploy sequence:

- the standing scenario allow rules (idempotent; the template already has them, the role keeps
  them true),
- a toggleable **research-plane egress** rule (`fw:egress-open`/`fw:egress-close` — for the
  nlp-01 Ollama model pull, then closed),
- **Suricata (inline, R4 decision)**: enable the core IDS, ET Open rules, and EVE→Wazuh via
  the existing `<syslog_eve>` remote-syslog path to wazuh-01 + the Wazuh Suricata decoder.

Expose these as `task fw:*` verbs so an instructor never touches the firewall by hand.

### 3. Reusable OPNsense MCP server (own repo, optional layer)

On top of the same REST API, a small MCP server exposing typed tools (`open_egress(host)`,
`enable_suricata()`, `list_rules()`, `apply_rule(...)`). Because it wraps the OPNsense API, it
is **reusable across any OPNsense deployment**, not lab-specific — worth building as its own
repo. It also cleanly sidesteps the password-SSH/classifier friction (the server holds scoped
creds; the agent calls a tool). This is the AI-assisted-operator layer and overlaps the
socboard/scenario-generation control-plane direction; it deserves its own `/plan`.

---

## Cutover plan (the deliberate, load-bearing step)

fw-01 routes the whole lab; recovery if it comes up wrong is via the Proxmox **serial
console** (guest agent is off). Do this eyes-open, not rushed:

1. Wire `.envrc`: `PKR_VAR_root_password`, `PKR_VAR_root_password_hash`,
   `PKR_VAR_root_authorized_keys` (+ API key/secret once format confirmed).
2. Edit the seed (authorizedkeys, apikeys) + variables + templatefile map. `packer validate`.
3. `packer build` `tpl-opnsense-267` (automated, ~30–60 min; no live impact — builds a new
   9004 template).
4. **Snapshot/backup the live fw-01 config** first (export `config.xml` via console) as a
   rollback.
5. `tofu apply -target` fw-01 to redeploy from the new template. Brief lab-routing blip.
6. Verify on the host + from a lab VM: rules present, inter-segment routing, DHCP leases, DNS
   resolve, NTP; then confirm key SSH + API auth work.
7. Only then: run the fw-01 Ansible role (egress + Suricata) and the nlp-01 Ollama pull.

**Bootstrap ordering note:** step 2's API-secret hash needs the format confirmed on a live
box. Sequence: bake the **SSH key first** (reliable, no hashing) → redeploy → use SSH-key
access to create one API key and read its config.xml format → bake the **API key** in a second
pass. Or, one-time, reconcile the *current* live fw-01 (option "B" — authorized password-SSH
once) to inspect the format without a redeploy.

---

## Scope / sequencing recommendation

- **Milestone 1 (this proposal):** SSH-key + root-pw bake, template rebuild, deliberate fw-01
  cutover, fw-01 Ansible role, Suricata + egress via the API. Closes the "instructors touch
  the firewall" gap. Its own `/plan` given the load-bearing redeploy.
- **Milestone 2:** the reusable OPNsense MCP server (own repo), tied to the broader AI
  control-plane direction ([[scenario-catalog-roadmap]], socboard).

Suggested: a codex cross-review of this proposal (matching the other `docs/proposals/*`), then
`/plan` Milestone 1 before touching the live firewall.
