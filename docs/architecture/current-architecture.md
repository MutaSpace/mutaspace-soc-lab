# Current Architecture

This document describes the current operational architecture of the MutaSpace Enterprise Security Lab.

It reflects systems and services that are deployed and actively used today. Planned components are documented separately in the project roadmap.

---

# 1. Physical Host

The entire environment runs on a dedicated custom-built virtualization host.

## Official Lab Host

| Component | Specification |
|---|---|
| Hostname | `mutaspace-soc-node01` |
| Hypervisor | Proxmox VE |
| Motherboard | B650 AORUS Elite AX |
| CPU | AMD Ryzen 9 7900X |
| Memory | 64 GB DDR5 |
| Storage | 2 TB NVMe SSD |
| Power Supply | 850W |
| Case | Corsair 3500X |
| CPU Cooling | Arctic Liquid Freezer III Pro 360 |

The host provides compute resources for:

- Firewall and routing
- Active Directory
- DNS
- PKI
- SIEM
- Analyst workstations
- Windows endpoints
- Linux application servers
- Container infrastructure
- Remote access services
- Student investigation systems

---

# 2. Architecture Overview

```text
                           INTERNET
                              |
                              |
                     Cloudflare Network
                              |
                       HTTPS / Tunnel
                              |
                              v
                     +----------------+
                     |   docker-01    |
                     |----------------|
                     | Docker Engine  |
                     | Portainer      |
                     | Guacamole      |
                     | cloudflared    |
                     +--------+-------+
                              |
                              | RDP
                              |
               +--------------+--------------+
               |              |              |
               v              v              v
      HELPDESK-TEAM01 HELPDESK-TEAM02 HELPDESK-TEAM03
               |
               |
+---------------------------------------------------------------+
|                    SOC INTERNAL NETWORK                       |
|                       10.10.10.0/24                            |
|                                                               |
|                         fw-01                                 |
|                        pfSense                                |
|                     10.10.10.1                               |
|                           |                                   |
|       +-------------------+-------------------+               |
|       |                   |                   |               |
|       v                   v                   v               |
|     dc-01              wazuh-01             ca-01             |
| AD DS / DNS              SIEM               AD CS             |
| 10.10.10.10           10.10.10.20        10.10.10.50          |
|       |                   ^                                   |
|       |                   |                                   |
|       +-------------------+--------------------------------+  |
|                           |                                |  |
|                           | Endpoint telemetry             |  |
|                           |                                |  |
|              +------------+------------+                   |  |
|              |            |            |                   |  |
|              v            v            v                   |  |
|         analyst-01   win-client-01 ubuntu-app-01            |  |
|                                     10.10.10.30             |  |
|                                                               |
|                           docker-01                            |
|                         10.10.10.40                            |
+---------------------------------------------------------------+
```

---

# 3. Network Architecture

## Internal Network

```text
Network: 10.10.10.0/24
Gateway: 10.10.10.1
Internal DNS: 10.10.10.10
Domain: mutaspace.local
```

## Virtual Bridges

### `vmbr0`

Purpose:

- Proxmox host management
- Upstream connectivity
- WAN-side connectivity for pfSense

### `vmbr1`

Purpose:

- Internal SOC network
- Communication between enterprise systems
- Endpoint-to-server traffic
- Wazuh telemetry
- Student investigation environments

---

# 4. Firewall and Routing

## `fw-01`

Platform:

`pfSense`

Primary role:

- Internal gateway
- Firewall
- Routing
- DHCP
- Upstream internet access

Internal address:

```text
10.10.10.1
```

The pfSense VM separates the SOC network from upstream connectivity and provides the routing foundation for the environment.

Current validation includes:

- Gateway reachability
- Internal routing
- Internet access
- DHCP functionality
- DNS forwarding path
- VM-to-VM communication

---

# 5. Identity Infrastructure

## `dc-01`

Platform:

Windows Server 2022

Address:

```text
10.10.10.10
```

Roles:

- Active Directory Domain Services
- DNS
- Kerberos authentication
- Domain identity
- Group Policy

Domain:

```text
mutaspace.local
```

Current capabilities:

- Domain user authentication
- Domain computer authentication
- Kerberos ticketing
- Internal DNS resolution
- Domain-joined Windows endpoints
- Group Policy processing

Critical services include:

```text
NTDS
DNS
Netlogon
KDC
DFSR
W32Time
```

---

# 6. PKI Architecture

## `ca-01`

Platform:

Windows Server 2022

Address:

```text
10.10.10.50
```

Role:

Active Directory Certificate Services

Current CA:

```text
MutaSpace Enterprise Root CA
```

Current capabilities:

- Enterprise CA deployment
- Active Directory integration
- Certificate services foundation

Planned extensions include:

- Certificate templates
- Manual enrollment
- Auto-enrollment
- Certificate lifecycle management
- CRLs
- OCSP
- AD CS security assessment
- Certificate abuse scenarios

---

# 7. Security Monitoring

## `wazuh-01`

Platform:

Ubuntu Server

Address:

```text
10.10.10.20
```

Role:

Central SIEM and security monitoring platform

Current Wazuh components include:

- Wazuh Manager
- Wazuh Indexer
- Wazuh Dashboard
- Agent management
- Security Configuration Assessment
- File Integrity Monitoring
- Rootcheck
- System inventory
- Windows event collection
- Linux log collection
- Application log collection

Current monitored systems include:

```text
dc-01
analyst-01
win-client-01
ubuntu-app-01
docker-01
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

Student Wazuh identities:

```text
006 - HELPDESK-TEAM01
007 - HELPDESK-TEAM03
008 - HELPDESK-TEAM02
```

---

# 8. SOC Analyst Workstation

## `analyst-01`

Platform:

Ubuntu Desktop

Role:

SOC analyst workstation

Current uses:

- Wazuh dashboard access
- Investigation
- Internal testing
- Web traffic generation
- Security validation
- Analyst workflow simulation

The analyst workstation is intentionally separate from the SIEM server so investigations can be performed from the perspective of an analyst accessing centralized telemetry.

---

# 9. Windows Security Endpoint

## `win-client-01`

Platform:

Windows 10 Pro

Role:

Primary Windows security testing endpoint

Current capabilities:

- Domain membership
- Active Directory authentication
- Group Policy
- Windows Event Viewer
- Wazuh endpoint monitoring
- Authentication telemetry generation
- Endpoint security testing

Observed Windows security events include:

```text
4624 - Successful logon
4625 - Failed logon
4648 - Explicit credential usage
4768 - Kerberos TGT request
4769 - Kerberos service ticket request
4771 - Kerberos pre-authentication failure
```

This endpoint is used to generate and investigate Windows authentication activity.

---

# 10. Linux Application Server

## `ubuntu-app-01`

Platform:

Ubuntu Server

Address:

```text
10.10.10.30
```

Services:

- Nginx
- SSH
- Wazuh Agent

Current monitored application logs:

```text
/var/log/nginx/access.log
/var/log/nginx/error.log
```

Validated activity includes:

- HTTP 200 responses
- HTTP 404 responses
- Web requests
- Sensitive-path enumeration tests
- Wazuh ingestion of Nginx telemetry

Example test paths:

```text
/admin
/login
/backup
/phpmyadmin
/.env
/.git
```

The system provides a controlled application workload for web log analysis and future detection engineering exercises.

---

# 11. Container Infrastructure

## `docker-01`

Platform:

Ubuntu Server

Address:

```text
10.10.10.40
```

Role:

Container and application infrastructure host

Current services:

- Docker Engine
- Docker Compose
- Portainer
- Nginx test container
- Apache Guacamole
- Cloudflare Tunnel
- Wazuh Agent

## Docker Network

Docker uses an internal bridge network in addition to the SOC network.

Example:

```text
SOC LAN:
10.10.10.0/24

docker-01:
10.10.10.40

Docker bridge:
172.17.0.0/16
```

Port mapping allows external lab systems to reach containerized services.

Example:

```text
docker-01:8080
        |
        v
web-test container:80
        |
        v
Nginx
```

---

# 12. Container Log Collection

Docker currently uses:

```text
json-file
```

as the container logging driver.

Container logs are stored under:

```text
/var/lib/docker/containers/
```

Wazuh log collection has been configured to monitor selected Docker JSON logs.

Testing with `wazuh-logtest` confirmed:

```text
Phase 1 - Pre-decoding
Phase 2 - JSON decoding
Phase 3 - Rule evaluation
```

The current Docker/Nginx telemetry is successfully decoded as JSON but currently maps to generic Wazuh rules.

This creates a future detection engineering objective:

> Build custom decoding and detection logic that extracts the security meaning of containerized Nginx traffic.

---

# 13. Student Lab Architecture

The environment currently contains three student Help Desk investigation workstations.

```text
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

Each system has:

- Unique Windows identity
- Unique hostname
- Active Directory membership
- Student-facing local account
- Instructor recovery account
- Unique Wazuh enrollment
- Independent endpoint telemetry
- Remote Desktop enabled

## Template Build Process

The student machines were created using:

```text
win-client-01
      |
      v
helpdesk-template-prep
      |
      | Sysprep /generalize
      v
Generalized Windows Master
      |
      +--------+--------+
      |        |        |
      v        v        v
   TEAM01   TEAM02   TEAM03
```

Each clone was independently:

1. Named
2. Network validated
3. Joined to `mutaspace.local`
4. Assigned a unique Wazuh agent name
5. Assigned a unique Wazuh key
6. Validated as Active in the Wazuh Manager

---

# 14. Remote Access Architecture

The student environment can now be accessed remotely using a web browser.

## External Flow

```text
School-Managed Computer
         |
         | HTTPS
         v
lab.mutaspacesoc.com
         |
         v
Cloudflare Network
         |
   Cloudflare Tunnel
         |
         v
docker-01
         |
   Apache Guacamole
         |
         | RDP
         v
HELPDESK-TEAM0X
```

## Public Domain

```text
mutaspacesoc.com
```

Student lab hostname:

```text
lab.mutaspacesoc.com
```

## Security Benefits

This design avoids directly exposing:

- Proxmox
- RDP port 3389
- pfSense
- Wazuh
- SSH
- Internal SOC addresses

to the public Internet.

The Cloudflare connector establishes an outbound tunnel from the lab infrastructure.

Apache Guacamole then brokers browser-based RDP sessions to the assigned internal Windows endpoint.

---

# 15. Student Access Flow

Current Team 01 proof-of-concept:

```text
Student browser
       |
       v
lab.mutaspacesoc.com
       |
       v
Guacamole authentication
       |
       v
HELPDESK-TEAM01 connection
       |
       v
RDP authentication
       |
       v
Windows desktop
```

This complete path has been successfully tested from a school-managed computer outside the home environment.

No Tailscale client or RDP software was required on the school computer.

---

# 16. Trust Boundaries

The architecture contains several important trust boundaries.

## Boundary 1: Internet to Lab

Controlled through:

- Cloudflare
- HTTPS
- Cloudflare Tunnel

## Boundary 2: Remote Access Gateway to Endpoint

Controlled through:

- Guacamole authentication
- Assigned connections
- RDP authentication

## Boundary 3: Windows Endpoint to Active Directory

Controlled through:

- Active Directory identity
- DNS
- Kerberos
- Domain membership

## Boundary 4: Endpoint to SIEM

Controlled through:

- Wazuh agent identity
- Enrollment keys
- Manager communication

## Boundary 5: Proxmox Management

Proxmox administration remains separate from student browser access.

Students do not require direct Proxmox administration to interact with assigned endpoint systems.

---

# 17. Current Security Considerations

The current architecture is operational but will continue to be hardened.

Planned improvements include:

- Cloudflare Access policy
- Stronger external identity controls
- Team-specific Guacamole permissions
- Network isolation between student teams
- VLANs
- Separate team subnets
- pfSense ACLs
- Additional student role restrictions
- Credential rotation procedures
- Automated reset procedures

---

# 18. Current Validation Status

| Component | Validation |
|---|---|
| Proxmox host | Passed |
| pfSense | Passed |
| Active Directory | Passed |
| DNS | Passed |
| Kerberos | Passed |
| Wazuh Manager | Passed |
| Windows Wazuh agents | Passed |
| Linux Wazuh agents | Passed |
| Nginx telemetry | Passed |
| Docker Engine | Passed |
| Docker container access | Passed |
| Portainer | Passed |
| Apache Guacamole | Passed |
| Windows RDP | Passed |
| Cloudflare Tunnel | Passed |
| External browser access | Passed |
| School-managed computer test | Passed |

---

# 19. Planned Architecture Expansion

Future systems may include:

```text
sensor-01
Splunk
Zeek
Suricata
Velociraptor
Kali Linux
Microsoft Sentinel
Microsoft Entra ID
Okta
TheHive
Shuffle
additional Windows endpoints
additional Linux workloads
team-specific student networks
```

Planned components will not be represented as operational until deployed and validated.

---

# 20. Architecture Principle

The architecture follows a simple rule:

> A system is not considered operational simply because it is installed.

Each component must be:

1. Deployed
2. Configured
3. Connected
4. Tested
5. Monitored
6. Documented
7. Troubleshot when necessary
8. Validated from the perspective of the user or analyst who will depend on it