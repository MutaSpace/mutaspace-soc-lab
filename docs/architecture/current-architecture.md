# MutaSpace Enterprise Security Lab Architecture

This document explains the architecture of the MutaSpace Enterprise Security Lab, how its major components interact, and the design decisions behind the environment.

The architecture can also be used as a reference for building a similar Proxmox-based enterprise cybersecurity lab.

---

# 1. Architecture Goals

The environment was designed to support practical work across multiple security domains without requiring separate physical hardware for every system.

The architecture needed to support:

- Enterprise networking
- Active Directory
- DNS
- Kerberos authentication
- Enterprise PKI
- Windows and Linux endpoints
- Centralized security monitoring
- Application workloads
- Containerized services
- Remote security labs
- Security investigations
- Detection engineering
- Controlled attack simulation
- Repeatable student environments

Rather than building each technology independently, the environment connects them so activity generated on one system can be observed and investigated elsewhere.

---

# 2. Physical Foundation

The environment runs on a dedicated custom-built virtualization server.

## Reference Host

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

The host was designed to run multiple Windows and Linux systems simultaneously while leaving room for future security tooling.

### Why Proxmox?

Proxmox VE provides:

- Virtual machines
- Virtual networking
- Snapshots
- Cloning
- Resource pools
- Centralized VM management
- Linux-based administration

These capabilities make it possible to model enterprise infrastructure while maintaining the ability to break, restore, clone, and rebuild systems.

---

# 3. High-Level Architecture

```text
                         INTERNET
                            |
                            v
                    External Access Layer
                            |
                            v
                      Remote Gateway
                            |
                            v
+-------------------------------------------------------+
|               ENTERPRISE SECURITY LAB                 |
|                                                       |
|                     Firewall                          |
|                        |                              |
|          +-------------+-------------+                |
|          |             |             |                |
|          v             v             v                |
|      Identity        Security      Application         |
|   Infrastructure   Monitoring    Infrastructure        |
|          |             |             |                |
|          |             |             |                |
|          +-------+-----+------+------+-+              |
|                  |            |                        |
|                  v            v                        |
|             Endpoints     Student Labs                 |
|                  |            |                        |
|                  +-----+------+                        |
|                        |                               |
|                        v                               |
|                 Security Telemetry                    |
+-------------------------------------------------------+
```

The architecture intentionally separates responsibilities even when systems currently share the same virtual network.

---

# 4. Virtualization Layer

The virtualization layer provides the foundation for every logical security environment above it.

```text
Physical Hardware
       |
       v
   Proxmox VE
       |
       +-------- Virtual Networking
       |
       +-------- Infrastructure VMs
       |
       +-------- Security Systems
       |
       +-------- Endpoints
       |
       +-------- Application Workloads
       |
       +-------- Student Environments
```

This makes the environment reproducible and allows systems to be cloned or restored without rebuilding physical machines.

---

# 5. Network Layer

The lab uses two primary Proxmox bridges.

```text
vmbr0
```

provides management and upstream connectivity.

```text
vmbr1
```

provides the internal enterprise security network.

The reference implementation currently uses:

```text
10.10.10.0/24
```

with:

```text
10.10.10.1
```

as the internal gateway.

A virtual pfSense firewall provides:

- Routing
- Firewall services
- DHCP
- Internet connectivity
- Foundation for future segmentation

---

# 6. Why Use a Virtual Firewall?

Placing pfSense inside the virtualization environment allows the lab network to behave more like an enterprise network.

Instead of allowing every VM to communicate directly through the host's upstream network:

```text
VM -> Home Network
```

traffic can follow:

```text
VM
 |
 v
Internal Virtual Network
 |
 v
pfSense
 |
 v
Upstream Network
```

This creates a control point where routing and security policies can later be implemented.

---

# 7. Identity Layer

The environment uses Microsoft Active Directory as its primary enterprise identity system.

The identity layer provides:

- Active Directory Domain Services
- DNS
- Kerberos
- Domain authentication
- Computer identities
- Group Policy
- Centralized Windows identity management

Reference domain:

```text
mutaspace.local
```

Architecture:

```text
Windows Endpoint
      |
      +------ DNS
      |
      +------ Kerberos
      |
      +------ LDAP
      |
      +------ Group Policy
      |
      v
Domain Controller
```

This allows identity activity to become part of security investigations rather than treating endpoints as independent machines.

---

# 8. PKI Layer

Active Directory Certificate Services adds enterprise certificate infrastructure.

```text
Active Directory
       |
       v
Certificate Authority
       |
       +---- Certificate Enrollment
       +---- Certificate Templates
       +---- Trust
       +---- Certificate Lifecycle
```

The PKI environment provides a foundation for studying:

- Digital certificates
- Enterprise trust
- Certificate enrollment
- Auto-enrollment
- Certificate templates
- Revocation
- Certificate lifecycle management
- AD CS security weaknesses

---

# 9. Security Monitoring Layer

Wazuh provides centralized security monitoring.

Instead of relying only on logs stored locally:

```text
Endpoint
   |
   v
Local Logs
```

the architecture adds:

```text
Endpoint
   |
   | Security telemetry
   v
Wazuh
   |
   v
Centralized Investigation
```

This allows activity from multiple systems to be investigated from one security platform.

---

# 10. Endpoint Layer

The environment includes Windows and Linux endpoints representing different enterprise workloads.

Examples include:

- Windows user workstations
- Windows infrastructure servers
- Linux analyst systems
- Linux application servers
- Container hosts

Endpoints generate telemetry that can be correlated with:

- Authentication
- Network activity
- Application activity
- File changes
- Security configuration
- System state

---

# 11. Application Layer

A Linux application server provides a realistic workload for security monitoring.

The current reference implementation uses Nginx.

This provides:

- HTTP traffic
- Access logs
- Error logs
- Web reconnaissance activity
- Application troubleshooting
- Detection engineering opportunities

Example:

```text
Client
  |
  | HTTP Request
  v
Nginx
  |
  +---- access.log
  |
  +---- error.log
          |
          v
        Wazuh
```

---

# 12. Container Layer

A dedicated Linux server hosts containerized infrastructure using Docker.

This introduces another common enterprise technology into the lab.

Container workloads currently support areas such as:

- Web applications
- Infrastructure management
- Remote access
- Security telemetry

Architecture:

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
       +---- Container
```

Containerization allows new applications to be introduced without requiring an additional VM for every service.

---

# 13. Student Lab Layer

Reusable Windows endpoints provide isolated logical environments for hands-on exercises.

```text
Generalized Windows Master
           |
           +----------+
           |          |
           v          v
        Team 01    Team 02
           |
           v
        Team 03
```

Each deployed workstation receives its own:

- Windows machine identity
- Hostname
- Active Directory computer identity
- Wazuh identity
- User context

This prevents cloned systems from operating under duplicated identities.

---

# 14. Remote Access Layer

The environment supports browser-based access using:

```text
Cloudflare Tunnel
        +
Apache Guacamole
        +
RDP
```

Architecture:

```text
Remote Browser
      |
      | HTTPS
      v
Cloudflare
      |
      v
Secure Tunnel
      |
      v
Guacamole
      |
      | RDP
      v
Assigned Endpoint
```

This approach avoids requiring users to connect directly to the hypervisor or expose RDP publicly.

---

# 15. Why Use an Access Gateway?

The user needs access to the endpoint.

The user does **not** need access to the infrastructure hosting the endpoint.

Instead of:

```text
Student
   |
   v
Proxmox
   |
   v
VM
```

the architecture uses:

```text
Student
   |
   v
Remote Access Gateway
   |
   v
Assigned VM
```

This follows the principle of providing only the access required for the task.

---

# 16. Security Telemetry Flow

One of the most important design characteristics is centralized observability.

Example authentication flow:

```text
User
 |
 v
Windows Endpoint
 |
 +------ Authentication Request ------> Active Directory
 |
 +------ Windows Security Event
 |
 v
Wazuh Agent
 |
 v
Wazuh Manager
 |
 v
Security Analyst
```

This allows the same activity to be studied from multiple perspectives.

For example:

```text
User Perspective
Endpoint Perspective
Identity Perspective
SIEM Perspective
Network Perspective
```

---

# 17. Investigation Model

A typical security investigation can cross several systems.

```text
Suspicious Activity
       |
       v
Endpoint Evidence
       |
       +------ Event Viewer
       |
       +------ Application Logs
       |
       +------ Network State
       |
       v
Centralized Telemetry
       |
       v
Wazuh
       |
       v
Analyst Investigation
```

Future tooling will expand this model with network and incident-response telemetry.

---

# 18. Current Segmentation Model

The current reference implementation primarily uses:

```text
10.10.10.0/24
```

for the internal environment.

Logical roles already exist, but full network segmentation is still being developed.

This is intentional documentation of the current maturity level rather than representing planned controls as already implemented.

---

# 19. Future Segmentation

The architecture is designed to evolve toward multiple security zones.

Potential future model:

```text
                    pfSense
                       |
       +---------------+---------------+
       |               |               |
       v               v               v
Infrastructure     Applications      Students
       |                               |
       |                    +----------+----------+
       |                    |          |          |
       v                    v          v          v
Identity / SOC           Team 01    Team 02    Team 03
```

Additional zones may eventually include:

- Management
- Identity
- Applications
- SOC
- Student environments
- Attack simulation
- Network sensors

---

# 20. Planned Monitoring Expansion

Future architecture will introduce additional visibility layers.

Potential tools include:

```text
Sysmon
Suricata
Zeek
Splunk
Velociraptor
```

Example future telemetry architecture:

```text
Endpoints --------+
                  |
Applications -----+----> Security Platforms
                  |
Identity ---------+
                  |
Network Sensors --+
```

---

# 21. MutaSpace Implementation

The current MutaSpace implementation has successfully validated the core architecture across:

- Proxmox virtualization
- pfSense routing
- Active Directory
- DNS
- Kerberos
- Enterprise PKI
- Windows endpoints
- Linux workloads
- Wazuh monitoring
- Docker infrastructure
- Containerized applications
- Reusable student workstations
- Browser-based remote access

The environment has progressed from individual virtual machines into an interconnected security lab capable of generating, collecting, and investigating activity across multiple security domains.

---

# 22. Design Principle

The architecture follows one central rule:

> Security technologies should not be studied as isolated tools.

A firewall affects network communication.

DNS affects Active Directory.

Active Directory generates authentication activity.

Endpoints generate security events.

Applications generate logs.

Security platforms collect that evidence.

Analysts use the combined evidence to investigate what happened.

Building these systems together creates a more realistic environment for understanding how enterprise security actually operates.