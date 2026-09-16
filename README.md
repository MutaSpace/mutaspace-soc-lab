# MutaSpace Enterprise Security Lab

The MutaSpace Enterprise Security Lab is a custom-built, Proxmox-based enterprise cybersecurity environment designed for hands-on security operations, SOC engineering, identity, networking, detection engineering, incident investigation, and cybersecurity instruction.

The lab is built on Proxmox VE and models a small enterprise environment with centralized identity, network security, endpoint telemetry, SIEM monitoring, application infrastructure, PKI, containerized services, and remotely accessible security workstations.

This repository documents the environment from architecture and implementation through troubleshooting, validation, security investigations, and lessons learned.

---

## Project Purpose

Cybersecurity concepts become much more useful when they can be built, broken, investigated, and explained.

The MutaSpace Enterprise Security Lab was created to turn security knowledge into practical experience through a repeatable process:

> **Build it. Understand it. Validate it. Document it. Teach it. Assess it.**

Rather than treating the environment as a collection of disconnected virtual machines, the goal is to build an evolving enterprise security environment where technologies interact realistically.

The lab supports hands-on work involving:

- Security Operations Center workflows
- SIEM administration and analysis
- Windows and Linux endpoint monitoring
- Active Directory security
- Identity and access management
- PKI and certificate services
- Authentication and Kerberos
- Network security
- Firewall administration
- Container security
- Detection engineering
- Incident investigation
- Vulnerability assessment
- Security architecture
- Security consulting
- Troubleshooting and root cause analysis
- Cybersecurity instruction and live lab exercises

---

# Current Environment

## Virtualization Platform

**Proxmox VE**

Primary node:

`mutaspace-soc-node01`

The Proxmox environment hosts the enterprise infrastructure, security systems, endpoints, application services, and student investigation environments.

---

# Official Lab Host

The MutaSpace Enterprise Security Lab runs on a dedicated custom-built host designed to support virtualization, security monitoring, identity services, networking, container workloads, and hands-on lab environments.

## Hardware

| Component | Specification |
|---|---|
| Motherboard | B650 AORUS Elite AX |
| CPU | AMD Ryzen 9 7900X |
| Memory | 64 GB DDR5 |
| Storage | 2 TB NVMe SSD |
| Power Supply | 850W PSU |
| Case | Corsair 3500X |
| CPU Cooling | Arctic Liquid Freezer III Pro 360 |
| Hypervisor | Proxmox VE |

## Host Role

The physical host provides the compute foundation for:

- Enterprise infrastructure VMs
- Active Directory and DNS
- PKI and certificate services
- Wazuh SIEM
- Linux application servers
- Docker workloads
- Student investigation endpoints
- Remote lab access services
- Future detection engineering and incident response systems

## Host Identity

```text
Hostname: mutaspace-soc-node01
Platform: Proxmox VE
Role: Primary enterprise security lab hypervisor

## Network

The internal SOC environment currently operates on:

```text
Network: 10.10.10.0/24
Gateway: 10.10.10.1
Domain: mutaspace.local
```

### Virtual Bridges

| Bridge | Purpose |
|---|---|
| `vmbr0` | Proxmox management and upstream connectivity |
| `vmbr1` | Internal SOC network |

Network routing and firewall services are provided by **pfSense**.

---

# Current Architecture

```text
                         Remote Browser Access
                                  |
                               HTTPS
                                  |
                          Cloudflare Tunnel
                                  |
                              docker-01
                                  |
                         Apache Guacamole
                                  |
                                  v
+----------------------------------------------------------------+
|                    MutaSpace SOC Network                        |
|                       10.10.10.0/24                             |
|                                                                |
|                         fw-01                                  |
|                        pfSense                                 |
|                     10.10.10.1                                |
|                           |                                    |
|          +----------------+----------------+                   |
|          |                |                |                   |
|          v                v                v                   |
|        dc-01           wazuh-01          ca-01                 |
|     AD DS + DNS          SIEM            AD CS                 |
|     10.10.10.10       10.10.10.20     10.10.10.50             |
|          |                |                                    |
|          |          Central Telemetry                           |
|          |                ^                                    |
|          |                |                                    |
|    +-----+----------------+-------------------------+          |
|    |              |               |                |          |
|    v              v               v                v          |
| analyst-01  ubuntu-app-01     docker-01       win-client-01    |
|               Nginx           Docker                           |
|               SSH             Portainer                        |
|               Wazuh           Guacamole                        |
|                               Wazuh                            |
|                                                                |
|                    Student Lab                                 |
|                                                                |
|         +----------------+----------------+                    |
|         |                |                |                    |
|         v                v                v                    |
| HELPDESK-TEAM01   HELPDESK-TEAM02   HELPDESK-TEAM03           |
| Windows Endpoint  Windows Endpoint  Windows Endpoint           |
| Domain Joined     Domain Joined     Domain Joined              |
| Wazuh Agent 006   Wazuh Agent 008   Wazuh Agent 007           |
+----------------------------------------------------------------+
```

---

# Core Systems

| System | Platform | Role | Status |
|---|---|---|---|
| `fw-01` | pfSense | Firewall, routing, gateway | Operational |
| `dc-01` | Windows Server 2022 | Active Directory Domain Services + DNS | Operational |
| `wazuh-01` | Ubuntu | Wazuh SIEM manager and dashboard | Operational |
| `analyst-01` | Ubuntu Desktop | SOC analyst workstation | Operational |
| `win-client-01` | Windows 10 Pro | Domain endpoint and security testing | Operational |
| `ubuntu-app-01` | Ubuntu Server | Nginx application server + SSH | Operational |
| `docker-01` | Ubuntu Server | Container and application infrastructure | Operational |
| `ca-01` | Windows Server 2022 | Active Directory Certificate Services | Operational |
| `HELPDESK-TEAM01` | Windows | Student investigation endpoint | Operational |
| `HELPDESK-TEAM02` | Windows | Student investigation endpoint | Operational |
| `HELPDESK-TEAM03` | Windows | Student investigation endpoint | Operational |

---

# Security Monitoring

## Wazuh SIEM

Wazuh provides centralized security monitoring across the environment.

Current telemetry sources include:

- Windows Server
- Windows endpoints
- Ubuntu systems
- Application servers
- Docker infrastructure
- Student investigation endpoints

Current classroom workstation enrollment:

```text
006 -> HELPDESK-TEAM01
007 -> HELPDESK-TEAM03
008 -> HELPDESK-TEAM02
```

The environment has been used to observe and investigate Windows security events including:

- Successful authentication
- Failed authentication
- Explicit credential usage
- User creation
- Kerberos authentication
- Kerberos service ticket activity

Examples include Windows Event IDs:

```text
4624
4625
4648
4720
4768
4769
```

Wazuh also collects security configuration assessment, file integrity monitoring, system inventory, rootcheck, Linux logs, and selected application/container telemetry.

---

# Identity Infrastructure

The lab contains an Active Directory environment for hands-on identity security work.

## Active Directory

Domain:

`mutaspace.local`

Primary domain controller:

`dc-01`

Current identity capabilities include:

- Active Directory Domain Services
- DNS
- Domain-joined Windows endpoints
- Kerberos authentication
- Centralized identity administration
- Windows security event generation and monitoring

## Enterprise PKI

`ca-01` provides Active Directory Certificate Services.

Current deployment:

```text
Server: ca-01
Role: Enterprise Root Certification Authority
CA Name: MutaSpace Enterprise Root CA
```

The PKI environment is being expanded to support hands-on work involving:

- Certificate templates
- Certificate enrollment
- Auto-enrollment
- Certificate lifecycle management
- Revocation
- CRLs
- OCSP
- AD CS security assessment
- Certificate-based attack paths

---

# Application and Container Infrastructure

## docker-01

`docker-01` provides containerized infrastructure for application and security experimentation.

Current services include:

- Docker Engine
- Docker Compose
- Portainer
- Nginx test workloads
- Apache Guacamole
- Cloudflare Tunnel
- Wazuh endpoint monitoring

Container telemetry is also being integrated into Wazuh for security monitoring and detection development.

---

# Remote Cybersecurity Lab Access

The environment now supports browser-based remote access for live cybersecurity exercises.

Students can access assigned Windows investigation environments without:

- Direct Proxmox access
- Public RDP exposure
- VPN software installation on managed computers
- Direct access to the home network

Current access architecture:

```text
School / Remote Computer
        |
      HTTPS
        |
        v
Cloudflare
        |
 Cloudflare Tunnel
        |
        v
    docker-01
        |
 Apache Guacamole
        |
       RDP
        |
        v
Assigned Windows Investigation Endpoint
```

The remote access path has been successfully validated from a school-managed computer outside the home network.

This allows the lab to support live investigations where users interact with endpoint systems while security telemetry is observed centrally through the SOC environment.

---

# Student Security Lab

A dedicated student environment is being developed within the larger enterprise lab.

Current team workstations:

```text
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

Each workstation was created from a generalized Windows master image and then assigned a unique:

- Windows system identity
- Hostname
- Active Directory computer object
- Student account
- Wazuh agent identity
- Wazuh enrollment key

The workstations can be used for scenarios involving:

- Help desk investigation
- Authentication troubleshooting
- Windows Event Viewer
- Network troubleshooting
- DNS troubleshooting
- Account problems
- Endpoint security
- Log analysis
- SOC escalation
- Incident investigation

The objective is to allow students to investigate problems locally while corresponding telemetry can be analyzed centrally.

---

# Troubleshooting as Part of the Build

Failures and troubleshooting are intentionally documented as part of this project.

Significant issues encountered include:

### Windows Sysprep and AppX Conflicts

Windows image generalization initially failed because installed AppX packages prevented Sysprep from completing.

Problematic packages were identified through Sysprep logs, removed, and the image was successfully generalized.

### Cloned Wazuh Agent Identity

Cloned Windows systems initially inherited the Wazuh identity of the source workstation.

The issue was resolved by:

1. Stopping the Wazuh service
2. Removing the inherited client key
3. Assigning a unique agent name
4. Creating a new agent on the Wazuh manager
5. Importing a unique enrollment key
6. Restarting the service
7. Validating independent agent connectivity

### Docker Dual-IP Configuration

`docker-01` initially received both static and DHCP addresses because multiple Netplan configurations were active.

The conflicting cloud-init configuration was disabled and network configuration was validated.

### Guacamole RDP Authentication

Apache Guacamole could reach the Windows endpoint over TCP 3389, but the RDP session immediately terminated.

`guacd` logs identified an authentication failure.

The root cause was traced to the local Windows student account configuration. After configuring valid credentials and updating the Guacamole connection, browser-based RDP access succeeded.

The final connection was validated from a school-managed computer outside the home environment.

---

# Current Capabilities

The environment currently supports hands-on work across several security domains.

### SOC Operations

- Centralized endpoint monitoring
- Windows security event analysis
- Linux monitoring
- File integrity monitoring
- Security configuration assessment
- System inventory
- Authentication investigation

### Identity Security

- Active Directory
- DNS
- Kerberos
- Domain-joined endpoints
- Enterprise PKI
- Certificate services

### Network Security

- pfSense firewall
- Internal routing
- Segmented virtual networking foundation
- DNS infrastructure
- Controlled application services

### Security Engineering

- Proxmox virtualization
- Windows Server
- Linux administration
- Docker
- Centralized logging
- Remote security lab infrastructure

### Investigation

- Endpoint troubleshooting
- Authentication failures
- Windows Event Viewer
- SIEM correlation
- Network troubleshooting
- Application/service investigation

---

# Validation Philosophy

A system is not considered complete simply because it installs successfully.

Each major component is validated through testing.

Examples include:

```text
Can the endpoint reach the gateway?
Can the endpoint resolve internal DNS?
Can the workstation authenticate to Active Directory?
Can the Wazuh manager receive endpoint telemetry?
Can the analyst identify authentication failures centrally?
Can Docker workloads generate observable telemetry?
Can Guacamole reach the endpoint over RDP?
Can a remote school computer access the assigned environment?
```

This validation-first approach is intended to make the environment reproducible and defensible.

---

# Documentation

Detailed implementation documentation is maintained under:

```text
docs/
```

Major documentation areas include:

- Hardware
- Proxmox
- Networking
- Virtual machines
- Identity
- Wazuh
- Docker
- Student lab
- Remote access
- Troubleshooting
- Security labs
- Incident scenarios

---

# Roadmap

The environment will continue expanding in phases.

Planned areas include:

### Detection and SOC Engineering

- Sysmon
- Custom Wazuh detection rules
- Splunk
- Suricata
- Zeek
- Detection engineering exercises

### Incident Response

- TheHive
- Shuffle
- Velociraptor
- Incident timelines
- Analyst runbooks
- After-action reviews

### Identity Security

- Certificate templates
- Auto-enrollment
- CRL and OCSP
- AD CS attack paths
- MFA
- SAML
- OIDC
- OAuth
- SSO
- Okta
- Identity security assessments

### Networking

- VLAN segmentation
- Student network isolation
- Inter-VLAN routing
- ACLs
- Wireshark
- IDS/IPS monitoring
- Additional enterprise network scenarios

### Offensive Security Validation

Controlled attack simulation will be introduced to generate telemetry and validate defensive controls.

Potential systems and techniques include:

- Kali Linux
- Authentication attacks
- Reconnaissance
- Credential abuse
- Web enumeration
- Active Directory attack paths

All offensive testing will remain within controlled lab environments.

---

# Project Status

The project has progressed from initial hardware and virtualization deployment into an operational enterprise security environment.

Current major milestones include:

- [x] Physical lab hardware assembled
- [x] Proxmox VE installed
- [x] Internal SOC network created
- [x] pfSense firewall deployed
- [x] Active Directory deployed
- [x] Internal DNS operational
- [x] Wazuh SIEM deployed
- [x] Windows endpoint monitoring
- [x] Linux endpoint monitoring
- [x] Application server deployed
- [x] Docker infrastructure deployed
- [x] Portainer deployed
- [x] Docker telemetry integration started
- [x] Enterprise Root CA deployed
- [x] Windows student master image created
- [x] Three student investigation workstations deployed
- [x] Student endpoints joined to Active Directory
- [x] Independent Wazuh enrollment validated
- [x] Apache Guacamole deployed
- [x] Cloudflare Tunnel deployed
- [x] Browser-based remote endpoint access validated
- [x] External access validated from a school-managed computer
- [ ] Cloudflare Access policy implementation
- [ ] Student network segmentation
- [ ] Advanced detection engineering
- [ ] Incident response platform
- [ ] Advanced identity security scenarios

---

# Repository Philosophy

This repository is intentionally not limited to successful final configurations.

It documents:

- Architecture decisions
- Commands
- Configuration
- Validation
- Troubleshooting
- Failures
- Root causes
- Remediation
- Security observations
- Lessons learned

The objective is not simply to show that a tool was installed.

The objective is to demonstrate the ability to **design, implement, troubleshoot, secure, monitor, investigate, explain, and improve an enterprise security environment.**