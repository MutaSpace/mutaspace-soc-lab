# packer/win-server-2022/scripts/90-cleanup.ps1
#
# WHAT THIS IS
#   The second-to-last provisioner. Credential hygiene, disk hygiene, and one
#   deliberate act of restraint.
#
# WHY IT EXISTS
#   A golden template is copied. Anything left in it is left in every VM built from it
#   for as long as the lab exists, and a build-time Administrator password sitting in
#   a template is a genuine finding, not a tidiness issue -- especially on a template
#   whose only consumer is a domain controller.
#
# WHAT sysprep DOES AND DOES NOT DO
#   sysprep /generalize (the next script) clears the machine SID, the WinRM listener
#   state and the LSA secret. It does NOT delete the AutoAdminLogon registry values,
#   does NOT remove the answer file copies Windows Setup cached under
#   C:\Windows\Panther, and does NOT touch the logs. Those are this script's job.
#
#   The widely-repeated advice to "set AutoLogonCount to 0" is a logon-counter fix.
#   It stops the next autologon; it does not scrub the stored password. Deleting the
#   values is what actually removes the credential.

$ErrorActionPreference = 'Continue'

Write-Host '--- Credential hygiene ---'

$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
foreach ($name in @('AutoAdminLogon', 'DefaultUserName', 'DefaultPassword', 'DefaultDomainName', 'AutoLogonCount')) {
    if (Get-ItemProperty -Path $winlogon -Name $name -ErrorAction SilentlyContinue) {
        Write-Host "Removing Winlogon\$name"
        Remove-ItemProperty -Path $winlogon -Name $name -Force -ErrorAction SilentlyContinue
    }
}

# Windows Setup caches the answer file -- including the plaintext password -- here.
Write-Host 'Scrubbing C:\Windows\Panther'
Remove-Item -Path 'C:\Windows\Panther\*' -Recurse -Force -ErrorAction SilentlyContinue

foreach ($stray in @('C:\Windows\System32\Sysprep\unattend.xml',
        'C:\Windows\System32\Sysprep\Panther',
        'C:\unattend.xml',
        'C:\Autounattend.xml')) {
    if (Test-Path $stray) {
        Write-Host "Removing $stray"
        Remove-Item -Path $stray -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The build-time bootstrap log records what setup.ps1 did. It contains no password,
# but it also has no reason to survive into every clone.
Remove-Item -Path 'C:\Windows\Temp\packer-bootstrap.log' -Force -ErrorAction SilentlyContinue

Write-Host '--- Log and temp cleanup ---'

# Clearing the event log matters here for a reason specific to this lab: the two
# completed incident scenarios in docs/incident-scenarios/ are built on Windows
# Security events. Shipping a template pre-loaded with build-time 4624/4625 events
# would put noise into the exact log learners are told to read.
foreach ($logName in (Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordCount -gt 0 -and $_.IsEnabled }).LogName) {
    try {
        [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($logName)
    } catch {
        # Some channels refuse to be cleared. Not worth failing a build over.
    }
}

Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
# EXCLUDE packer-* HERE. Packer stages its own helper scripts in C:\Windows\Temp -
# notably packer-ps-env-vars-<guid>.ps1, which it dot-sources at the start of EVERY
# remaining provisioner to set environment variables. Deleting it mid-build produces:
#
#   . : The term 'c:/Windows/Temp/packer-ps-env-vars-<guid>.ps1' is not recognized as
#   the name of a cmdlet, function, script file, or operable program.
#
# It is non-fatal today - Packer carries on and the build completes - which is exactly
# why it is worth fixing rather than tolerating: it is loud red output that means
# nothing, printed immediately after "Cleanup complete", and it trains whoever is
# watching to ignore red text from this template. The next error will be a real one.
#
# Packer removes its own files when the build ends, so nothing is left behind by
# skipping them here.
# Excludes script-* as well as packer-*. Packer stages the provisioner script
# ITSELF as C:\Windows\Temp\script-<uuid>.ps1, not just the env-vars file, so a
# packer-*-only exclusion still deletes the next script. That cost a silent
# 20-minute hang on the win11 template (sysprep never ran, the VM never shut
# down, Packer waited forever). Fixed here too rather than leaving the two
# templates to diverge again.
Get-ChildItem -Path 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike 'packer-*' -and $_.Name -notlike 'script-*' } |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '--- Disk hygiene ---'

# Return freed blocks to the LVM-thin pool.
#
# This pairs with `discard = true` / `ssd = true` on the disk in win-server.pkr.hcl.
# Without the guest-side trim, the pool never learns that these blocks are free, and
# a full LVM-thin pool stalls or corrupts writes across EVERY VM on the host -- this
# is a host-wide failure mode, not a per-VM one.
try {
    Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction Stop
} catch {
    Write-Host "Optimize-Volume -ReTrim failed (this is not fatal): $($_.Exception.Message)"
}

Write-Host '--- Make sure Packer can still get back in ---'
#
# LAST THING BEFORE SYSPREP, AND IT MUST STAY LAST.
#
# Kept identical to win11-client/scripts/90-cleanup.ps1. There, client Windows
# disables the built-in Administrator when the answer file's AutoLogon LogonCount
# reaches 0, and every WinRM shell afterwards fails with:
#
#   Couldn't create shell: http response error: 401 - invalid content type
#
# Server is not known to do that - the built-in Administrator is the primary
# account here - so this is pure insurance on this template. It is present anyway
# because the two Windows templates keep diverging by having a fix applied to only
# one of them, and it costs one command.
try {
    $admin = Get-LocalUser -Name 'Administrator' -ErrorAction Stop
    if (-not $admin.Enabled) {
        Write-Host 'WARNING: the built-in Administrator was disabled during this build - re-enabling it.'
        Write-Host 'WARNING: check the AutoLogon LogonCount in the answer file; that is the usual cause.'
        Enable-LocalUser -Name 'Administrator'
    } else {
        Write-Host 'Built-in Administrator is enabled, as it should be.'
    }
} catch {
    Write-Host "Could not check the Administrator account: $($_.Exception.Message)"
}

Write-Host '--- What this script deliberately does NOT do ---'
#
#   slmgr /rearm
#
# This is the trap. It looks like the obvious thing to put in a template build: reset
# the evaluation clock so every clone starts with a full 180 days.
#
# It does not work that way. `slmgr /rearm` decrements the rearm counter IMMEDIATELY,
# at the moment it runs, not at expiry. Windows Server 2022 Evaluation allows six
# rearms. Putting this line in a Packer build spends one of them on every single
# build, and a template you rebuild half a dozen times while getting the answer file
# right is a template that has already burned its entire licensing runway before it
# ever became a domain controller.
#
# There is no recovery from that except reinstalling from the ISO -- which, since the
# media is registration-gated and cannot be re-fetched by a script, is a genuinely
# expensive mistake.
#
# The evaluation clock is managed as an operational fact instead. See D-03 in
# docs/iac/decisions.md: 180 days, six rearms, and a hard requirement to activate
# over the internet within the first 10 days or the machine shuts itself down. That
# last point is why fw-01 must permit dc-01 outbound during its first ten days --
# an unavoidable hole in the "isolated lab" story, and one worth teaching rather
# than hiding.

Write-Host 'Cleanup complete'
