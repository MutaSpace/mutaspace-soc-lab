# ubuntu-app-01 Build

This document records the installation, configuration, validation, and Wazuh enrollment of `ubuntu-app-01`, the Linux application server for the MutaSpace SOC Lab.

`ubuntu-app-01` provides a monitored Linux server target for service troubleshooting, SSH activity, web server logs, file integrity monitoring, and future attack/defense labs.

---

## VM Purpose

`ubuntu-app-01` is a Linux server inside the internal SOC lab network.

This VM supports:

- Linux server administration practice
- SSH log generation
- Nginx web server testing
- Linux service troubleshooting
- File integrity monitoring
- Wazuh Linux agent telemetry
- Future Linux attack simulation labs
- Future web log analysis labs

This system gives the lab a realistic Linux server target instead of only workstation and domain infrastructure.

---

## VM Configuration

| Setting | Value |
|---|---|
| VM Name | `ubuntu-app-01` |
| VM ID | `106` |
| Operating System | Ubuntu Server |
| Role | Linux application server |
| vCPU | 2 |
| Memory | 4GB |
| Disk | 40GB |
| Network Bridge | `vmbr1` |
| Network Model | VirtIO |
| Network Role | Internal SOC LAN |

---

## Network Placement

`ubuntu-app-01` is connected to:

```text
vmbr1
```

This places the server inside the internal SOC lab network.

It is not connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## IP Configuration

`ubuntu-app-01` was configured with a static IP address.

| Setting | Value |
|---|---|
| IP Address | `10.10.10.30` |
| Subnet | `/24` |
| Default Gateway | `10.10.10.1` |
| DNS Server | `10.10.10.10` |
| DNS Domain | `mutaspace.local` |

---

## DNS Configuration

A DNS record was added on `dc-01`.

| DNS Record | Value |
|---|---|
| Hostname | `ubuntu-app-01` |
| FQDN | `ubuntu-app-01.mutaspace.local` |
| IP Address | `10.10.10.30` |
| DNS Server | `dc-01` |

A reverse lookup zone was also added for the internal SOC lab network.

This supports better reverse DNS lookups and cleaner troubleshooting.

---

## Installed Services

The following services were installed and validated.

| Service | Purpose | Status |
|---|---|---|
| OpenSSH Server | Remote Linux administration and SSH log generation | Running |
| Nginx | Web server for HTTP testing and web log generation | Running |

---

## SSH Validation

SSH was enabled and started.

Command used:

```bash
sudo systemctl enable --now ssh
```

Validation command:

```bash
systemctl status ssh
```

Expected result:

```text
active (running)
enabled
```

---

## Nginx Validation

Nginx was installed and confirmed running.

Validation command:

```bash
systemctl status nginx
```

Expected result:

```text
active (running)
enabled
```

From `analyst-01`, the web server was tested by opening:

```text
http://ubuntu-app-01.mutaspace.local
```

The Nginx welcome page displayed successfully.

This confirmed that:

- DNS resolution worked
- HTTP connectivity worked
- The web server was reachable from the analyst workstation
- The Linux server was functioning on the internal SOC LAN

---

## Wazuh Agent Enrollment

The Wazuh Linux agent was installed on `ubuntu-app-01`.

The Wazuh manager is:

```text
wazuh-01.mutaspace.local
```

The agent name used was:

```text
ubuntu-app-01
```

After installation, the Wazuh agent was started and validated.

Validation command:

```bash
sudo systemctl status wazuh-agent
```

Expected result:

```text
active (running)
```

---

## Wazuh Dashboard Validation

The Wazuh dashboard showed `ubuntu-app-01` under agents.

This confirmed that:

- The Wazuh agent installed successfully
- The Wazuh service started successfully
- `ubuntu-app-01` could reach `wazuh-01`
- The Wazuh manager received the agent connection
- Linux server telemetry collection has started

---

## Troubleshooting Notes

During agent installation, the first Wazuh package download attempt returned:

```text
403 Forbidden
```

The issue was related to the package download URL.

The correct package path included the `wazuh-agent` directory and the correct DEB package format.

After correcting the package download and installation process, the Wazuh agent installed successfully and appeared in the Wazuh dashboard.

---

## Validation Results

| Validation Item | Status |
|---|---|
| Ubuntu Server installed | Completed |
| Static IP configured | Completed |
| DNS A record added | Completed |
| Reverse DNS zone added | Completed |
| Gateway reachable | Completed |
| Domain controller reachable | Completed |
| Wazuh server reachable | Completed |
| Nginx installed | Completed |
| Nginx running | Completed |
| Nginx page reachable from `analyst-01` | Completed |
| SSH installed | Completed |
| SSH enabled | Completed |
| SSH running | Completed |
| Wazuh agent installed | Completed |
| Wazuh agent running | Completed |
| `ubuntu-app-01` visible in Wazuh | Completed |

---

## Why This Matters

`ubuntu-app-01` expands the SOC lab from identity and endpoint monitoring into Linux server monitoring.

This system can now be used to generate realistic Linux and web server activity.

Future labs can investigate:

- SSH failed logins
- Successful SSH logins
- Nginx access logs
- Nginx service restarts
- Linux privilege activity
- File integrity monitoring events
- Suspicious Linux behavior

---

## Learning Reflection

Building `ubuntu-app-01` showed how adding a simple Linux server increases the value of the SOC lab.

The lab now has Windows, Linux workstation, Linux server, Active Directory, DNS, and SIEM telemetry working together.

This creates more realistic conditions for SOC investigation, detection engineering, and learner-ready cybersecurity labs.
