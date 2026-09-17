# IP Addressing, DHCP, and Network Validation

This guide explains how to plan IP addressing, configure DHCP through pfSense, and validate that a new internal lab network is functioning correctly.

The reference implementation uses:

- Proxmox VE
- pfSense
- `vmbr1` as the internal lab bridge
- `10.10.10.0/24` as the internal subnet
- DHCP for client systems
- Predictable addressing for infrastructure

The goal is to confirm that a virtual machine can successfully communicate through the internal lab network before adding higher-level services such as Active Directory, Wazuh, application servers, or student endpoints.

---

# 1. Why Validate the Network First?

Security systems depend on working infrastructure.

Before deploying:

- Active Directory
- Wazuh
- Windows endpoints
- Linux servers
- Docker
- PKI
- Remote-access services

the base network should already be able to provide:

- IP addressing
- Gateway connectivity
- Routing
- NAT
- DNS resolution

A useful deployment principle is:

```text
Build the network
      |
      v
Validate the network
      |
      v
Add infrastructure
      |
      v
Add security tooling
```

This makes later troubleshooting much easier.

---

# 2. Reference Network

The MutaSpace reference implementation uses:

```text
Internal Network:
10.10.10.0/24

Gateway:
10.10.10.1

Internal Bridge:
vmbr1
```

A typical addressing pattern is:

```text
10.10.10.1     Gateway

10.10.10.10    Identity / DNS
10.10.10.20    Security Monitoring
10.10.10.30    Application Server
10.10.10.40    Container Host
10.10.10.50    Certificate Services

10.10.10.100+  DHCP Clients
```

The exact addresses can be changed for another environment.

The important design goal is to separate predictable infrastructure addressing from client addressing.

---

# 3. Understanding `/24`

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

Typical Usable Host Range:
10.10.10.1 - 10.10.10.254

Broadcast Address:
10.10.10.255
```

The gateway is assigned one of the usable addresses:

```text
10.10.10.1
```

---

# 4. Static vs Dynamic Addressing

Not every system should be configured the same way.

A useful model is:

```text
Infrastructure
      |
      v
Predictable Addressing

Client Systems
      |
      v
DHCP
```

Systems that benefit from predictable addressing include:

- Domain controllers
- DNS servers
- SIEM servers
- Application servers
- Container hosts
- Certificate authorities
- Network appliances

DHCP is useful for:

- User workstations
- Temporary lab systems
- Test clients
- Student endpoints

---

# 5. Why Predictable Infrastructure Addresses Matter

Suppose a Wazuh manager changes addresses unexpectedly.

Every endpoint configured to communicate with the old address may stop reporting.

The same problem can affect:

- DNS
- Active Directory
- Application services
- PKI
- Remote access

Predictable infrastructure addressing reduces unnecessary dependency changes.

---

# 6. DHCP in the Reference Design

pfSense provides DHCP for the internal lab network.

Conceptually:

```text
Client VM
   |
   v
vmbr1
   |
   v
pfSense
   |
   v
DHCP Lease
```

The client receives network settings automatically.

These may include:

- IP address
- Subnet mask
- Default gateway
- DNS server
- Domain information

---

# 7. Example DHCP Scope

A possible DHCP range for the reference subnet is:

```text
10.10.10.100
through
10.10.10.200
```

This leaves lower addresses available for infrastructure.

Conceptually:

```text
10.10.10.1 - 10.10.10.99
        |
        v
Infrastructure

10.10.10.100 - 10.10.10.200
        |
        v
DHCP Clients
```

The specific range is a design choice.

---

# 8. Configure DHCP in pfSense

In pfSense, navigate to the DHCP configuration for the LAN interface.

Configure a range appropriate for the internal subnet.

At minimum, DHCP clients should receive:

```text
IP Address
Subnet Mask
Default Gateway
DNS Server
```

For an Active Directory lab, the DNS server should normally be the internal AD-integrated DNS server once Active Directory is deployed.

---

# 9. Initial DNS During Early Build Stages

During the earliest networking stage, the environment may not yet have Active Directory DNS.

At that point, basic external DNS may be used temporarily to validate internet connectivity.

Once Active Directory DNS is deployed, domain-joined systems should use the internal DNS service.

This distinction matters because:

```text
External DNS working
```

does not prove:

```text
Active Directory DNS working
```

---

# 10. Create a Temporary Test Client

Before deploying production-style lab systems, create a simple test VM.

The test system only needs to answer basic questions:

```text
Did DHCP work?
Can I reach the gateway?
Can I reach the Internet?
Does DNS work?
```

A temporary Linux VM works well because it is lightweight and easy to validate.

The VM should be attached to:

```text
vmbr1
```

not the upstream bridge.

---

# 11. Why the Correct Bridge Matters

If the test VM is attached to:

```text
vmbr0
```

it may receive an address from the upstream network instead of the internal lab.

That would test the wrong network path.

The intended path is:

```text
Test VM
   |
   v
vmbr1
   |
   v
pfSense LAN
   |
   v
pfSense Routing / NAT
   |
   v
Upstream Network
```

---

# 12. Validate the Client Address

Linux:

```bash
ip addr
```

or:

```bash
ip -br addr
```

Windows:

```powershell
ipconfig /all
```

Verify that the client received:

- An address from the expected subnet
- The correct subnet mask
- The intended default gateway
- The intended DNS server

---

# 13. Validate the Default Route

Linux:

```bash
ip route
```

A result should include a default route similar to:

```text
default via 10.10.10.1
```

Windows:

```powershell
route print
```

Look for the default route:

```text
0.0.0.0
```

pointing toward the lab gateway.

---

# 14. Test 1: Reach the Gateway

Linux:

```bash
ping -c 3 10.10.10.1
```

Windows:

```powershell
ping 10.10.10.1
```

A successful response confirms several things:

- The VM NIC is connected
- The VM is on the correct internal bridge
- IP addressing is usable
- The pfSense LAN interface is reachable

---

# 15. What a Failed Gateway Test Means

If the client cannot reach the gateway, investigate:

```text
VM NIC enabled?
      |
      v
Correct Proxmox bridge?
      |
      v
Correct IP address?
      |
      v
Correct subnet mask?
      |
      v
pfSense LAN interface active?
```

Do not begin troubleshooting DNS or Internet routing until the gateway itself is reachable.

---

# 16. Test 2: Reach an External IP Address

Linux:

```bash
ping -c 3 1.1.1.1
```

Windows:

```powershell
ping 1.1.1.1
```

If this works, the client can reach an external IP network.

That suggests the following are functioning:

- Default gateway
- pfSense routing
- pfSense WAN connectivity
- NAT
- Upstream connectivity

---

# 17. What External IP Testing Does Not Prove

A successful ping to:

```text
1.1.1.1
```

does not prove DNS is working.

IP connectivity and name resolution are separate functions.

That is why DNS should always be tested independently.

---

# 18. Test 3: Validate External DNS

Linux:

```bash
getent hosts example.com
```

or:

```bash
ping -c 2 example.com
```

Windows:

```powershell
Resolve-DnsName example.com
```

A successful result confirms that the client can translate a hostname into an IP address.

---

# 19. Interpret the Results

## Gateway works, external IP fails

Investigate:

- pfSense routing
- NAT
- WAN connectivity
- Firewall policy
- Upstream network

## External IP works, hostname fails

Investigate:

- DNS configuration
- DNS reachability
- Resolver settings

## Nothing works

Start closer to the endpoint:

- NIC
- Bridge
- DHCP
- IP address
- Gateway

---

# 20. Test Internal DNS Separately

Once an internal DNS server exists, test it independently.

Example:

```powershell
Resolve-DnsName dc-01.example.local
```

or on Linux:

```bash
getent hosts dc-01.example.local
```

A client may have:

```text
Working Internet DNS
```

while still having:

```text
Broken Internal DNS
```

This is especially important in Active Directory environments.

---

# 21. DHCP Validation Checklist

A DHCP client should be able to answer all of these correctly:

```text
What is my IP address?
What subnet am I on?
What is my default gateway?
What DNS server am I using?
```

If any of those values are unexpected, fix DHCP before continuing.

---

# 22. Example Validation Sequence

A useful Linux validation sequence is:

```bash
ip -br addr

ip route

ping -c 3 10.10.10.1

ping -c 3 1.1.1.1

getent hosts example.com
```

A Windows equivalent is:

```powershell
ipconfig /all

ping 10.10.10.1

ping 1.1.1.1

Resolve-DnsName example.com
```

---

# 23. Why These Tests Are Ordered

Each test builds on the previous layer.

```text
IP Address
    |
    v
Gateway
    |
    v
Routing
    |
    v
External Connectivity
    |
    v
DNS
```

If the gateway fails, testing DNS first is not useful.

This layered approach reduces troubleshooting time.

---

# 24. Common Problem: Address From the Wrong Network

If a client receives an unexpected address, check:

- Proxmox bridge assignment
- pfSense DHCP scope
- Multiple DHCP servers
- Additional NICs
- Static configuration left on the guest

The address itself often reveals which network the client actually joined.

---

# 25. Common Problem: Client Has No DHCP Lease

Check:

```text
Is the VM attached to vmbr1?
Is the virtual NIC enabled?
Is pfSense LAN active?
Is DHCP enabled on the correct interface?
Is the DHCP pool valid?
```

Linux can request or inspect DHCP-related state through the system's normal network tooling.

Windows can retry DHCP using:

```powershell
ipconfig /release
ipconfig /renew
```

---

# 26. Common Problem: Multiple IP Addresses

A system may receive both:

```text
Static IP
```

and:

```text
DHCP IP
```

if multiple configuration sources are active.

On Linux, inspect:

```bash
ip addr
```

and:

```bash
ls -l /etc/netplan/
```

Then review the active Netplan files.

Multiple configuration files can unintentionally enable both static and DHCP addressing.

---

# 27. DHCP Reservations

As the environment matures, DHCP reservations can provide a middle ground between static addressing and fully dynamic clients.

A reservation associates a predictable IP with a specific client identity, often using its MAC address.

This can be useful when:

- A client should remain DHCP-managed
- The address still needs to remain predictable

---

# 28. Infrastructure Address Planning

Do not assign infrastructure addresses randomly.

Use a predictable convention.

Example:

```text
.1    Gateway
.10   Identity
.20   Monitoring
.30   Applications
.40   Containers
.50   PKI
```

The exact convention is less important than consistency.

---

# 29. Document the Addressing Strategy

A public build guide should document the addressing pattern, but not every temporary DHCP lease.

Good public documentation:

```text
Infrastructure uses predictable addressing.
Clients use DHCP.
```

Operational tracking such as current DHCP leases belongs in private administrative notes.

---

# 30. Validate Before Building More Systems

Once a test client can successfully:

```text
Receive correct addressing
Reach the gateway
Reach an external IP
Resolve DNS
```

the network is ready for the next infrastructure layer.

At that point, it becomes reasonable to deploy:

- Active Directory
- Wazuh
- Application servers
- Endpoints
- Containers

---

# 31. MutaSpace Reference Implementation

The MutaSpace network was validated using a temporary test client attached to the internal Proxmox bridge.

The validation confirmed that the environment could:

- Assign client network settings
- Reach the pfSense gateway
- Route traffic externally
- Perform NAT
- Resolve DNS

This validation was completed before the rest of the enterprise security infrastructure was built.

That early test reduced uncertainty during later deployments.

---

# 32. Why Temporary Test Systems Are Useful

A dedicated test client isolates the network from application complexity.

Instead of asking:

```text
Why can't Wazuh connect?
```

or:

```text
Why can't Active Directory join?
```

the first question becomes:

```text
Does the network itself work?
```

A minimal test system helps answer that before more complex services are introduced.

---

# 33. Validation Principle

A DHCP lease is not enough to declare the network healthy.

A complete basic validation should confirm:

```text
Correct IP
    |
    v
Correct Subnet
    |
    v
Correct Gateway
    |
    v
Internal Connectivity
    |
    v
External Routing
    |
    v
DNS Resolution
```

Only after those layers work should higher-level services be added.