# packer/win11-client/scripts/90-cleanup.ps1
#
# WHAT THIS IS
#   The second-to-last provisioner. Credential hygiene, disk hygiene, and one
#   deliberate act of restraint.
#
# WHY IT EXISTS
#   A golden template is copied. Anything left in it is left in every VM built from it
#   for as long as the lab exists, and a build-time Administrator password sitting in
#   a template is a genuine finding, not a tidiness issue -- especially on a template
#   inherited by every learner workstation clone.
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
Remove-Item -Path 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '--- Disk hygiene ---'

# Return freed blocks to the LVM-thin pool.
#
# This pairs with `discard = true` / `ssd = true` on the disk in win11-client.pkr.hcl.
# Without the guest-side trim, the pool never learns that these blocks are free, and
# a full LVM-thin pool stalls or corrupts writes across EVERY VM on the host -- this
# is a host-wide failure mode, not a per-VM one.
try {
    Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction Stop
} catch {
    Write-Host "Optimize-Volume -ReTrim failed (this is not fatal): $($_.Exception.Message)"
}

Write-Host '--- What this script deliberately does NOT do ---'
#
#   slmgr /rearm
#
# THE LICENSING TIMEBOMB, AND WHY THE OBVIOUS FIX MAKES IT WORSE.
#
# Windows 11 Enterprise Evaluation is the harshest licence in this lab:
#
#   * 90 days, not 180.
#   * TWO rearms, not six. Total runway is roughly 270 days.
#   * It CANNOT be converted in place. Server 2022 Evaluation can be turned into a
#     retail install with `DISM /Set-Edition`; the Windows 11 client evaluation
#     cannot. When the clock runs out, the only route forward is a rebuild.
#
# `slmgr /rearm` looks like the obvious thing to put in a template build: reset the
# clock so every clone starts fresh. It does the opposite of what people expect. The
# rearm counter is decremented IMMEDIATELY, at the moment the command runs, not at
# expiry. With only two rearms available, a Packer build containing this line spends
# half the remaining runway per build - and getting an answer file right usually takes
# more than two builds. The template would be out of rearms before it ever produced a
# working win-client-01.
#
# There is no recovery except reinstalling from media that is registration-gated and
# cannot be re-fetched by a script.
#
# THE REAL FIX, IF YOU HAVE IT: build this template from Volume Licensing media and
# set the `product_key` variable to the matching Windows 11 Enterprise GVLK. A VL
# install has no evaluation clock at all, which converts a recurring 90-day
# operational problem into a one-off media problem. The evaluation path exists because
# not everyone has VL media, not because it is the better choice.
#
# Either way the constraint is documented rather than hidden. A lab that quietly stops
# working after 90 days teaches something, but not the thing you intended.

Write-Host 'Cleanup complete'
