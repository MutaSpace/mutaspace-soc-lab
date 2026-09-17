# MutaSpace Enterprise Security Lab

A hands-on enterprise cybersecurity lab built to practice, teach, and document security operations, identity, networking, monitoring, incident investigation, and infrastructure security.

The environment is built on **Proxmox VE** and models a small enterprise network containing:

- Active Directory
- DNS
- Kerberos
- Enterprise PKI
- Windows and Linux endpoints
- Wazuh SIEM
- pfSense
- Docker
- Web application workloads
- Browser-based student lab access
- Reusable team investigation environments

This repository documents how the environment is designed, built, validated, troubleshot, and expanded.

The goal is not simply to install security tools.

The goal is to understand how the systems interact.

---

# Project Philosophy

The MutaSpace lab follows a simple process:

```text
Build it
   |
   v
Understand it
   |
   v
Validate it
   |
   v
Break it
   |
   v
Investigate it
   |
   v
Document it
   |
   v
Teach it
```

Security technologies become more useful when they are connected to the infrastructure around them.

For example:

```text
User authentication
        |
        v
Active Directory
        |
        v
Windows Security Event
        |
        v
Wazuh
        |
        v
SOC Investigation
```

The lab is designed to make those relationships visible.

---

# What This Lab Is Built For

The environment supports hands-on work across several security domains.

## Security Operations

- Centralized endpoint monitoring
- Windows event analysis
- Linux log analysis
- Authentication investigations
- File integrity monitoring
- Security configuration assessment
- Alert investigation
- Detection engineering

## Identity and Access Management

- Active Directory
- Kerberos
- DNS
- Group Policy
- Domain authentication
- Enterprise PKI
- Certificate services
- Future SSO and cloud identity scenarios

## Network Security

- Firewalling
- Routing
- NAT
- DHCP
- Internal DNS
- Network troubleshooting
- Future VLAN segmentation
- Future IDS/IPS monitoring

## Security Engineering

- Proxmox virtualization
- Windows Server
- Linux administration
- Docker
- Container networking
- Remote access architecture
- Reusable workstation deployment

## Cybersecurity Education

- Team-based investigation labs
- Help Desk troubleshooting
- SOC escalation
- Windows Event Viewer
- SIEM analysis
- Authentication troubleshooting
- Live security demonstrations

---

# Official Lab Host

The environment runs on a dedicated custom-built virtualization host.

| Component | Specification |
|---|---|
| Motherboard | B650 AORUS Elite AX |
| Processor | AMD Ryzen 9 7900X |
| Memory | 64 GB DDR5 |
| Storage | 2 TB NVMe SSD |
| Power Supply | 850W |
| Case | Corsair 3500X |
| CPU Cooling | Arctic Liquid Freezer III Pro 360 |
| Hypervisor | Proxmox VE |

The host provides compute resources for:

- Enterprise infrastructure
- Security monitoring
- Identity services
- Application workloads
- Containers
- Student workstations
- Remote lab access
- Future detection and incident-response tooling

---

# High-Level Architecture

```text
                           Internet
                              |
                              v
                     External Access Layer
                              |
                              v
                       Remote Gateway
                              |
                              v
+----------------------------------------------------------------+
|                 MUTASPACE ENTERPRISE SECURITY LAB               |
|                                                                |
|                         pfSense                                |
|                    Firewall / Gateway                          |
|                            |                                   |
|          +-----------------+-----------------+                 |
|          |                 |                 |                 |
|          v                 v                 v                 |
|       Identity          Monitoring       Applications           |
|          |                 |                 |                 |
|          |                 |                 |                 |
|          +---------+-------+-------+---------+                 |
|                    |               |                           |
|                    v               v                           |
|                Endpoints       Student Lab                     |
|                    |               |                           |
|                    +-------+-------+                           |
|                            |                                   |
|                            v                                   |
|                     Security Telemetry                         |
+----------------------------------------------------------------+
```

The current environment connects networking, identity, endpoints, applications, monitoring, and remote-access infrastructure into one lab.

---

# Current Technology Stack

## Virtualization

```text
Proxmox VE
```

Used for:

- Virtual machines
- Virtual networking
- Snapshots
- Cloning
- Resource pools
- Infrastructure management

---

## Networking

```text
pfSense
Proxmox Linux Bridges
```

Current network design includes:

```text
vmbr0 -> Upstream / Management
vmbr1 -> Internal Enterprise Lab
```

The internal reference subnet is:

```text
10.10.10.0/24
```

---

## Identity

```text
Windows Server
Active Directory Domain Services
DNS
Kerberos
Group Policy
```

Reference domain:

```text
mutaspace.local
```

---

## Enterprise PKI

```text
Active Directory Certificate Services
```

The environment includes an Enterprise Certification Authority for certificate and trust-based security work.

---

## Security Monitoring

```text
Wazuh
```

Current capabilities include:

- Windows event collection
- Linux log collection
- File Integrity Monitoring
- Security Configuration Assessment
- Rootcheck
- System inventory
- Authentication telemetry
- Application telemetry

---

## Applications

```text
Ubuntu Server
Nginx
SSH
```

The application layer provides realistic server-side telemetry for investigation and detection exercises.

---

## Containers

```text
Docker
Docker Compose
Portainer
```

Containerized services are used for:

- Web workloads
- Remote access
- Infrastructure services
- Security experimentation

---

## Remote Lab Access

```text
Apache Guacamole
Cloudflare Tunnel
RDP
```

This allows users to access assigned Windows environments through a browser without requiring direct Proxmox access or exposing RDP publicly.

---

# Current Lab Capabilities

The environment currently supports:

- Internal virtual networking
- Firewall routing
- DHCP
- Active Directory
- Active Directory-integrated DNS
- Kerberos authentication
- Windows domain joins
- Enterprise certificate services
- Windows endpoint monitoring
- Linux endpoint monitoring
- Application log collection
- Docker infrastructure
- Container telemetry experimentation
- Team-based Windows lab workstations
- Wazuh monitoring for student endpoints
- Browser-based remote Windows access
- External lab access from managed computers

---

# Student Cybersecurity Lab

A reusable team-based student environment has been added to the larger enterprise lab.

The design uses:

```text
Generalized Windows Golden Image
             |
             +----------+----------+
             |          |          |
             v          v          v
          Team 01    Team 02    Team 03
```

Each deployed workstation receives its own:

- Windows identity
- Hostname
- Active Directory computer object
- Wazuh identity
- User context
- Remote-access connection

The goal is to provide systems students can investigate and modify without giving them unnecessary access to the infrastructure hosting the lab.

---

# Browser-Based Student Access

The current remote-access design is:

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
Apache Guacamole
      |
      | RDP
      v
Assigned Windows Endpoint
```

This design avoids directly exposing:

- Proxmox
- pfSense
- RDP
- SSH
- Wazuh administration
- Internal infrastructure

The browser-based access path has been validated from a managed computer outside the home network.

---

# Repository Structure

```text
mutaspace-soc-lab/
|
├── README.md
|
└── docs/
    |
    ├── README.md
    |
    ├── architecture/
    │   ├── current-architecture.md
    │   ├── network-design.md
    │   ├── lab-systems-and-roles.md
    │   └── remote-access-architecture.md
    |
    ├── hardware/
    |
    ├── proxmox/
    |
    ├── network/
    │   ├── README.md
    │   ├── 01-proxmox-bridges.md
    │   ├── 02-pfsense-network-setup.md
    │   ├── 03-ip-addressing-and-dhcp.md
    │   ├── 04-active-directory-dns.md
    │   └── 05-network-validation-and-troubleshooting.md
    |
    ├── identity/
    |
    ├── wazuh/
    |
    ├── docker/
    |
    ├── student-lab/
    │   ├── building-a-team-based-cybersecurity-lab.md
    │   └── windows-golden-image.md
    |
    ├── troubleshooting/
    |
    ├── labs/
    |
    └── incident-scenarios/
```

Some sections will expand as additional lab components are implemented.

---

# Build Path

If you want to build a similar environment, follow the project in layers.

```text
01. Physical Host
        |
        v
02. Proxmox
        |
        v
03. Virtual Networking
        |
        v
04. pfSense
        |
        v
05. IP Addressing + DHCP
        |
        v
06. Active Directory + DNS
        |
        v
07. Wazuh
        |
        v
08. Windows Endpoint
        |
        v
09. Linux Workloads
        |
        v
10. Docker
        |
        v
11. Enterprise PKI
        |
        v
12. Student Workstations
        |
        v
13. Remote Access
        |
        v
14. Security Investigations
        |
        v
15. Detection Engineering
```

Each layer should be validated before moving to the next.

---

# Start Here

## Architecture

Understand the overall design:

[`docs/architecture/current-architecture.md`](docs/architecture/current-architecture.md)

Learn what each system does:

[`docs/architecture/lab-systems-and-roles.md`](docs/architecture/lab-systems-and-roles.md)

Review the network design:

[`docs/architecture/network-design.md`](docs/architecture/network-design.md)

Review the remote-access architecture:

[`docs/architecture/remote-access-architecture.md`](docs/architecture/remote-access-architecture.md)

---

# Network Build

Start the network implementation here:

[`docs/network/README.md`](docs/network/README.md)

The current networking sequence is:

1. Proxmox virtual bridges
2. pfSense
3. IP addressing and DHCP
4. Active Directory DNS
5. Network validation and troubleshooting

---

# Student Lab

Build reusable team environments:

[`docs/student-lab/building-a-team-based-cybersecurity-lab.md`](docs/student-lab/building-a-team-based-cybersecurity-lab.md)

Build a reusable Windows image:

[`docs/student-lab/windows-golden-image.md`](docs/student-lab/windows-golden-image.md)

---

# Validation Philosophy

A system is not considered complete because it installed successfully.

Every component should have an explicit validation step.

Examples:

```text
Can the client reach the gateway?

Can internal DNS resolve?

Can Windows locate the domain controller?

Can the workstation join Active Directory?

Can the Wazuh agent connect independently?

Can the application generate logs?

Can those logs reach the SIEM?

Can the remote gateway reach the endpoint?

Can an external user reach the assigned lab?
```

This helps distinguish:

```text
Installed
```

from:

```text
Operational
```

---

# Troubleshooting Philosophy

Troubleshooting is part of the project rather than something hidden from the documentation.

A useful workflow is:

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
Remediation
   |
   v
Validation
```

Examples encountered during the build have included:

- DNS misconfiguration
- Multiple Linux IP addresses
- Windows Sysprep failures
- AppX provisioning conflicts
- Duplicate monitoring identities after cloning
- Interrupted VM clone operations
- RDP authentication failures
- Remote-access troubleshooting

These failures are useful because they demonstrate how the environment behaves when something is wrong.

---

# Current Project Status

## Infrastructure

- [x] Dedicated physical lab host
- [x] Proxmox VE
- [x] Internal virtual network
- [x] pfSense
- [x] DHCP
- [x] Internal routing and NAT

## Identity

- [x] Active Directory
- [x] DNS
- [x] Kerberos
- [x] Domain-joined Windows systems
- [x] Enterprise PKI foundation

## Monitoring

- [x] Wazuh
- [x] Windows monitoring
- [x] Linux monitoring
- [x] Application telemetry
- [x] Student workstation telemetry
- [ ] Advanced custom detections

## Applications and Containers

- [x] Linux application server
- [x] Nginx
- [x] Docker
- [x] Docker Compose
- [x] Portainer
- [x] Container log collection experimentation

## Student Lab

- [x] Windows golden image
- [x] Multiple student workstations
- [x] Active Directory integration
- [x] Independent Wazuh enrollment
- [x] Browser-based remote-access proof of concept
- [ ] Complete remote-access rollout to all teams
- [ ] Network-level team segmentation
- [ ] Automated reset workflow

## Remote Access

- [x] Apache Guacamole
- [x] Cloudflare Tunnel
- [x] External browser validation
- [x] Managed-computer validation
- [ ] Cloudflare Access policy
- [ ] Additional access hardening

---

# Roadmap

The project will continue expanding in stages.

## Detection Engineering

Planned areas include:

- Sysmon
- Custom Wazuh rules
- Additional Windows telemetry
- Detection tuning
- Threat-hunting exercises

## Network Visibility

Planned technologies include:

- Wireshark
- Suricata
- Zeek
- Network traffic analysis

## Incident Response

Future capabilities may include:

- Velociraptor
- TheHive
- Shuffle
- Incident timelines
- Analyst runbooks
- After-action reviews

## Identity Security

Planned work includes:

- Certificate templates
- Auto-enrollment
- Revocation
- AD CS security assessment
- Certificate attack paths
- SSO
- SAML
- OIDC
- OAuth
- MFA
- Cloud identity

## Attack Simulation

Controlled attack simulation will be introduced to validate defensive monitoring.

Potential future systems and scenarios include:

- Kali Linux
- Authentication attacks
- Credential abuse
- Reconnaissance
- Web enumeration
- Active Directory attack paths

All testing will remain inside controlled lab environments.

---

# Public Documentation and Security

This repository intentionally documents architecture and implementation without publishing operational secrets.

The following should never be committed:

```text
Passwords
API tokens
Enrollment keys
Cloudflare tunnel tokens
Private certificate keys
SSH private keys
Recovery codes
Session tokens
Administrative credentials
```

Placeholders are used where sensitive values would otherwise appear.

---

# MutaSpace

MutaSpace is focused on creating practical learning opportunities around technology, cybersecurity, infrastructure, and professional development.

The MutaSpace Enterprise Security Lab serves as a hands-on environment for:

- Building
- Experimenting
- Troubleshooting
- Teaching
- Security investigation
- Technical documentation

A dedicated public site for the SOC lab is also being developed separately from the technical repository.

---

# Project Principle

The purpose of this repository is not to show a collection of installed tools.

It is to demonstrate how to:

> **Design, build, connect, troubleshoot, monitor, investigate, secure, document, and teach an enterprise security environment.**