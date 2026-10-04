# win-client-01: Sysmon and Wazuh Integration

**Build dates:** October 2–3, 2026  
**Status:** Process and DNS detection validated; network telemetry captured locally.

## System Purpose

Expand Windows endpoint visibility in the MutaSpace SOC by collecting detailed process, DNS, and network activity through Sysmon and forwarding its event channel to Wazuh.

This integration supports future endpoint investigations, detection development, and repeatable security scenarios.

## System Configuration

| Component | Configuration |
|---|---|
| Endpoint | win-client-01 |
| Platform | Windows VM on Proxmox |
| Lab address | <WINDOWS_CLIENT_IP> |
| Domain | <LAB_DOMAIN> |
| Wazuh agent ID | 003 |
| Sysmon version | 15.22 |
| Configuration location | C:\SOC\Sysmon\sysmon-lab.xml |
| Executable hashing | SHA256 |

## Sysmon Configuration

Enabled process creation, network connection, and DNS query logging:

```xml
<Sysmon schemaversion="4.82">
  <HashAlgorithms>SHA256</HashAlgorithms>
  <EventFiltering>
    <ProcessCreate onmatch="exclude" />
    <NetworkConnect onmatch="exclude" />
    <DnsQuery onmatch="exclude" />
  </EventFiltering>
</Sysmon>
```

Installed from Administrator PowerShell:

```powershell
.\Sysmon64.exe -accepteula -i .\sysmon-lab.xml
```

The installation validated the configuration and started the Sysmon service and driver.

## Wazuh Integration

Backed up the existing Windows agent configuration before adding the Sysmon event channel to:

```text
C:\Program Files (x86)\ossec-agent\ossec.conf
```

Added inside the existing `<ossec_config>` block:

```xml
<localfile>
  <location>Microsoft-Windows-Sysmon/Operational</location>
  <log_format>eventchannel</log_format>
</localfile>
```

Restarted the agent and confirmed that both WazuhSvc and Sysmon64 were running.

## Detection Configuration

| Rule | Purpose | Result |
|---|---|---|
| 92004, built-in | Detect PowerShell spawning a Windows command shell | Triggered during the process test |
| 100100, custom | Match the process marker MUTASPACE-SYSMON-TEST under rule 92004 | Positive and negative-control tests passed |
| 92057, built-in | Detect PowerShell spawning another PowerShell process with an encoded command | Triggered during a harmless encoded-command test |
| 100101, custom | Match DNS queries for soc-dns-test.example.com under rule 61650 | Positive test passed |

Custom rule files:

```text
/var/ossec/etc/rules/mutaspace_sysmon_rules.xml
/var/ossec/etc/rules/mutaspace_dns_rules.xml
```

Both configurations passed `wazuh-analysisd -t` with exit code 0 before the manager was restarted.

## Validation Results

### Process Activity: Event ID 1

Confirmed local capture and Wazuh alerting for the controlled process test. The event preserved the executable, parent process, command line, user, process identifiers, and SHA256 hash.

Custom rule 100100 produced a level 5 alert. A separate control command triggered the original rule 92004 without triggering the custom marker rule.

### DNS Activity: Event ID 22

Confirmed local DNS events containing the queried domain, originating process, user, query status, and results.

The built-in DNS rule 61650 was configured at level 0. A targeted custom rule was added to generate an alert for one test domain. Rule 100101 produced the expected level 5 alert in Wazuh.

### Network Activity: Event ID 3

Confirmed local capture of curl.exe initiating a TCP connection from 10.10.10.105 to destination port 443.

Network connection alerting in Wazuh remains unvalidated.

## Troubleshooting Notes

- An initial process search missed the event because its filter did not match the recorded command-line format. Searching for the unique marker located the event.
- Local DNS collection was working even when no matching alerts appeared in Wazuh. The targeted DNS rule demonstrated the collection-to-alert path.
- A narrow time window initially missed the curl connection event. A broader search located it.
- Comparing the HTTP response time with the Sysmon event exposed approximately two hours of clock skew.
- The client used Local CMOS Clock. Domain synchronization failed, and Windows Time logs reported a broken domain trust relationship.
- The time zone and clock were manually corrected. Secure-channel repair, computer-password reset, and Netlogon restart attempts did not restore domain trust.

**Open issue:** Automatic domain time synchronization and domain trust remain unresolved.

## Why This Matters

The environment now has detailed Windows endpoint telemetry and validated process and DNS alerts. This provides a foundation for investigating activity through process ancestry, command lines, identities, and network-related evidence.

The custom marker rules validate specific collection and detection paths. They do not establish broad malicious-activity coverage.

## Learning Reflection

This build reinforced the distinction between generating an event, collecting it, and producing an alert. A missing dashboard result requires checking each stage before assuming telemetry collection failed.

It also demonstrated why timestamp alignment matters when correlating evidence across systems.
