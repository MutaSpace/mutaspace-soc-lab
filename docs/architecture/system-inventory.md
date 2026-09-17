# MutaSpace Enterprise Security Lab System Inventory

This document maintains the current asset inventory for the MutaSpace Enterprise Security Lab.

It records the systems that are actually deployed in the environment, their roles, network identities, security monitoring status, access classification, and operational purpose.

> **Inventory rule:** Planned systems are not added to the operational inventory until they have been deployed and validated.

---

# 1. Inventory Overview

The environment currently consists of:

- 1 dedicated physical virtualization host
- 1 virtual firewall/router
- 2 Windows Server infrastructure systems
- 1 centralized Wazuh SIEM
- 1 analyst workstation
- 1 primary Windows security endpoint
- 1 Linux application server
- 1 Docker infrastructure server
- 3 student investigation workstations

Primary virtualization host:

```text
mutaspace-soc-node01
```

Primary internal network:

```text
10.10.10.0/24
```

Active Directory domain:

```text
mutaspace.local
```

---

# 2. Physical Host Inventory

## `mutaspace-soc-node01`

| Attribute | Value |
|---|---|
| Asset Type | Physical Server |
| Role | Primary Virtualization Host |
| Hypervisor | Proxmox VE |
| Motherboard | B650 AORUS Elite AX |
| Processor | AMD Ryzen 9 7900X |
| Memory | 64 GB DDR5 |
| Storage | 2 TB NVMe SSD |
| Power Supply | 850W |
| Case | Corsair 3500X |
| Cooling | Arctic Liquid Freezer III Pro 360 |
| Administrative Access | Instructor / Administrator Only |
| Operational Status | Operational |
| Criticality | Critical |

### Purpose

The physical host provides the compute foundation for the entire enterprise security environment.

A failure of this system can affect:

- Firewall services
- Active Directory
- DNS
- PKI
- SIEM
- Application infrastructure
- Student environments
- Remote lab access

---

# 3. Operational VM Inventory

| Asset | Platform | IP Address | Primary Role | Monitoring | Access | Status |
|---|---|---:|---|---|---|---|
| `fw-01` | pfSense | `10.10.10.1` | Firewall / Router | Infrastructure | Admin Only | Operational |
| `dc-01` | Windows Server 2022 | `10.10.10.10` | AD DS / DNS | Wazuh | Admin Only | Operational |
| `wazuh-01` | Ubuntu | `10.10.10.20` | SIEM | Self / Wazuh | Admin Only | Operational |
| `analyst-01` | Ubuntu Desktop | DHCP / observed `10.10.10.103` | Analyst Workstation | Wazuh | Analyst / Admin | Operational |
| `ubuntu-app-01` | Ubuntu Server | `10.10.10.30` | Application Server | Wazuh | Admin / Lab | Operational |
| `docker-01` | Ubuntu Server 24.04 | `10.10.10.40` | Container Infrastructure | Wazuh | Admin / Service | Operational |
| `ca-01` | Windows Server 2022 | `10.10.10.50` | Enterprise CA | Identity Infrastructure | Admin Only | Operational |
| `win-client-01` | Windows 10 Pro | DHCP / observed `10.10.10.105` | Security Test Endpoint | Wazuh | Admin / Lab | Operational |
| `HELPDESK-TEAM01` | Windows 10 Pro | DHCP | Student Investigation Endpoint | Wazuh 006 | Team 01 | Operational |
| `HELPDESK-TEAM02` | Windows 10 Pro | DHCP | Student Investigation Endpoint | Wazuh 008 | Team 02 | Operational |
| `HELPDESK-TEAM03` | Windows 10 Pro | DHCP | Student Investigation Endpoint | Wazuh 007 | Team 03 | Operational |

> DHCP addresses marked as observed should not be treated as permanent infrastructure assignments until reservations or static addressing are configured.

---

# 4. Core Infrastructure

## `fw-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Core Infrastructure
Criticality: Critical
Student Access: Prohibited
```

### Platform

```text
Operating System: pfSense
IP Address: 10.10.10.1
```

### Roles

- Default gateway
- Firewall
- Internal routing
- DHCP
- Upstream connectivity

### Dependencies

`fw-01` provides network connectivity for the SOC environment.

Systems dependent on it include:

- `dc-01`
- `wazuh-01`
- `analyst-01`
- `ubuntu-app-01`
- `docker-01`
- `ca-01`
- Windows endpoints
- Student workstations

### Operational Status

```text
Status: Operational
```

Health validation has included:

- Interface availability
- Gateway connectivity
- Routing
- Storage health
- Memory review
- Swap utilization

---

## `dc-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Core Infrastructure
Criticality: Critical
Student Administrative Access: Prohibited
```

### Platform

```text
Operating System: Windows Server 2022
IP Address: 10.10.10.10
Domain: mutaspace.local
```

### Roles

- Active Directory Domain Services
- DNS
- Kerberos authentication
- Domain identity
- Group Policy

### Monitoring

```text
Wazuh Agent: Enrolled
Status: Active
```

### Important Windows Security Events

The system provides authentication and identity telemetry including:

```text
4624 - Successful logon
4625 - Failed logon
4648 - Explicit credential usage
4720 - User account creation
4768 - Kerberos TGT request
4769 - Kerberos service ticket request
```

### Dependencies

Critical dependencies include:

- `fw-01`
- Internal DNS
- Proxmox host

Systems dependent on `dc-01` include all domain-joined Windows systems.

---

## `wazuh-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Security Infrastructure
Criticality: Critical
Student Administrative Access: Prohibited
```

### Platform

```text
Operating System: Ubuntu
IP Address: 10.10.10.20
```

### Roles

- Wazuh Manager
- Wazuh Indexer
- Wazuh Dashboard
- Agent enrollment
- Security telemetry collection
- Security event analysis

### Important Services / Ports

Current Wazuh agent communication includes:

```text
TCP 1514 - Agent communication
TCP 1515 - Agent enrollment
```

### Monitoring Scope

Current monitored assets include:

```text
analyst-01
dc-01
win-client-01
ubuntu-app-01
docker-01
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

### Student Endpoint Mapping

```text
006 -> HELPDESK-TEAM01
007 -> HELPDESK-TEAM03
008 -> HELPDESK-TEAM02
```

---

# 5. Identity Infrastructure

## `ca-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Identity Infrastructure
Criticality: High
Student Administrative Access: Prohibited
```

### Platform

```text
Operating System: Windows Server 2022
IP Address: 10.10.10.50
Domain: mutaspace.local
```

### Role

```text
Active Directory Certificate Services
Enterprise Certification Authority
```

### Certification Authority

```text
MutaSpace Enterprise Root CA
```

### Current Purpose

Provides the PKI foundation for:

- Certificate enrollment
- Certificate templates
- Certificate lifecycle management
- Certificate trust
- Future auto-enrollment
- Revocation testing
- AD CS security assessment
- Certificate attack-path analysis

### Status

```text
Domain Joined: Yes
AD CS Installed: Yes
Enterprise CA: Operational
```

---

# 6. Analyst Infrastructure

## `analyst-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Analyst
Criticality: Medium
```

### Platform

```text
Operating System: Ubuntu Desktop
Addressing: DHCP
Observed Address: approximately 10.10.10.103
```

### Roles

- SOC analyst workstation
- Wazuh Dashboard access
- Investigation
- Security validation
- Internal testing
- Traffic generation
- Classroom demonstrations

### Monitoring

```text
Wazuh Agent: Enrolled
Status: Active
```

### Design Purpose

The analyst workstation remains separate from `wazuh-01` so analyst activity occurs from a dedicated workstation rather than directly from the SIEM server.

---

# 7. Application Infrastructure

## `ubuntu-app-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Application
Criticality: Medium
```

### Platform

```text
Operating System: Ubuntu Server
IP Address: 10.10.10.30
```

### Services

- Nginx
- SSH
- Wazuh Agent

### Monitored Logs

```text
/var/log/nginx/access.log
/var/log/nginx/error.log
```

### Validated Test Activity

Application traffic has included requests to:

```text
/admin
/login
/backup
/phpmyadmin
/.env
/.git
```

These requests provide controlled reconnaissance-style telemetry for log analysis and future detection engineering.

### Monitoring

```text
Wazuh Agent: Enrolled
Status: Active
```

### Baseline

Recommended baseline snapshot:

```text
ubuntu-app-01-baseline-fall-2026
```

Snapshot status should be verified in Proxmox.

---

# 8. Container Infrastructure

## `docker-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Application / Security Infrastructure
Criticality: High
Student Direct Administrative Access: Prohibited
```

### Platform

```text
Operating System: Ubuntu Server 24.04
IP Address: 10.10.10.40
Memory: approximately 7.8 GB
Disk: approximately 39 GB
```

### Services

- Docker Engine
- Docker Compose
- Portainer
- Nginx test workload
- Apache Guacamole
- Cloudflare Tunnel
- Wazuh Agent

### Docker Version

At validation:

```text
Docker Engine: 29.6.2
Docker Compose: v5.3.1
```

### Wazuh

```text
Agent ID: 005
Status: Active
```

### Nginx Test Container

```text
Container Name: web-test
Image: nginx:alpine
Host Port: 8080
Container Port: 80
```

Internal service access:

```text
http://10.10.10.40:8080
```

### Portainer

Management interface:

```text
HTTPS
Port: 9443
```

### Guacamole

Role:

```text
Browser-based remote desktop gateway
```

Guacamole brokers RDP sessions between remote users and assigned Windows investigation endpoints.

### Cloudflare Tunnel

Role:

```text
Secure outbound connection between the lab and Cloudflare
```

The tunnel allows the Guacamole service to be reached without directly exposing internal services through inbound router port forwarding.

Public lab hostname:

```text
lab.mutaspacesoc.com
```

### Network Configuration Note

`docker-01` previously experienced a dual-IP condition caused by:

```text
/etc/netplan/00-installer-config.yaml
```

and:

```text
/etc/netplan/50-cloud-init.yaml
```

being active simultaneously.

The cloud-init DHCP configuration was disabled and the intended static configuration was retained.

---

# 9. Primary Windows Security Endpoint

## `win-client-01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Endpoint
Criticality: Medium
```

### Platform

```text
Operating System: Windows 10 Pro
Build: 19045
Addressing: DHCP
Observed Address: 10.10.10.105
```

### Roles

- Domain endpoint
- Authentication testing
- Windows security telemetry
- Group Policy testing
- Security investigation
- Source image for student lab development

### Identity

```text
Domain: mutaspace.local
Domain Joined: Yes
```

### Monitoring

```text
Wazuh Agent: Enrolled
Status: Active
```

### Preservation Note

The original endpoint should be preserved as a known-good security testing system rather than continuously modified for student cloning.

---

# 10. Student Lab

The student environment currently contains three Windows investigation endpoints.

## Student Asset Summary

| System | Domain | Wazuh ID | Student Account | Remote Access | Status |
|---|---|---:|---|---|---|
| `HELPDESK-TEAM01` | `mutaspace.local` | 006 | `Team01` | Guacamole / RDP | Operational |
| `HELPDESK-TEAM02` | `mutaspace.local` | 008 | `Team02` | Pending final configuration | Operational |
| `HELPDESK-TEAM03` | `mutaspace.local` | 007 | `Team03` | Pending final configuration | Operational |

---

## `HELPDESK-TEAM01`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Student Lab
Criticality: Low
Assigned Team: Team 01
```

### Platform

```text
Operating System: Windows 10 Pro
Hostname: HELPDESK-TEAM01
Domain: mutaspace.local
```

### Accounts

```text
Local Student Account: Team01
Local Instructor Recovery Account: LabAdmin
```

### Monitoring

```text
Wazuh Agent ID: 006
Agent Name: HELPDESK-TEAM01
Status: Active
```

### Remote Access

```text
RDP: Enabled
Browser Gateway: Apache Guacamole
External Access: Validated
```

End-to-end access has been successfully tested from a school-managed computer outside the home network.

---

## `HELPDESK-TEAM02`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Student Lab
Criticality: Low
Assigned Team: Team 02
```

### Platform

```text
Operating System: Windows 10 Pro
Hostname: HELPDESK-TEAM02
Domain: mutaspace.local
```

### Accounts

```text
Local Student Account: Team02
Local Instructor Recovery Account: LabAdmin
```

### Monitoring

```text
Wazuh Agent ID: 008
Agent Name: HELPDESK-TEAM02
Status: Active
```

### Remote Access

```text
Browser access configuration: Pending
```

---

## `HELPDESK-TEAM03`

### Classification

```text
Asset Type: Virtual Machine
Security Zone: Student Lab
Criticality: Low
Assigned Team: Team 03
```

### Platform

```text
Operating System: Windows 10 Pro
Hostname: HELPDESK-TEAM03
Domain: mutaspace.local
```

### Accounts

```text
Local Student Account: Team03
Local Instructor Recovery Account: LabAdmin
```

### Monitoring

```text
Wazuh Agent ID: 007
Agent Name: HELPDESK-TEAM03
Status: Active
```

### Remote Access

```text
Browser access configuration: Pending
```

---

# 11. Student Golden Image

## `helpdesk-template-prep`

### Classification

```text
Asset Type: Generalized VM Master
Purpose: Student Windows workstation deployment
Boot Status: MUST REMAIN POWERED OFF
```

### Build State

The master image has been:

- Removed from the Active Directory domain
- Placed in `WORKGROUP`
- Cleaned of Sysprep-blocking AppX packages
- Generalized using Sysprep
- Shut down after successful generalization

### Important Handling Rule

> Do not boot `helpdesk-template-prep` as a normal workstation.

It exists as the generalized source for future student workstation deployments.

### Known Clone Considerations

New clones require unique:

- Hostname
- Windows identity
- Student account
- Active Directory computer membership
- Wazuh agent name
- Wazuh enrollment key

Wazuh identity should always be validated before the service is started on a newly cloned system.

---

# 12. Security Zones

Current logical asset classifications are:

```text
CORE INFRASTRUCTURE
├── fw-01
├── dc-01
└── wazuh-01

IDENTITY INFRASTRUCTURE
└── ca-01

ANALYST
└── analyst-01

APPLICATION INFRASTRUCTURE
├── ubuntu-app-01
└── docker-01

SECURITY ENDPOINTS
└── win-client-01

STUDENT LAB
├── HELPDESK-TEAM01
├── HELPDESK-TEAM02
└── HELPDESK-TEAM03

TEMPLATES
└── helpdesk-template-prep
```

These classifications describe current logical roles.

They should not be interpreted as proof of complete network segmentation. Additional VLAN and firewall isolation remains planned.

---

# 13. Access Classification

| Classification | Intended Access |
|---|---|
| Critical Infrastructure | Administrator only |
| Identity Infrastructure | Administrator only |
| Security Infrastructure | Administrator / authorized analyst |
| Analyst Systems | Authorized analyst |
| Application Systems | Administrator / controlled lab activity |
| Security Endpoints | Administrator / controlled lab activity |
| Student Endpoints | Assigned student team |
| Golden Images | Administrator only |

Students should never receive direct administrative access to:

```text
mutaspace-soc-node01
fw-01
dc-01
wazuh-01
ca-01
docker-01
```

---

# 14. External Services

## Student Lab Domain

```text
mutaspacesoc.com
```

## Remote Lab Hostname

```text
lab.mutaspacesoc.com
```

### Service Path

```text
Internet
   |
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
   v
Assigned Windows Endpoint
```

No Cloudflare Tunnel tokens, passwords, private keys, API credentials, or other authentication secrets should be stored in this repository.

---

# 15. Credential and Secret Handling

The following information must never be committed to GitHub:

- Passwords
- Wazuh enrollment keys
- Cloudflare Tunnel tokens
- API keys
- Private certificate keys
- Recovery codes
- Authentication cookies
- Session tokens
- SSH private keys
- Proxmox authentication secrets

Documentation may describe the enrollment or authentication process without recording the actual secret.

Example:

```text
Agent ID: 006
Agent Name: HELPDESK-TEAM01
Enrollment Key: [REDACTED]
```

---

# 16. Resource Allocation Tracking

Resource allocation should be verified directly in Proxmox before being treated as authoritative.

| Asset | vCPU | RAM | Disk | Verified |
|---|---:|---:|---:|---|
| `fw-01` | TBD | TBD | TBD | No |
| `dc-01` | TBD | TBD | TBD | No |
| `wazuh-01` | TBD | TBD | TBD | No |
| `analyst-01` | TBD | TBD | TBD | No |
| `ubuntu-app-01` | TBD | TBD | TBD | No |
| `docker-01` | TBD | ~7.8 GB | ~39 GB | Partial |
| `ca-01` | TBD | TBD | TBD | No |
| `win-client-01` | TBD | TBD | TBD | No |
| `HELPDESK-TEAM01` | TBD | TBD | TBD | No |
| `HELPDESK-TEAM02` | TBD | TBD | TBD | No |
| `HELPDESK-TEAM03` | TBD | TBD | TBD | No |


---

# 17. Snapshot and Recovery Tracking

| Asset | Baseline Snapshot | Status |
|---|---|---|
| `fw-01` | TBD | Verify |
| `dc-01` | TBD | Verify |
| `wazuh-01` | TBD | Verify |
| `analyst-01` | TBD | Verify |
| `ubuntu-app-01` | `ubuntu-app-01-baseline-fall-2026` | Verify |
| `docker-01` | TBD | Verify |
| `ca-01` | TBD | Verify |
| `win-client-01` | TBD | Verify |
| `HELPDESK-TEAM01` | TBD | Needed |
| `HELPDESK-TEAM02` | TBD | Needed |
| `HELPDESK-TEAM03` | TBD | Needed |

Snapshots should be created at known-good milestones before destructive labs or major configuration changes.

---

# 18. Dependency Overview

```text
mutaspace-soc-node01
        |
        +-- fw-01
        |     |
        |     +-- SOC network connectivity
        |
        +-- dc-01
        |     |
        |     +-- Active Directory
        |     +-- DNS
        |     +-- Kerberos
        |
        +-- ca-01
        |     |
        |     +-- Enterprise PKI
        |
        +-- wazuh-01
        |     |
        |     +-- Central telemetry
        |
        +-- docker-01
        |     |
        |     +-- Containers
        |     +-- Guacamole
        |     +-- Cloudflare Tunnel
        |
        +-- Student Endpoints
              |
              +-- Active Directory
              +-- DNS
              +-- Wazuh
              +-- Guacamole / RDP
```

This dependency model is important when evaluating failures.

For example:

```text
dc-01 failure
    ->
DNS and authentication impact

wazuh-01 failure
    ->
central monitoring impact

docker-01 failure
    ->
Guacamole and remote student access impact

fw-01 failure
    ->
network connectivity impact

mutaspace-soc-node01 failure
    ->
potential entire lab outage
```

---

# 19. Inventory Maintenance Procedure

Update this inventory whenever:

1. A new system is deployed
2. A system is decommissioned
3. An IP address changes
4. A Wazuh agent is added or removed
5. A system changes security zones
6. Remote access is enabled
7. Resource allocations change
8. A baseline snapshot is created
9. A major service is added
10. A system's operational status changes

Every inventory change should be committed to Git so the history of the environment remains traceable.

---

# 20. Inventory Status Definitions

## Operational

The system has been deployed, configured, tested, and is currently available for its intended role.

## Partially Operational

The system is deployed and provides some intended functionality, but one or more planned capabilities remain incomplete.

## Maintenance

The system is intentionally unavailable while configuration, repair, or upgrades are being performed.

## Offline

The system is unavailable and is not currently providing its intended service.

## Template

The asset exists as a deployment source and should not operate as a normal production-style VM.

## Planned

The asset has not yet been deployed.

Planned assets belong in the roadmap rather than the operational inventory.