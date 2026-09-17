# Building Secure Browser-Based Remote Access for a Cybersecurity Lab

This guide explains how to provide browser-based remote access to internal lab systems without exposing the hypervisor, firewall, RDP, or management interfaces directly to the public Internet.

The reference design uses:

- Apache Guacamole
- Docker
- RDP
- Cloudflare Tunnel
- A dedicated public hostname

The same architecture can be adapted to other homelab or training environments.

---

# 1. Design Goal

A remote cybersecurity lab should allow users to access the systems they need without giving them unnecessary access to the infrastructure that hosts the lab.

The target experience is:

```text
Remote User
    |
    | HTTPS
    v
Public Lab URL
    |
    v
Remote Access Gateway
    |
    v
Assigned Internal Endpoint
```

The user should not need:

- Proxmox access
- Direct firewall access
- A public RDP port
- A local RDP client
- VPN software on a managed school or work computer

---

# 2. Why Not Expose Proxmox Directly?

Giving students direct access to the hypervisor creates unnecessary risk.

A user who only needs to interact with a Windows workstation does not need access to:

- VM creation
- VM deletion
- Storage
- Network bridges
- Snapshots
- Host configuration
- Other lab systems

The better model is:

```text
User
  |
  v
Remote Access Gateway
  |
  v
Assigned VM
```

This follows least privilege.

---

# 3. Why Not Expose RDP Directly?

Directly publishing:

```text
TCP 3389
```

to the public Internet increases exposure of the Windows endpoint.

Instead, keep RDP internal:

```text
Remote Browser
     |
     v
Gateway
     |
     | Internal RDP
     v
Windows Endpoint
```

The gateway becomes the only externally reachable application.

---

# 4. Why Apache Guacamole?

Apache Guacamole provides browser-based remote desktop access using HTML5.

It can proxy protocols such as:

- RDP
- SSH
- VNC

For a Windows student lab, this means a user can open a browser and interact with a Windows desktop without installing a local RDP client.

---

# 5. Why Cloudflare Tunnel?

A traditional public service often requires:

- Router port forwarding
- Public firewall rules
- Public exposure of an origin service

Cloudflare Tunnel changes that model.

The connector establishes an outbound connection from the lab to Cloudflare.

Conceptually:

```text
Lab
 |
 | Outbound tunnel
 v
Cloudflare
```

Remote users then access the application through Cloudflare without opening inbound ports on the home router.

---

# 6. Reference Architecture

```text
School / Remote Computer
          |
          | HTTPS
          v
     Cloudflare Edge
          |
          | Tunnel
          v
      Docker Host
          |
          v
 Apache Guacamole
          |
          | RDP
          v
 Windows Lab Endpoint
```

The Docker host remains on the private internal lab network.

---

# 7. Prerequisites

Before deploying the remote access layer, you should already have:

- A working internal lab network
- A Linux system with Docker
- A Windows endpoint
- RDP enabled on that endpoint
- Internal network connectivity between Docker and Windows
- A domain you control
- DNS managed through Cloudflare

You should also confirm that the Windows endpoint is reachable internally before adding Guacamole.

---

# 8. Validate RDP First

Do not begin by troubleshooting Guacamole.

First prove that the Windows endpoint is listening for RDP.

On Windows:

```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

Expected:

```text
State : Listen
```

Enable RDP if required:

```powershell
Set-ItemProperty `
  -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name 'fDenyTSConnections' `
  -Value 0
```

Enable the Windows Firewall rules:

```powershell
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

---

# 9. Validate the Network Path

From the future Guacamole host, verify TCP 3389 is reachable.

Example:

```bash
nc -vz <WINDOWS-LAB-IP> 3389
```

A successful result proves:

```text
Docker Host
    |
    | TCP 3389
    v
Windows Endpoint
```

If this fails, troubleshoot networking before installing or changing Guacamole.

---

# 10. Student RDP Account

The Windows account used for remote access should:

- Be active
- Have a password
- Be authorized for Remote Desktop
- Have only the permissions required for the lab

Example:

```powershell
net localgroup "Remote Desktop Users" <STUDENT_USER> /add
```

Verify:

```powershell
net localgroup "Remote Desktop Users"
```

---

# 11. Important Windows Authentication Note

Local Windows accounts used over RDP require valid credentials.

A local user with no usable password may work interactively at the console but fail when used for remote authentication.

Set a password securely:

```powershell
net user <STUDENT_USER> *
```

Do not hard-code passwords into scripts or GitHub documentation.

---

# 12. Deploy Apache Guacamole with Docker

A typical deployment uses three components:

```text
guacamole
guacd
postgresql
```

Roles:

```text
guacamole
    |
    +---- Web application

guacd
    |
    +---- Remote desktop proxy

postgresql
    |
    +---- Configuration database
```

---

# 13. Create a Working Directory

Example:

```bash
mkdir -p ~/guacamole
cd ~/guacamole
```

---

# 14. Example Docker Compose Design

Use placeholders for secrets.

```yaml
services:

  guacd:
    image: guacamole/guacd:latest
    container_name: guacd
    restart: unless-stopped

  postgres:
    image: postgres:16
    container_name: guac-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: guacamole_db
      POSTGRES_USER: guacamole_user
      POSTGRES_PASSWORD: <STRONG_DATABASE_PASSWORD>
    volumes:
      - guac_db:/var/lib/postgresql/data

  guacamole:
    image: guacamole/guacamole:latest
    container_name: guacamole
    restart: unless-stopped
    depends_on:
      - guacd
      - postgres
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRESQL_HOSTNAME: postgres
      POSTGRESQL_DATABASE: guacamole_db
      POSTGRESQL_USER: guacamole_user
      POSTGRESQL_PASSWORD: <STRONG_DATABASE_PASSWORD>
    ports:
      - "8081:8080"

volumes:
  guac_db:
```

Do not commit real database passwords.

---

# 15. Initialize the Guacamole Database

Generate the PostgreSQL schema:

```bash
docker run --rm \
  guacamole/guacamole:latest \
  /opt/guacamole/bin/initdb.sh --postgresql \
  > initdb.sql
```

Start PostgreSQL:

```bash
docker compose up -d postgres
```

Import the schema:

```bash
cat initdb.sql |
docker exec -i guac-postgres \
psql -U guacamole_user -d guacamole_db
```

Then start the remaining services:

```bash
docker compose up -d
```

---

# 16. Verify Containers

Check:

```bash
docker ps
```

Expected services include:

```text
guacamole
guacd
guac-postgres
```

---

# 17. Test Guacamole Internally

Before publishing anything externally, open Guacamole from a system already inside the lab.

Example:

```text
http://<DOCKER-HOST-IP>:8081/guacamole
```

Do not publish the service until internal access works.

---

# 18. Change Default Administrative Credentials

If the deployment includes default administrative credentials, change them immediately.

Do not leave default credentials enabled once the service is reachable beyond a local test environment.

---

# 19. Create an RDP Connection

In Guacamole, create a new connection.

Example:

```text
Name:
Windows-Lab-01

Protocol:
RDP
```

Network parameters:

```text
Hostname:
<PRIVATE_WINDOWS_IP>

Port:
3389
```

Authentication:

```text
Username:
<STUDENT_USER>

Password:
<STUDENT_PASSWORD>

Domain:
<LOCAL_COMPUTER_NAME_OR_DOMAIN>
```

Keep credentials out of GitHub.

---

# 20. Local vs Domain Accounts

If the user is a local Windows account:

```text
LAB-PC\Student01
```

then the RDP authentication domain should correspond to the local computer.

If the user is an Active Directory account:

```text
LABDOMAIN\Student01
```

then use the domain context.

This distinction is important when troubleshooting authentication failures.

---

# 21. RDP Security Settings

For an internal lab environment, Guacamole may require adjustments for certificate or security negotiation.

Common options include:

```text
Security Mode: Any
Ignore Server Certificate: Enabled
```

Use the least permissive settings that work in your environment.

---

# 22. Test the Browser Session

From the Guacamole interface:

1. Select the connection
2. Start the session
3. Confirm the Windows desktop loads
4. Verify keyboard and mouse input
5. Confirm the correct user session

Do not move to external publishing until this works reliably.

---

# 23. Troubleshooting Immediate Disconnects

A common symptom is:

```text
Connection opens
        |
        v
Session closes immediately
```

Do not assume this is a firewall issue.

First check:

```bash
docker logs guacd --tail 50
```

`guacd` is the component responsible for the actual RDP connection.

---

# 24. Example Authentication Failure

A Guacamole RDP session may fail even when:

```text
TCP 3389 is reachable
RDP is listening
Guacamole is healthy
```

because the Windows credentials are invalid.

Troubleshooting flow:

```text
Can the Docker host reach TCP 3389?
            |
            v
Yes
            |
            v
Check guacd logs
            |
            v
Authentication failure?
            |
            v
Validate Windows account
```

This helps distinguish a network issue from an identity issue.

---

# 25. Deploy Cloudflare Tunnel

Once Guacamole works internally, create a Cloudflare Tunnel.

A typical tunnel should publish only the required application.

Do not publish:

- Proxmox
- pfSense
- SSH
- Wazuh administration
- Docker management

if students only require Guacamole.

---

# 26. Cloudflare Connector

The connector can run as another Docker container.

Cloudflare provides the actual connector command and token.

The token is sensitive.

Never commit:

```text
<CLOUDFLARE_TUNNEL_TOKEN>
```

to GitHub.

---

# 27. Container Restart Policy

For a persistent lab gateway, the Cloudflare connector should use an appropriate restart policy so it returns after a Docker host reboot.

Example concept:

```text
restart: unless-stopped
```

Do not publish the actual tunnel token as part of a Docker command.

---

# 28. Publish the Application

Create a public hostname such as:

```text
lab.example.com
```

and route it to the internal Guacamole service.

Example origin:

```text
HTTP
http://<GUACAMOLE-HOST>:8081
```

Guacamole itself may remain under:

```text
/guacamole
```

depending on the deployment.

---

# 29. External Traffic Flow

The completed architecture becomes:

```text
Remote Browser
      |
      | HTTPS
      v
Cloudflare
      |
      | Tunnel
      v
Docker Host
      |
      v
Guacamole
      |
      | RDP
      v
Internal Windows Endpoint
```

---

# 30. Validate from Outside the Lab

Do not consider the remote-access layer complete because it works from inside the network.

Test from a genuinely external system.

Examples:

- Cellular hotspot
- School computer
- Work computer
- Another external network

The test should not depend on your existing administrative VPN.

---

# 31. Browser-Only Validation

A successful browser-only design should require the remote user to install nothing.

The remote system should only require:

```text
Modern Web Browser
        +
Valid Lab Credentials
```

No:

```text
Tailscale
RDP Client
Proxmox Client
VPN Software
```

should be required for the basic user experience.

---

# 32. User Separation

Do not give students the Guacamole administrator account.

Create separate users:

```text
team01
team02
team03
```

Each user should only receive permission to use its assigned connection.

Example:

```text
team01
   |
   v
Windows-Lab-Team01
```

not:

```text
team01
   |
   +---- Team01
   +---- Team02
   +---- Team03
   +---- Administrative Connections
```

---

# 33. Multiple Security Layers

A mature implementation can use multiple authentication layers.

Example:

```text
Layer 1:
Cloudflare Access

Layer 2:
Guacamole Authentication

Layer 3:
Windows / Active Directory Authentication
```

Each layer protects a different boundary.

---

# 34. Add Cloudflare Access

Cloudflare Tunnel publishes the application.

Cloudflare Access can add an identity-aware gate in front of it.

Conceptually:

```text
Internet
   |
   v
Cloudflare Access
   |
   v
Guacamole
   |
   v
Windows Endpoint
```

This is recommended before broad or long-term student use.

---

# 35. Remote Access and Network Segmentation

Remote access does not automatically isolate internal endpoints.

Even if:

```text
team01
```

can only see Team01 in Guacamole, the underlying Windows endpoints may still share a network.

For stronger isolation, combine the remote access gateway with:

- VLANs
- Separate subnets
- Firewall policies
- Team-specific ACLs

---

# 36. Security Boundaries

A useful remote-access design separates:

```text
External Access
      |
      v
Access Gateway
      |
      v
Internal Endpoint
      |
      v
Core Infrastructure
```

Students should not need access to the infrastructure layer.

---

# 37. Logging

Remote access itself should eventually become part of the monitoring architecture.

Useful log sources include:

- Cloudflare access events
- Guacamole authentication
- Guacamole connection activity
- Windows RDP authentication
- Windows Security logs
- Wazuh endpoint telemetry

This creates an investigation path such as:

```text
Remote Login
    |
    v
Guacamole
    |
    v
Windows Authentication
    |
    v
Windows Security Log
    |
    v
SIEM
```

---

# 38. Recommended Validation Checklist

Before allowing users into the lab, validate:

```text
[ ] Guacamole containers are healthy
[ ] Guacamole loads internally
[ ] RDP is listening
[ ] Docker host reaches RDP
[ ] Student account has a password
[ ] Student account has RDP permission
[ ] Guacamole connection succeeds
[ ] Public hostname resolves
[ ] Cloudflare Tunnel is healthy
[ ] External browser reaches Guacamole
[ ] Non-admin user can log in
[ ] User only sees assigned connection
```

---

# 39. Common Failure: Tunnel Is Inactive

If Cloudflare reports the tunnel as inactive:

1. Verify the connector is running
2. Review connector logs
3. Confirm the tunnel token was entered correctly
4. Confirm the connector registered successfully
5. Do not troubleshoot DNS before the connector itself is healthy

---

# 40. Common Failure: Public URL Returns 404

A 404 does not always mean the tunnel is broken.

Check:

- Published application route
- Origin service address
- Application path
- Guacamole context path
- Whether the root hostname and `/guacamole` path behave differently

Always distinguish:

```text
Cloudflare routing problem
```

from:

```text
Application routing problem
```

---

# 41. MutaSpace Reference Implementation

The MutaSpace lab uses this design to provide browser-based access to internal Windows investigation systems.

The implementation successfully demonstrated:

- Internal RDP
- Guacamole proxying
- Docker-based deployment
- Cloudflare Tunnel
- Public HTTPS access
- Browser-based Windows sessions
- Access from a school-managed computer without VPN software

The MutaSpace environment serves as the reference implementation for this guide.

---

# 42. Security Principle

The core design principle is:

> Publish the minimum application required for the user to perform the task.

If a user only needs a Windows desktop, publish the controlled remote desktop gateway.

Do not expose the hypervisor, firewall, or internal management interfaces simply because they are convenient.