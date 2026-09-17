# MutaSpace Enterprise Security Lab Documentation

Welcome to the technical documentation for the **MutaSpace Enterprise Security Lab**.

This documentation is designed as a reproducible build guide for creating an enterprise-style cybersecurity environment using virtualization, networking, identity services, security monitoring, endpoints, applications, containers, and remote-access infrastructure.

The documentation follows the same philosophy as the lab:

```text
Build
  |
  v
Understand
  |
  v
Validate
  |
  v
Troubleshoot
  |
  v
Secure
  |
  v
Investigate
```

The goal is not simply to reproduce a collection of virtual machines.

The goal is to understand how enterprise systems depend on one another and how those relationships affect security.

---

# How to Use This Documentation

The documentation can be used in two ways.

## Build the Lab from the Beginning

Follow the sections in approximately this order:

```text
01. Physical Infrastructure
        |
        v
02. Proxmox
        |
        v
03. Networking
        |
        v
04. Identity
        |
        v
05. Security Monitoring
        |
        v
06. Endpoints and Workloads
        |
        v
07. Containers
        |
        v
08. Enterprise PKI
        |
        v
09. Student Lab
        |
        v
10. Remote Access
        |
        v
11. Security Investigations
        |
        v
12. Detection Engineering
```

## Use Individual Sections as References

If the environment already exists, individual guides can also be used independently for:

- Troubleshooting
- Architecture review
- Security validation
- Classroom preparation
- Infrastructure expansion
- Detection development
- Incident investigation

---

# 1. Architecture

Start here to understand how the environment fits together.

Directory:

```text
docs/architecture/
```

## Current Architecture

[`architecture/current-architecture.md`](architecture/current-architecture.md)

Explains:

- Physical infrastructure
- Virtualization
- Network architecture
- Identity services
- Security monitoring
- Endpoints
- Applications
- Containers
- Student environments
- Remote access
- Security telemetry

---

## Network Design

[`architecture/network-design.md`](architecture/network-design.md)

Explains the high-level network architecture and design decisions.

Use this document to understand **why** the network is structured the way it is.

The implementation steps live under:

```text
docs/network/
```

---

## Lab Systems and Roles

[`architecture/lab-systems-and-roles.md`](architecture/lab-systems-and-roles.md)

Explains the purpose of the major systems in the environment and how they interact.

This is useful when trying to understand questions such as:

```text
Why do we need pfSense?

What does the domain controller provide?

Why does Wazuh need endpoint agents?

What belongs on the Docker host?

How does the student environment interact with core infrastructure?
```

---

## Remote Access Architecture

[`architecture/remote-access-architecture.md`](architecture/remote-access-architecture.md)

Explains the browser-based remote-access design using:

- Apache Guacamole
- Docker
- RDP
- Cloudflare Tunnel

The design allows assigned Windows environments to be accessed through a browser without exposing Proxmox or RDP directly to the Internet.

---

# 2. Physical Infrastructure

Directory:

```text
docs/hardware/
```

This section documents the physical platform supporting the virtual lab.

Topics include:

- Hardware selection
- Component roles
- System assembly
- Resource planning
- Hardware validation

Reference platform:

```text
CPU:
AMD Ryzen 9 7900X

Memory:
64 GB DDR5

Storage:
2 TB NVMe

Motherboard:
B650 AORUS Elite AX

Hypervisor:
Proxmox VE
```

The hardware can be adapted to available resources.

The important consideration is having enough compute, memory, and storage for the desired workloads.

---

# 3. Proxmox Virtualization

Directory:

```text
docs/proxmox/
```

This section covers the virtualization layer.

Topics include:

- Proxmox installation
- Initial access
- Host configuration
- Virtual machine creation
- Virtual networking
- Resource allocation
- Snapshots
- Cloning
- Reusable VM deployment

Proxmox acts as the foundation for the rest of the environment.

Conceptually:

```text
Physical Host
      |
      v
Proxmox
      |
      +---- pfSense
      +---- Active Directory
      +---- Wazuh
      +---- Windows
      +---- Linux
      +---- Docker
      +---- PKI
      +---- Student Workstations
```

---

# 4. Networking

Directory:

```text
docs/network/
```

Start with:

[`network/README.md`](network/README.md)

The networking documentation follows this sequence:

```text
01-proxmox-bridges.md
02-pfsense-network-setup.md
03-ip-addressing-and-dhcp.md
04-active-directory-dns.md
05-network-validation-and-troubleshooting.md
```

---

## Proxmox Bridges

[`network/01-proxmox-bridges.md`](network/01-proxmox-bridges.md)

Build the virtual Layer 2 network.

Topics include:

- Physical NICs
- Linux bridges
- `vmbr0`
- `vmbr1`
- Internal virtual networking
- pfSense interface placement

---

## pfSense

[`network/02-pfsense-network-setup.md`](network/02-pfsense-network-setup.md)

Turn the virtual network into a routed network.

Topics include:

- WAN
- LAN
- Routing
- NAT
- Firewalling
- DHCP
- Gateway configuration

---

## IP Addressing and DHCP

[`network/03-ip-addressing-and-dhcp.md`](network/03-ip-addressing-and-dhcp.md)

Topics include:

- Subnets
- `/24`
- Infrastructure addressing
- DHCP
- Gateway validation
- External connectivity
- Initial DNS testing

---

## Active Directory DNS

[`network/04-active-directory-dns.md`](network/04-active-directory-dns.md)

Topics include:

- Internal DNS
- DHCP-provided DNS
- Active Directory name resolution
- SRV records
- Linux DNS behavior
- Windows DNS validation
- Kerberos dependencies

---

## Network Troubleshooting

[`network/05-network-validation-and-troubleshooting.md`](network/05-network-validation-and-troubleshooting.md)

Provides a repeatable troubleshooting workflow:

```text
NIC
 |
 v
IP
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
Port
 |
 v
Application
```

---

# 5. Identity and Active Directory

Directory:

```text
docs/identity/
```

Identity is treated as a major security domain rather than simply another Windows Server feature.

Current documentation includes:

```text
01-identity-fundamentals.md
02-kerberos-authentication.md
03-trust-and-certificates.md
04-adcs-enterprise-root-ca-build.md
```

---

## Identity Fundamentals

Covers the foundational relationship between:

```text
Identity
Authentication
Authorization
Directory Services
Trust
```

---

## Kerberos Authentication

Explains how domain authentication works through:

```text
User
 |
 v
Authentication Service
 |
 v
Ticket Granting Ticket
 |
 v
Service Ticket
 |
 v
Resource
```

This becomes important when analyzing Windows authentication telemetry.

---

## Trust and Certificates

Introduces:

- Digital certificates
- Certificate authorities
- Trust chains
- Public key infrastructure
- Enterprise trust

---

## Active Directory Certificate Services

Documents the enterprise certificate authority implementation.

Current reference implementation includes an Enterprise Certification Authority used for PKI learning and future identity-security exercises.

---

# 6. Security Monitoring

Directory:

```text
docs/wazuh/
```

Wazuh provides centralized security monitoring for the environment.

Current monitoring includes:

- Windows systems
- Linux systems
- Infrastructure servers
- Student workstations
- Application telemetry
- Container telemetry experimentation

---

## Monitoring Flow

```text
Endpoint
   |
   v
Wazuh Agent
   |
   v
Wazuh Manager
   |
   v
Analysis
   |
   v
Dashboard
```

---

## Current Telemetry

The environment can collect and investigate information such as:

- Windows Security events
- Authentication activity
- Linux logs
- Application logs
- File integrity changes
- Security configuration findings
- System inventory
- Endpoint activity

---

## Detection Engineering

Future monitoring work will expand into:

- Sysmon
- Custom Wazuh rules
- Detection tuning
- Threat hunting
- Correlation
- Additional Windows telemetry
- Network telemetry

---

# 7. Endpoints and Application Workloads

The environment includes both Windows and Linux workloads.

These systems are not simply test machines.

They generate the activity and telemetry required for realistic security investigations.

Examples include:

```text
Windows Workstations
Linux Servers
Web Servers
Containerized Applications
Student Workstations
```

---

## Windows

Windows systems support:

- Active Directory
- Authentication testing
- Event Viewer
- Wazuh telemetry
- RDP
- Student investigations
- Group Policy
- Identity scenarios

---

## Linux

Linux systems support:

- SSH
- Web services
- System logging
- Wazuh telemetry
- Network troubleshooting
- Application investigations

---

# 8. Docker and Containers

Directory:

```text
docs/docker/
```

Docker provides a flexible application layer for the lab.

Current technologies include:

```text
Docker Engine
Docker Compose
Portainer
Nginx Containers
Apache Guacamole
```

Containerized workloads provide additional opportunities to practice:

- Service deployment
- Container networking
- Logging
- Monitoring
- Troubleshooting
- Security configuration

---

# 9. Enterprise PKI

PKI currently begins under:

```text
docs/identity/
```

The environment includes Active Directory Certificate Services.

The identity roadmap expands this into:

```text
Certificate Authority
       |
       v
Certificate Templates
       |
       v
Enrollment
       |
       v
Auto-Enrollment
       |
       v
Lifecycle Management
       |
       v
Revocation
       |
       v
CRL / OCSP
       |
       v
Security Assessment
       |
       v
Attack Paths
```

The goal is to understand both PKI administration and PKI security.

---

# 10. Student Cybersecurity Lab

Directory:

```text
docs/student-lab/
```

The student lab provides reusable Windows environments for team-based cybersecurity exercises.

Start with:

[`student-lab/building-a-team-based-cybersecurity-lab.md`](student-lab/building-a-team-based-cybersecurity-lab.md)

---

## Team-Based Environment

The architecture uses independent student workstations:

```text
Student Lab
    |
    +---- Team 01
    |
    +---- Team 02
    |
    +---- Team 03
```

Each workstation can have its own:

- Hostname
- Active Directory identity
- Wazuh identity
- User accounts
- Investigation state
- Remote-access connection

---

## Reusable Windows Image

The Windows deployment process uses a generalized source image to create reusable workstations.

The workflow includes:

```text
Build Windows
     |
     v
Prepare Local Recovery Access
     |
     v
Remove Environment Identity
     |
     v
Prepare Security Agents
     |
     v
Generalize
     |
     v
Clone
     |
     v
Complete OOBE
     |
     v
Assign Unique Identity
     |
     v
Join Active Directory
     |
     v
Enroll Monitoring
     |
     v
Validate
```

---

# 11. Remote Student Access

Remote access is designed around browser-based connectivity.

Architecture:

```text
Student Browser
      |
      v
Cloudflare
      |
      v
Cloudflare Tunnel
      |
      v
Apache Guacamole
      |
      v
RDP
      |
      v
Assigned Windows Workstation
```

This allows students to access lab workstations without:

- Proxmox credentials
- Direct RDP exposure
- VPN software on managed computers
- Access to the hypervisor

The architecture is documented under:

[`architecture/remote-access-architecture.md`](architecture/remote-access-architecture.md)

---

# 12. Security Labs

Directory:

```text
docs/labs/
```

Security labs turn infrastructure into hands-on exercises.

A lab should answer:

```text
What happened?

What evidence exists?

Where should the analyst look?

What is the root cause?

What should be remediated?

How do we prove the remediation worked?
```

---

# 13. Incident Scenarios

Directory:

```text
docs/incident-scenarios/
```

Incident scenarios are designed to create realistic activity for investigation.

Potential scenarios include:

- Failed authentication
- Account misuse
- Suspicious administrative activity
- Web reconnaissance
- Service failure
- Endpoint configuration problems
- Credential abuse
- Unauthorized access attempts

The goal is to connect:

```text
Activity
   |
   v
Telemetry
   |
   v
Detection
   |
   v
Investigation
   |
   v
Response
```

---

# 14. Troubleshooting

Troubleshooting is treated as part of the build process.

The documentation should capture:

```text
Symptom
   |
   v
Evidence
   |
   v
Hypothesis
   |
   v
Test
   |
   v
Root Cause
   |
   v
Fix
   |
   v
Validation
```

Useful troubleshooting lessons should become reproducible technical guidance rather than remaining isolated build notes.

---

# 15. Current Build Status

## Core Infrastructure

```text
[x] Physical virtualization host
[x] Proxmox VE
[x] Virtual networking
[x] pfSense
[x] Internal routing
[x] DHCP
[x] NAT
```

## Identity

```text
[x] Windows Server
[x] Active Directory
[x] Internal DNS
[x] Kerberos
[x] Domain-joined endpoints
[x] Enterprise CA foundation
```

## Security Monitoring

```text
[x] Wazuh manager
[x] Windows monitoring
[x] Linux monitoring
[x] Application telemetry
[x] Student workstation telemetry
[ ] Advanced detection engineering
```

## Applications

```text
[x] Linux application server
[x] Nginx
[x] SSH
```

## Containers

```text
[x] Docker
[x] Docker Compose
[x] Portainer
[x] Nginx container
[x] Apache Guacamole
[x] Container log collection experimentation
```

## Student Lab

```text
[x] Generalized Windows source image
[x] Multiple independent Windows workstations
[x] Active Directory integration
[x] Independent Wazuh identities
[x] Browser-based remote-access proof of concept
[ ] Complete remote-access rollout
[ ] Team network segmentation
[ ] Automated reset workflow
```

## Remote Access

```text
[x] Apache Guacamole
[x] Cloudflare Tunnel
[x] External browser validation
[x] Managed-computer validation
[ ] Cloudflare Access
[ ] Additional access hardening
```

---

# 16. Planned Expansion

Future lab capabilities include:

## Network Security

```text
VLANs
Inter-VLAN Routing
Firewall Segmentation
Wireshark
Suricata
Zeek
```

## Detection Engineering

```text
Sysmon
Custom Wazuh Rules
Threat Hunting
Detection Tuning
```

## Incident Response

```text
Velociraptor
TheHive
Shuffle
Incident Timelines
Analyst Runbooks
After-Action Reviews
```

## Identity Security

```text
Certificate Templates
Auto-Enrollment
CRL
OCSP
AD CS Attack Paths
MFA
SAML
OIDC
OAuth
SSO
Cloud Identity
```

## Controlled Attack Simulation

```text
Kali Linux
Reconnaissance
Authentication Attacks
Credential Abuse
Web Enumeration
Active Directory Security Testing
```

Future capabilities should be documented as implemented only after they are built and validated.

---

# 17. Documentation Standard

Every major implementation guide should try to answer five questions:

## 1. What are we building?

Explain the component or capability.

## 2. Why does it exist?

Explain its enterprise and security purpose.

## 3. How do we build it?

Provide reproducible steps.

## 4. How do we validate it?

Provide commands, tests, and expected behavior.

## 5. What can go wrong?

Document common failure patterns and troubleshooting approaches.

---

# 18. Public Documentation Standard

This repository is designed to be reproducible without exposing operational secrets.

Never commit:

```text
Passwords
Private Keys
API Keys
Cloudflare Tunnel Tokens
Enrollment Secrets
Recovery Codes
Session Tokens
Administrative Credentials
Authentication Cookies
```

Screenshots should also be reviewed before publication.

Check for:

- Credentials
- Tokens
- Email addresses
- Public IP addresses
- Browser session information
- Sensitive configuration
- Private keys
- Recovery information

Use placeholders when necessary.

---

# 19. Documentation vs Operational Notes

This repository is the **public build guide**.

It should contain:

- Architecture
- Concepts
- Reproducible steps
- Commands
- Validation
- Troubleshooting lessons
- Security considerations

Private operational records should be maintained separately.

Examples include:

```text
Current DHCP leases
Exact VM IDs
Current Wazuh agent IDs
Passwords
Recovery procedures
Current snapshot inventory
Temporary fixes
Class-specific account state
Live administrative configuration
```

This separation keeps the public documentation useful without turning the repository into an operational notebook.

---

# 20. Final Goal

The completed environment should allow someone to move through the full security lifecycle:

```text
Build Infrastructure
        |
        v
Create Identity
        |
        v
Deploy Workloads
        |
        v
Collect Telemetry
        |
        v
Generate Security Activity
        |
        v
Detect
        |
        v
Investigate
        |
        v
Respond
        |
        v
Improve
        |
        v
Retest
```

That is the purpose of the MutaSpace Enterprise Security Lab.

It is not just a collection of tools.

It is an environment for learning how enterprise infrastructure behaves, how security controls interact with that infrastructure, and how defenders investigate what happens inside it.