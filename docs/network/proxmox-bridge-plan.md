# Proxmox Bridge Plan

This document explains the planned Proxmox bridge configuration for the MutaSpace SOC Lab.

A Proxmox bridge works like a virtual switch. Virtual machines connect to bridges so they can communicate with other systems.

In this lab, bridges are used to separate management traffic, internal SOC lab traffic, and isolated/untrusted lab traffic.

---

## Bridge Purpose

The purpose of using multiple bridges is to avoid placing every virtual machine on the same network.

A SOC lab should teach how networks are separated, routed, monitored, and protected.

Using multiple bridges helps support:

- Proxmox management access
- Firewall/router placement
- WAN and LAN separation
- Internal lab networking
- Isolated attack simulation
- Controlled traffic flow
- Future monitoring and detection work

---

## Physical Interface

During installation, Proxmox detected the physical wired network interface as:

```text
nic0
```

In this lab:

```text
nic0 = physical Ethernet adapter
vmbr0 = virtual bridge connected to nic0
```

The physical Ethernet adapter connects the Proxmox host to the outside network.

The bridge allows Proxmox and selected VMs to use that connection.

---

## Planned Bridges

| Bridge | Connected To | Role | Purpose |
|---|---|---|---|
| `vmbr0` | `nic0` | Management / WAN | Proxmox access and firewall WAN |
| `vmbr1` | No physical port | Internal SOC LAN | Main internal lab network |
| `vmbr2` | No physical port | Isolated / Untrusted | Attack simulation and trust-boundary testing |

---

## `vmbr0`: Management and WAN

`vmbr0` is the primary bridge connected to the physical network interface.

This bridge is used for:

- Proxmox web interface access
- Proxmox host management
- Upstream network access
- Firewall/router WAN interface

The Proxmox management IP is assigned to `vmbr0`.

The firewall/router VM will also connect one virtual NIC to `vmbr0` so it can reach the outside network.

In simple terms:

```text
nic0 -> vmbr0 -> Proxmox management and firewall WAN
```

This bridge should be treated carefully because it is connected to the management side of the lab.

---

## `vmbr1`: Internal SOC LAN

`vmbr1` is the main internal lab bridge.

This bridge is not connected directly to the physical network interface.

It will be used for internal lab systems such as:

- Wazuh SIEM
- Windows endpoint
- Linux endpoint
- Ubuntu analyst workstation
- Active Directory domain controller
- Internal DNS services

The firewall/router VM will act as the gateway for this network.

In simple terms:

```text
vmbr1 = main protected lab network
```

This is where most defended systems will live.

---

## `vmbr2`: Isolated / Untrusted Network

`vmbr2` is planned for isolated or higher-risk systems.

This bridge is not connected directly to the physical network interface.

It may be used for:

- Kali Linux
- Untrusted test systems
- Controlled attack simulation
- Trust-boundary experiments

The firewall/router VM may connect to this bridge through an optional interface.

In simple terms:

```text
vmbr2 = isolated testing network
```

This helps prevent attack simulation systems from sitting directly on the main SOC LAN.

---

## Firewall VM Interface Plan

The firewall/router VM will connect to multiple bridges.

| Firewall Interface | Bridge | Role |
|---|---|---|
| WAN | `vmbr0` | Outside/upstream connection |
| LAN | `vmbr1` | Internal SOC lab network |
| OPT/DMZ | `vmbr2` | Optional isolated/untrusted network |

This firewall VM will control how traffic moves between networks.

---

## Example Traffic Flow

```text
Outside Network
     |
   nic0
     |
   vmbr0
     |
 Firewall VM
   /     \
vmbr1   vmbr2
SOC LAN Isolated Network
```

This design makes the firewall/router VM the control point for lab traffic.

---

## Why `vmbr1` and `vmbr2` Do Not Need Physical Ports

Not every bridge needs to connect to a physical Ethernet port.

A bridge can exist only inside Proxmox.

This is useful because internal lab networks can stay virtual and isolated.

For this lab:

- `vmbr0` connects to the real network through `nic0`.
- `vmbr1` exists inside Proxmox for the internal SOC LAN.
- `vmbr2` exists inside Proxmox for isolated testing.

This allows the lab to simulate enterprise-style networks without needing extra physical network cards at the beginning.

---

## Beginner Explanation

A simple way to understand this design:

```text
nic0 is the real Ethernet port.

vmbr0 is the virtual switch connected to the real Ethernet port.

vmbr1 is an internal virtual switch for normal lab systems.

vmbr2 is another internal virtual switch for isolated or risky systems.
```

VMs connect to these bridges using virtual NICs.

The firewall/router VM connects to more than one bridge so it can route traffic between networks.

---

## Common Mistakes

### Mistake: Thinking `nic0` replaces `vmbr0`

`nic0` is the physical adapter.

`vmbr0` is the bridge that uses it.

The Proxmox management IP should be on the bridge, not treated as a separate VM network card.

### Mistake: Connecting every VM to `vmbr0`

This makes setup easier at first, but it weakens segmentation.

Most lab VMs should not be placed directly on the management/WAN bridge.

### Mistake: Creating bridges without a traffic plan

Bridges should match the lab architecture.

Each bridge should have a clear purpose.

### Mistake: Forgetting the gateway

Internal networks need a gateway if they need access outside their own subnet.

In this design, the firewall/router VM will become the gateway for `vmbr1` and possibly `vmbr2`.

---

## Validation Goals

The bridge design is working when:

- Proxmox remains reachable through `vmbr0`
- The firewall/router VM can connect to `vmbr0`
- Internal lab VMs can connect to `vmbr1`
- Isolated systems can connect to `vmbr2`
- Internal systems use the firewall/router VM as their gateway
- Traffic between networks is controlled by firewall rules

---

## Learning Reflection

Proxmox bridges are one of the most important concepts in this lab.

They determine how virtual machines connect, communicate, and separate from each other.

Understanding bridges helps explain virtual networking, segmentation, firewalls, routing, monitoring, and troubleshooting.

A SOC lab should not only teach tools. It should teach how the network underneath those tools works.
