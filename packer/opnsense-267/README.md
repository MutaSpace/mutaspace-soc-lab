# OPNsense 26.7 Template (`tpl-opnsense-267`, VMID 9004)

This directory builds the golden template that becomes `fw-01`, the firewall, router, DHCP server,
NTP server and — per decision D-04 — the intrusion detection sensor for the MutaSpace SOC Lab.

It is the hardest template in the repository, and this document says so up front rather than
burying it. Every other template in `packer/` has a supported unattended install path. This one
does not.

---

## Honest Status

| Question | Answer |
|---|---|
| Does `packer fmt -check` pass? | Yes |
| Does `packer validate` pass? | Yes |
| Has this build ever been run? | **No.** It was authored offline (decision D-05) before the Proxmox host existed |
| Has the boot command been tested against a real installer? | **No** |
| Has `config.xml` been diffed against a real OPNsense 26.7 export? | **No** |

`packer validate` proves the HCL is well formed, the plugin accepts every field, and the config
template renders. It proves nothing at all about whether the keystrokes land on the right screens.
Expect the first real build to need corrections, and read the
`THIS WILL BREAK ON VERSION BUMPS` block in `opnsense.pkr.hcl` before starting one.

---

## Why This Template Is Difficult

OPNsense has no cloud-init, no answer file and no unattended installer. The install is a series of
interactive console dialogs.

Automating it means typing keystrokes into a virtual console and using `<wait>` as the only
synchronisation primitive, because Packer cannot read the screen. That encodes three assumptions,
all specific to OPNsense 26.7:

1. Which screens appear, and in what order.
2. Where each menu's cursor starts, so that a given number of arrow presses lands on the intended
   entry.
3. How long each screen takes to appear.

A minor release that moves a menu entry or adds a question does not make this build fail loudly. It
makes it type the right keys at the wrong screen.

This was known before OPNsense was chosen. Decision D-02 picked it over pfSense CE anyway, because
pfSense CE 2.8.x has no downloadable ISO at all — only a network installer behind a store account,
which cannot be pinned or checksummed. **OPNsense won on the artifact, not on the install.**

---

## Manual Prerequisites

A fresh clone of this repository cannot build this template. Two things must be done by hand first.

### 1. Install `xorriso` on the Packer host

Packer builds the config-seed ISO locally, not on Proxmox. Without `xorriso` the failure message is
confusing.

```bash
sudo apt install xorriso
```

### 2. Put a decompressed OPNsense DVD on the ISO shelf

OPNsense publishes the DVD image bzip2-compressed. Proxmox cannot boot a compressed image, so the
`.bz2` has to be expanded before the file is usable. Run this on the Proxmox host:

```bash
cd /var/lib/vz/template/iso
curl -fLO https://mirror.dns-root.de/opnsense/releases/26.7/OPNsense-26.7-dvd-amd64.iso.bz2
curl -fLO https://mirror.dns-root.de/opnsense/releases/26.7/OPNsense-26.7-checksums-amd64.sha256

# Verify the COMPRESSED file against the project's published checksums
sha256sum -c --ignore-missing OPNsense-26.7-checksums-amd64.sha256

bunzip2 OPNsense-26.7-dvd-amd64.iso.bz2

# Record this value in docs/proxmox/iso-shelf.md and compare it on every rebuild
sha256sum OPNsense-26.7-dvd-amd64.iso
```

Two points worth understanding rather than copying:

- The published checksum covers the `.bz2`, not the `.iso`. The project does not publish a checksum
  for the decompressed image, so the only integrity check available afterwards is the one you
  record yourself.
- No SHA256 is hardcoded anywhere in this repository. None was verified while these files were
  written, and inventing one would be worse than having none — it would look like a guarantee.

---

## Credentials

Nothing secret is committed. Set these in the environment before building:

| Variable | What it is |
|---|---|
| `PKR_VAR_proxmox_token` | The API token secret (a bare UUID) |
| `PKR_VAR_root_password` | The firewall's root password, typed at the installer console |
| `PKR_VAR_root_password_hash` | The same password, crypt-hashed, for `config.xml` |

```bash
export PKR_VAR_proxmox_token='<uuid>'
export PKR_VAR_root_password='<password>'
export PKR_VAR_root_password_hash="$(openssl passwd -6 '<password>')"
```

Two variables for one password is awkward and deliberate. Importing a configuration replaces
OPNsense's user database, so the installer needs the plaintext and `config.xml` needs the hash —
and HCL has no `crypt()` function, so Packer cannot derive one from the other.

`PKR_VAR_root_password` defaults to empty. That is not an oversight: an empty password makes the
installer reject the entry, so a build that forgot to set it hangs and fails visibly instead of
shipping a firewall whose password is published in a public repository.

⚠️ The password is typed by `boot_command`, which means `packer build -debug` and `PACKER_LOG=1`
will print it. Do not paste build logs into a ticket.

---

## Building

This template accepts the repository's shared variable file, so the connection and storage settings
are configured once for every build:

```bash
cd packer/opnsense-267
packer init .
packer fmt -check .
packer validate -var-file=../common.pkrvars.hcl .
packer build    -var-file=../common.pkrvars.hcl .
```

Variable names are deliberately the same as the other templates — `proxmox_url`, `proxmox_node`,
`proxmox_insecure_tls`, `storage_pool`, `iso_storage_pool`, `build_bridge`, `task_timeout` — so
`../common.pkrvars.hcl` applies here unchanged.

If you want to override the OPNsense-specific values as well, copy this directory's example and
pass both files. Later files win:

```bash
cp opnsense.pkrvars.hcl.example opnsense.pkrvars.hcl   # then edit it
packer build -var-file=../common.pkrvars.hcl -var-file=opnsense.pkrvars.hcl .
```

Do not name either copy `*.auto.pkrvars.hcl`. Packer loads those automatically, which makes
`git add -A` a one-keystroke credential leak; the repository's `.gitignore` blocks them for that
reason.

Watch the build on the Proxmox console (`VM 9004 > Console`). This is the one build in the lab
where watching is genuinely useful, because a desynchronised keystroke sequence looks like a
perfectly healthy VM sitting on the wrong screen.

---

## What The Build Actually Does

| Phase | What happens | How fragile |
|---|---|---|
| 1 | Boot the DVD, log in as `installer`, accept the keymap, install to UFS, set the root password, reboot | **Very.** Menu order and cursor positions are version-specific |
| 2 | Log in at the console, drop to a shell, give the machine a temporary build-plane address, install `os-qemu-guest-agent` and `os-suricata`, copy the seeded `config.xml` into `/conf/`, remove SSH host keys and stale config backups, power off | Low. These are shell commands, and shell commands do not move between releases |

The split is intentional. When this breaks — and it will — Phase 1 is what needs re-deriving and
Phase 2 is what should survive untouched.

### Design choices worth knowing

| Choice | Reason |
|---|---|
| UFS, not ZFS | Two dialogs instead of four. This firewall is rebuilt from the template rather than upgraded in place, so ZFS boot environments buy nothing here |
| Three NICs during the build, all on `vmbr9` | The seeded config names `vtnet0`/`vtnet1`/`vtnet2`. Building with one NIC would leave two interfaces missing on first boot and drop the machine into OPNsense's interactive interface-assignment prompt, unattended |
| `communicator = "none"` | Once the real config is imported, the machine has no working uplink until it is cloned into `fw-01`. The alternative — a second, throwaway config that enables SSH — is better engineering but is more untestable code, not less |
| Config seed as a labelled ISO9660 volume, mounted via `/dev/iso9660/OPNCFG` | Mounting by volume label is immune to whether the seed landed on `cd0` or `cd1`. `opnsense.pkr.hcl` documents the FAT-image fallback if a future release refuses ISO9660 |
| SSH host keys deleted before the template is sealed | Otherwise every clone shares one host identity — a real security problem, and the reason people learn to ignore host-key change warnings |

---

## What The Seeded Configuration Contains

`config/config.xml.pkrtpl.hcl` is rendered by Packer and becomes `fw-01`'s entire configuration on
first boot.

| Area | Value |
|---|---|
| Hostname / domain | `fw-01` / `mutaspace.local` |
| WAN (`vtnet0`, `vmbr0`) | DHCP by default; static via `wan_mode = "static"`. The real address is a secret |
| LAN (`vtnet1`, `vmbr1`) | `10.10.10.1/24` |
| OPT1 (`vtnet2`, `vmbr2`) | `10.10.20.1/24` |
| DHCP pool | `10.10.10.100` – `10.10.10.200` on LAN only |
| DHCP options | Gateway `10.10.10.1`, DNS `10.10.10.10` (dc-01), domain `mutaspace.local`, NTP `10.10.10.1` |
| Reservations | Derived from `lab.yaml`. With the default `learner_count = 3`: `analyst-01` → `.50`, `win-client-01` → `.51`, `win-client-l01` → `.60`, `win-client-l02` → `.62`, `win-client-l03` → `.64`. All keyed on pinned `BC:24:11` MACs |
| Outbound NAT | Automatic |
| Suricata | Enabled on `lan,opt1`, detection only (`ips = 0`) |

### The DHCP reservations are the interesting part

The MACs are **inputs, not outputs**. Proxmox would happily invent a MAC at VM-create time, but a
DHCP reservation written before that happens could never match it. Instead the MACs are pinned in
`lab.yaml`, handed to Proxmox by OpenTofu, and templated into this configuration from the same map.
Because both sides read one source, `analyst-01` is still on `.50` after a full rebuild without
anyone touching the firewall.

The MACs use the Proxmox OUI `BC:24:11` with the last three octets derived from the address, which
makes a packet capture partly self-documenting. These are virtual MACs invented for the lab; the
physical NIC's MAC is a secret and appears nowhere.

**"Both sides read one source" was not true until recently, and the way it was false is worth
learning from.** The list used to be a literal `dhcp_reservations` default in `variables.pkr.hcl`
holding exactly two entries. OpenTofu, meanwhile, computes reservations for the per-learner Windows
clients as well — `lab.yaml` declares `learner_endpoints.win-client` with `mode: dhcp`, `host_base:
60`, `host_step: 2` — so with `learner_count = 3` it produced **five**. Three of those five had a
pinned MAC on the hypervisor and no matching `<reservation>` on the firewall.

Nothing would have failed. The three learner clients would have booted, taken an address from the
`.100`–`.200` pool, and worked. The lab would simply not have had the addresses its own design
documents promise, and the drift would have been invisible from either README.

`opnsense.pkr.hcl` now reads `lab.yaml` with `yamldecode()` and derives the list, applying the same
rules `tofu/locals.tf` applies. The only thing it still needs told is `learner_count`, which must
match `tofu/variables.tf`. A reservation for a learner who was never built is harmless — Kea never
sees that MAC — so if the two ever have to differ, make this one the larger.

### The rule that looks wrong and is not

The first firewall rule permits `10.10.10.10` — the domain controller — outbound to anywhere.

Windows Server 2022 Evaluation must activate over the internet within **ten days** or it begins
shutting itself down. On `vmbr1` there is no route out except through this firewall. Without that
rule the domain controller quietly dies about a week and a half into the semester and takes the
Active Directory exercises with it.

It sits first so that a learner who tightens the general LAN rule — a perfectly reasonable exercise
— does not remove the DC's access as a side effect. It is redundant while the permissive rule below
it exists, and that redundancy is the point: it is a seatbelt for a rule that is expected to change.

It is also the one place where "isolated lab" is not true. That tension is worth teaching, not
hiding.

### Suricata sees less than you think

Suricata runs here, on the firewall, rather than on a separate `sensor-01` VM. The reason is that
**a plain Linux bridge does not mirror traffic.** A promiscuous NIC attached to `vmbr1` will not see
unicast traffic flowing between two other VMs on `vmbr1`. Attaching a sensor to a bridge and
expecting full visibility is one of the most common mistakes in virtualised lab design.

Putting the sensor where the packets already have to go sidesteps mirroring entirely.

**The limitation, stated plainly:** this placement sees only traffic that *crosses* the firewall. It
does not see east-west traffic. An attack from `win-client-01` against `ubuntu-app-01`, both on
`vmbr1`, is completely invisible to it. Host-based Wazuh agents are what cover that gap in the
meantime.

The upgrade path is Open vSwitch with a mirror port feeding a real `sensor-01`. It is deferred
because it changes host networking, and host networking changes are the ones most likely to break a
class in progress.

Note also that "inline" here means *topologically* in the path. It is not the same as OPNsense's
IPS mode, which switches interfaces to netmap and lets Suricata drop packets. IPS mode is off by
default (`suricata_ips_mode = false`) because a false positive that black-holes the classroom
mid-exercise costs more than the detection is worth.

---

## Known Gaps and Unverified Assumptions

Listed rather than glossed over, because a reader deserves to know which parts are engineering and
which parts are educated guesses.

| # | Assumption | How to close it |
|---|---|---|
| 1 | The installer's first menu entry is `Install (UFS)` and the cursor starts on it | Boot the ISO by hand and look. This is the most likely thing to have moved |
| 2 | The keymap screen accepts a bare Enter for the default layout | Same |
| 3 | The console menu's Shell option is `8` | Same |
| 4 | Every `<wait>` duration is long enough on the target host | Watch one real build and record actual timings |
| 5 | OPNsense 26.7 uses Kea for DHCPv4 and the model layout in `config.xml` matches | Build once, configure in the GUI, export the config from *System > Configuration > Backups*, and diff |
| 6 | The `<IDS>` model version attribute is accepted or migrated forward | Same as 5 |
| 7 | Packer's `cd_content` creates the intermediate `conf/` directory for a nested key | Run one build; if the CD step fails, flatten the key and adjust the `cp` line |
| 8 | The firewall can reach the package mirrors from `vmbr9` with a hand-set address | The `ping` line in Phase 2 exists to make this visible on the console |
| 9 | `pkg install os-qemu-guest-agent` enables the guest-agent service without further configuration | Check `qm agent 100 ping` after the first clone |

The correct way to make `config.xml` authoritative is to build `fw-01` once, finish the
configuration in the GUI until the lab actually works, export it, and fold the export's element
names back into the template with the lab-specific values replaced by markers. The file in this
directory is a strong starting point, not a transcript of something that ran.

---

## Files

| File | Purpose |
|---|---|
| `opnsense.pkr.hcl` | The builder: hardware, media, and the fragile boot command |
| `variables.pkr.hcl` | Every input, with the reasoning for each default |
| `config/config.xml.pkrtpl.hcl` | The seeded `/conf/config.xml`, rendered from those variables |
| `opnsense.pkrvars.hcl.example` | Copy, edit, pass with `-var-file`. Secrets stay in the environment |
| `manifest.json` | Written by the build. Git-ignored — it is a record, never an input |

`manifest.json` deserves the emphasis. It records the VMID this build produced, and feeding that
straight into OpenTofu's `clone { vm_id = ... }` would be actively dangerous: the entire clone block
is ForceNew, so a manifest-driven VMID means every template rebuild destroys and recreates every VM
cloned from it. The VMID is pinned in both places and asserted at plan time instead.

---

## Learning Reflection

The interesting thing about this template is that it is the worst-engineered file in the repository
and it is still the right decision.

Every other template in `packer/` uses a supported unattended mechanism, so those files describe
*what* should be installed. This one describes *which keys to press*, which is a much weaker kind of
automation — it encodes what a screen looked like on one day, in one version. It cannot be unit
tested, it cannot be checked without hardware, and it will rot on a schedule set by someone else's
release calendar.

The alternative was worse. pfSense CE 2.8.x has no ISO to pin, so its firewall could only ever be
"a machine somebody configured once". Choosing OPNsense trades a clean install for a pinnable
artifact, and reproducibility is the point of the exercise. Naming that trade rather than
presenting the result as clean automation is the part that matters.

There is a second lesson buried in the structure. The build is split into a fragile dialog phase and
a stable shell phase, and once that split is visible the maintenance story changes: instead of "this
build is fragile", it becomes "these fifteen lines are fragile and the rest is fine". Isolating the
part that will break is not as good as not having a part that breaks, but it is a great deal better
than spreading the fragility evenly and calling the whole thing unreliable.

The third is about sensor placement. The most valuable sentence in this directory is probably the
admission that Suricata cannot see two VMs talking to each other on the same bridge. A lab that
quietly implied full network visibility would teach a habit that fails in production, where the
question "would this sensor actually have seen that?" is one of the most useful questions an analyst
can ask.
