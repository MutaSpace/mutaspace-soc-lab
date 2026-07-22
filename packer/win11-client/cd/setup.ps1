# packer/win11-client/cd/setup.ps1
#
# WHAT THIS IS
#   The WinRM bootstrap. It ships on the generated PACKERCD seed ISO next to
#   Autounattend.xml, and the answer file's FirstLogonCommands dot-sources it at the
#   first (auto-logon) sign-in.
#
# WHY IT EXISTS
#   Packer has no way into a fresh Windows machine. There is no SSH, WinRM is not
#   listening for remote connections by default, and the plugin discovers the guest's
#   IP address through the QEMU guest agent rather than by scraping DHCP leases.
#   Until both of those exist, the build just sits there. So this script is the
#   handover point between "Windows Setup drove itself" and "Packer is driving".
#
# ORDER MATTERS
#   WinRM is configured FIRST and the guest agent LAST. Packer starts polling for an
#   IP as soon as the agent answers; if the agent came up first there would be a
#   window where Packer knows the address but nothing is listening on 5985, and the
#   connection retries would just be noise. Doing it this way means that by the time
#   Packer knows where the machine is, it is already reachable.
#
# THE WINDOWS 11 DIFFERENCE
#   Step 1 below - forcing the network profile to Private - is optional on Server 2022
#   and MANDATORY here. On a client SKU the default profile for a new network is
#   Public, and `winrm quickconfig` flatly refuses to run on a Public network. It
#   reports a firewall error that never mentions the network profile, so the symptom is
#   "WinRM bootstrap appears to succeed, Packer never connects, build hangs until
#   winrm_timeout". This is the classic "works on Server 2022, hangs on Windows 11"
#   failure, and step 1 is the entire fix.
#
# THIS FILE IS INTENTIONALLY DUPLICATED
#   packer/win-server-2022/cd/setup.ps1 is a near-copy. The two templates are
#   independent build units with different media, different driver directories and
#   different licensing constraints, and a shared file across sibling Packer
#   directories is fragile (relative paths resolve against the template folder). Keep
#   them in sync by hand; the differences are commented where they exist.

$ErrorActionPreference = 'Stop'

# Log to a file as well as the console. When a Packer Windows build hangs, this log is
# usually the only evidence of what happened, because nothing is connected yet.
$logDir = 'C:\Windows\Temp'
$log = Join-Path $logDir 'packer-bootstrap.log'

function Write-Step {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 's'), $Message
    Write-Host $line
    Add-Content -Path $log -Value $line
}

Write-Step 'setup.ps1 starting'

# ---------------------------------------------------------------------------
# 1. Network profile -> Private
#
# `winrm quickconfig` refuses to run when any connected network is classed as Public,
# with a message about the firewall that does not mention the profile at all. On
# Windows Server the default profile is usually Domain or Private so this is a no-op;
# on Windows 11 it is Public and this line is the difference between a build that
# works and the classic "works on Server 2022, hangs on Win11" failure.
# ---------------------------------------------------------------------------
try {
    Get-NetConnectionProfile |
        Where-Object { $_.NetworkCategory -ne 'DomainAuthenticated' } |
        ForEach-Object {
            Write-Step ("Setting network profile '{0}' to Private" -f $_.Name)
            Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
        }
} catch {
    Write-Step ("WARNING: could not set network profile: {0}" -f $_.Exception.Message)
}

# ---------------------------------------------------------------------------
# 2. WinRM
#
# Plain HTTP on 5985, Basic auth, unencrypted. That is a genuinely weak configuration
# and it is deliberate: this exists only on the isolated, host-masqueraded build plane
# (vmbr9) for the length of one build. sysprep /generalize at the end of the build
# resets the WinRM listener and its credential state, and the finished VMs are managed
# by Ansible over Kerberos, not over this.
# ---------------------------------------------------------------------------
Write-Step 'Configuring WinRM'
& winrm quickconfig -quiet -force

& winrm set winrm/config/service '@{AllowUnencrypted="true"}'
& winrm set winrm/config/service/auth '@{Basic="true"}'
& winrm set winrm/config/client/auth '@{Basic="true"}'

# The default MaxTimeoutms (60s) is short enough that a slow MSI install can look
# like a dropped connection. The default MaxMemoryPerShellMB is also low enough to
# trip up large PowerShell provisioners.
& winrm set winrm/config '@{MaxTimeoutms="1800000"}'
& winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'

# Without this, a remote logon as a local administrator is filtered down to a standard
# user token and every provisioner silently loses its privileges.
Write-Step 'Setting LocalAccountTokenFilterPolicy'
New-ItemProperty `
    -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name 'LocalAccountTokenFilterPolicy' `
    -Value 1 -PropertyType DWord -Force | Out-Null

# quickconfig usually opens the firewall itself, but only for the profiles that were
# active when it ran. An explicit rule survives a later profile change.
Write-Step 'Opening TCP 5985 inbound'
if (-not (Get-NetFirewallRule -Name 'Packer-WinRM-HTTP-In' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name 'Packer-WinRM-HTTP-In' `
        -DisplayName 'Packer WinRM HTTP (build only)' `
        -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 `
        -Action Allow -Profile Any | Out-Null
}

# Delayed auto-start: WinRM occasionally loses a race against the network stack on a
# cold boot, and a delayed start costs nothing on a machine that is about to be
# sysprepped anyway.
Write-Step 'Setting WinRM to delayed auto-start'
& sc.exe config WinRM start= delayed-auto | Out-Null
Restart-Service WinRM

# The build password must not expire mid-build on a machine with a default 42-day
# maximum password age.
& net accounts /maxpwage:unlimited | Out-Null

# ---------------------------------------------------------------------------
# 3. QEMU guest agent
#
# This is not a nicety. The proxmox-iso builder resolves the guest's IP address by
# asking the QEMU guest agent, and `qemu_agent` defaults to true. With the agent
# absent, Packer waits, then times out -- and the same is true later for OpenTofu,
# where a missing agent turns every create AND every refresh into a fifteen-minute
# stall. The agent belongs in the template, not in a post-clone script.
#
# The virtio-win CD is located by content, not by drive letter, for the same reason
# setup.ps1 is located by volume label: letters shift when ISO devices are reordered.
# The full virtio driver and tool set (including blnsvr.exe for ballooning) is
# installed later by scripts/00-virtio-guest-tools.ps1 over WinRM; all we need right
# now is enough of an agent to be found.
# ---------------------------------------------------------------------------
Write-Step 'Locating the virtio-win CD'
$agentMsi = $null
foreach ($vol in (Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter })) {
    $candidate = '{0}:\guest-agent\qemu-ga-x86_64.msi' -f $vol.DriveLetter
    if (Test-Path $candidate) {
        $agentMsi = $candidate
        break
    }
}

if ($agentMsi) {
    Write-Step ("Installing QEMU guest agent from {0}" -f $agentMsi)
    $p = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList '/i', ('"{0}"' -f $agentMsi), '/qn', '/norestart' `
        -Wait -PassThru
    Write-Step ("msiexec exit code {0}" -f $p.ExitCode)
} else {
    # Loud, not silent. A build that reaches winrm_timeout with no explanation is the
    # single most time-consuming failure mode in Windows Packer work.
    Write-Step 'ERROR: qemu-ga-x86_64.msi not found on any CD-ROM volume.'
    Write-Step 'ERROR: Packer discovers the guest IP through the QEMU guest agent.'
    Write-Step 'ERROR: Without it this build WILL hang until winrm_timeout expires.'
    Write-Step 'ERROR: Check that virtio_win_iso_file points at a real, uncompressed virtio-win ISO.'
}

Write-Step 'setup.ps1 finished'
