# Building Proxmox Virtual Network Bridges

This guide explains how Proxmox VE network bridges are used to create the network foundation for the MutaSpace Enterprise Security Lab.

A Proxmox Linux bridge functions similarly to a virtual Ethernet switch. Virtual machines connect their virtual network interfaces to bridges, allowing them to communicate with other virtual machines, physical networks, or virtual routers and firewalls.

The reference implementation uses two primary bridges:

- `vmbr0` for Proxmox management and upstream connectivity
- `vmbr1` for the private internal security lab

This creates a network where internal systems communicate through pfSense rather than being placed directly on the upstream network.

---

# 1. What Are We Building?

The target architecture is:

```text
                    Upstream Network
                           |
                           v
                    Physical NIC
                           |
                           v
                         vmbr0
                           |
                  +--------+--------+
                  |                 |
                  v                 v
            Proxmox Host        pfSense WAN
                                    |
                                 pfSense
                                    |
                               pfSense LAN
                                    |
                                    v
                                  vmbr1
                                    |
              +---------------------+---------------------+
              |                     |                     |
              v                     v                     v
          AD / DNS                Wazuh                Endpoints
```

The key design principle is:

> Internal lab systems should not need to connect directly to the upstream network.

Instead, pfSense provides the routing boundary between the internal lab and upstream network.

---

# 2. What Is a Proxmox Bridge?

A bridge connects network interfaces at Layer 2 of the network model.

A physical network might look like:

```text
Computer
   |
   v
Ethernet Switch
   |
   +---- Server
   |
   +---- Another Computer
```

A virtualized environment can accomplish something similar:

```text
Virtual Machine
      |
      v
Proxmox Bridge
      |
      +---- Virtual Machine
      |
      +---- Virtual Firewall
```

The bridge acts like the virtual switch connecting those systems.

---

# 3. Physical NIC vs Virtual Bridge

It is important to distinguish the physical network interface from the bridge.

Conceptually:

```text
Physical NIC
     |
     v
Proxmox Bridge
     |
     +---- Proxmox Host
     |
     +---- Virtual Machines
```

The physical NIC provides the physical connection.

The bridge provides the virtual Layer 2 network that Proxmox and virtual machines can use.

These are related, but they are not the same thing.

---

# 4. Reference Bridge Design

The implemented MutaSpace architecture currently uses:

| Bridge | Physical Port | Role |
|---|---|---|
| `vmbr0` | Upstream physical NIC | Proxmox management and pfSense WAN |
| `vmbr1` | None | Private internal lab network |

The architecture intentionally begins with two bridges.

Additional network segments can be introduced later as segmentation requirements become more advanced.

---

# 5. `vmbr0`: Management and Upstream Connectivity

`vmbr0` connects to the physical network interface on the Proxmox host.

Its responsibilities include:

- Proxmox management connectivity
- Connectivity to the upstream network
- pfSense WAN connectivity

Conceptually:

```text
Upstream Network
       |
       v
Physical NIC
       |
       v
     vmbr0
       |
       +---- Proxmox Management
       |
       +---- pfSense WAN
```

The Proxmox management configuration resides on this side of the architecture.

Because `vmbr0` is connected to the upstream environment, it should be treated differently from the private lab network.

---

# 6. `vmbr1`: Private Internal Lab Network

`vmbr1` provides the main internal network for the cybersecurity environment.

Unlike `vmbr0`, it does not require a physical Ethernet interface.

It exists within the Proxmox host.

Conceptually:

```text
                     vmbr1
                       |
       +---------------+---------------+
       |               |               |
       v               v               v
    AD / DNS          Wazuh          Windows
       |                               |
       +------------- Linux -----------+
```

Systems attached to this bridge can include:

- Domain controllers
- DNS servers
- Wazuh infrastructure
- Analyst workstations
- Windows endpoints
- Linux endpoints
- Application servers
- Container infrastructure
- Certificate services
- Student workstations

---

# 7. Why `vmbr1` Does Not Need a Physical Port

A virtual bridge does not need to connect to a physical network adapter.

Consider:

```text
VM-A
 |
 +----------+
            |
          vmbr1
            |
 +----------+
 |
VM-B
```

Both virtual machines can communicate because they are connected to the same virtual Layer 2 network.

The traffic can remain entirely inside the virtualization environment.

This is useful for cybersecurity labs because it allows isolated networks to be created without purchasing a separate physical network adapter or switch for every network segment.

---

# 8. Connecting pfSense

pfSense connects the two network environments.

The pfSense VM requires two virtual network interfaces for the current architecture:

| pfSense Interface | Proxmox Bridge | Purpose |
|---|---|---|
| WAN | `vmbr0` | Upstream connectivity |
| LAN | `vmbr1` | Internal lab connectivity |

Conceptually:

```text
                    pfSense
                 +-----------+
                 |           |
                WAN         LAN
                 |           |
                 v           v
               vmbr0       vmbr1
                 |           |
                 v           v
             Upstream    Internal Lab
```

This makes pfSense the routing boundary between the two networks.

---

# 9. Why Use pfSense Instead of Connecting Everything to `vmbr0`?

Technically, virtual machines could be attached directly to `vmbr0`.

That architecture might resemble:

```text
Upstream Network
       |
     vmbr0
       |
       +---- Proxmox
       +---- Windows
       +---- Linux
       +---- Wazuh
       +---- Domain Controller
```

This is simple, but it bypasses much of the network architecture we want to learn and control.

The preferred design is:

```text
Upstream Network
       |
     vmbr0
       |
    pfSense
       |
     vmbr1
       |
       +---- Windows
       +---- Linux
       +---- Wazuh
       +---- Active Directory
```

Now the internal environment has its own:

- Gateway
- Firewall
- Routing
- NAT
- DHCP
- Security boundary
- Future segmentation capabilities

---

# 10. Create an Internal Bridge in Proxmox

A bridge can be created from the Proxmox web interface.

Navigate to:

```text
Datacenter
    |
    v
Proxmox Node
    |
    v
System
    |
    v
Network
```

Select:

```text
Create
  |
  v
Linux Bridge
```

For an internal-only bridge, configure the bridge without assigning it a physical bridge port.

Example:

```text
Name:
vmbr1

Bridge ports:
None

Autostart:
Enabled
```

The exact interface options may vary depending on the Proxmox version.

---

# 11. Why the Internal Bridge Does Not Need an IP Address

The Proxmox host does not necessarily need an IP address on every bridge.

For the internal lab:

```text
Proxmox Host
     |
     v
   vmbr1
```

does not need to act as the router.

pfSense performs that role.

Therefore:

```text
pfSense LAN
10.10.10.1/24
```

becomes the Layer 3 gateway for systems connected to `vmbr1`.

The bridge itself primarily provides Layer 2 connectivity.

---

# 12. Apply Network Configuration Carefully

Changing Proxmox networking can affect access to the hypervisor.

Before applying changes:

- Confirm which interface provides management connectivity
- Verify the bridge name
- Verify whether a physical port should be assigned
- Avoid changing `vmbr0` unnecessarily
- Ensure you have a recovery method if management connectivity is lost

Network changes should be treated carefully when Proxmox is being administered remotely.

---

# 13. Attach the pfSense WAN Interface

Open the pfSense VM hardware configuration.

Add or verify a network device connected to:

```text
vmbr0
```

This interface becomes the pfSense WAN side.

Conceptually:

```text
pfSense WAN
     |
     v
   vmbr0
     |
     v
Upstream Network
```

---

# 14. Attach the pfSense LAN Interface

Add another virtual network interface connected to:

```text
vmbr1
```

This becomes the pfSense LAN side.

Conceptually:

```text
pfSense LAN
     |
     v
   vmbr1
     |
     v
Internal Lab
```

The two pfSense interfaces must connect to the correct bridges.

---

# 15. Attach Internal Virtual Machines

Internal systems should connect their primary lab-facing NIC to:

```text
vmbr1
```

In Proxmox:

```text
VM
 |
 v
Hardware
 |
 v
Network Device
 |
 v
Bridge: vmbr1
```

Examples include:

```text
Domain Controller
Wazuh Server
Analyst Workstation
Windows Endpoint
Linux Application Server
Docker Host
Certificate Authority
Student Workstation
```

---

# 16. Internal Traffic Flow

Two systems connected to `vmbr1` and located in the same IP subnet can communicate directly through the virtual bridge.

Example:

```text
Windows Endpoint
10.10.10.x
      |
      v
    vmbr1
      |
      v
Wazuh Server
10.10.10.20
```

Because both systems belong to the same subnet, pfSense does not need to route that specific traffic.

---

# 17. External Traffic Flow

When an internal system needs to reach a different network, it sends the traffic to its default gateway.

For the reference implementation:

```text
Default Gateway:
10.10.10.1
```

Traffic flows:

```text
Internal VM
    |
    v
  vmbr1
    |
    v
pfSense LAN
    |
    v
pfSense Routing / NAT
    |
    v
pfSense WAN
    |
    v
  vmbr0
    |
    v
Upstream Network
```

---

# 18. Understanding Layer 2 and Layer 3

This architecture demonstrates an important networking distinction.

## Layer 2

The Proxmox bridge connects devices on the virtual Ethernet network.

```text
VM
 |
 v
vmbr1
 |
 v
VM
```

## Layer 3

pfSense routes traffic between different IP networks.

```text
Internal Network
       |
       v
    pfSense
       |
       v
External Network
```

A useful mental model is:

> Bridges connect devices within a network. Routers move traffic between networks.

---

# 19. Validate the Bridge Configuration

After creating the bridges, verify them in:

```text
Proxmox
  |
  v
Node
  |
  v
System
  |
  v
Network
```

Confirm:

```text
vmbr0 -> upstream physical interface
vmbr1 -> no physical bridge port
```

Do not assume the configuration is correct simply because both bridges exist.

---

# 20. Validate VM Bridge Assignment

For each VM:

```text
VM
 |
 v
Hardware
 |
 v
Network Device
```

Verify the assigned bridge.

For example:

```text
pfSense WAN -> vmbr0
pfSense LAN -> vmbr1

Domain Controller -> vmbr1
Wazuh -> vmbr1
Windows Endpoint -> vmbr1
Linux Endpoint -> vmbr1
```

---

# 21. Validate the Internal Network

Once pfSense LAN has been configured, test from an internal VM.

Windows:

```powershell
ipconfig /all
ping 10.10.10.1
```

Linux:

```bash
ip addr
ip route
ping -c 2 10.10.10.1
```

The goal is to confirm that the VM:

1. Has an address on the intended subnet
2. Is connected to `vmbr1`
3. Can reach the pfSense gateway

---

# 22. Common Problem: VM Attached to the Wrong Bridge

A VM accidentally connected to `vmbr0` may receive addressing from the upstream network instead of the internal lab.

Symptoms can include:

- Unexpected IP address
- Internal DNS failure
- Domain join failure
- Bypassing pfSense
- Different gateway than expected

Check the VM's Proxmox network device before troubleshooting higher-level services.

---

# 23. Common Problem: Internal VM Has No Connectivity

If a VM attached to `vmbr1` cannot communicate, validate in this order:

```text
VM NIC enabled?
      |
      v
Correct bridge?
      |
      v
Correct IP address?
      |
      v
Correct subnet?
      |
      v
Can reach pfSense LAN?
      |
      v
Correct gateway?
      |
      v
Correct DNS?
```

This prevents application troubleshooting from hiding a basic network configuration problem.

---

# 24. Common Problem: Confusing the Physical NIC with the Bridge

The physical interface provides connectivity to the physical network.

The bridge allows Proxmox and virtual systems to participate in that network.

Conceptually:

```text
Physical Ethernet
       |
       v
Physical NIC
       |
       v
     vmbr0
       |
       +---- Proxmox
       |
       +---- pfSense WAN
```

Do not treat the physical NIC and `vmbr0` as interchangeable concepts.

---

# 25. Common Problem: Giving Every VM Upstream Access

Attaching every VM directly to `vmbr0` may appear convenient during initial setup.

However, doing so can bypass:

- pfSense
- Internal DHCP
- Internal routing policy
- Future segmentation controls

Unless a system specifically requires upstream-side connectivity, internal lab systems should remain behind the firewall.

---

# 26. Current vs Future Architecture

The current implemented bridge architecture is:

```text
vmbr0
  |
  v
pfSense
  |
  v
vmbr1
```

A separate untrusted bridge is **not currently part of the implemented environment**.

Future security work may introduce additional:

- Bridges
- VLANs
- Subnets
- Firewall interfaces
- Student networks
- Attack-simulation networks
- Sensor networks

Those controls should be documented as implemented only after they are actually built and validated.

---

# 27. Why Add Segmentation Later?

Starting with two bridges makes it easier to understand the fundamentals:

```text
Physical Interface
        |
        v
Virtual Bridge
        |
        v
Virtual Firewall
        |
        v
Internal Bridge
        |
        v
Virtual Machines
```

Once that traffic flow is understood and validated, the architecture can evolve into:

```text
Firewall
   |
   +---- Infrastructure
   |
   +---- Student Labs
   |
   +---- Applications
   |
   +---- Security Sensors
   |
   +---- Attack Simulation
```

The goal is to introduce complexity intentionally rather than simply creating additional networks.

---

# 28. Validation Checklist

Before considering the bridge layer complete:

```text
[ ] Proxmox management remains reachable
[ ] vmbr0 is connected to the intended upstream interface
[ ] vmbr1 exists
[ ] vmbr1 does not require a physical bridge port
[ ] pfSense WAN is connected to vmbr0
[ ] pfSense LAN is connected to vmbr1
[ ] Internal VMs are connected to vmbr1
[ ] Internal VMs receive or use the intended addressing
[ ] Internal VMs can reach the pfSense LAN gateway
[ ] Internal systems do not require direct vmbr0 connectivity
```

---

# 29. MutaSpace Reference Implementation

The MutaSpace Enterprise Security Lab currently uses:

```text
vmbr0
```

for Proxmox management and pfSense upstream connectivity, and:

```text
vmbr1
```

for the private enterprise security lab.

The internal bridge currently supports systems providing:

- Active Directory
- DNS
- Wazuh monitoring
- Windows endpoints
- Linux services
- Container infrastructure
- Certificate services
- Student lab workstations

pfSense provides the gateway between the internal lab and upstream network.

Additional network segmentation is planned as the environment develops, but it is intentionally not represented as an already implemented control.

---

# 30. Design Principle

The important lesson is not simply how to create a Linux bridge in Proxmox.

It is understanding the relationship between:

```text
Physical Networking
        |
        v
Virtual Switching
        |
        v
Routing / Firewalling
        |
        v
Virtual Systems
```

Once those relationships are understood, more advanced concepts such as VLANs, firewall segmentation, attack networks, network sensors, and controlled student environments become much easier to design and troubleshoot.