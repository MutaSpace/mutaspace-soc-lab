# Network Design

This document describes the current network architecture of the MutaSpace Enterprise Security Lab.

It separates the **current operational design** from the **planned segmentation model** so that deployed infrastructure is not confused with future architecture.

---

# 1. Network Overview

The current lab operates primarily on a single internal SOC network:

```text
Network: 10.10.10.0/24
Gateway: 10.10.10.1
Internal DNS: 10.10.10.10
Active Directory Domain: mutaspace.local
```

The network is hosted within Proxmox and routed through a virtual pfSense firewall.

Current design goals include:

- Centralized routing
- Controlled internet access
- Internal DNS
- Active Directory communication
- Wazuh telemetry transport
- Application testing
- Remote student access
- Future network segmentation
- Future attack and defense scenarios

---

# 2. Physical and Virtual Network Layers

The lab uses a dedicated Proxmox virtualization host:

```text
mutaspace-soc-node01
```

Proxmox provides virtual network bridges that connect virtual machines to management, upstream, and internal SOC networks.

Current bridges include:

```text
vmbr0
vmbr1
```

---

# 3. Current Virtual Bridges

## `vmbr0`

### Purpose

`vmbr0` provides the upstream-facing side of the lab architecture.

Current uses include:

- Proxmox host management
- Connectivity to the upstream/home network
- WAN-side connectivity for pfSense

Conceptually:

```text
Upstream Network
      |
      v
    vmbr0
      |
      +---- Proxmox Management
      |
      +---- pfSense WAN
```

Students should not receive direct access to this network layer.

---

## `vmbr1`

### Purpose

`vmbr1` provides the internal SOC network.

Current network:

```text
10.10.10.0/24
```

This bridge connects most internal enterprise security systems.

Conceptually:

```text
                       vmbr1
                         |
        +----------------+----------------+
        |                |                |
        v                v                v
      dc-01           wazuh-01         docker-01
        |
        +------------------------------------------+
        |                 |                        |
        v                 v                        v
   win-client-01     ubuntu-app-01         student endpoints
```

---

# 4. Firewall and Gateway

## `fw-01`

Platform:

```text
pfSense
```

Internal address:

```text
10.10.10.1
```

Roles:

- Default gateway
- Firewall
- Routing
- DHCP
- Internet access
- Network policy foundation

The firewall separates the internal SOC network from upstream connectivity.

Current internal systems use:

```text
Default Gateway: 10.10.10.1
```

---

# 5. Current Internal Addressing

## Infrastructure Systems

| System | IP Address | Address Type | Role |
|---|---:|---|---|
| `fw-01` | `10.10.10.1` | Static | Firewall / Gateway |
| `dc-01` | `10.10.10.10` | Static | AD DS / DNS |
| `wazuh-01` | `10.10.10.20` | Static | SIEM |
| `ubuntu-app-01` | `10.10.10.30` | Static | Application Server |
| `docker-01` | `10.10.10.40` | Static | Container Infrastructure |
| `ca-01` | `10.10.10.50` | Static | Enterprise CA |

## Dynamic / Endpoint Systems

| System | Addressing | Observed Address | Role |
|---|---|---:|---|
| `analyst-01` | DHCP | `10.10.10.103` | Analyst Workstation |
| `win-client-01` | DHCP | `10.10.10.105` | Windows Endpoint |
| `HELPDESK-TEAM01` | DHCP | Dynamic | Student Endpoint |
| `HELPDESK-TEAM02` | DHCP | Dynamic | Student Endpoint |
| `HELPDESK-TEAM03` | DHCP | Dynamic | Student Endpoint |

Observed DHCP addresses should not be treated as permanent until DHCP reservations or static assignments are configured.

---

# 6. DNS Architecture

## Internal DNS

Primary internal DNS server:

```text
dc-01
10.10.10.10
```

Domain:

```text
mutaspace.local
```

Domain-joined systems should use:

```text
10.10.10.10
```

as their primary DNS resolver.

This allows clients to resolve:

- Active Directory domain records
- Domain controllers
- Internal servers
- Kerberos service records
- Internal application names

Examples:

```text
dc-01.mutaspace.local
wazuh-01.mutaspace.local
ubuntu-app-01.mutaspace.local
```

---

# 7. External DNS Resolution

Internal clients use `dc-01` for DNS.

External DNS requests are forwarded upstream.

Conceptually:

```text
Client
  |
  v
dc-01 DNS
  |
  +---- Internal zone? ----> Answer locally
  |
  +---- External name? ----> Forward upstream
```

This keeps Active Directory name resolution centralized while still supporting internet access.

---

# 8. DHCP

DHCP is currently provided through pfSense.

Dynamic systems may receive addresses within the internal SOC network:

```text
10.10.10.0/24
```

DHCP is currently used for systems such as:

- Analyst workstation
- Windows endpoints
- Student endpoints

Infrastructure systems use static addressing.

---

# 9. Routing Model

The current routing path is:

```text
Internal VM
    |
    v
vmbr1
    |
    v
fw-01
10.10.10.1
    |
    v
Upstream Network
    |
    v
Internet
```

Examples of validated paths include:

```text
HELPDESK-TEAM01
      |
      v
10.10.10.1
      |
      v
Internet
```

and:

```text
analyst-01
      |
      v
ubuntu-app-01
10.10.10.30
```

---

# 10. Active Directory Traffic

Domain-joined Windows systems communicate with:

```text
dc-01
10.10.10.10
```

for:

- DNS
- Kerberos
- LDAP
- Group Policy
- Domain authentication
- Computer account validation

Conceptually:

```text
Windows Endpoint
      |
      +---- DNS --------+
      |
      +---- Kerberos ---+
      |
      +---- LDAP -------+
      |
      +---- Group Policy
      |
      v
    dc-01
```

---

# 11. Wazuh Communication

Wazuh agents communicate with:

```text
wazuh-01
10.10.10.20
```

Important ports currently include:

```text
TCP 1514 - Agent communication
TCP 1515 - Agent enrollment
```

Conceptually:

```text
Endpoint
   |
   | Security telemetry
   v
wazuh-01:1514
```

Agent enrollment uses:

```text
Endpoint
   |
   v
wazuh-01:1515
```

Current student agents include:

```text
006 - HELPDESK-TEAM01
007 - HELPDESK-TEAM03
008 - HELPDESK-TEAM02
```

---

# 12. Application Traffic

## Nginx Application Server

`ubuntu-app-01` hosts Nginx on:

```text
10.10.10.30
TCP 80
```

Traffic flow:

```text
analyst-01
     |
     | HTTP
     v
ubuntu-app-01:80
     |
     v
Nginx
```

This server is used for:

- HTTP testing
- Web log analysis
- Security telemetry
- Reconnaissance simulations
- Detection engineering

---

# 13. Docker Networking

## docker-01

Address:

```text
10.10.10.40
```

Docker also maintains an internal bridge network.

Example:

```text
Docker bridge:
172.17.0.0/16
```

Conceptual traffic path:

```text
SOC Network
10.10.10.0/24
     |
     v
docker-01
10.10.10.40
     |
     v
Docker Bridge
172.17.0.0/16
     |
     v
Container
```

---

# 14. Docker Port Mapping

Containerized services may be exposed through Docker port mapping.

Example:

```text
docker-01:8080
      |
      v
web-test:80
```

This means:

```text
Host Port: 8080
Container Port: 80
```

External lab systems connect to:

```text
http://10.10.10.40:8080
```

Docker forwards the traffic to the Nginx container.

---

# 15. Portainer

Portainer provides Docker management over:

```text
TCP 9443
```

Portainer is considered administrative infrastructure and should not be directly exposed to students.

---

# 16. Guacamole Remote Access

Apache Guacamole is hosted on `docker-01`.

Internal access currently uses:

```text
http://10.10.10.40:8081/guacamole
```

Guacamole brokers browser-based RDP connections to student Windows systems.

Conceptually:

```text
Browser
   |
   v
Guacamole
   |
   | RDP
   v
HELPDESK-TEAM0X
```

---

# 17. Remote Access Architecture

The public student lab hostname is:

```text
lab.mutaspacesoc.com
```

Current flow:

```text
Remote Browser
      |
      | HTTPS
      v
Cloudflare
      |
      v
Cloudflare Tunnel
      |
      v
docker-01
      |
      v
Apache Guacamole
      |
      | RDP
      v
Assigned Windows Endpoint
```

This allows school-managed computers to access the lab without:

- Tailscale
- Local RDP clients
- Proxmox access
- VPN software
- Direct exposure of TCP 3389

---

# 18. Cloudflare Tunnel

The Cloudflare Tunnel connector runs from `docker-01`.

The connector establishes an outbound session to Cloudflare.

This avoids inbound port forwarding from the public internet into the home network.

Conceptually:

```text
docker-01
    |
    | outbound encrypted tunnel
    v
Cloudflare
```

Students then access:

```text
https://lab.mutaspacesoc.com
```

Cloudflare forwards requests through the tunnel to Guacamole.

---

# 19. Public Exposure Model

The current design intentionally does not directly publish:

```text
Proxmox TCP 8006
RDP TCP 3389
SSH TCP 22
Wazuh
pfSense
Active Directory
Docker management ports
```

Instead:

```text
Internet
   |
   v
Cloudflare
   |
   v
Guacamole
   |
   v
Internal Windows endpoint
```

This reduces direct exposure of core lab infrastructure.

---

# 20. Current Student Network Model

The three student systems currently exist on the same internal SOC network:

```text
10.10.10.0/24
```

Current systems:

```text
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

At present, these systems are logically separated through:

- Unique hostnames
- Unique accounts
- Unique Wazuh identities
- Guacamole connection assignment

They are **not yet fully isolated at the network layer**.

This is a known design limitation.

---

# 21. Current Student Trust Model

Current access separation is primarily identity-based:

```text
Guacamole user team01
      |
      v
HELPDESK-TEAM01

Guacamole user team02
      |
      v
HELPDESK-TEAM02

Guacamole user team03
      |
      v
HELPDESK-TEAM03
```

Future architecture will add network-based segmentation.

---

# 22. Planned Student Network Segmentation

The future student architecture will separate each team into its own subnet.

Example planned model:

```text
TEAM 1
10.10.21.0/24

TEAM 2
10.10.22.0/24

TEAM 3
10.10.23.0/24
```

Conceptually:

```text
                    pfSense
                       |
          +------------+------------+
          |            |            |
          v            v            v
       TEAM 1        TEAM 2        TEAM 3
   10.10.21.0/24 10.10.22.0/24 10.10.23.0/24
```

---

# 23. Planned VLAN Model

Potential future VLAN structure:

| VLAN | Purpose | Example Network |
|---:|---|---|
| 10 | Core Infrastructure | `10.10.10.0/24` |
| 20 | Analyst Systems | TBD |
| 21 | Student Team 01 | `10.10.21.0/24` |
| 22 | Student Team 02 | `10.10.22.0/24` |
| 23 | Student Team 03 | `10.10.23.0/24` |
| 30 | Application / Server Network | TBD |
| 40 | Attack / Testing Network | TBD |
| 50 | Monitoring / Sensor Network | TBD |

These VLANs are planned and should not be treated as currently deployed.

---

# 24. Planned Firewall Policy

Future pfSense policies should support:

```text
Student Team -> Assigned Domain Services
Student Team -> DNS
Student Team -> Required Application Services
Student Team -> Wazuh
Student Team -> Internet as needed
```

while restricting:

```text
Team 01 -> Team 02
Team 01 -> Team 03

Team 02 -> Team 01
Team 02 -> Team 03

Team 03 -> Team 01
Team 03 -> Team 02
```

except where a specific lab intentionally requires cross-team communication.

---

# 25. Planned Core Infrastructure Protection

Student systems should not receive unrestricted network access to:

```text
Proxmox
pfSense administration
Wazuh administration
AD CS administration
Docker administration
Cloudflare Tunnel configuration
```

Where communication is required, access should be limited to the necessary service ports.

---

# 26. Planned Security Zones

Future logical zones may include:

```text
MANAGEMENT
CORE INFRASTRUCTURE
IDENTITY
SOC
APPLICATION
STUDENT
ATTACK
SENSOR
CLOUD
```

Example:

```text
Management
    |
    v
Proxmox / pfSense

Core
    |
    +-- dc-01
    +-- wazuh-01
    +-- ca-01

Application
    |
    +-- ubuntu-app-01
    +-- docker-01

Student
    |
    +-- Team 01
    +-- Team 02
    +-- Team 03

Attack
    |
    +-- future Kali systems

Sensor
    |
    +-- future Zeek / Suricata
```

---

# 27. Planned Network Monitoring

Future monitoring expansion includes:

- Zeek
- Suricata
- Packet capture
- IDS/IPS
- DNS monitoring
- NetFlow-style analysis
- East-west traffic analysis

Potential architecture:

```text
Traffic
   |
   +---- Normal destination
   |
   +---- Mirrored / monitored traffic
             |
             v
         sensor-01
        /         \
      Zeek      Suricata
        \         /
             |
             v
          SIEM
```

---

# 28. Network Validation Procedures

A system should not be considered network-ready simply because it receives an IP address.

Validation should include:

## Interface

```bash
ip addr
```

or:

```powershell
ipconfig /all
```

## Gateway

```text
Ping 10.10.10.1
```

## DNS Server

```text
Ping 10.10.10.10
```

## Internal DNS

Example:

```text
Resolve dc-01.mutaspace.local
```

## External IP Connectivity

Example:

```text
Ping 1.1.1.1
```

## External DNS

Example:

```text
Resolve microsoft.com
```

## Service-Specific Ports

Examples:

```text
Wazuh: 1514
Enrollment: 1515
RDP: 3389
HTTP: 80
HTTPS: 443
Guacamole: 8081 internal
Portainer: 9443
```

---

# 29. Example Windows Validation

```powershell
ipconfig /all

Test-Connection 10.10.10.1 -Count 2
Test-Connection 10.10.10.10 -Count 2
Test-Connection 10.10.10.20 -Count 2

Resolve-DnsName dc-01.mutaspace.local
Resolve-DnsName microsoft.com

Test-NetConnection 10.10.10.20 -Port 1514
Test-NetConnection 10.10.10.20 -Port 1515
```

---

# 30. Example Linux Validation

```bash
ip -br addr

ip route

resolvectl status

ping -c 3 10.10.10.1
ping -c 3 10.10.10.10
ping -c 3 10.10.10.20
ping -c 3 1.1.1.1

getent hosts dc-01.mutaspace.local
getent hosts google.com
```

---

# 31. Known Network Issues Resolved

## docker-01 Dual Addressing

### Symptom

`docker-01` had two addresses:

```text
10.10.10.40
10.10.10.107
```

and multiple default routes.

### Cause

Two Netplan configurations were active:

```text
00-installer-config.yaml
50-cloud-init.yaml
```

The first configured static addressing.

The second enabled DHCP.

### Resolution

The cloud-init configuration was disabled.

The intended configuration retained:

```text
Address: 10.10.10.40/24
Gateway: 10.10.10.1
DNS: 10.10.10.10
Search Domain: mutaspace.local
```

### Validation

Confirmed:

- Single IPv4 address
- Single default route
- Internal connectivity
- Internet connectivity
- Internal DNS
- External DNS

---

# 32. Remote RDP Validation

Before enabling Guacamole access, RDP was validated independently.

Example:

```text
docker-01
    |
    | TCP 3389
    v
HELPDESK-TEAM01
```

Successful TCP connectivity confirmed that the network path was functional before Guacamole authentication was investigated.

This prevented an application authentication issue from being misdiagnosed as a network problem.

---

# 33. Network Troubleshooting Philosophy

Network troubleshooting should proceed by layer.

Example:

```text
Is the VM running?
       |
       v
Does it have an IP?
       |
       v
Does it have a route?
       |
       v
Can it reach the gateway?
       |
       v
Can it reach the destination IP?
       |
       v
Does DNS resolve?
       |
       v
Is the destination port open?
       |
       v
Does the application authenticate?
```

This approach helps distinguish:

```text
Network failure
```

from:

```text
Application failure
```

or:

```text
Authentication failure
```

---

# 34. Network Security Principle

The current design follows the principle:

> Connectivity should be validated before application troubleshooting, and access should be restricted to the minimum paths required for each system's role.

The long-term architecture will continue moving from a functional flat lab network toward a segmented enterprise-style design with clearly defined trust boundaries and controlled east-west traffic.