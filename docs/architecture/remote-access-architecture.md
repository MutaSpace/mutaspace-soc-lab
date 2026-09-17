# Remote Access Architecture

This document describes the remote-access design used to provide browser-based access to the MutaSpace Enterprise Security Lab.

The objective is to allow students to interact with assigned Windows investigation environments from managed school computers without requiring direct access to Proxmox, VPN software installation, or public exposure of internal management services.

---

# 1. Remote Access Goal

The student access requirement was:

- Browser-only
- No Tailscale installation on school-managed computers
- No direct Proxmox access
- No direct RDP exposure to the public Internet
- No access to the home network
- Team-specific access to assigned Windows environments
- Centralized monitoring through Wazuh
- Minimal disruption to existing infrastructure

The resulting design uses:

- Cloudflare Tunnel
- Apache Guacamole
- RDP
- Dedicated Windows student endpoints

---

# 2. Public Access Domain

Primary lab domain:

```text
mutaspacesoc.com
```

Remote lab hostname:

```text
lab.mutaspacesoc.com
```

Students access the environment through:

```text
https://lab.mutaspacesoc.com
```

The Guacamole application is available through the published lab hostname.

---

# 3. High-Level Architecture

```text
School-Managed Computer
        |
        | HTTPS
        v
lab.mutaspacesoc.com
        |
        v
Cloudflare Edge
        |
        | Encrypted Cloudflare Tunnel
        v
docker-01
10.10.10.40
        |
        v
Apache Guacamole
        |
        | RDP
        v
Assigned Windows Endpoint
```

Current student endpoints:

```text
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

---

# 4. Why Browser-Based Access Was Selected

Several access models were considered.

## Direct Proxmox Access

Rejected as the primary student-access method.

Reasons:

- Students do not need hypervisor administration
- Increased exposure of management infrastructure
- Greater risk of accidental VM or infrastructure changes
- More complex RBAC requirements
- Poorer student experience for simple endpoint access

---

## Tailscale on Student Computers

Tailscale is used by the administrator to access the lab remotely.

It was not selected as the primary student method because school-managed computers may:

- Restrict software installation
- Require administrative privileges
- Block unapproved VPN clients
- Have institutional security restrictions

The goal was therefore to remove the requirement for locally installed VPN software.

---

## Direct Public RDP

Rejected.

Direct exposure of:

```text
TCP 3389
```

would unnecessarily expose Windows endpoints to the public Internet.

The final design keeps RDP internal.

---

## Browser-Based Gateway

Selected.

Apache Guacamole allows users to access RDP sessions through an HTML5 browser.

Advantages include:

- No local RDP client required
- No student VPN installation
- No Proxmox account required
- Centralized connection management
- Team-specific connection permissions
- Browser-based access from managed school computers

---

# 5. Apache Guacamole

Guacamole runs as a containerized service on:

```text
docker-01
10.10.10.40
```

Internal Guacamole access:

```text
http://10.10.10.40:8081/guacamole
```

Current supporting containers include:

```text
guacamole
guacd
guac-postgres
```

---

# 6. Guacamole Component Roles

## `guacamole`

Provides the browser-based application interface.

Responsibilities include:

- User authentication
- Connection configuration
- Session presentation
- Permission assignment
- Browser interface

---

## `guacd`

Guacamole proxy daemon.

`guacd` establishes the actual remote desktop session to the destination endpoint.

For the current student environment:

```text
guacd
   |
   | RDP TCP 3389
   v
HELPDESK-TEAM0X
```

---

## PostgreSQL

Guacamole stores configuration data in PostgreSQL.

The database stores information such as:

- Users
- Connections
- Permissions
- Configuration relationships

Passwords and database secrets must never be committed to this repository.

---

# 7. Windows RDP Configuration

Student endpoints require Remote Desktop to be enabled.

Example PowerShell configuration:

```powershell
Set-ItemProperty `
  -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name 'fDenyTSConnections' `
  -Value 0
```

Windows Firewall RDP rules:

```powershell
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

RDP listener validation:

```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

Expected result:

```text
LocalPort : 3389
State     : Listen
```

---

# 8. Student RDP Accounts

Each team workstation contains a student-facing local account.

Examples:

```text
HELPDESK-TEAM01\Team01
HELPDESK-TEAM02\Team02
HELPDESK-TEAM03\Team03
```

These accounts are separate from the instructor recovery account:

```text
LabAdmin
```

Student accounts must:

- Be active
- Have a valid password
- Be authorized for Remote Desktop
- Use credentials assigned only to their team

Example:

```powershell
net localgroup "Remote Desktop Users" Team01 /add
```

---

# 9. Guacamole Connection Mapping

The intended connection model is:

```text
Guacamole User: team01
        |
        v
HELPDESK-TEAM01

Guacamole User: team02
        |
        v
HELPDESK-TEAM02

Guacamole User: team03
        |
        v
HELPDESK-TEAM03
```

Each user should only receive permission to use their assigned connection.

Students should not receive:

- Guacamole administrator privileges
- Access to other teams
- Connection creation privileges
- User-management privileges
- System-management privileges

---

# 10. Team 01 Proof of Concept

The first fully validated remote-access path was built for:

```text
HELPDESK-TEAM01
```

Validation sequence:

```text
Student Account
      |
      v
RDP Enabled
      |
      v
TCP 3389 Listening
      |
      v
docker-01 Reaches TCP 3389
      |
      v
Guacamole Connection Created
      |
      v
Browser Session Established
```

---

# 11. RDP Troubleshooting

The first Guacamole connection attempt failed.

## Symptom

Clicking the Guacamole connection caused the session to close immediately.

The browser did not display the Windows desktop.

---

## Network Validation

From `docker-01`, the RDP service was tested:

```bash
nc -vz <TEAM01-IP> 3389
```

The connection succeeded.

This proved:

```text
docker-01
     |
     | TCP 3389
     v
HELPDESK-TEAM01
```

was reachable.

Therefore, the failure was not caused by:

- Routing
- Firewall connectivity
- Closed TCP port
- RDP listener failure

---

## Guacamole Logs

The `guacd` container logs were reviewed:

```bash
sudo docker logs guacd --tail 50
```

The logs identified:

```text
Authentication failure
```

This isolated the issue to the Windows authentication layer.

---

## Root Cause

The Team01 local account did not have a usable password for remote authentication.

The account showed:

```text
Password required: No
```

A valid password was configured:

```powershell
net user Team01 *
```

Guacamole credentials were updated accordingly.

---

## Validation

After correcting the Windows credentials:

```text
Browser
   |
   v
Guacamole
   |
   v
RDP
   |
   v
HELPDESK-TEAM01
   |
   v
Windows Desktop
```

completed successfully.

---

# 12. Cloudflare Tunnel

Cloudflare Tunnel provides the external access path.

Tunnel name:

```text
mutaspace-guacamole
```

The connector runs from:

```text
docker-01
```

The tunnel establishes an outbound connection from the lab to Cloudflare.

This means no inbound port forwarding is required on the home router.

---

# 13. Cloudflare Tunnel Traffic Flow

```text
docker-01
     |
     | outbound encrypted connection
     v
Cloudflare
```

External users connect in the opposite logical direction:

```text
Remote Browser
      |
      | HTTPS
      v
Cloudflare
      |
      | Existing tunnel
      v
docker-01
      |
      v
Guacamole
```

---

# 14. Published Application Route

The published hostname is:

```text
lab.mutaspacesoc.com
```

The Cloudflare route forwards the application to:

```text
HTTP
10.10.10.40:8081
```

The Guacamole application path is:

```text
/guacamole
```

Example:

```text
https://lab.mutaspacesoc.com/guacamole
```

---

# 15. Public Exposure Model

The remote-access design intentionally avoids directly exposing:

```text
Proxmox TCP 8006
RDP TCP 3389
SSH TCP 22
Portainer TCP 9443
Wazuh management interfaces
pfSense administration
Active Directory
AD CS
```

The publicly accessible application layer is:

```text
Cloudflare
     |
     v
Guacamole
```

Internal services remain behind the private lab network.

---

# 16. Trust Boundaries

## Boundary 1: Public Internet to Cloudflare

Protected through:

- HTTPS
- Cloudflare edge infrastructure
- Tunnel routing

---

## Boundary 2: Cloudflare to Lab

Protected through:

- Cloudflare Tunnel
- Outbound connector
- No inbound router port forwarding

---

## Boundary 3: Guacamole to Windows Endpoint

Protected through:

- Internal networking
- RDP authentication
- Windows account permissions

---

## Boundary 4: Team User to Assigned Endpoint

Controlled through:

- Guacamole user permissions
- Connection assignment
- Windows authentication

---

# 17. External Validation

The remote-access architecture was tested from outside the home network.

Validation included:

1. Access from the administrator laptop while on campus
2. Access from a school-managed computer
3. No Tailscale client on the school computer
4. Browser-based Guacamole login
5. Team01 connection selection
6. Successful Windows RDP authentication
7. Successful interactive desktop session

Result:

```text
External Browser Access: PASSED
```

---

# 18. Successful End-to-End Path

The validated path is:

```text
School-Managed Computer
        |
        | HTTPS
        v
lab.mutaspacesoc.com
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
        | TCP 3389
        v
HELPDESK-TEAM01
        |
        v
Team01 Windows Session
```

This is the current reference architecture for future student remote access.

---

# 19. Security Advantages

The architecture provides several advantages over direct access models.

## Reduced Public Exposure

Internal management services are not directly exposed.

## Browser-Only Student Workflow

Students require only:

- Supported browser
- Guacamole credentials
- Windows lab credentials

## Centralized Access

Remote sessions are brokered through one controlled gateway.

## Endpoint Assignment

Users can be limited to their assigned systems.

## No Hypervisor Access

Students do not require Proxmox accounts.

## No Student VPN Requirement

School computers do not require local VPN software installation.

---

# 20. Current Limitations

The current design is functional but not considered fully hardened.

Known limitations include:

- Cloudflare Access is not yet implemented
- Team 02 Guacamole access requires final configuration
- Team 03 Guacamole access requires final configuration
- Student networks are not yet isolated by VLAN/subnet
- Team systems share the current `10.10.10.0/24` network
- Credential rotation procedures still need formalization
- Automated workstation reset procedures remain planned

---

# 21. Planned Cloudflare Access Layer

A planned improvement is to place Cloudflare Access in front of Guacamole.

Future flow:

```text
Remote Browser
      |
      v
Cloudflare Access
      |
      | identity check
      v
Guacamole
      |
      | team-specific login
      v
Assigned Endpoint
```

This creates two authentication layers:

```text
Cloudflare Access
        +
Guacamole
        +
Windows
```

---

# 22. Planned Authentication Model

Long-term student authentication may use:

```text
Layer 1
Cloudflare identity validation

Layer 2
Guacamole team/user identity

Layer 3
Active Directory or Windows identity
```

This will provide clearer separation between:

- External access
- Lab access
- Endpoint identity

---

# 23. Planned Team Isolation

Future network segmentation will place each team on a dedicated subnet or VLAN.

Example:

```text
Team 01
10.10.21.0/24

Team 02
10.10.22.0/24

Team 03
10.10.23.0/24
```

pfSense will control communication between these environments.

---

# 24. Planned Session Security Improvements

Future hardening may include:

- Session timeouts
- Account lockout
- Password rotation
- Temporary student accounts
- Per-semester account lifecycle
- Limited clipboard permissions
- Limited file transfer
- Connection recording where appropriate
- Audit logging
- Conditional Cloudflare policies
- Device or location restrictions where appropriate

---

# 25. Operational Checks

## Guacamole Containers

Validate:

```bash
sudo docker ps
```

Expected containers include:

```text
guacamole
guacd
guac-postgres
cloudflared
```

---

## Guacamole Logs

```bash
sudo docker logs guacamole --tail 50
```

---

## RDP Proxy Logs

```bash
sudo docker logs guacd --tail 50
```

These logs are useful when distinguishing:

```text
Network failure
Authentication failure
Protocol negotiation failure
Session failure
```

---

## Cloudflare Connector

Check:

```bash
sudo docker ps --filter name=cloudflared
```

Review logs:

```bash
sudo docker logs cloudflared --tail 50
```

The connector should remain healthy.

---

# 26. RDP Endpoint Validation

On Windows:

```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

Account validation:

```powershell
Get-LocalUser Team01
```

Remote Desktop Users:

```powershell
net localgroup "Remote Desktop Users"
```

---

# 27. Troubleshooting Workflow

If a remote session fails:

```text
Can the public hostname load?
        |
        v
Is Cloudflare Tunnel healthy?
        |
        v
Can Guacamole load?
        |
        v
Can docker-01 reach endpoint:3389?
        |
        v
Is Windows listening on 3389?
        |
        v
Is the student account active?
        |
        v
Does it have a valid password?
        |
        v
Is it allowed to use RDP?
        |
        v
Do guacd logs show authentication failure?
```

This sequence avoids immediately changing firewall or network configuration when the problem may exist at the authentication layer.

---

# 28. Security Decision Record

## Decision

Use Cloudflare Tunnel and Apache Guacamole for student remote access.

## Alternatives Considered

- Direct Proxmox access
- Tailscale on student devices
- Public RDP
- Direct VPN access

## Reason

The selected architecture:

- Requires only a browser
- Works from managed school computers
- Does not require student software installation
- Avoids direct Proxmox exposure
- Avoids public RDP
- Preserves internal network boundaries
- Supports team-specific endpoint assignments

---

# 29. Credential Handling

The following must never be stored in this repository:

- Cloudflare Tunnel tokens
- Guacamole passwords
- PostgreSQL passwords
- Windows student passwords
- Administrator passwords
- Wazuh enrollment keys
- API keys
- Private authentication secrets

Example documentation:

```text
Tunnel Name: mutaspace-guacamole
Tunnel Token: [REDACTED]
```

---

# 30. Remote Access Status

| Capability | Status |
|---|---|
| Internal Guacamole | Operational |
| Team01 RDP | Operational |
| Team01 Guacamole | Operational |
| Cloudflare Tunnel | Operational |
| Public HTTPS hostname | Operational |
| School computer access | Validated |
| No-Tailscale student access | Validated |
| Team02 Guacamole | Pending |
| Team03 Guacamole | Pending |
| Cloudflare Access | Planned |
| Team network segmentation | Planned |

---

# 31. Architecture Principle

The remote-access architecture follows this rule:

> Students should receive access to the systems required for the lab without receiving unnecessary access to the infrastructure that hosts the lab.

The long-term goal is to combine:

```text
Strong external authentication
        +
Team-specific application access
        +
Network segmentation
        +
Centralized logging
        +
Repeatable reset procedures
```

to provide a secure and reusable browser-based cybersecurity lab environment.