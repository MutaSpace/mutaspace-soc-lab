# Student Lab Architecture

This document describes the current design and deployment process for the MutaSpace student cybersecurity lab environment.

The student lab is designed to provide reusable Windows investigation systems that can be assigned to student teams for hands-on troubleshooting, security investigations, log analysis, and live classroom exercises.

The environment currently supports three student teams.

---

# 1. Student Lab Purpose

The student lab exists to provide hands-on environments where students can:

- Investigate Windows problems
- Review Event Viewer
- Troubleshoot authentication
- Investigate DNS and networking issues
- Work with domain-joined systems
- Generate security events
- Compare local logs with centralized Wazuh telemetry
- Practice Help Desk investigation
- Practice SOC escalation
- Perform guided incident investigation
- Learn troubleshooting methodology
- Work in team-based scenarios

The goal is to make security concepts operational rather than purely theoretical.

---

# 2. Current Student Systems

Current student workstations:

```text
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

Each system is:

- Windows 10 Pro
- Domain joined to `mutaspace.local`
- Independently enrolled in Wazuh
- Configured with a student-facing local account
- Configured with an instructor recovery account
- Available for remote browser-based access
- Intended for team-based exercises

---

# 3. Student Lab Architecture

```text
                        Student Browser
                              |
                              v
                    lab.mutaspacesoc.com
                              |
                              v
                     Apache Guacamole
                              |
                +-------------+-------------+
                |             |             |
                v             v             v
        HELPDESK-TEAM01 HELPDESK-TEAM02 HELPDESK-TEAM03
                |             |             |
                +-------------+-------------+
                              |
                              v
                        mutaspace.local
                              |
                              v
                            dc-01
                       Active Directory
                              |
                              v
                           wazuh-01
                     Centralized Monitoring
```

---

# 4. Student Lab Resource Pool

The student systems are organized in Proxmox using:

```text
student-lab
```

The pool exists to provide an organizational boundary for student-focused systems.

The pool should not be interpreted as complete security isolation.

Network isolation and access-control enforcement are handled separately.

---

# 5. Golden Image Strategy

The student Windows systems are created from a generalized master image.

The build path is:

```text
win-client-01
      |
      v
helpdesk-template-prep
      |
      v
Windows cleanup
      |
      v
Sysprep /generalize
      |
      v
Powered-off generalized master
      |
      +-------------+-------------+
      |             |             |
      v             v             v
HELPDESK-TEAM01 HELPDESK-TEAM02 HELPDESK-TEAM03
```

The generalized template allows future student endpoints to be created without performing a complete Windows installation each time.

---

# 6. Template Preparation

The preparation system was created as a full clone of:

```text
win-client-01
```

The preparation VM was named:

```text
helpdesk-template-prep
```

Before generalization, the system was:

- Disconnected from the network
- Verified as domain joined
- Given a local instructor administrator account
- Prepared for removal from inherited domain identity
- Stopped from using the inherited Wazuh identity
- Cleaned for Sysprep

---

# 7. Instructor Recovery Account

A local account was created:

```text
LabAdmin
```

Purpose:

- Instructor recovery
- Local administrative access
- Troubleshooting
- Template maintenance
- Emergency access

This account is separate from student accounts.

The password is not documented in GitHub.

---

# 8. Domain Removal

The preparation machine originally inherited:

```text
Domain: mutaspace.local
Computer Name: WIN-CLIENT-01
```

The clone was removed from the domain and placed into:

```text
WORKGROUP
```

This was necessary before final generalization and redeployment.

---

# 9. Sysprep Generalization

The Windows image was generalized using:

```text
System Preparation Tool
```

Settings:

```text
System Cleanup Action:
Enter System Out-of-Box Experience (OOBE)

Generalize:
Enabled

Shutdown Option:
Shutdown
```

The final generalized image was allowed to shut itself down.

After successful Sysprep:

> `helpdesk-template-prep` should remain powered off and should not be used as a normal workstation.

---

# 10. Sysprep Troubleshooting

Sysprep initially failed validation because AppX packages were installed for individual users but not provisioned consistently across the system.

Packages identified included:

```text
Microsoft.BingSearch
MicrosoftWindows.CrossDevice
Microsoft.Copilot
```

Sysprep logs were reviewed from:

```text
C:\Windows\System32\Sysprep\Panther\setuperr.log
```

Example troubleshooting command:

```powershell
Get-Content "C:\Windows\System32\Sysprep\Panther\setuperr.log" -Tail 30
```

Specific package failures were identified and removed before retrying Sysprep.

The image successfully generalized after the blocking AppX packages were resolved.

---

# 11. Clone Deployment

Each team workstation was created as a full clone of the generalized master.

Current clones:

```text
helpdesk-team01
helpdesk-team02
helpdesk-team03
```

Full clones were selected so each workstation has independent virtual disk storage.

---

# 12. Clone Failure Recovery

An interrupted cloning operation caused incomplete team VMs to remain locked in Proxmox.

The issue was resolved by:

1. Confirming clone jobs were no longer running
2. Identifying the incomplete VM IDs
3. Unlocking the VMs using:

```bash
qm unlock <VM-ID>
```

4. Removing the incomplete clones
5. Recreating the clones from the generalized master

This process preserved the master template and the already-working Team 01 environment.

---

# 13. Windows OOBE

Each cloned team system completed Windows OOBE.

During setup:

```text
Set up for an organization
```

was selected.

When Microsoft account authentication was requested:

```text
Domain join instead
```

was selected.

This allowed creation of local student accounts without linking the machines to personal Microsoft accounts.

---

# 14. Student Accounts

Current local student accounts:

```text
Team01
Team02
Team03
```

Each account exists only on its assigned endpoint.

Examples:

```text
HELPDESK-TEAM01\Team01
HELPDESK-TEAM02\Team02
HELPDESK-TEAM03\Team03
```

The student accounts are separate from:

```text
LabAdmin
```

which remains the instructor recovery account.

---

# 15. Unique Hostnames

Each workstation was assigned a unique hostname.

```text
HELPDESK-TEAM01
HELPDESK-TEAM02
HELPDESK-TEAM03
```

Example PowerShell command:

```powershell
Rename-Computer -NewName "HELPDESK-TEAM01"
```

The system was restarted after renaming.

---

# 16. Network Validation

Before joining Active Directory, each endpoint was validated against:

```text
Gateway: 10.10.10.1
Domain Controller / DNS: 10.10.10.10
```

Validation included:

```powershell
ping 10.10.10.1
ping 10.10.10.10
nslookup dc-01.mutaspace.local
```

Each system passed before domain join.

---

# 17. Active Directory Join

Each workstation was joined to:

```text
mutaspace.local
```

Example:

```powershell
Add-Computer `
  -DomainName "mutaspace.local" `
  -Credential "MUTASPACE\Administrator" `
  -Restart
```

Domain membership was validated after reboot.

Example:

```powershell
Get-ComputerInfo |
Select-Object CsName,CsDomain,CsPartOfDomain
```

Expected:

```text
CsPartOfDomain : True
```

---

# 18. Wazuh Clone Identity Problem

The original Windows source machine already contained a Wazuh agent.

Cloning the Windows image also copied:

- `client.keys`
- Wazuh configuration
- Original agent identity

This caused clones to attempt to identify themselves as:

```text
win-client-01
```

The Wazuh manager rejected the duplicate identity.

Example error:

```text
Duplicate agent name: win-client-01
```

---

# 19. Wazuh Clone Remediation

Each cloned workstation required a unique Wazuh identity.

The remediation process included:

1. Stop the Wazuh service
2. Remove or preserve the inherited key
3. Configure the correct agent name
4. Create a unique manager-side agent
5. Extract the corresponding key
6. Import the key into the endpoint
7. Start the Wazuh service
8. Validate Active status

---

# 20. Wazuh Agent Name Configuration

The agent name is configured in:

```text
C:\Program Files (x86)\ossec-agent\ossec.conf
```

Example:

```xml
<enrollment>
  <enabled>yes</enabled>
  <agent_name>HELPDESK-TEAM01</agent_name>
</enrollment>
```

Each team uses its corresponding hostname.

---

# 21. Wazuh Key Handling

The inherited:

```text
client.keys
```

file was preserved by renaming it during remediation.

Example:

```powershell
Rename-Item `
"C:\Program Files (x86)\ossec-agent\client.keys" `
"client.keys.old"
```

New keys were then imported from `wazuh-01`.

Wazuh authentication keys are never committed to GitHub.

---

# 22. Current Wazuh Mapping

Current student endpoint enrollment:

```text
006 -> HELPDESK-TEAM01
007 -> HELPDESK-TEAM03
008 -> HELPDESK-TEAM02
```

All three agents have been validated as:

```text
Active
```

---

# 23. Wazuh Validation

Manager-side verification:

```bash
sudo /var/ossec/bin/agent_control -l
```

Individual agent verification:

```bash
sudo /var/ossec/bin/agent_control -i <AGENT-ID>
```

Expected:

```text
Status: Active
```

---

# 24. Student Endpoint Monitoring

Current Wazuh capabilities include:

- Windows Security logs
- Authentication events
- File Integrity Monitoring
- Security Configuration Assessment
- Rootcheck
- System inventory
- Endpoint state monitoring

This allows the instructor or analyst to observe security activity generated by student investigations.

---

# 25. Remote Desktop Configuration

Student workstations use RDP for Guacamole access.

Example enablement:

```powershell
Set-ItemProperty `
  -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name 'fDenyTSConnections' `
  -Value 0
```

Firewall rules:

```powershell
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

Validation:

```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

---

# 26. Remote Desktop User Authorization

Student accounts must be authorized for Remote Desktop.

Example:

```powershell
net localgroup "Remote Desktop Users" Team01 /add
```

Verification:

```powershell
net localgroup "Remote Desktop Users"
```

---

# 27. Student Account Password Requirement

A working RDP session requires valid credentials.

During Team 01 validation, the student account did not initially have a usable password for remote authentication.

A password was configured using:

```powershell
net user Team01 *
```

After updating Guacamole with the correct credentials, the RDP connection succeeded.

---

# 28. Browser Access

Student access is brokered through:

```text
Apache Guacamole
```

The public access path is:

```text
https://lab.mutaspacesoc.com
```

Current validated path:

```text
School Computer
      |
      v
Cloudflare
      |
      v
Guacamole
      |
      v
HELPDESK-TEAM01
```

No Tailscale or local RDP client is required on the school computer.

---

# 29. Student Team Isolation

Current isolation is primarily identity-based.

Intended Guacamole mapping:

```text
team01 -> HELPDESK-TEAM01
team02 -> HELPDESK-TEAM02
team03 -> HELPDESK-TEAM03
```

Users should only receive permission to use their assigned connection.

Network-level team isolation remains planned.

---

# 30. Current Network Limitation

All student systems currently share:

```text
10.10.10.0/24
```

This means the systems are not yet fully isolated from one another at Layer 3.

Future segmentation is planned.

---

# 31. Planned Team Networks

Proposed future addressing:

```text
Team 01 -> 10.10.21.0/24
Team 02 -> 10.10.22.0/24
Team 03 -> 10.10.23.0/24
```

pfSense will control inter-team traffic.

---

# 32. Help Desk Investigation Use Case

The first intended student use case is Help Desk Investigation.

Students can investigate:

- Failed authentication
- DNS problems
- Network connectivity
- Windows services
- Local accounts
- Domain authentication
- Event Viewer
- Application access
- Endpoint state

The instructor can simultaneously observe endpoint telemetry through Wazuh.

---

# 33. Example Investigation Flow

```text
Student receives ticket
        |
        v
Opens assigned workstation
        |
        v
Collects symptoms
        |
        v
Checks networking
        |
        v
Checks DNS
        |
        v
Checks user/account state
        |
        v
Checks Event Viewer
        |
        v
Tests remediation
        |
        v
Documents findings
        |
        v
Instructor reviews corresponding Wazuh telemetry
```

---

# 34. Local vs Centralized Logs

The environment supports teaching the difference between:

```text
Local endpoint evidence
```

and:

```text
Centralized security telemetry
```

Example:

```text
HELPDESK-TEAM01
      |
      v
Windows Event Viewer
      |
      v
Windows Security Event
```

compared with:

```text
HELPDESK-TEAM01
      |
      v
Wazuh Agent
      |
      v
wazuh-01
      |
      v
Centralized investigation
```

---

# 35. Student Lab Reset Strategy

A formal reset procedure is still being developed.

The intended model is:

```text
Known-Good Baseline
       |
       v
Lab Scenario
       |
       v
Student Changes
       |
       v
Investigation Complete
       |
       v
Restore Snapshot / Reclone
       |
       v
Known-Good Baseline
```

Each team workstation should eventually have a validated baseline snapshot.

---

# 36. Snapshot Requirements

Planned snapshots:

```text
HELPDESK-TEAM01-baseline
HELPDESK-TEAM02-baseline
HELPDESK-TEAM03-baseline
```

Snapshots should be created only after:

- AD membership is validated
- Wazuh is Active
- Networking is validated
- Student account works
- RDP works
- Guacamole access works
- Required classroom tools are installed

---

# 37. Classroom Design Principle

Student systems should be intentionally breakable.

Core infrastructure should not be.

This means students may be allowed to modify:

- Their assigned endpoint
- Local services
- Local network configuration during controlled exercises
- Accounts where appropriate
- Application configuration during controlled exercises

Students should not receive unrestricted administrative access to:

```text
Proxmox
pfSense
dc-01
wazuh-01
ca-01
docker-01
```

---

# 38. Future Student Lab Expansion

Planned additions may include:

- Linux investigation workstations
- Web application targets
- Vulnerable endpoints
- Incident response systems
- Attack simulation systems
- Additional Windows clients
- Team-specific servers
- Network troubleshooting scenarios
- PKI troubleshooting scenarios
- IAM scenarios
- Malware-analysis-safe environments
- SOC escalation workflows

---

# 39. Future Automation

Long-term provisioning should become automated.

Potential automation areas include:

- VM cloning
- Naming
- IP assignment
- AD join
- Wazuh enrollment
- Guacamole connection creation
- Team account creation
- Snapshot creation
- End-of-class reset

This will reduce manual setup time between classes.

---

# 40. Student Lab Security Principle

The student-lab architecture follows this rule:

> Give students enough access to investigate, troubleshoot, and learn, while keeping the infrastructure that hosts and monitors the lab protected.

The environment should remain:

- Reusable
- Observable
- Resettable
- Team-specific
- Safe to break
- Safe to teach from