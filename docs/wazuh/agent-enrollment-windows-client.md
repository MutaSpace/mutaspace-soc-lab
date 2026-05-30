# Windows Client Wazuh Agent Enrollment

This document records the Wazuh agent enrollment for `win-client-01`, the Windows domain workstation in the MutaSpace SOC Lab.

The goal of this step was to connect a normal Windows client endpoint to Wazuh so the lab can begin collecting workstation telemetry.

---

## Enrollment Purpose

Wazuh agents collect endpoint telemetry and send it to the Wazuh manager for analysis.

Enrolling `win-client-01` is important because it gives the SOC lab visibility into a standard Windows workstation.

This supports future labs involving:

- Successful logins
- Failed logins
- User activity
- Windows security logs
- Endpoint behavior
- Domain user activity
- Basic incident investigation

---

## Systems Involved

| System | Role | IP Address |
|---|---|---|
| `wazuh-01` | Wazuh server / manager | `10.10.10.20` |
| `dc-01` | Domain Controller and DNS server | `10.10.10.10` |
| `win-client-01` | Windows domain workstation / Wazuh agent | DHCP address |
| `fw-01` | Gateway / firewall | `10.10.10.1` |

---

## Agent Target

The Windows agent was installed on:

```text
win-client-01
```

`win-client-01` is a Windows client system joined to:

```text
mutaspace.local
```

---

## Manager Target

The Wazuh manager is:

```text
wazuh-01
```

The Wazuh manager can be reached at:

```text
10.10.10.20
```

and by DNS name:

```text
wazuh-01.mutaspace.local
```

---

## Network Placement

`win-client-01` is connected to:

```text
vmbr1
```

This places the system inside the internal SOC lab network.

It is not connected directly to `vmbr0`.

```text
vmbr0 = Proxmox management / upstream network
vmbr1 = internal SOC lab network
```

---

## Domain Membership

`win-client-01` was joined to the internal Active Directory domain:

```text
mutaspace.local
```

The domain controller is:

```text
dc-01
```

The DNS server for the internal domain is:

```text
10.10.10.10
```

---

## Installation Method

The agent was installed using the Wazuh dashboard deployment workflow.

In the Wazuh dashboard:

```text
Agents > Deploy new agent
```

The selected operating system was:

```text
Windows
```

The generated PowerShell command was run on `win-client-01` using PowerShell as Administrator.

---

## Agent Name

The agent was enrolled as:

```text
win-client-01
```

The agent name should match the endpoint being monitored.

This makes it easier to identify systems inside the Wazuh dashboard.

---

## Service Validation

After installation, the Wazuh service was validated on `win-client-01`.

PowerShell command:

```powershell
Get-Service WazuhSvc
```

Expected result:

```text
Running
```

---

## Dashboard Validation

The Wazuh dashboard showed `win-client-01` under agents.

This confirmed that:

- The Windows agent installed successfully
- The Wazuh service started successfully
- `win-client-01` could reach `wazuh-01`
- The Wazuh manager received the agent connection
- Windows workstation telemetry collection has started

---

## Validation Results

| Validation Item | Status |
|---|---|
| Windows client installed | Completed |
| Computer renamed to `win-client-01` | Completed |
| Client joined to `mutaspace.local` | Completed |
| Windows agent package selected | Completed |
| Wazuh agent installed on `win-client-01` | Completed |
| Wazuh agent service started | Completed |
| Wazuh agent service running | Completed |
| Agent connected to Wazuh manager | Completed |
| `win-client-01` visible in Wazuh dashboard | Completed |

---

## Why This Matters

This is the first standard Windows workstation telemetry source in the MutaSpace SOC Lab.

The lab now has:

- Linux endpoint telemetry
- Windows Server and Active Directory telemetry
- Windows workstation telemetry

This creates a stronger foundation for beginner-friendly SOC labs because students can compare activity across different system types.

---

## Security Events This Enables

With `win-client-01` enrolled, future labs can investigate:

- Successful workstation logins
- Failed workstation logins
- Domain user logins
- Local user activity
- Windows security events
- Basic suspicious endpoint behavior
- Authentication patterns between client and domain controller

These events will support future detection engineering and investigation workflows.

---

## Troubleshooting Notes

After the system joined the domain, login context mattered.

Windows may default to domain login after joining Active Directory.

To log in with a domain account, use:

```text
MUTASPACE\Administrator
```

To log in with a local account, use:

```text
.\localusername
```

This distinction matters because Windows needs to know whether the user is authenticating against the local machine or the domain.

---

## Learning Reflection

Enrolling `win-client-01` showed how endpoint visibility expands the SOC lab.

The lab is now collecting telemetry from a Linux workstation, a Windows Server domain controller, and a Windows client workstation.

This gives the MutaSpace SOC Lab a stronger foundation for real investigation practice.