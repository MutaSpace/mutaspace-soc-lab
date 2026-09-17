# Building the Lab Gateway with pfSense

This guide explains how pfSense is used as the firewall, router, gateway, DHCP provider, and network boundary for the MutaSpace Enterprise Security Lab.

The Proxmox bridge layer provides virtual network connectivity, but bridges alone do not route traffic between different networks.

pfSense provides that Layer 3 functionality.

The reference implementation connects pfSense between:

- `vmbr0`, which provides upstream connectivity
- `vmbr1`, which provides the private internal lab network

---

# 1. What Are We Building?

The target architecture is:

```text
                    Upstream Network
                           |
                           v
                         vmbr0
                           |
                           v
                      pfSense WAN
                           |
                    +-------------+
                    |   pfSense   |
                    +-------------+
                           |
                      pfSense LAN
                           |
                           v
                         vmbr1
                           |
             +-------------+-------------+
             |             |             |
             v             v             v
          AD / DNS       Wazuh        Endpoints
```

pfSense becomes the gateway between the internal security lab and the upstream network.

---

# 2. What Does pfSense Do?

In this architecture, pfSense provides several important network functions:

- Routing
- Firewalling
- Default gateway services
- Network Address Translation
- DHCP
- Traffic policy enforcement
- A foundation for future segmentation

Instead of allowing every internal VM to connect directly to the upstream network, internal systems send traffic through pfSense.

---

# 3. Firewall vs Router

A router moves traffic between networks.

A firewall determines which traffic should be permitted between those networks.

pfSense performs both roles.

Conceptually:

```text
Network A
   |
   v
+----------------+
|    pfSense     |
|                |
| Routing        |
| Firewall Rules |
+----------------+
   |
   v
Network B
```

This makes pfSense a useful platform for learning both networking and security concepts.

---

# 4. Reference Interfaces

The pfSense VM uses two virtual network interfaces in the current MutaSpace implementation.

| pfSense Interface | Proxmox Bridge | Purpose |
|---|---|---|
| WAN | `vmbr0` | Upstream connectivity |
| LAN | `vmbr1` | Internal security lab |

Conceptually:

```text
WAN -> vmbr0

LAN -> vmbr1
```

Additional interfaces can be introduced later when the lab implements additional network segments.

---

# 5. Create the pfSense VM

Create a new virtual machine in Proxmox using the pfSense installation image.

A typical deployment requires:

- pfSense installation media
- Virtual CPU resources
- Memory
- Virtual disk
- Two virtual network interfaces

The exact resource allocation can be adjusted based on the host and expected lab workload.

The important requirement for this architecture is that the VM has at least two NICs.

---

# 6. Assign the Virtual NICs

In Proxmox, open:

```text
pfSense VM
    |
    v
Hardware
```

Verify that two network devices exist.

Assign:

```text
WAN NIC -> vmbr0
LAN NIC -> vmbr1
```

The order in which pfSense detects the interfaces may vary.

Do not assume the first interface is automatically WAN.

Verify the interface assignments during pfSense configuration.

---

# 7. Understanding WAN and LAN

The two interfaces have different trust roles.

## WAN

The WAN interface faces the upstream network.

```text
Upstream
   |
   v
WAN
```

## LAN

The LAN interface faces the protected internal lab.

```text
LAN
 |
 v
Internal Security Lab
```

Together:

```text
Upstream
   |
   v
 WAN
   |
pfSense
   |
 LAN
   |
   v
Internal Lab
```

---

# 8. Configure the WAN Interface

The WAN interface connects to `vmbr0`.

Its exact IP configuration depends on the upstream environment.

It may receive an address through DHCP or use another configuration appropriate for the environment.

The public documentation should not require the builder to use the same upstream addressing as the MutaSpace environment.

The important relationship is:

```text
pfSense WAN
     |
     v
   vmbr0
     |
     v
Upstream Network
```

---

# 9. Configure the LAN Interface

The reference internal network is:

```text
10.10.10.0/24
```

pfSense uses:

```text
10.10.10.1
```

as its LAN address.

Therefore:

```text
LAN Address:
10.10.10.1/24
```

This makes pfSense the default gateway for the internal network.

---

# 10. Understanding `/24`

The network:

```text
10.10.10.0/24
```

uses the subnet mask:

```text
255.255.255.0
```

In a conventional `/24` network:

```text
Network Address:
10.10.10.0

Typical Host Range:
10.10.10.1 - 10.10.10.254

Broadcast Address:
10.10.10.255
```

The gateway occupies one usable address:

```text
10.10.10.1
```

Other addresses can then be assigned to infrastructure and endpoints.

---

# 11. Why pfSense Becomes the Gateway

Consider an internal endpoint:

```text
10.10.10.100
```

If it communicates with:

```text
10.10.10.20
```

both systems are on the same subnet.

The traffic can remain on the internal network.

But if the endpoint needs to reach a different network, it sends that traffic to:

```text
10.10.10.1
```

which is pfSense.

Conceptually:

```text
Internal Endpoint
10.10.10.100
      |
      | Destination outside 10.10.10.0/24
      v
10.10.10.1
      |
      v
   pfSense
      |
      v
Other Network
```

---

# 12. Configure DHCP

pfSense can provide DHCP addresses to client systems on the internal LAN.

This is useful for systems such as:

- Windows workstations
- Temporary lab endpoints
- Student workstations
- Test systems

Infrastructure systems generally benefit from predictable addressing.

---

# 13. Plan the Address Space

The MutaSpace reference implementation reserves predictable addresses for core infrastructure.

Example:

```text
10.10.10.1    Gateway
10.10.10.10   Directory / DNS
10.10.10.20   Security Monitoring
10.10.10.30   Application Server
10.10.10.40   Container Host
10.10.10.50   Certificate Services
```

Client systems can use a separate portion of the subnet through DHCP.

This produces a pattern such as:

```text
Lower Addresses
      |
      v
Core Infrastructure

Higher Addresses
      |
      v
DHCP Clients
```

The exact ranges are design choices.

---

# 14. Static Addressing vs DHCP

A useful general strategy is:

```text
Core Infrastructure
       |
       v
Predictable Addressing

Client Workstations
       |
       v
DHCP
```

Systems that other services depend on should generally be easy to locate consistently.

Examples include:

- DNS servers
- Domain controllers
- SIEM servers
- Application servers
- Certificate services
- Container hosts

---

# 15. Configure DHCP DNS Carefully

DHCP does more than provide an IP address.

It can also provide:

- Subnet mask
- Default gateway
- DNS server
- Domain information

In an Active Directory environment, the DNS configuration is especially important.

Domain-joined clients should use the internal Active Directory DNS service.

For the reference architecture:

```text
DNS Server:
10.10.10.10
```

---

# 16. Why Public DNS Is Not Enough

A workstation configured with a public resolver may still access the Internet.

For example:

```text
DNS:
8.8.8.8
```

might successfully resolve:

```text
github.com
```

but it cannot provide authoritative information about the private Active Directory environment.

That can lead to:

```text
Internet works
       |
       v
Internal domain resolution fails
       |
       v
Domain services fail
```

This is why working Internet access does not prove the endpoint has correct DNS configuration.

---

# 17. Active Directory DNS Flow

A better design is:

```text
Windows Endpoint
      |
      | DNS Query
      v
Active Directory DNS
      |
      +---- Internal name?
      |         |
      |         v
      |    Resolve internally
      |
      +---- External name?
                |
                v
          Forward upstream
```

This allows clients to use one DNS configuration for both internal and external resolution.

The Active Directory DNS configuration is covered in a separate networking guide.

---

# 18. Network Address Translation

The internal network uses private RFC1918 addressing.

Addresses such as:

```text
10.10.10.20
```

are not directly routed across the public Internet.

pfSense can use Network Address Translation to allow internal systems to initiate external connections.

Conceptually:

```text
Internal VM
10.10.10.x
     |
     v
   pfSense
     |
     | NAT
     v
Upstream Network
     |
     v
Internet
```

---

# 19. Why NAT Matters

Without appropriate routing and NAT, an internal VM may be able to communicate with other internal systems but fail to reach external networks.

This distinction is useful when troubleshooting.

For example:

```text
Can reach 10.10.10.1
Can reach 10.10.10.20
Cannot reach external IP
```

suggests a different problem from:

```text
Cannot reach 10.10.10.1
```

The first may involve routing, NAT, firewalling, or upstream connectivity.

The second indicates a problem much closer to the endpoint or internal network.

---

# 20. Firewall Rules

pfSense evaluates traffic according to firewall policy.

A firewall rule typically considers information such as:

```text
Source
Destination
Protocol
Port
Action
```

Conceptually:

```text
Source:
Internal LAN

Destination:
External Network

Protocol:
TCP

Action:
Allow
```

The actual rules should reflect the security requirements of the environment.

---

# 21. Start Simple

During the initial build, the goal is to establish and validate basic connectivity.

A useful progression is:

```text
Build connectivity
       |
       v
Validate routing
       |
       v
Validate DNS
       |
       v
Validate applications
       |
       v
Restrict traffic intentionally
```

Adding restrictive firewall policy before understanding the required traffic can make initial troubleshooting unnecessarily difficult.

---

# 22. Validate the LAN Interface

From an internal Windows system:

```powershell
ipconfig /all
```

Confirm:

- IP address belongs to the intended subnet
- Subnet mask is correct
- Default gateway points to pfSense
- DNS points to the intended internal DNS server

Then:

```powershell
ping 10.10.10.1
```

---

# 23. Validate from Linux

On Linux:

```bash
ip addr
ip route
```

Look for a default route similar to:

```text
default via 10.10.10.1
```

Then:

```bash
ping -c 2 10.10.10.1
```

---

# 24. Validate Internal Connectivity

Test another internal infrastructure system.

Example:

```powershell
ping 10.10.10.10
```

or:

```bash
ping -c 2 10.10.10.10
```

This confirms that the endpoint can communicate with another system on the internal network.

---

# 25. Validate External Connectivity

Test an external IP address.

Example:

```powershell
ping 1.1.1.1
```

or:

```bash
ping -c 2 1.1.1.1
```

If internal connectivity works but external connectivity fails, investigate:

- pfSense routing
- NAT
- Firewall policy
- WAN configuration
- Upstream connectivity

---

# 26. Validate DNS Separately

After testing external connectivity by IP, test name resolution.

Windows:

```powershell
Resolve-DnsName example.com
```

Linux:

```bash
getent hosts example.com
```

This distinction is important.

If:

```text
External IP works
Hostname fails
```

the problem is likely related to DNS rather than basic routing.

---

# 27. Troubleshooting Order

When an internal system cannot communicate, use a consistent troubleshooting process.

```text
1. VM NIC connected?
        |
        v
2. Correct Proxmox bridge?
        |
        v
3. Correct IP address?
        |
        v
4. Correct subnet?
        |
        v
5. Correct gateway?
        |
        v
6. Can reach pfSense?
        |
        v
7. Can reach internal systems?
        |
        v
8. Can reach an external IP?
        |
        v
9. Does DNS work?
        |
        v
10. Does the application work?
```

This approach separates network-layer problems from application-layer problems.

---

# 28. Common Problem: Wrong Bridge

If a VM is accidentally attached to:

```text
vmbr0
```

instead of:

```text
vmbr1
```

it may receive addressing from the upstream network.

Symptoms can include:

- Unexpected IP address
- Wrong default gateway
- Internal DNS failure
- Domain join problems
- Bypassing the lab firewall

Always verify the Proxmox virtual NIC configuration.

---

# 29. Common Problem: Wrong Gateway

An internal VM should use the pfSense LAN address as its gateway.

For the reference network:

```text
10.10.10.1
```

If the gateway is missing or incorrect, the system may communicate locally while failing to reach other networks.

---

# 30. Common Problem: Wrong DNS

A client may successfully reach:

```text
1.1.1.1
```

while failing to locate:

```text
dc-01.mutaspace.local
```

That indicates connectivity exists, but name resolution needs investigation.

Do not interpret successful Internet connectivity as proof that Active Directory networking is healthy.

---

# 31. Common Problem: Firewall Rule

If:

- IP configuration is correct
- Gateway is reachable
- Routing appears correct
- Required destination exists

but a specific connection still fails, investigate firewall policy.

Review:

- Source network
- Destination
- Protocol
- Port
- Rule order
- Firewall logs

Firewall logs can help determine whether traffic was rejected or dropped.

---

# 32. Test Services, Not Just Ping

Ping tests ICMP.

It does not prove that a specific application port is reachable.

Windows:

```powershell
Test-NetConnection <HOST> -Port <PORT>
```

Linux:

```bash
nc -vz <HOST> <PORT>
```

Examples of services that may need independent testing include:

```text
DNS
Kerberos
LDAP
RDP
SSH
HTTP
HTTPS
Wazuh
```

---

# 33. Security Boundary

The current architecture creates this primary boundary:

```text
Upstream Network
       |
       v
    pfSense
       |
       v
Internal Security Lab
```

This is the first major network trust boundary in the environment.

The internal network is currently broader than the final desired architecture.

Additional segmentation will be introduced later.

---

# 34. Current vs Future Segmentation

The current implementation primarily uses:

```text
10.10.10.0/24
```

as the internal enterprise lab network.

The lab does not yet claim separate network isolation for:

- Student teams
- Attack simulation
- Identity infrastructure
- Applications
- Security sensors

Those are future security architecture improvements.

---

# 35. Why Segmentation Comes Later

A more advanced design may eventually resemble:

```text
                       pfSense
                          |
        +-----------------+-----------------+
        |                 |                 |
        v                 v                 v
 Infrastructure       Applications        Students
                                           |
                                  +--------+--------+
                                  |        |        |
                                  v        v        v
                               Team 01  Team 02  Team 03
```

However, segmentation introduces additional:

- Interfaces
- Subnets
- VLANs
- Routes
- DHCP scopes
- Firewall rules
- Troubleshooting paths

The base network should be understood before adding those layers.

---

# 36. pfSense as a Security Learning Platform

pfSense is not only providing Internet access.

It creates opportunities to practice:

- Firewall rule analysis
- Routing
- NAT
- DHCP
- DNS troubleshooting
- Network segmentation
- Traffic logging
- Access-control design
- Incident investigation

This makes the firewall part of the cybersecurity lab rather than merely supporting infrastructure.

---

# 37. Validation Checklist

Before considering the base pfSense network functional:

```text
[ ] pfSense WAN is connected to vmbr0
[ ] pfSense LAN is connected to vmbr1
[ ] LAN uses the intended internal subnet
[ ] Internal clients receive or use correct IP addresses
[ ] Internal clients use pfSense as their default gateway
[ ] Infrastructure addressing is predictable
[ ] DHCP works for intended clients
[ ] Clients use the intended internal DNS server
[ ] Internal systems can reach the gateway
[ ] Internal systems can communicate where required
[ ] Outbound routing works
[ ] NAT works
[ ] External name resolution works
```

---

# 38. MutaSpace Reference Implementation

The MutaSpace Enterprise Security Lab currently uses pfSense as the gateway between the upstream environment and the private lab network.

The implemented design includes:

```text
WAN -> vmbr0

LAN -> vmbr1

Internal Network -> 10.10.10.0/24

Internal Gateway -> 10.10.10.1
```

The environment has successfully supported communication between:

- Active Directory and DNS
- Wazuh
- Windows endpoints
- Linux endpoints
- Application infrastructure
- Docker infrastructure
- Certificate services
- Student workstations
- Remote-access infrastructure

The current network intentionally establishes a functional enterprise foundation before introducing additional VLAN and firewall segmentation.

---

# 39. Design Principle

pfSense is the point where virtual networking becomes routed and controlled networking.

The relationship is:

```text
Proxmox Bridge
      |
      v
Virtual Firewall
      |
      v
Routing + Policy
      |
      v
Internal Services
```

Understanding that relationship provides the foundation for later work involving VLANs, network monitoring, attack simulation, firewall analysis, and security segmentation.