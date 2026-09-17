# Network Build Guide

This section documents how to build and validate the network foundation for the MutaSpace Enterprise Security Lab.

The guides are written in the order the network should be built.

The goal is to move from:

```text
Physical Connectivity
        |
        v
Virtual Networking
        |
        v
Firewall / Routing
        |
        v
Addressing
        |
        v
DNS
        |
        v
Validation
```

before introducing higher-level systems such as Active Directory, Wazuh, applications, containers, and student workstations.

---

# Build Sequence

## 1. Proxmox Bridges

File:

`01-proxmox-bridges.md`

Covers:

- Physical NIC vs Linux bridge
- `vmbr0`
- `vmbr1`
- pfSense WAN/LAN placement
- Internal virtual networking
- Bridge validation
- Common bridge mistakes

Start here if the virtual network itself has not been created yet.

---

## 2. pfSense Network Setup

File:

`02-pfsense-network-setup.md`

Covers:

- pfSense placement
- WAN and LAN interfaces
- Routing
- NAT
- Firewall responsibilities
- Internal gateway configuration
- DHCP
- Basic connectivity validation

This guide turns the virtual bridges into a routed internal network.

---

## 3. IP Addressing and DHCP

File:

`03-ip-addressing-and-dhcp.md`

Covers:

- `/24` addressing
- Static vs dynamic addressing
- Infrastructure address planning
- DHCP scopes
- Client validation
- Gateway testing
- External connectivity
- Early DNS validation

This guide confirms that clients receive usable network configuration.

---

## 4. Active Directory DNS

File:

`04-active-directory-dns.md`

Covers:

- Why Active Directory depends on DNS
- Internal DNS architecture
- DHCP-provided DNS
- Windows validation
- Linux validation
- `systemd-resolved`
- SRV records
- DNS troubleshooting
- Kerberos and DNS dependencies

Complete this before relying heavily on domain joins or enterprise authentication.

---

## 5. Network Validation and Troubleshooting

File:

`05-network-validation-and-troubleshooting.md`

Covers:

- Layered troubleshooting
- IP configuration
- Gateway checks
- Routing
- DNS
- Port testing
- Linux networking
- Windows networking
- Common lab failure patterns
- Network vs application troubleshooting

Use this guide when a system does not behave as expected.

---

# Reference Architecture

The current reference architecture is:

```text
                         Internet
                            |
                            v
                    Upstream Network
                            |
                            v
                          vmbr0
                            |
                         pfSense
                            |
                          vmbr1
                            |
                   Internal Lab Network
                            |
          +-----------------+-----------------+
          |                 |                 |
          v                 v                 v
       Identity          Security         Applications
       Services         Monitoring            |
          |                 |                 |
          +--------+--------+--------+--------+
                   |                 |
                   v                 v
                Endpoints        Student Lab
```

The detailed network design rationale is documented separately under:

`docs/architecture/network-design.md`

---

# Current Reference Network

The MutaSpace reference implementation currently uses:

```text
Internal Network:
10.10.10.0/24

Gateway:
10.10.10.1
```

Core infrastructure uses predictable addressing, while client systems can use DHCP.

These values are examples from the reference implementation and can be adapted to another lab.

---

# Build Philosophy

The network is intentionally built in layers.

Do not begin with VLANs, IDS sensors, attack networks, and multiple firewall zones before the base network is understood.

A better progression is:

```text
Build
  |
  v
Validate
  |
  v
Understand
  |
  v
Add Complexity
```

This creates a stronger troubleshooting foundation.

---

# What Is Not Implemented Yet

The current lab does not yet claim full network segmentation for:

- Student teams
- Applications
- Identity infrastructure
- Attack simulation
- Security sensors

Future work may introduce:

- VLANs
- Multiple internal subnets
- Inter-VLAN routing
- Firewall ACLs
- Zeek
- Suricata
- Packet capture
- Team isolation

These will be documented after they are implemented and validated.

---

# Validation Standard

A network component is not considered complete because it was configured successfully.

It should be validated from a client perspective.

At minimum, test:

```text
Correct IP
Correct Subnet
Correct Gateway
Internal Connectivity
External Connectivity
Internal DNS
External DNS
Required Service Ports
```

Only then should higher-level services be added.

---

# Recommended Learning Outcomes

After completing this section, a builder should understand:

- What a Proxmox bridge does
- Why pfSense uses multiple NICs
- The difference between WAN and LAN
- The difference between a bridge and a subnet
- How a default gateway works
- How DHCP works
- Why infrastructure needs predictable addressing
- Why Active Directory depends on DNS
- How NAT provides outbound access
- How to validate network layers separately
- Why ping alone does not prove an application works
- How to distinguish network, DNS, port, and application failures

---

# Next Section

Once the network is validated, continue into:

```text
Active Directory
        |
        v
Security Monitoring
        |
        v
Endpoints
        |
        v
Applications
        |
        v
Containers
        |
        v
Remote Access
```

The network is the dependency layer for everything that follows.