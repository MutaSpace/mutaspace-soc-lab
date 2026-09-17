# Network Validation and Troubleshooting

This guide provides a repeatable troubleshooting method for Windows and Linux systems in the MutaSpace Enterprise Security Lab.

The goal is to avoid random troubleshooting.

Instead, validate the network one layer at a time.

---

# 1. The Troubleshooting Model

Use this sequence:

```text
NIC
 |
 v
IP Address
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
Service Port
 |
 v
Application
```

Do not start at the application layer if the underlying network has not been validated.

---

# 2. Step 1: Confirm the Network Interface

Windows:

```powershell
Get-NetAdapter
```

Linux:

```bash
ip link
```

Confirm:

- Interface exists
- Interface is enabled
- Link state is up where appropriate

If the interface is missing or disconnected, check the VM configuration in Proxmox.

---

# 3. Step 2: Confirm IP Addressing

Windows:

```powershell
ipconfig /all
```

Linux:

```bash
ip -br addr
```

Confirm:

- Correct subnet
- Expected address type
- No unexpected duplicate addresses
- Correct interface

---

# 4. Step 3: Confirm the Default Route

Windows:

```powershell
route print
```

Linux:

```bash
ip route
```

Look for a default route.

Example:

```text
default via 10.10.10.1
```

Without a valid default route, the host may communicate locally but fail to reach other networks.

---

# 5. Step 4: Test the Gateway

Windows:

```powershell
ping 10.10.10.1
```

Linux:

```bash
ping -c 3 10.10.10.1
```

If this fails, investigate:

- Proxmox bridge assignment
- Guest IP configuration
- Subnet
- Virtual NIC
- pfSense LAN state

---

# 6. Step 5: Test Another Internal Host

Example:

```powershell
ping 10.10.10.10
```

or:

```bash
ping -c 3 10.10.10.10
```

This helps distinguish:

```text
Local VM problem
```

from:

```text
Gateway / external routing problem
```

---

# 7. Step 6: Test External Connectivity by IP

Windows:

```powershell
ping 1.1.1.1
```

Linux:

```bash
ping -c 3 1.1.1.1
```

If this works but names fail, routing likely works and DNS needs investigation.

---

# 8. Step 7: Validate DNS

Windows:

```powershell
Resolve-DnsName example.com
```

Linux:

```bash
getent hosts example.com
```

For Active Directory:

```powershell
Resolve-DnsName <DOMAIN_CONTROLLER_FQDN>
```

Linux:

```bash
getent hosts <DOMAIN_CONTROLLER_FQDN>
```

---

# 9. Step 8: Validate the Service Port

Ping does not prove that an application is reachable.

Windows:

```powershell
Test-NetConnection <HOST> -Port <PORT>
```

Linux:

```bash
nc -vz <HOST> <PORT>
```

Examples:

```text
DNS      53
SSH      22
HTTP     80
HTTPS    443
RDP      3389
```

Monitoring platforms may use additional service-specific ports.

---

# 10. Step 9: Test the Application

Only after the lower layers are validated should you troubleshoot the application itself.

Examples:

```text
Browser
SSH Client
RDP
Wazuh Agent
LDAP
Kerberos
Guacamole
```

If the port is reachable but the application fails, investigate:

- Authentication
- Authorization
- Application configuration
- Certificates
- Service state
- Protocol negotiation

---

# 11. Network vs Application Failure

This distinction is extremely important.

Example:

```text
TCP 3389 reachable
        |
        v
RDP session fails
```

The network path exists.

The next investigation should focus on:

- Credentials
- RDP permission
- Security negotiation
- Account state

not on changing routing randomly.

---

# 12. DNS vs Connectivity Failure

Example:

```text
Ping 1.1.1.1 works
Resolve example.com fails
```

This strongly suggests:

```text
Routing works
DNS does not
```

Do not troubleshoot NAT first.

---

# 13. Internal DNS vs Public DNS

Example:

```text
example.com resolves
dc-01.example.local does not
```

This indicates:

```text
Public DNS works
Internal enterprise DNS does not
```

Investigate:

- Client DNS configuration
- Internal DNS server
- DHCP DNS settings
- AD DNS zone
- Client lease state

---

# 14. Domain Join Failure

Before troubleshooting Active Directory credentials, validate:

```text
Correct IP
Correct Gateway
Correct DNS
Domain Controller Resolution
AD SRV Records
```

A domain join problem is often actually a DNS problem.

---

# 15. Check Windows DNS

```powershell
ipconfig /all
```

Look for:

```text
DNS Servers
```

For an Active Directory environment, the client should normally use the internal AD DNS service.

---

# 16. Check Ubuntu DNS

```bash
resolvectl status
```

Modern Ubuntu may use:

```text
127.0.0.53
```

as a local resolver stub.

That is not necessarily an error.

Check the actual upstream DNS server shown for the active interface.

---

# 17. Flush Windows DNS Cache

If stale results are suspected:

```powershell
ipconfig /flushdns
```

Then rerun the query.

---

# 18. Renew Windows DHCP

```powershell
ipconfig /release
ipconfig /renew
```

Then verify:

```powershell
ipconfig /all
```

This is especially useful after changing DHCP-provided DNS settings.

---

# 19. Multiple Linux IP Addresses

If a Linux VM has multiple unexpected addresses:

```bash
ip addr
```

Then inspect:

```bash
ls -l /etc/netplan/
```

and:

```bash
sudo cat /etc/netplan/*.yaml
```

Multiple Netplan files may be configuring the same interface.

---

# 20. Multiple Default Routes

Check:

```bash
ip route
```

Unexpected multiple default routes can result from:

- Static configuration
- DHCP
- Cloud-init
- Multiple network interfaces

Identify the source before removing routes manually.

---

# 21. Validate Proxmox Bridge Placement

If a VM receives unexpected addressing, check:

```text
Proxmox
   |
   v
VM
   |
   v
Hardware
   |
   v
Network Device
```

Verify the bridge.

Typical internal VM:

```text
vmbr1
```

A VM accidentally connected to `vmbr0` may bypass the intended internal network.

---

# 22. Verify Service State

Sometimes the network is working and the service is not.

Windows example:

```powershell
Get-Service
```

Linux example:

```bash
systemctl status <SERVICE>
```

Do not assume an open network path means the destination application is running.

---

# 23. Firewall Troubleshooting

If the destination host and service appear healthy but traffic fails:

Check:

- Host firewall
- pfSense firewall
- Source
- Destination
- Protocol
- Port
- Rule order
- Firewall logs

Use logs whenever possible instead of guessing.

---

# 24. Troubleshooting RDP

Validate:

```text
RDP enabled?
Windows Firewall rule enabled?
TCP 3389 listening?
Gateway can reach 3389?
User has RDP permission?
User has valid credentials?
```

Windows listener:

```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

Linux gateway test:

```bash
nc -vz <WINDOWS_IP> 3389
```

---

# 25. Troubleshooting Wazuh Connectivity

Separate:

```text
Network Connectivity
```

from:

```text
Agent Identity / Authentication
```

First test manager reachability and the appropriate service port.

Then investigate:

- Agent name
- Enrollment state
- Key
- Service status
- Agent logs

Do not immediately recreate the agent if basic networking has not been tested.

---

# 26. Troubleshooting Remote Access Gateways

For a browser-based remote gateway:

```text
Can the browser reach the gateway?
        |
        v
Is the gateway application healthy?
        |
        v
Can gateway reach endpoint port?
        |
        v
Is endpoint service running?
        |
        v
Are credentials valid?
```

This sequence prevents an authentication failure from being mistaken for a routing issue.

---

# 27. Linux Validation Sequence

A compact sequence:

```bash
ip -br addr

ip route

resolvectl status

ping -c 2 10.10.10.1

ping -c 2 1.1.1.1

getent hosts example.com
```

Then test the required application port.

---

# 28. Windows Validation Sequence

```powershell
ipconfig /all

ping 10.10.10.1

ping 1.1.1.1

Resolve-DnsName example.com

Resolve-DnsName <INTERNAL_HOST>

Test-NetConnection <HOST> -Port <PORT>
```

---

# 29. Read the Error Message

A useful troubleshooting habit is to identify the layer suggested by the error.

Examples:

```text
Host unreachable
```

often points toward networking.

```text
Name not found
```

often points toward DNS.

```text
Connection refused
```

may indicate the destination is reachable but nothing is listening on the requested port.

```text
Authentication failed
```

usually means the network path progressed far enough to reach an authentication layer.

---

# 30. Do Not Change Multiple Layers at Once

Avoid:

```text
Change IP
Change DNS
Disable firewall
Reinstall application
Reset credentials
```

all at once.

If the issue disappears, you will not know what fixed it.

A better method is:

```text
Form hypothesis
      |
      v
Test one layer
      |
      v
Observe result
      |
      v
Change one thing
      |
      v
Validate again
```

---

# 31. Use Logs

Network troubleshooting should not rely only on commands.

Useful logs may include:

- pfSense firewall logs
- Windows Event Viewer
- Linux system logs
- Application logs
- Wazuh agent logs
- Guacamole / guacd logs
- Docker logs

Logs help explain why a technically reachable service still failed.

---

# 32. Document the Root Cause

A strong troubleshooting note should capture:

```text
Symptom
   |
   v
Evidence
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

This makes troubleshooting reusable instead of becoming a one-time fix.

---

# 33. MutaSpace Troubleshooting Lessons

The MutaSpace build has reinforced several general lessons:

- Working Internet does not prove internal DNS is correct
- Ping does not prove an application port is reachable
- A reachable port does not prove authentication will succeed
- A domain problem may actually be DNS
- Multiple configuration files can create multiple IP addresses
- Monitoring failures can involve identity rather than routing
- Remote access failures can occur after the network path is already working

These patterns are applicable well beyond the lab.

---

# 34. Final Troubleshooting Checklist

When a system cannot communicate:

```text
[ ] VM is powered on
[ ] Virtual NIC is connected
[ ] Correct Proxmox bridge
[ ] Correct IP address
[ ] Correct subnet
[ ] Correct gateway
[ ] Gateway reachable
[ ] Destination IP reachable
[ ] Correct DNS server
[ ] Internal name resolves
[ ] External name resolves
[ ] Required port reachable
[ ] Destination service running
[ ] Host firewall allows traffic
[ ] pfSense policy allows traffic
[ ] Authentication is valid
[ ] Application logs reviewed
```

---

# 35. Troubleshooting Principle

The most important rule is:

> Prove the lower layers before changing the higher layers.

A structured troubleshooting process turns a large, confusing failure into a sequence of smaller questions that can be answered one at a time.