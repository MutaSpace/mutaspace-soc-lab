# Ansible

This folder holds everything that has to happen *inside* the virtual machines.

Packer builds the golden templates. OpenTofu creates the virtual machines from those templates and
places them on the right networks. Neither of them can create an Active Directory forest, enroll a
SIEM agent, or push a detection rule. That is what lives here.

---

## Why Ansible and not more OpenTofu

The honest answer is that there is no alternative for the largest job in this folder.

HashiCorp archived `terraform-provider-ad` on 2025-08-11. It was never more than an experimental
technical preview, and it is now unmaintained. There is no supported Infrastructure-as-Code
provider for Active Directory objects, which means the forest, the DNS records, the organisational
units, and the lab accounts have to be created by something imperative.

That is not a defeat. Some work genuinely is imperative. Promoting a domain controller is a
sequence — install the role, create the forest, reboot, wait for the directory service to start,
then configure it — and a declarative tool that pretended otherwise would be lying about what is
happening.

---

## Run order

The playbooks are numbered because the order is not a preference. Each one depends on state the
previous one created.

| # | Playbook | Runs against | What it does |
|---|---|---|---|
| 00 | `00-preflight.yml` | control node, `linux`, `bootstrap_windows` | Checks credentials, reachability and DNS. Changes nothing. |
| 10 | `10-dc-promote.yml` | `dc-01-bootstrap` | Creates the `mutaspace.local` forest, installs DNS, creates the reverse lookup zone |
| 20 | `20-dns-records.yml` | `dc-01` | A and PTR records for `wazuh-01` and `ubuntu-app-01` |
| 30 | `30-domain-join.yml` | `win-client-01-bootstrap` | Renames and joins the Windows workstation |
| 40 | `40-wazuh-server.yml` | `wazuh-01` | Installs the Wazuh 4.14.6 all-in-one deployment |
| 50 | `50-wazuh-agents.yml` | `wazuh-01`, then all agents | Creates agent groups, then enrolls every endpoint |
| 60 | `60-endpoints.yml` | `ubuntu-app-01`, `win-client-01` | Nginx and OpenSSH; Sysmon and logon auditing |
| 70 | `70-detections.yml` | `wazuh-01` | Pushes `local_rules.xml` through the API and reloads analysisd |
| 90 | `90-lab-seed.yml` | `dc-01` | Creates the OUs and the accounts the incident scenarios depend on |

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
set -a; . ./lab-credentials.env; set +a

ansible-playbook playbooks/00-preflight.yml
ansible-playbook playbooks/10-dc-promote.yml
ansible-playbook playbooks/20-dns-records.yml
ansible-playbook playbooks/30-domain-join.yml
ansible-playbook playbooks/40-wazuh-server.yml
ansible-playbook playbooks/50-wazuh-agents.yml
ansible-playbook playbooks/60-endpoints.yml
ansible-playbook playbooks/70-detections.yml
ansible-playbook playbooks/90-lab-seed.yml
```

Or through the repository's single entrypoint, which asserts the credentials each playbook needs
before it starts rather than halfway through:

```bash
task ansible:deps
task ansible:preflight        # 00
task ansible:dc-promote       # 10
task ansible:dns-records      # 20
task ansible:domain-join      # 30
task ansible:wazuh-server     # 40
task ansible:wazuh-agents     # 50
task ansible:endpoints        # 60
task ansible:detections       # 70
task ansible:lab-seed         # 90

task ansible:all              # all of the above, in order
```

**There is no `task ansible:suricata`, and that is not an omission.** Decision D-04 puts Suricata
inline on `fw-01` as an OPNsense plugin. OPNsense is a FreeBSD appliance with no Python and no
WinRM; it is not in this inventory and there is nothing here for a playbook to configure. The plugin
is installed by the Packer build and enabled by the `<IDS>` block in the `config.xml` that build
seeds — see `packer/opnsense-267/`.

### There is deliberately no `site.yml`

A single playbook that ran all nine in sequence would be convenient and would hide the two most
important facts about this sequence: that `10-dc-promote.yml` changes the identity of a machine
partway through, and that `40-wazuh-server.yml` needs outbound internet access that the rest of the
lab does not.

Both of those are decisions an operator should make consciously, one at a time, on a first build.
Running them one at a time also means a failure stops where it happened instead of somewhere later.

---

## The two Windows groups

This is the part of the inventory that surprises people, so it is worth stating plainly.

A Windows machine **changes identity** during this build.

Before promotion or domain join, the only account that exists is the local `Administrator` created
by Cloudbase-Init, and the only way to authenticate is NTLM over WinRM. After promotion, the local
account on `dc-01` is gone — it has become `MUTASPACE\Administrator` — and the correct transport is
Kerberos. After the domain join, `win-client-01` is a domain member and should be addressed as one.

Ansible has no way to say "these credentials, but only until task 14". So the inventory lists each
Windows machine twice:

| Group | Inventory name | Credentials | Transport | Addressed by |
|---|---|---|---|---|
| `bootstrap_windows` | `dc-01-bootstrap`, `win-client-01-bootstrap` | local `Administrator` | NTLM, WinRM 5985 | IP address |
| `domain_windows` | `dc-01`, `win-client-01` | `MUTASPACE\Administrator` | Kerberos, WinRM 5985 | FQDN |

The bootstrap entries are addressed by IP because no DNS exists yet. The domain entries are
addressed by FQDN because Kerberos matches a ticket against the service principal name of the host
you asked for, and an IP address is not a name.

Playbooks 10 and 30 are the only ones that use the bootstrap identities. Everything from 20 onward
uses the domain identities.

### Port 5985 is HTTP, and that is not as bad as it looks

NTLM and Kerberos both negotiate a session key and Ansible encrypts the WinRM message payload with
it. The traffic is encrypted; it simply is not TLS. That avoids having to provision and trust a
certificate on every Windows template before the certificate authority that would issue it exists.

It is still a lab. Do not copy `group_vars/bootstrap_windows.yml` into a production inventory.

---

## The NTLM delegation constraint

Two playbooks — `20-dns-records.yml` and `90-lab-seed.yml` — carry a comment saying they must run
against `dc-01` itself. That comment is load-bearing.

NTLM cannot delegate. When Ansible authenticates to a Windows host over NTLM, the remote session
receives a **network logon token with no credentials attached to it**. Anything that session tries
to do which requires authenticating *onward* to another machine fails, because there is nothing to
authenticate with. This is the classic Kerberos double-hop problem, and every Active Directory
object operation runs into it: creating a DNS record, creating a user, creating an OU.

The failure is not a clean permission error. It is:

```text
Failed to contact the AD server
```

which sends people looking for a network problem that does not exist, on a machine that can ping
the domain controller perfectly well.

Kerberos with constrained delegation solves this in general. **This lab does not rely on that.**
Every AD-object play runs *on the domain controller*, so the operation is local and there is no
second hop to fail. It is a simpler answer than configuring delegation, and it has the useful
property of being obvious once you have read it.

### Kerberos needs a working krb5 client on the control node

The `domain_windows` group uses Kerberos, which means the machine running `ansible-playbook` needs
a Kerberos client configured for the realm. On Ubuntu:

```bash
sudo apt install krb5-user python3-kerberos
```

`/etc/krb5.conf` needs the realm mapped to the domain controller:

```ini
[libdefaults]
    default_realm = MUTASPACE.LOCAL
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    MUTASPACE.LOCAL = {
        kdc = dc-01.mutaspace.local
        admin_server = dc-01.mutaspace.local
    }

[domain_realm]
    .mutaspace.local = MUTASPACE.LOCAL
    mutaspace.local = MUTASPACE.LOCAL
```

Check it before blaming a playbook:

```bash
kinit Administrator@MUTASPACE.LOCAL
klist
```

The control node also needs `dc-01.mutaspace.local` to resolve, which means either using
`10.10.10.10` as its resolver or adding a hosts entry.

---

## Credentials

No password, token, key or management address is written into any file in this folder.

Every secret is read from an environment variable at run time, using the `default=Undefined`
argument to the env lookup — which makes a missing variable a named error instead of an empty
string that silently sets a blank password on a domain controller.

```bash
cp lab-credentials.env.example lab-credentials.env
$EDITOR lab-credentials.env
set -a; . ./lab-credentials.env; set +a
```

`00-preflight.yml` asserts that every required variable is present before anything mutates.

Ansible Vault was considered and not chosen. Both approaches are defensible, but this repository is
public teaching material, and an encrypted vault file in a public repository invites exactly one
question — "what is in it?" — and offers exactly one defence, a passphrase. With environment
variables there is nothing secret in the repository at all. The cost is that credentials live in the
operator's shell session and have to be re-exported in a new terminal. That is a real inconvenience,
and an honest trade rather than a free win.

### Generated credentials

The Wazuh installation assistant generates its own passwords. `40-wazuh-server.yml` captures them
out of `wazuh-install-files.tar` and writes them to `.secrets/wazuh-passwords.txt` with mode `0600`.
That path is excluded by `ansible/.gitignore`. The task uses `no_log` so the values never appear in
the run output, and the installer task uses `no_log` for the same reason — it prints the admin
password to stdout on completion.

---

## Things worth knowing before you run this

**`40-wazuh-server.yml` needs the internet.** The Wazuh installation assistant fetches
`wazuh-template.json` from `raw.githubusercontent.com` during the indexer stage, and the packages
come from `packages.wazuh.com`. That means `wazuh-01` needs outbound HTTPS through `fw-01` — on a
network whose entire design premise is isolation. The better long-term home for that work is the
Packer build of template 9000, on the build plane, where outbound access already exists by design.
The playbook is kept because it documents what the template must contain and because "the SIEM
install needs the internet" is a constraint worth teaching rather than hiding.

**Agent groups are created before any agent is installed.** Enrolling an agent into a group that
does not exist does not create the group. The enrollment succeeds, the agent appears in the
dashboard, and it lands silently in `default` — so every piece of group-specific configuration you
later write never reaches it. There is no error message to search for.

**Agents enroll by IP and then move to the FQDN.** Enrollment happens inside the package's postinst
script or the MSI, before Ansible can fix anything, and at that moment the FQDN may not resolve. The
agent roles enroll against `10.10.10.20` and then rewrite `ossec.conf` to
`wazuh-01.mutaspace.local`, which is what you want long term: the manager can be re-addressed
without touching eight endpoints.

**Detections are reloaded, not restarted.** `70-detections.yml` calls
`PUT /manager/analysisd/reload` rather than restarting `wazuh-manager`. A restart also loads the new
rules — and drops every agent connection, re-queues events mid-flight, and puts a gap in the data at
exactly the moment a class is looking at it.

**`90-lab-seed.yml` is coursework, not convenience.** Two completed incident scenarios reference
`test.user` and `lab.user02` by name. On the old hand-built lab those accounts existed because
someone clicked them into existence. On a greenfield host they exist only if that playbook creates
them, and if the names drift, both exercises stop reproducing — silently, by returning no search
results rather than by failing.

---

## What has been verified, and what has not

This code was written before the Proxmox host existed. That is deliberate — the goal of authoring
offline is not to be right on the first run, it is to make the first run fail for interesting
reasons rather than for typos. But it means the honest answer to "does this work?" has two parts.

**Verified offline:**

| Check | Result |
|---|---|
| Every YAML file parses | 24 files, all parse |
| Every play resolves to a real host or group in the inventory | 16 plays across 9 playbooks, all resolve |
| Every task has exactly one module, and every module is fully qualified | 35 distinct modules, all FQCN |
| Every module comes from a collection listed in `requirements.yml` | yes |
| Every `notify` matches a handler that exists | yes |
| Every Jinja expression is syntactically valid | 177 expressions |
| `files/wazuh-rules/local_rules.xml` is well-formed XML | `xmllint --noout` passes |

**Not verified, and cannot be until the host exists:**

- `ansible-lint` has not been run. It is not installed on the authoring machine, and neither is
  `ansible-core`, so no module argument has been checked against its real specification.
- No playbook has been executed. Nothing here has ever talked to a Windows host, a Wazuh manager, or
  a domain controller.
- The `frequency` threshold on rule `100011` is written as 5 but has not been observed firing. Wazuh
  has counted this differently across versions. Test it before teaching a specific number.
- The Sysmon and Wazuh installer download URLs are the documented upstream ones but have not been
  fetched.
- Whether `win_powershell`'s `parameters` binding behaves as expected for every script in these
  playbooks has been reasoned about, not observed.

Nothing in this folder claims a validation result it did not produce. When these playbooks are run
against real hardware for the first time, the results belong in a build document alongside whatever
had to be corrected.

---

## Learning Reflection

The most interesting thing about writing this was discovering how much of the difficulty had nothing
to do with Ansible.

Three of the hardest decisions here — the two Windows groups, running AD plays on the domain
controller, and enrolling agents by IP before switching to a name — are all the same problem wearing
different clothes. Each one is a case where **the system changes identity partway through the
build**, and the tool has no way to express "this is true now but will not be in ten minutes".

A configuration management tool describes a desired end state. That model is excellent and it has a
blind spot: it assumes the thing being configured is the same thing throughout. A machine that is a
workgroup member at the start of a play and a domain controller at the end of it violates that
assumption, and every awkward part of this folder is an accommodation for that violation.

The second lesson is about failures that are not errors. An agent enrolled into a nonexistent group
does not fail — it lands in `default`. A DNS record created in the wrong zone does not fail — it
just never resolves. An account created with the wrong `sAMAccountName` does not fail — a learner's
search simply returns nothing. None of those produce a red line anywhere.

That is why almost every playbook here ends with an assertion rather than with the task that did the
work. Checking that the change happened is a different claim from watching the command succeed, and
in this domain it is the only one worth making.
