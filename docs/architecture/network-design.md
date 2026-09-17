# Network Architecture

This document explains the network design of the MutaSpace Enterprise Security Lab.

For step-by-step implementation instructions, see the guides under:

`docs/network/`

---

# 1. Design Goals

The lab network was designed to provide:

- Separation between upstream and internal lab traffic
- A dedicated firewall and gateway
- Predictable infrastructure addressing
- Active Directory-integrated DNS
- Centralized security monitoring
- Support for Windows and Linux endpoints
- Containerized applications
- Student lab environments
- A foundation for future VLAN segmentation

The goal is to model the structure of an enterprise network rather than place every virtual machine directly on the upstream network.

---

# 2. High-Level Topology

```text
                         Internet
                            |
                            v
                    Upstream Network
                            |
                            v
                          vmbr0
                            |
                         pfSense
                            |
                          vmbr1
                            |
                   Internal Lab Network
                            |
          +-----------------+-----------------+
          |                 |                 |
          v                 v                 v
       Identity          Security         Applications
       Services         Monitoring            |
          |                 |                 |
          +--------+--------+--------+--------+
                   |                 |
                   v                 v
                Endpoints        Student Lab
```

---

# 3. Virtual Bridges

The reference architecture uses two primary Proxmox bridges.

## `vmbr0`

Purpose:

- Proxmox management connectivity
- Upstream network access
- pfSense WAN connectivity

Conceptually:

```text
Upstream Network
      |
      v
    vmbr0
      |
      +---- Proxmox Host
      |
      +---- pfSense WAN
```

## `vmbr1`

Purpose:

- Internal enterprise lab network

Conceptually:

```text
               vmbr1
                 |
        +--------+--------+
        |        |        |
        v        v        v
       AD      Wazuh    Endpoints
```

---

# 4. Firewall Boundary

pfSense sits between the upstream network and the internal lab network.

```text
Upstream
   |
   v
pfSense WAN
   |
   | Routing / NAT / Firewall
   v
pfSense LAN
   |
   v
Internal Lab
```

This provides a central control point for:

- Routing
- NAT
- DHCP
- Firewall policy
- Future VLAN routing
- Future segmentation

---

# 5. Internal Addressing

The current reference implementation uses:

```text
10.10.10.0/24
```

with:

```text
10.10.10.1
```

as the internal gateway.

Core infrastructure uses predictable addressing.

Example pattern:

```text
Gateway               10.10.10.1
Directory / DNS        10.10.10.10
Security Monitoring    10.10.10.20
Application Server     10.10.10.30
Container Host         10.10.10.40
Certificate Services   10.10.10.50
```

Client systems may use DHCP.

These addresses are examples from the reference implementation and can be changed in another environment.

---

# 6. DNS Design

Active Directory-integrated DNS is provided by the domain controller.

Domain-joined systems should normally use the internal DNS server rather than a public DNS resolver.

Conceptually:

```text
Windows Endpoint
      |
      | DNS
      v
Active Directory DNS
      |
      +---- Internal domain -> resolve locally
      |
      +---- External domain -> forward upstream
```

This allows internal domain services and external Internet names to resolve through one consistent client configuration.

---

# 7. Why DNS Is Critical

In an Active Directory environment, DNS is part of the identity architecture.

Clients use DNS to locate:

- Domain controllers
- Kerberos services
- LDAP services
- Other internal systems

A machine can have working Internet connectivity and still fail domain operations if its DNS configuration is incorrect.

---

# 8. Routing Model

Traffic between systems on the same subnet can communicate directly at Layer 2.

Traffic leaving the internal subnet is sent to the default gateway.

```text
Internal Host
     |
     v
10.10.10.1
     |
     v
pfSense
     |
     v
Upstream Network
```

---

# 9. NAT

Internal systems use private RFC1918 addresses.

pfSense performs NAT for outbound Internet access.

```text
10.10.10.x
     |
     v
pfSense NAT
     |
     v
Upstream / Internet
```

This allows internal systems to initiate external connections without requiring public IP addresses.

---

# 10. Security Monitoring Traffic

Endpoints send security telemetry to the SIEM over the internal network.

Example:

```text
Endpoint
   |
   | Security Telemetry
   v
Wazuh
```

The monitoring layer depends on working:

- Routing
- DNS
- Service ports
- Endpoint agent configuration

---

# 11. Application Traffic

Application systems remain on the internal network.

Example:

```text
Analyst Workstation
        |
        | HTTP
        v
Application Server
        |
        v
Application Logs
        |
        v
SIEM
```

This provides a controlled environment for generating and analyzing realistic application telemetry.

---

# 12. Container Networking

The container host participates in the internal enterprise network while Docker maintains its own internal bridge network.

Conceptually:

```text
Enterprise Network
       |
       v
Docker Host
       |
       v
Docker Bridge
       |
       +---- Container
       +---- Container
```

Port mappings allow selected container services to be reached from the enterprise network.

---

# 13. Remote Access Traffic

Remote access follows a different path from ordinary internal traffic.

```text
Remote Browser
      |
      v
Cloudflare
      |
      v
Tunnel
      |
      v
Remote Access Gateway
      |
      v
Internal Endpoint
```

The user does not require direct access to:

- Proxmox
- pfSense
- Internal management interfaces
- Public RDP

---

# 14. Current Segmentation State

The current lab primarily operates on a single internal subnet.

This simplifies the initial build and allows the core services to be validated before introducing more complex segmentation.

Logical security roles already exist, but logical role separation is not the same as network isolation.

---

# 15. Future Segmentation

The network is designed to evolve toward separate security zones.

Possible future zones include:

```text
Management
Identity
SOC
Applications
Student Labs
Attack Simulation
Sensors
```

A future architecture might resemble:

```text
                         pfSense
                            |
       +--------------------+--------------------+
       |                    |                    |
       v                    v                    v
   Infrastructure       Applications          Students
                                               |
                                   +-----------+-----------+
                                   |           |           |
                                   v           v           v
                                Team 01     Team 02     Team 03
```

---

# 16. Why Segment Later?

Introducing VLANs too early adds complexity while the builder is still learning basic:

- Addressing
- Routing
- DNS
- Active Directory
- Firewalling

The reference build intentionally follows:

```text
Build a working network
        |
        v
Validate it
        |
        v
Understand traffic flow
        |
        v
Introduce segmentation
```

---

# 17. Future VLAN Design

One possible design could include:

```text
VLAN 10  Management
VLAN 20  Infrastructure
VLAN 30  Applications
VLAN 40  Student Labs
VLAN 50  Security Sensors
```

Team-based student environments could later receive dedicated subnets or VLANs.

The exact VLAN numbering is a design choice rather than a requirement.

---

# 18. Trust Boundaries

The network architecture creates several trust boundaries.

Examples:

```text
Internet
   |
   v
Remote Access Boundary

Upstream Network
   |
   v
Firewall Boundary

Internal Network
   |
   +---- Identity Infrastructure
   +---- Monitoring Infrastructure
   +---- Applications
   +---- Endpoints
```

Future firewall rules should enforce communication based on system role rather than allowing unrestricted east-west traffic.

---

# 19. Validation Philosophy

Network validation should occur before application troubleshooting.

A useful model is:

```text
NIC
 |
 v
IP Address
 |
 v
Subnet
 |
 v
Gateway
 |
 v
Routing
 |
 v
DNS
 |
 v
Service Port
 |
 v
Application
```

If the lower layers fail, troubleshooting the application first wastes time.

---

# 20. Implementation Guides

The step-by-step build process is documented separately under:

`docs/network/`

Recommended sequence:

```text
01. Proxmox Bridges
02. pfSense Network Setup
03. Addressing and DHCP
04. Active Directory DNS
05. Linux Network Configuration
06. Network Validation and Troubleshooting
07. VLAN Segmentation
```

---

# 21. MutaSpace Reference Implementation

The current MutaSpace implementation validates:

- Separate upstream and internal Proxmox bridges
- pfSense routing
- Private internal addressing
- DHCP
- Active Directory-integrated DNS
- Windows and Linux connectivity
- Wazuh telemetry
- Container workloads
- Remote browser-based access

The architecture is intentionally being expanded in stages so each layer can be understood and validated before additional complexity is introduced.

---

# 22. Design Principle

The network should not exist merely to provide Internet connectivity.

It should provide the structure that connects:

```text
Identity
Monitoring
Applications
Endpoints
Remote Access
Training Environments
```

and eventually provide the security boundaries between them.