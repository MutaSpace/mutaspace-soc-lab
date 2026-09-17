# Lab Systems and Roles

This guide explains the major systems used in the MutaSpace Enterprise Security Lab, why each system exists, and what role it plays in the overall architecture.

It is intended as a reference for anyone building a similar Proxmox-based cybersecurity lab.

The goal is not to prescribe one exact configuration. The goal is to show the logical roles required to build a functional enterprise-style security environment.

---

# 1. Core Design

A useful enterprise security lab should contain more than isolated endpoints.

At minimum, the environment should include systems that represent:

- Networking
- Identity
- Security monitoring
- Endpoints
- Applications
- Containers
- Remote access
- Student or analyst workstations

A simplified architecture looks like:

```text
                    Firewall / Gateway
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
       Identity         Security        Applications
          |             Monitoring          |
          |                |                |
          +--------+-------+-------+--------+
                   |               |
                   v               v
               Endpoints       Student Labs
```

---

# 2. Recommended System Roles

A small but useful lab can be built around the following systems:

| Role | Example Platform | Purpose |
|---|---|---|
| Hypervisor | Proxmox VE | Runs all virtual systems |
| Firewall | pfSense | Routing, DHCP, firewalling |
| Domain Controller | Windows Server | Active Directory, DNS, Kerberos |
| SIEM | Wazuh | Centralized security monitoring |
| Analyst Workstation | Ubuntu Desktop | Investigation and analyst workflow |
| Windows Endpoint | Windows 10/11 Pro | Authentication and endpoint telemetry |
| Linux Application Server | Ubuntu Server | Web applications and Linux logging |
| Container Host | Ubuntu Server + Docker | Containerized services |
| Certificate Authority | Windows Server + AD CS | Enterprise PKI |
| Student Endpoints | Windows | Hands-on investigations |
| Remote Access Gateway | Apache Guacamole | Browser-based remote access |

---

# 3. Hypervisor

## Purpose

The hypervisor provides the compute foundation for the lab.

A hypervisor allows multiple operating systems to run on one physical server while maintaining separate:

- CPU allocation
- Memory allocation
- Storage
- Virtual network interfaces
- Snapshots
- Power state

## Recommended Platform

```text
Proxmox VE
```

Proxmox is well suited for a security lab because it supports:

- Virtual machines
- Containers
- Virtual bridges
- Snapshots
- Cloning
- Resource pools
- Centralized management

---

# 4. Firewall and Router

## Purpose

A dedicated firewall gives the lab its own network boundary.

Without one, lab systems may communicate directly with the upstream network and miss an important layer of enterprise architecture.

## Recommended Platform

```text
pfSense
```

Typical responsibilities include:

- Default gateway
- DHCP
- Firewall policy
- Routing
- NAT
- Future VLAN routing

Conceptually:

```text
Lab VM
   |
   v
Internal Network
   |
   v
pfSense
   |
   v
Upstream Network
```

---

# 5. Domain Controller

## Purpose

The domain controller introduces enterprise identity into the environment.

A Windows Server domain controller can provide:

- Active Directory Domain Services
- DNS
- Kerberos
- LDAP
- Group Policy
- Computer identities
- User identities

## Why It Matters

Many security investigations depend on identity.

Examples include:

- Failed logons
- Password changes
- Account lockouts
- Kerberos ticket requests
- Group membership changes
- Domain authentication failures

Without Active Directory, these scenarios are difficult to reproduce realistically.

---

# 6. DNS Server

In an Active Directory environment, DNS is not optional infrastructure.

Domain systems depend on DNS to locate:

- Domain controllers
- Kerberos services
- LDAP services
- Internal servers

A common design is:

```text
Windows Endpoint
      |
      | DNS
      v
Domain Controller / DNS
```

External DNS requests can then be forwarded upstream.

---

# 7. SIEM

## Purpose

The SIEM centralizes telemetry from multiple systems.

The MutaSpace reference implementation uses:

```text
Wazuh
```

A SIEM allows the lab to move from:

```text
Open Event Viewer on one computer
```

to:

```text
Investigate activity across many endpoints centrally
```

## Typical Data Sources

- Windows event logs
- Linux system logs
- Authentication activity
- Application logs
- File integrity events
- Security configuration findings
- Container telemetry

---

# 8. Analyst Workstation

## Purpose

The analyst workstation represents the system used by a SOC analyst.

Keeping the analyst workstation separate from the SIEM server creates a more realistic workflow.

The analyst connects to monitoring tools from a dedicated workstation rather than performing investigations directly on the server.

Typical uses include:

- SIEM access
- Security investigations
- Traffic generation
- Browser testing
- SSH
- Command-line analysis

---

# 9. Windows Endpoint

## Purpose

A Windows workstation provides a realistic user endpoint for:

- Authentication
- Active Directory membership
- Event Viewer
- Group Policy
- Endpoint monitoring
- Troubleshooting
- Security investigations

Useful Windows event categories include:

- Successful logons
- Failed logons
- Explicit credential use
- Kerberos authentication
- Account creation
- Group membership changes

A Windows endpoint becomes especially valuable once it is:

```text
Domain Joined
     +
Monitored by SIEM
```

---

# 10. Linux Application Server

## Purpose

A Linux server provides application and server-side telemetry.

A simple implementation can use:

```text
Ubuntu Server
Nginx
SSH
```

This allows investigation of:

- Web access logs
- Error logs
- HTTP status codes
- SSH activity
- Linux services
- Linux authentication

---

# 11. Container Host

## Purpose

A dedicated Docker host introduces container infrastructure into the lab.

Recommended components:

```text
Ubuntu Server
Docker Engine
Docker Compose
```

Useful workloads include:

- Nginx
- Remote access services
- Security tools
- Databases
- Test applications

This allows the lab to explore:

- Container networking
- Container logs
- Docker bridge networks
- Port mapping
- Container security

---

# 12. Container Management

A graphical Docker management interface can be useful when learning container operations.

The MutaSpace implementation uses:

```text
Portainer
```

Portainer provides visibility into:

- Containers
- Images
- Networks
- Volumes
- Runtime state

It should be treated as an administrative interface and not exposed unnecessarily.

---

# 13. Enterprise PKI

## Purpose

A Certificate Authority introduces enterprise certificate services.

The reference implementation uses:

```text
Active Directory Certificate Services
```

A PKI environment supports hands-on work with:

- Certificate enrollment
- Certificate templates
- Auto-enrollment
- Trust chains
- Revocation
- CRLs
- Certificate lifecycle management

It also enables future study of AD CS attack paths and certificate abuse.

---

# 14. Student Workstations

Student workstations are separate Windows systems used for live exercises.

Each workstation should have a unique:

- Hostname
- Windows identity
- Domain computer account
- Monitoring identity
- Student login context

They should not simply be identical clones sharing machine identities.

---

# 15. Golden Image

A generalized Windows master image makes it possible to deploy many student systems quickly.

The recommended model is:

```text
Base Windows System
      |
      v
Prepared Master
      |
      v
Sysprep / Generalize
      |
      v
Powered-Off Golden Image
      |
      +---------+---------+
      |         |         |
      v         v         v
   Team 01   Team 02   Team 03
```

Each clone is then given its own identity.

---

# 16. Remote Access Gateway

## Purpose

A remote access gateway allows users to reach internal lab systems without exposing the underlying virtualization platform.

The MutaSpace reference implementation uses:

```text
Apache Guacamole
```

Guacamole provides browser-based access to protocols such as RDP.

Architecture:

```text
Browser
   |
   v
Guacamole
   |
   v
Windows Endpoint
```

---

# 17. Secure External Access

The remote gateway should not require direct inbound exposure of internal management services.

The MutaSpace reference implementation uses:

```text
Cloudflare Tunnel
```

The tunnel creates an outbound connection from the lab to Cloudflare.

Conceptually:

```text
Lab
 |
 | outbound tunnel
 v
Cloudflare
 |
 v
Remote Browser
```

This avoids publishing:

- Proxmox
- RDP
- SSH
- pfSense
- SIEM administration

directly to the public Internet.

---

# 18. System Relationships

The systems become more valuable when they interact.

Example:

```text
Windows Endpoint
      |
      +----> Active Directory
      |
      +----> DNS
      |
      +----> Wazuh
```

Another example:

```text
Student Browser
      |
      v
Remote Access Gateway
      |
      v
Windows Endpoint
      |
      v
Wazuh
```

This interconnected design creates realistic troubleshooting and investigation paths.

---

# 19. Minimum Build

A practical starter environment could use:

```text
1 x Proxmox Host
1 x pfSense VM
1 x Windows Domain Controller
1 x Wazuh Server
1 x Windows Client
1 x Analyst Workstation
```

This already supports:

- Networking
- Active Directory
- Authentication
- Windows telemetry
- SIEM monitoring
- Basic security investigations

---

# 20. Intermediate Build

Add:

```text
1 x Linux Application Server
1 x Docker Host
1 x Certificate Authority
```

This expands the lab into:

- Application security
- Linux monitoring
- Container security
- Enterprise PKI

---

# 21. Advanced Build

Add:

```text
Student Endpoints
Network Sensors
Attack Simulation Hosts
Incident Response Platforms
Additional SIEM Tools
Cloud Identity
```

Potential technologies include:

```text
Sysmon
Zeek
Suricata
Splunk
Velociraptor
Kali Linux
TheHive
Shuffle
Okta
Microsoft Entra ID
```

---

# 22. Deployment Order

A useful build sequence is:

```text
1. Physical Host
2. Proxmox
3. Virtual Networking
4. pfSense
5. Active Directory + DNS
6. Wazuh
7. Windows Endpoint
8. Analyst Workstation
9. Linux Application Server
10. Docker Host
11. PKI
12. Student Workstations
13. Remote Access
14. Detection Engineering
15. Incident Scenarios
```

This order allows each new system to build on infrastructure that has already been validated.

---

# 23. Why Build in Layers?

Installing every system at once makes troubleshooting difficult.

A layered approach allows each stage to answer a specific question.

Example:

```text
Can the network route traffic?
        |
        v
Can DNS resolve?
        |
        v
Can Active Directory authenticate?
        |
        v
Can the endpoint generate events?
        |
        v
Can the SIEM collect them?
        |
        v
Can the analyst investigate them?
```

If something fails, the problem can be isolated to a smaller part of the environment.

---

# 24. Validation Principle

Every system should have an explicit validation test.

Examples:

| System | Validation |
|---|---|
| Firewall | Endpoint reaches gateway and internet |
| DNS | Internal hostname resolves |
| Active Directory | Client joins domain |
| Wazuh | Agent appears Active |
| Nginx | HTTP request returns expected response |
| Docker | Container starts successfully |
| Guacamole | Browser session reaches endpoint |
| Cloudflare Tunnel | External browser reaches gateway |
| PKI | Certificate can be issued and validated |

---

# 25. What Not to Publish

A public build repository should explain configuration without exposing secrets.

Do not publish:

```text
Passwords
Enrollment keys
API tokens
Cloudflare tunnel tokens
Private certificate keys
Session cookies
Recovery codes
Private SSH keys
```

Use placeholders instead:

```text
<DOMAIN_ADMIN_PASSWORD>
<WAZUH_ENROLLMENT_KEY>
<CLOUDFLARE_TUNNEL_TOKEN>
```

---

# 26. MutaSpace Reference Implementation

The MutaSpace lab currently includes working examples of:

- Proxmox virtualization
- pfSense
- Active Directory
- DNS
- Kerberos
- Wazuh
- Windows endpoints
- Linux workloads
- Nginx
- Docker
- Portainer
- Active Directory Certificate Services
- Reusable Windows student systems
- Apache Guacamole
- Cloudflare Tunnel

These systems serve as the implementation behind the build guides in this repository.

---

# 27. Design Principle

Each system in the lab should have a reason to exist.

Avoid adding tools simply because they are popular.

A component should support at least one of the following:

```text
Infrastructure
Identity
Visibility
Investigation
Detection
Response
Teaching
Security Testing
```

The goal is to build an environment where technologies reinforce one another and produce realistic security workflows.