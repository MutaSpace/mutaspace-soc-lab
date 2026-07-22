# The Build Plane (vmbr9)

Why a fourth, invisible network exists, why it is `10.99.0.0/24` and not something more obvious, and
why the Proxmox host itself is its gateway.

---

## The Problem This Solves

The MutaSpace SOC Lab is a **greenfield** build. There is one physical machine, a fresh Proxmox
install, and nothing else. Everything the lab needs is built from scratch.

That creates a circular dependency that is easy to miss until you hit it:

1. Every VM on the SOC LAN (`vmbr1`, `10.10.10.0/24`) reaches the internet through `fw-01`.
2. `fw-01` is the OPNsense firewall.
3. `fw-01` is itself a virtual machine, cloned from a golden template.
4. That template is built by Packer, which has to download an installer and fetch packages.
5. So Packer needs internet access, on a network, before `fw-01` exists.

There is no ordering of those five steps that works. The first template build has nowhere to run.

**`vmbr9` is the answer.** It is a bridge with no physical port, on which the *Proxmox host itself*
holds `10.99.0.1/24` and masquerades outbound traffic through the machine's real uplink NIC. Packer
builds every template there. When OpenTofu later clones a template into a real VM, it re-points the
NIC to `vmbr1` or `vmbr2`.

Re-pointing costs nothing: `bridge` is a normal, non-ForceNew attribute on the `bpg/proxmox`
provider, so changing it is an in-place update rather than a destroy-and-recreate.

---

## The Four Planes

| Bridge | Name | Subnet | Gateway | Who holds the gateway | Physical port |
|---|---|---|---|---|---|
| `vmbr0` | Management / WAN | *secret* | *secret* | the upstream router | yes — the host's uplink NIC |
| `vmbr1` | SOC LAN | `10.10.10.0/24` | `10.10.10.1` | `fw-01` | no |
| `vmbr2` | Isolated | `10.10.20.0/24` | `10.10.20.1` | `fw-01` | no |
| `vmbr9` | **Build plane** | `10.99.0.0/24` | `10.99.0.1` | **the Proxmox host** | no |

`vmbr1` and `vmbr2` are **portless and addressless on the host**. That is deliberate and it is the
single most important thing to get right. If the host also held `10.10.10.1`, there would be two
devices answering as the default gateway on the same segment, and the resulting routing would be
close to undebuggable — traffic would work for some flows and not others depending on which ARP
reply arrived first.

`vmbr9` is the exception. The host holds an address on it *because* the host is the gateway there.

---

## ⚠️ Why 10.99.0.0/24 And Not The Address In Proxmox's Own Documentation

The Proxmox VE admin guide has a worked example of a masqueraded, port-less bridge. That example
uses **`10.10.10.1/24`**.

In this lab, `10.10.10.1` is `fw-01`'s LAN address.

Copying that example verbatim puts the Proxmox host on the firewall's gateway address. The symptom
is not a clean failure — it is intermittent: some LAN machines get their ARP reply from the host,
some from the firewall, and traffic silently splits between a device that routes and a device that
does not.

`10.99.0.0/24` was chosen to be as far from the lab's own space as RFC1918 allows while staying
readable. Nothing else in the lab uses `10.99.` anything, which means a `10.99.` address appearing
anywhere it should not is immediately recognisable as build-plane leakage.

---

## How It Is Created

`scripts/bootstrap-host.sh` creates all three of `vmbr1`, `vmbr2` and `vmbr9` in
`/etc/network/interfaces`, as part of step 5 of its run. You do not create them by hand.

The script runs **on the Proxmox node, as root, once**, and it supports `--dry-run`. It is not
invoked from the `Taskfile` on purpose: it rewrites the host's network configuration and prints API
token secrets, and neither of those should scroll past inside other output.

```bash
scp scripts/bootstrap-host.sh root@<LAB_MANAGEMENT_IP>:/root/
ssh root@<LAB_MANAGEMENT_IP>
less /root/bootstrap-host.sh          # read it first
bash /root/bootstrap-host.sh --dry-run
bash /root/bootstrap-host.sh
```

The stanza it writes for the build plane looks like this:

```
auto vmbr9
iface vmbr9 inet static
        address  10.99.0.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s '10.99.0.0/24' -o <uplink> -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '10.99.0.0/24' -o <uplink> -j MASQUERADE
```

Three details worth understanding rather than copying:

- **`bridge-ports none`** is what makes it portless. No physical interface is enslaved, so nothing
  outside the host can reach this network directly.
- **`ip_forward`** is what makes the host a router at all. Without it the masquerade rule is
  irrelevant, because packets never leave the input path.
- **`-o <uplink>`** names the *physical* NIC, not `vmbr0`. The uplink interface name is
  machine-specific and is deliberately recorded nowhere in this repository — the script detects it,
  and `--uplink` overrides the detection.

---

## Verifying It

`scripts/preflight.sh` checks that all three bridges exist before any build starts, and refuses to
continue if one is missing:

```bash
./scripts/preflight.sh
```

By hand, on the host:

```bash
ip -br link show vmbr9
ip -br addr show vmbr9                       # expect 10.99.0.1/24
sysctl net.ipv4.ip_forward                   # expect 1
iptables -t nat -S POSTROUTING | grep 10.99  # expect one MASQUERADE rule
```

From inside a template while Packer is building it, the useful test is not `ping 8.8.8.8` but a name
lookup and a fetch, because that is what the installer actually needs:

```bash
getent hosts archive.ubuntu.com
curl -sI https://archive.ubuntu.com | head -1
```

---

## Life Cycle: The Build Plane Is Temporary Per-Machine, Permanent Per-Host

A VM's relationship with `vmbr9` ends the moment Packer finishes with it:

| Stage | Bridge | Address |
|---|---|---|
| Packer builds `tpl-ubuntu-server-2404` | `vmbr9` | DHCP-less; assigned by the installer or set by hand |
| OpenTofu clones it into `wazuh-01` | `vmbr1` | `10.10.10.20/24`, from cloud-init |

Nothing serves DHCP on `vmbr9`. That is why `packer/opnsense-267/variables.pkr.hcl` carries a
`build_address` of `10.99.0.90` typed in by hand at the OPNsense console — OPNsense has no
autoinstaller, so its temporary build-plane address is part of the keystroke sequence.

The bridge itself stays on the host permanently. Templates get rebuilt; the plane they are rebuilt
on has to still be there.

**A VM found sitting on `vmbr9` after a build is a bug.** `tofu/tests/network_placement.tftest.hcl`
asserts that no machine in the lab is left stranded on the build plane, precisely because "it works,
it just has internet it should not have" is not the kind of thing anyone notices.

---

## What Has Not Been Verified

The Proxmox host does not exist yet. Everything in this document was authored from the Proxmox
admin guide, the `bpg/proxmox` provider documentation and the scripts in this repository.

Specifically unverified:

- That `bootstrap-host.sh`'s uplink detection picks the right NIC on this hardware.
- That the masquerade rule survives a host reboot in the exact form the script writes it. `post-up`
  in `/etc/network/interfaces` is the documented mechanism, but `ifupdown2` on Proxmox 9.x has its
  own opinions about rule ordering.
- Whether the OPNsense installer's console accepts the `10.99.0.90` assignment at the point in the
  keystroke sequence where the template tries it. That whole build is the most fragile artifact in
  the repository and says so in its own header.

None of the above has been run against hardware. Correct anything here that turns out to be wrong
when it is.

---

## Learning Reflection

The build plane is a bootstrapping problem, and bootstrapping problems have a recognisable shape:
the system you are building is a prerequisite for building it.

The instinct is to solve them by ordering — "just build the firewall first". That instinct fails
here because the ordering is genuinely circular, not merely unstated. What actually resolves it is
introducing a *temporary, different* mechanism that provides the same service badly: the Proxmox
host is a worse router than OPNsense in every respect except one, which is that it already exists.

That pattern shows up constantly once you look for it. A self-hosting compiler needs a compiler
written in something else. A certificate authority needs a self-signed root. A configuration
management tool needs a machine it did not configure. In each case the answer is not to break the
cycle in place but to stand up a scaffold, use it once, and take it down — or, as here, leave it
standing but make sure nothing depends on it in steady state.

The second lesson is smaller and more practical: the most dangerous documentation example is the one
that is *almost* right for you. Proxmox's masquerading example is correct, well-written, and uses an
address that happens to be load-bearing in this lab. Nothing about it is wrong; it simply was not
written with this topology in mind. Reading an example for its *structure* and then choosing your
own values is a slower habit than copy-paste and it is the one that survives contact with a real
network.
