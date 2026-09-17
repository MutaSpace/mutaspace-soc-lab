# Building a Reusable Team-Based Cybersecurity Lab

This guide explains how to design a reusable cybersecurity training environment where multiple teams can work inside separate Windows systems while instructors retain control of the underlying infrastructure.

The reference implementation uses:

- Proxmox VE
- Windows 10 Pro
- Active Directory
- Wazuh
- Apache Guacamole
- Cloudflare Tunnel

The same design can be adapted to other virtualization, SIEM, and remote-access platforms.

---

# 1. Design Goal

A student cyber lab should let learners:

- Investigate realistic endpoint issues
- Generate security telemetry
- Work in teams
- Practice Help Desk and SOC workflows
- Use Windows Event Viewer
- Troubleshoot networking and authentication
- Compare local logs with centralized monitoring
- Break assigned systems without damaging core infrastructure

At the same time, students should not need direct access to:

- The hypervisor
- The firewall
- The SIEM server
- The domain controller
- The certificate authority
- Other teams' systems

---

# 2. Reference Architecture

```text
                       Instructor
                           |
                           v
                    Core Infrastructure
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
     Active Directory     SIEM        Remote Access
          |                |                |
          +--------+-------+-------+--------+
                   |               |
                   v               v
              Student Lab     Analyst View
                   |
          +--------+--------+
          |        |        |
          v        v        v
       Team 01  Team 02  Team 03
```

Each team receives its own endpoint.

The infrastructure remains centrally managed.

---

# 3. Why Use Team-Based Workstations?

A shared VM makes it difficult to determine which team generated an event or changed a configuration.

Dedicated team systems provide:

- Separate user activity
- Separate event logs
- Separate Wazuh identities
- Separate troubleshooting states
- Easier reset procedures
- Cleaner attribution

Example:

```text
Team 01
   |
   v
Windows-Lab-01
   |
   v
SIEM

Team 02
   |
   v
Windows-Lab-02
   |
   v
SIEM
```

---

# 4. Build a Reusable Master Image

Installing Windows manually for every team does not scale well.

Instead, create:

```text
Base Windows VM
      |
      v
Prepared Master
      |
      v
Sysprep / Generalize
      |
      v
Powered-Off Golden Image
```

Then clone that image for each team.

---

# 5. Why Generalization Matters

A VM clone copies more than the operating system.

It may also copy:

- Computer name
- Domain identity
- Monitoring agent identity
- Application configuration
- Security keys
- Machine-specific state

Running multiple clones without preparing them can create identity conflicts.

The correct model is:

```text
Clone Operating System State
          |
          v
Regenerate Machine Identity
```

---

# 6. Prepare a Local Recovery Account

Before modifying domain membership or running Sysprep, create a local administrator account for instructor recovery.

Example:

```text
LabAdmin
```

Verify local administrator membership:

```powershell
net localgroup Administrators
```

Do not publish the account password.

---

# 7. Remove Environment-Specific Identity

If the source system is already domain joined, prepare it before generalization.

A reusable master should not remain dependent on the original computer's Active Directory identity.

Typical preparation includes:

- Confirming local administrator access
- Removing the machine from the domain
- Returning it to a workgroup
- Stopping monitoring agents that contain machine-specific identity
- Removing temporary credentials or files

---

# 8. Validate Domain Removal

Example:

```powershell
(Get-CimInstance Win32_ComputerSystem) |
Select-Object Name,Domain,PartOfDomain
```

Expected:

```text
PartOfDomain : False
```

---

# 9. Prepare Security Agents Before Cloning

Endpoint monitoring tools often contain unique identity information.

Examples include:

- Agent IDs
- Enrollment keys
- Hostnames
- Certificates
- API tokens

If a monitoring agent is already installed, determine what must be regenerated after cloning.

For Wazuh, cloned machines should receive unique:

- Agent names
- Agent IDs
- Enrollment keys

Never allow multiple machines to operate under the same monitoring identity.

---

# 10. Run Sysprep

Launch:

```powershell
C:\Windows\System32\Sysprep\Sysprep.exe
```

Use:

```text
Enter System Out-of-Box Experience (OOBE)
Generalize: Enabled
Shutdown
```

Allow the machine to shut down completely.

The generalized master should remain powered off.

---

# 11. Troubleshoot Sysprep Failures

If Windows reports:

```text
Sysprep was not able to validate your Windows installation.
```

review:

```text
C:\Windows\System32\Sysprep\Panther\setuperr.log
```

Example:

```powershell
Get-Content `
"C:\Windows\System32\Sysprep\Panther\setuperr.log" `
-Tail 30
```

---

# 12. Common AppX Failure Pattern

A common Sysprep issue is:

```text
Package <name> was installed for a user,
but not provisioned for all users.
```

Only remove the specific package identified by the log.

Avoid bulk-removing Windows applications without understanding the impact.

---

# 13. Create Team Clones

Create one full clone per team.

Example naming:

```text
helpdesk-team01
helpdesk-team02
helpdesk-team03
```

A full clone gives each VM independent storage.

This is useful when students are expected to modify or break their systems.

---

# 14. Handle Interrupted Clone Jobs

If a Proxmox cloning operation is interrupted, a VM may remain locked.

Before changing anything:

1. Confirm the clone task is no longer running
2. Identify the incomplete clone
3. Verify the correct VM ID

Then unlock:

```bash
qm unlock <VM-ID>
```

Remove the incomplete clone and recreate it from the golden image.

---

# 15. Complete Windows OOBE

Each new clone should complete Windows first-boot setup.

If the system is intended for a local lab account rather than a Microsoft account, use the appropriate local setup path.

For Windows Pro editions, this may include:

```text
Set up for an organization
```

followed by:

```text
Domain join instead
```

This allows a local account to be created before joining the enterprise domain.

---

# 16. Assign a Unique Hostname

Every team endpoint must have a unique computer name.

Example:

```powershell
Rename-Computer -NewName "HELPDESK-TEAM01"
```

Restart after renaming.

A consistent naming convention helps with:

- Active Directory
- SIEM searches
- Event correlation
- Troubleshooting
- Classroom management

---

# 17. Validate Networking Before Domain Join

Before joining the domain, verify:

- Gateway access
- Domain controller access
- Internal DNS
- External connectivity if required

Example:

```powershell
ping <GATEWAY_IP>
ping <DOMAIN_CONTROLLER_IP>
nslookup <DOMAIN_CONTROLLER_HOSTNAME>
```

Do not troubleshoot domain joining until DNS works correctly.

---

# 18. Join Active Directory

Example:

```powershell
Add-Computer `
  -DomainName "<LAB_DOMAIN>" `
  -Credential "<DOMAIN_ADMIN_ACCOUNT>" `
  -Restart
```

Enter credentials interactively.

Do not store administrator passwords in scripts or documentation.

---

# 19. Validate Domain Membership

After restart:

```powershell
Get-ComputerInfo |
Select-Object CsName,CsDomain,CsPartOfDomain
```

Expected:

```text
CsPartOfDomain : True
```

---

# 20. Assign Unique Monitoring Identity

After cloning, configure a unique Wazuh identity for each endpoint.

Example workflow:

```text
Clone
  |
  v
Unique Hostname
  |
  v
Unique Wazuh Agent Name
  |
  v
Unique Enrollment Key
  |
  v
Active Agent
```

---

# 21. Avoid Duplicate Wazuh Agents

A cloned endpoint may attempt to connect using the source system's identity.

Symptoms may include:

```text
Duplicate agent name
```

or a new system appearing as the original endpoint.

The fix is not to reuse the old identity.

Each clone needs its own manager-side registration.

---

# 22. Configure Wazuh Agent Name

On Windows, the Wazuh configuration is typically located under:

```text
C:\Program Files (x86)\ossec-agent\
```

Example:

```xml
<enrollment>
  <enabled>yes</enabled>
  <agent_name>HELPDESK-TEAM01</agent_name>
</enrollment>
```

Use a unique name for each clone.

---

# 23. Replace the Inherited Agent Key

Stop the Wazuh service before replacing identity information.

Preserve the old key if necessary:

```powershell
Rename-Item `
"C:\Program Files (x86)\ossec-agent\client.keys" `
"client.keys.old"
```

Then import the new manager-generated key.

Never publish the actual key.

---

# 24. Validate Wazuh Enrollment

On the manager:

```bash
sudo /var/ossec/bin/agent_control -l
```

Each team system should appear independently.

Expected concept:

```text
Team01 -> Active
Team02 -> Active
Team03 -> Active
```

---

# 25. Why Centralized Monitoring Matters

The instructor should be able to compare what students see locally with what the SOC sees centrally.

Example:

```text
Student
   |
   v
Windows Event Viewer
```

while:

```text
Instructor / Analyst
       |
       v
Wazuh
       |
       v
Centralized Endpoint Telemetry
```

This creates a useful teaching bridge between Help Desk and SOC responsibilities.

---

# 26. Enable Remote Desktop

If the endpoints will be accessed through Guacamole, enable RDP.

Example:

```powershell
Set-ItemProperty `
  -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name 'fDenyTSConnections' `
  -Value 0
```

Enable firewall rules:

```powershell
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

---

# 27. Validate the RDP Listener

```powershell
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

Confirm the endpoint is listening before configuring the remote gateway.

---

# 28. Create Student Accounts

Each team should have its own student-facing account.

Example:

```text
Team01
Team02
Team03
```

The exact account model can be:

- Local accounts
- Active Directory accounts
- Temporary classroom accounts

Choose based on the exercise.

---

# 29. Separate Student and Instructor Accounts

Do not use the instructor recovery account as the student account.

Use:

```text
Instructor:
LabAdmin

Student:
Team01
```

This preserves a recovery path if the student account becomes broken or locked.

---

# 30. Authorize Remote Desktop

Example:

```powershell
net localgroup "Remote Desktop Users" Team01 /add
```

Verify:

```powershell
net localgroup "Remote Desktop Users"
```

---

# 31. Add Browser-Based Access

The MutaSpace reference design uses:

```text
Apache Guacamole
```

Each Guacamole user should be mapped only to its assigned endpoint.

Example:

```text
team01
   |
   v
HELPDESK-TEAM01
```

---

# 32. Do Not Give Students Hypervisor Access

Students who only need an endpoint do not need direct access to:

- Proxmox
- Storage
- Virtual networking
- Other VMs
- Snapshots
- Core infrastructure

The access gateway should abstract the virtualization layer away from the student.

---

# 33. Current Isolation Model

Logical team separation can begin with:

- Unique endpoints
- Unique users
- Unique monitoring identities
- Guacamole connection permissions

This is useful, but it is not the same as network segmentation.

---

# 34. Add Network Segmentation Later

A stronger architecture places each team on its own subnet or VLAN.

Example:

```text
Team 01 -> Student VLAN 01
Team 02 -> Student VLAN 02
Team 03 -> Student VLAN 03
```

The firewall can then restrict east-west communication between teams.

---

# 35. Build Scenarios Around Tickets

A team-based environment works well for Help Desk and security scenarios.

Example ticket categories:

- User cannot log in
- DNS does not resolve
- Internal service is unavailable
- Account is locked
- Windows service is stopped
- Group membership is incorrect
- Endpoint generates suspicious events
- Network configuration is incorrect

---

# 36. Example Investigation Workflow

```text
Receive Ticket
     |
     v
Identify Symptoms
     |
     v
Check Connectivity
     |
     v
Check DNS
     |
     v
Check Identity
     |
     v
Check Services
     |
     v
Review Logs
     |
     v
Apply Fix
     |
     v
Validate
     |
     v
Document Findings
```

This mirrors a real troubleshooting process better than simply giving students a list of commands.

---

# 37. Teach Local vs Centralized Evidence

The student may observe:

```text
Event Viewer
```

while the instructor observes:

```text
SIEM
```

This creates opportunities to ask:

- What did the endpoint record?
- What did the SIEM receive?
- Did a detection rule fire?
- What context exists centrally that the endpoint does not show?

---

# 38. Create Known-Good Baselines

Before introducing intentional problems, create a validated snapshot.

A good baseline should confirm:

```text
Networking
DNS
Domain membership
Monitoring
Student login
RDP
Remote gateway access
```

Then:

```text
Known-Good Snapshot
       |
       v
Scenario
       |
       v
Student Investigation
       |
       v
Restore
```

---

# 39. Design for Resetability

A student lab should be easy to reset.

If rebuilding a workstation takes hours, instructors will hesitate to let students make meaningful changes.

Cloning and snapshots make the environment safe to experiment with.

---

# 40. Future Automation

Once the manual process is understood, automate repetitive deployment.

Potential automation targets include:

- VM cloning
- Naming
- DNS
- Domain joining
- Monitoring enrollment
- Student accounts
- Remote-access connections
- Snapshot creation
- Reset workflows

Automation should come after the manual process is understood and validated.

---

# 41. MutaSpace Reference Implementation

The MutaSpace student environment uses this design to support team-based investigation work.

The implementation has validated:

- Generalized Windows deployment
- Multi-team cloning
- Unique Windows identities
- Active Directory membership
- Independent Wazuh enrollment
- RDP
- Browser-based remote access
- Centralized telemetry

The implementation serves as the reference environment for the procedures described in this repository.

---

# 42. Design Principle

A classroom cyber lab should be:

```text
Safe to break
Easy to restore
Observable
Repeatable
Team-specific
Separated from core infrastructure
```

The objective is not simply to give students virtual machines.

The objective is to give them a controlled environment where they can investigate realistic technical problems without putting the underlying lab infrastructure at unnecessary risk.