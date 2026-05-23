# fw-01 Firewall VM Plan

This document explains the plan for `fw-01`, the firewall/router VM for the MutaSpace SOC Lab.

The firewall VM is one of the most important systems in the lab because it controls how traffic moves between networks.

Before building endpoints, Wazuh, Suricata, or Active Directory, the lab needs a clear routing and firewall foundation.

---

## VM Purpose

`fw-01` will act as the firewall and router for the SOC lab.

It will separate the lab networks and control traffic between them.

The firewall VM will support:

- WAN and LAN separation
- Lab network routing
- DHCP services
- DNS forwarding
- Firewall rules
- Controlled access between networks
- Isolation for attack simulation systems
- Better visibility into network behavior

This VM helps the lab behave more like a real enterprise environment.

---

## Why the Firewall Comes First

The firewall should be built before most other VMs because other systems will depend on it for network access.

If the firewall is configured correctly, the rest of the lab becomes easier to build.

The firewall will help define:

- Which network a VM belongs to
- Which gateway a VM uses
- Which systems can reach the internet
- Which systems can communicate internally
- Which traffic should be allowed or blocked
- Where network troubleshooting should begin

Building the firewall first prevents the lab from becoming a flat network where every VM is connected directly to the management bridge.

---

## Planned Firewall Software

The planned firewall/router platform is:

```text
pfSense
```

pfSense will be used because it provides a web interface and supports common firewall/router functions used in real environments.

The lab will use pfSense to practice:

- Interface assignment
- WAN and LAN configuration
- DHCP setup
- Gateway configuration
- Firewall rules
- DNS forwarding
- Connectivity testing
- Basic network troubleshooting

---

## Planned Interfaces

The firewall VM will connect to multiple Proxmox bridges.

| pfSense Interface | Proxmox Bridge | Role |
|---|---|---|
| WAN | `vmbr0` | Outside/upstream network |
| LAN | `vmbr1` | Internal SOC lab network |
| OPT1 | `vmbr2` | Isolated or untrusted network |

The WAN interface connects toward the outside network.

The LAN interface connects to the internal SOC lab network.

The OPT1 interface can be used later for isolated testing, controlled attack simulation, or trust-boundary experiments.

---

## Planned Network Roles

| Network | Bridge | Purpose |
|---|---|---|
| Management / WAN | `vmbr0` | Proxmox management and pfSense WAN |
| SOC LAN | `vmbr1` | Main internal lab network |
| Isolated / Untrusted | `vmbr2` | Controlled attack simulation and isolated testing |

---

## Example Addressing Plan

Public documentation should use example values instead of live environment details.

| Network | Example Subnet | Example Gateway |
|---|---|---|
| SOC LAN | `10.10.10.0/24` | `10.10.10.1` |
| Isolated / Untrusted | `10.10.20.0/24` | `10.10.20.1` |

In this example:

- `10.10.10.1` would be the pfSense LAN gateway.
- `10.10.20.1` would be the pfSense OPT1 gateway.
- Internal VMs on `vmbr1` would use `10.10.10.1` as their gateway.
- Isolated VMs on `vmbr2` would use `10.10.20.1` as their gateway.

These values are examples and can be adjusted during the actual build.

---

## Suggested VM Resources

The firewall VM does not need large resources at the beginning.

| Resource | Starting Value |
|---|---|
| vCPU | 2 |
| RAM | 2GB |
| Disk | 20GB |
| Network Interfaces | 2 to 3 |
| Boot Media | pfSense ISO |

This can be adjusted later if the firewall begins handling more traffic or services.

---

## Firewall VM Placement

The firewall VM should be connected like this:

```text
fw-01
├── NIC 1 -> vmbr0 -> WAN
├── NIC 2 -> vmbr1 -> SOC LAN
└── NIC 3 -> vmbr2 -> Isolated / Untrusted
```

This placement allows the firewall to route and filter traffic between the networks.

---

## Initial Firewall Goals

The first firewall build should accomplish the following:

- pfSense installed successfully
- WAN interface assigned to `vmbr0`
- LAN interface assigned to `vmbr1`
- Optional OPT1 interface assigned to `vmbr2`
- LAN gateway configured
- DHCP enabled on the SOC LAN
- Internal client receives an IP address
- Internal client can reach the gateway
- Internal client can reach the internet if allowed
- Firewall web interface can be accessed from the internal lab network

---

## Why WAN and LAN Separation Matters

WAN and LAN separation is one of the most important firewall concepts.

The WAN side faces the outside or upstream network.

The LAN side protects the internal systems.

In this lab:

```text
WAN = upstream side of pfSense
LAN = internal SOC lab side of pfSense
```

This design helps teach how real networks separate trusted and less-trusted areas.

It also helps prevent lab systems from being placed directly on the Proxmox management network.

---

## DHCP Plan

pfSense can provide DHCP for the internal SOC LAN.

DHCP allows internal VMs to automatically receive:

- IP address
- Subnet mask
- Gateway
- DNS server

This makes early VM setup easier.

Later, when Active Directory and DNS are introduced, DNS settings may change so that domain-joined systems use the domain controller for DNS.

---

## DNS Plan

At first, pfSense may provide DNS forwarding for internal systems.

Later, when Active Directory is installed, the domain controller will likely become the main DNS server for domain systems.

This matters because Active Directory depends heavily on DNS.

The lab should document DNS changes carefully because DNS problems can cause:

- Domain join failures
- Authentication issues
- Wazuh agent communication problems
- Hostname resolution failures
- Confusing logs

---

## Firewall Rule Philosophy

The first firewall rules should be simple.

Early goals:

- Allow SOC LAN systems to reach the internet if needed
- Allow internal systems to reach required lab services
- Keep isolated systems controlled
- Avoid exposing Proxmox management unnecessarily
- Document each firewall rule and why it exists

Firewall rules should not be random.

Each rule should answer:

```text
What traffic is allowed?
From where?
To where?
On what port?
Why is it needed?
How was it validated?
```

---

## Common Beginner Mistakes

### Mistake: Assigning interfaces randomly

If WAN and LAN are assigned incorrectly, the firewall may block access or route traffic incorrectly.

The correct Proxmox bridge should be matched to the correct pfSense interface.

### Mistake: Putting internal VMs on `vmbr0`

Internal lab systems should not be placed directly on the management/WAN bridge unless there is a specific reason.

Most internal lab systems should use `vmbr1`.

### Mistake: Forgetting the gateway

A VM can have an IP address and still fail to reach other networks if the gateway is missing or wrong.

### Mistake: Changing too many rules at once

Firewall troubleshooting is easier when one change is made at a time.

---

## Troubleshooting Mindset

If a VM cannot communicate, ask:

1. Is the VM connected to the correct Proxmox bridge?
2. Does the VM have an IP address?
3. Is the IP address in the correct subnet?
4. Is the gateway correct?
5. Can the VM ping the firewall LAN interface?
6. Can the firewall see the interface as up?
7. Is DHCP working?
8. Is DNS working?
9. Is a firewall rule blocking the traffic?
10. What do the firewall logs show?

This approach teaches network troubleshooting instead of guessing.

---

## Validation Checklist

| Validation Item | Status |
|---|---|
| pfSense ISO obtained | Pending |
| VM created in Proxmox | Pending |
| WAN connected to `vmbr0` | Pending |
| LAN connected to `vmbr1` | Pending |
| OPT1 connected to `vmbr2` | Pending |
| pfSense installed | Pending |
| Interfaces assigned correctly | Pending |
| LAN gateway configured | Pending |
| DHCP configured | Pending |
| Test VM receives IP address | Pending |
| Test VM can ping gateway | Pending |
| Firewall web interface accessible | Pending |

---

## Learning Reflection

The firewall VM teaches that cybersecurity labs are not just about installing tools.

The network has to be designed first.

A firewall controls trust boundaries, routing, access, and visibility. Understanding the firewall helps explain why traffic moves, why traffic fails, and where security monitoring should happen.

A good SOC lab starts with a network that makes sense.