# Active Directory DNS Design and Validation

This guide explains why DNS is critical in an Active Directory environment, how to configure clients to use the domain controller for internal name resolution, and how to validate the complete DNS path.

The reference implementation uses:

- pfSense for DHCP
- Windows Server for Active Directory Domain Services
- Windows Server DNS
- Linux and Windows clients on the internal lab network

The central design principle is:

> Domain-joined systems should use the Active Directory DNS server for internal name resolution.

---

# 1. Why DNS Matters in Active Directory

Active Directory depends heavily on DNS.

A client does not simply need to know the IP address of the domain controller.

It also needs to locate domain services such as:

- Domain controllers
- Kerberos
- LDAP
- Global Catalog services
- Service records
- Internal hosts

This means a network can appear healthy while Active Directory is still broken.

For example:

```text
Client can reach the gateway
Client can access the Internet
Client can resolve public websites
```

while still failing to:

```text
Resolve the internal domain
Locate the domain controller
Join Active Directory
Authenticate to the domain
```

The missing layer may be DNS.

---

# 2. Reference DNS Architecture

The reference design is:

```text
Internal Client
      |
      | DNS Query
      v
Active Directory DNS Server
      |
      +---- Internal name?
      |         |
      |         v
      |    Resolve locally
      |
      +---- External name?
                |
                v
          Forward upstream
```

This allows internal clients to use one DNS configuration for both:

- Internal enterprise names
- External Internet names

---

# 3. Reference Environment

The MutaSpace reference implementation uses:

```text
Internal Network:
10.10.10.0/24

Gateway:
10.10.10.1

Active Directory / DNS:
10.10.10.10

Internal Domain:
mutaspace.local
```

These addresses are examples and can be changed in another environment.

---

# 4. Why Clients Should Not Use Public DNS Directly

Suppose a domain-joined workstation uses:

```text
8.8.8.8
```

as its DNS server.

The client may successfully resolve:

```text
google.com
```

but a public resolver does not know about the private Active Directory domain:

```text
mutaspace.local
```

This can lead to:

```text
Internet works
      |
      v
Internal DNS fails
      |
      v
Domain services fail
```

This is one of the most common beginner mistakes in Active Directory labs.

---

# 5. DNS and DHCP

If clients receive network settings through DHCP, the DHCP server should provide the correct internal DNS server.

In the reference architecture:

```text
DHCP Provider:
pfSense

Gateway:
10.10.10.1

DNS Server:
10.10.10.10

DNS Domain:
mutaspace.local
```

The gateway and DNS server are different systems.

That distinction is important.

---

# 6. Gateway vs DNS Server

The gateway answers:

```text
Where should traffic go when the destination is outside my subnet?
```

The DNS server answers:

```text
What IP address belongs to this hostname?
```

In the reference design:

```text
Gateway:
10.10.10.1

DNS:
10.10.10.10
```

They serve different purposes.

---

# 7. Configure DHCP to Hand Out Internal DNS

In pfSense, update the LAN DHCP settings so clients receive the Active Directory DNS server.

The exact menu wording may vary by pfSense version, but the intended configuration is:

```text
DNS Server:
<DOMAIN_CONTROLLER_IP>

Domain:
<ACTIVE_DIRECTORY_DOMAIN>
```

For the reference environment:

```text
DNS Server:
10.10.10.10

Domain:
mutaspace.local
```

---

# 8. Renew Client DHCP Settings

After changing the DHCP-provided DNS server, existing clients may still have an old lease.

Windows:

```powershell
ipconfig /release
ipconfig /renew
```

Linux behavior depends on the network stack in use.

In many modern Ubuntu systems, DHCP and DNS state can be inspected using:

```bash
resolvectl status
```

The goal is to confirm that the client is actually using the new DNS configuration.

---

# 9. Validate DNS on Windows

Start with:

```powershell
ipconfig /all
```

Look for:

```text
DNS Servers
```

and confirm the internal DNS server appears.

Then test:

```powershell
Resolve-DnsName <ACTIVE_DIRECTORY_DOMAIN>
```

and:

```powershell
Resolve-DnsName <DOMAIN_CONTROLLER_FQDN>
```

Example:

```powershell
Resolve-DnsName mutaspace.local
Resolve-DnsName dc-01.mutaspace.local
```

---

# 10. Validate DNS on Linux

On Ubuntu:

```bash
resolvectl status
```

Look for the DNS server associated with the active interface.

Example:

```text
DNS Servers: 10.10.10.10
DNS Domain: mutaspace.local
```

Then test internal resolution:

```bash
getent hosts dc-01.mutaspace.local
```

or:

```bash
nslookup dc-01.mutaspace.local
```

---

# 11. Understanding `127.0.0.53` on Ubuntu

Ubuntu may show:

```text
127.0.0.53
```

as the DNS server during commands such as:

```bash
nslookup
```

This does not necessarily mean the system is using the wrong DNS server.

Modern Ubuntu commonly uses:

```text
systemd-resolved
```

with a local stub resolver.

Conceptually:

```text
Application
    |
    v
127.0.0.53
    |
    v
systemd-resolved
    |
    v
Actual Upstream DNS Server
```

The important information is shown by:

```bash
resolvectl status
```

which identifies the upstream DNS server associated with the interface.

---

# 12. Validate the Internal Domain

A basic test is:

```bash
nslookup mutaspace.local
```

or on Windows:

```powershell
Resolve-DnsName mutaspace.local
```

This confirms that the DNS server recognizes the internal domain.

---

# 13. Validate the Domain Controller

Next, resolve the domain controller directly.

Example:

```bash
nslookup dc-01.mutaspace.local
```

or:

```powershell
Resolve-DnsName dc-01.mutaspace.local
```

Expected behavior:

```text
Hostname resolves to the internal domain controller address
```

---

# 14. Why Resolving the Domain Controller Matters

Active Directory clients need to locate domain services.

DNS records help answer questions such as:

```text
Where is the domain controller?
Where is Kerberos?
Where is LDAP?
```

If the domain controller hostname cannot resolve, domain operations should not be trusted yet.

---

# 15. Active Directory Service Records

Active Directory uses DNS SRV records to advertise services.

Useful queries include:

```powershell
Resolve-DnsName _ldap._tcp.dc._msdcs.<DOMAIN> -Type SRV
```

and:

```powershell
Resolve-DnsName _kerberos._tcp.<DOMAIN> -Type SRV
```

Example:

```powershell
Resolve-DnsName _ldap._tcp.dc._msdcs.mutaspace.local -Type SRV
Resolve-DnsName _kerberos._tcp.mutaspace.local -Type SRV
```

These queries provide stronger validation than simply resolving the domain name.

---

# 16. Linux SRV Queries

If `dig` is installed:

```bash
dig SRV _ldap._tcp.dc._msdcs.<DOMAIN>
```

and:

```bash
dig SRV _kerberos._tcp.<DOMAIN>
```

These help confirm that the DNS server is advertising the domain services Active Directory clients need.

---

# 17. Test External Resolution Through Internal DNS

The internal DNS server should also support external name resolution through forwarding or recursion.

Test:

```powershell
Resolve-DnsName example.com
```

or:

```bash
getent hosts example.com
```

A working configuration should support both:

```text
Internal Names
      +
External Names
```

through the internal DNS server.

---

# 18. Complete DNS Validation Sequence

A useful Windows sequence is:

```powershell
ipconfig /all

Resolve-DnsName <DOMAIN>

Resolve-DnsName <DOMAIN_CONTROLLER_FQDN>

Resolve-DnsName _ldap._tcp.dc._msdcs.<DOMAIN> -Type SRV

Resolve-DnsName _kerberos._tcp.<DOMAIN> -Type SRV

Resolve-DnsName example.com
```

A useful Linux sequence is:

```bash
resolvectl status

getent hosts <DOMAIN_CONTROLLER_FQDN>

nslookup <DOMAIN>

nslookup <DOMAIN_CONTROLLER_FQDN>

getent hosts example.com
```

---

# 19. Troubleshooting Pattern: Internet Works, Domain Does Not

This is an important failure pattern.

Suppose:

```text
Gateway reachable
Internet reachable
Public DNS works
Internal domain does not resolve
```

The likely problem is not basic networking.

Investigate:

- Client DNS server
- DHCP DNS settings
- Internal DNS availability
- AD DNS zone
- SRV records
- Client lease state

---

# 20. Common Problem: pfSense Is Still Being Used as DNS

A client may receive:

```text
Gateway: pfSense
DNS: pfSense
```

and still reach the Internet.

However, if pfSense is not correctly forwarding or resolving the Active Directory zone, internal domain resolution may fail.

In an AD lab, the intended client DNS path is typically:

```text
Client
   |
   v
Active Directory DNS
   |
   v
Upstream DNS as needed
```

---

# 21. Common Problem: Client Did Not Renew DHCP

After changing DHCP settings, a client may continue using the old DNS server until its lease is refreshed.

Verify the actual client state instead of assuming the new DHCP configuration has already applied.

Windows:

```powershell
ipconfig /all
```

Linux:

```bash
resolvectl status
```

---

# 22. Common Problem: Public DNS Added as a Secondary Client Resolver

It may seem helpful to configure:

```text
Primary DNS:
Internal AD DNS

Secondary DNS:
Public DNS
```

but this can create inconsistent Active Directory behavior.

A client does not necessarily use DNS servers strictly in the order listed for every query.

For domain-joined systems, a safer design is usually:

```text
Client -> Internal AD DNS -> Forward external queries upstream
```

rather than sending clients directly to public resolvers.

---

# 23. Common Problem: DNS Cache

A client may cache a previous result.

Windows:

```powershell
ipconfig /flushdns
```

Then retry the query.

On Linux, the cache behavior depends on the resolver in use.

With `systemd-resolved`, status and cache behavior can be inspected through the system's resolver tooling.

---

# 24. Common Problem: Hostname Resolves but Domain Join Still Fails

Resolving:

```text
dc-01.example.local
```

is useful, but it does not prove all Active Directory service records are correct.

Test SRV records as well.

Active Directory relies heavily on those records for service discovery.

---

# 25. DNS and Kerberos

Kerberos relies on correct name resolution.

If the client cannot reliably locate the correct domain services, authentication may fail in confusing ways.

This is one reason DNS problems can appear to be:

```text
Password problems
Domain problems
Kerberos problems
```

when the actual root cause is name resolution.

---

# 26. DNS and Wazuh

Wazuh agents can be configured using:

```text
IP address
```

or:

```text
Hostname
```

If hostnames are used, DNS becomes another dependency in the monitoring path.

Conceptually:

```text
Wazuh Agent
    |
    | Resolve manager hostname
    v
DNS
    |
    v
Wazuh Manager
```

If DNS fails, the monitoring agent may appear to have a connectivity problem.

---

# 27. DNS and Application Infrastructure

Internal applications also benefit from reliable DNS.

Instead of requiring users to remember:

```text
10.10.10.30
```

they can use names such as:

```text
app01.example.local
```

This becomes increasingly important as the environment grows.

---

# 28. Validation Checklist

Before joining systems to Active Directory:

```text
[ ] Client has the correct IP address
[ ] Client has the correct gateway
[ ] Client is using internal AD DNS
[ ] Internal domain resolves
[ ] Domain controller FQDN resolves
[ ] LDAP SRV records resolve
[ ] Kerberos SRV records resolve
[ ] External names resolve through internal DNS
```

---

# 29. MutaSpace Reference Implementation

In the MutaSpace environment, the network initially passed:

```text
Gateway connectivity
External IP connectivity
Public DNS resolution
```

while internal Active Directory name resolution still failed.

The root cause was client DNS configuration.

Clients were updated through DHCP to use the internal Active Directory DNS server.

After renewing the client network configuration:

- The internal domain resolved
- The domain controller resolved
- Internal DNS became usable for later Active Directory operations

This demonstrated an important lesson:

> A network can appear healthy while the DNS configuration required by enterprise identity is still wrong.

---

# 30. Why This Validation Should Happen Early

Active Directory DNS should be validated before building large numbers of domain-dependent systems.

Otherwise, later failures may appear in:

- Domain joins
- Authentication
- Kerberos
- Monitoring
- Application connectivity

and create unnecessary troubleshooting complexity.

A better order is:

```text
Network
   |
   v
DNS
   |
   v
Active Directory Client Integration
   |
   v
Security Monitoring
   |
   v
Applications and Labs
```

---

# 31. Design Principle

In an Active Directory environment:

> DNS is part of the identity infrastructure.

Do not treat DNS as an optional convenience or something to troubleshoot only after authentication fails.

Validate it explicitly, early, and from the perspective of the clients that will depend on it.