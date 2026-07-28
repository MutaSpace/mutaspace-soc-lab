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

# ⚠️ THE AUTOLOGON REGISTRY VALUES ARE NOT DELETED HERE. Do not move them back.
#
# They are deleted at the top of 99-sysprep.ps1 instead, and the reason is not
# stylistic: deleting them here BREAKS THE BUILD.
#
# On client Windows, the built-in Administrator is enabled for the duration of the
# OOBE autologon. Take the autologon configuration away and, at the next session
# boundary a few minutes later, Windows finalises it and DISABLES the account -
# Security event 4725, subject and target both the built-in Administrator,
# followed by a burst of logon-triggered scheduled tasks that gives the boundary
# away. Every WinRM shell Packer opens after that is rejected:
#
#   Couldn't create shell: http response error: 401 - invalid content type
#
# So this script would delete the values, finish, report the account still
# enabled - and then the upload of the NEXT provisioner would fail. Measured at
# roughly t+21m in two consecutive builds, about four minutes after this script
# deleted them.
#
# 99-sysprep.ps1 is the right home for them because it is the last thing that
# needs WinRM at all: there is no shutdown_command in the template, so Packer
# stops the VM through the Proxmox API afterwards. Deleting the values there means
# nothing has to authenticate again.
#
# The credential is still gone from the finished template, which is the point of
# the exercise - it is removed a minute later than it used to be, inside the same
# build.

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

# Clear the temp directories, but NEVER Packer's own scaffolding.
#
# This ran as an unconditional `Remove-Item 'C:\Windows\Temp\*'` and broke the
# NEXT provisioner. Packer stages a per-provisioner env-vars script at
# C:\Windows\Temp\packer-ps-env-vars-<uuid>.ps1 and dot-sources it, so wiping
# that directory mid-build deletes a file the following script is about to run:
#
#   The term 'c:/Windows/Temp/packer-ps-env-vars-....ps1' is not recognized as
#   the name of a cmdlet, function, script file, or operable program.
#
# It was non-fatal here only because the failing dot-source did not stop sysprep.
# That is luck, not design - and the error looks like a Packer bug rather than
# something this script did.
#
# TWO name patterns must survive, not one. Packer stages BOTH
#   packer-ps-env-vars-<uuid>.ps1   the env-vars it dot-sources, and
#   script-<uuid>.ps1               THE PROVISIONER SCRIPT ITSELF
# in C:\Windows\Temp. Excluding only packer-* still deletes the next script, so
# sysprep never ran, the VM never shut down, and Packer waited on a shutdown that
# was never coming - a silent 20-minute hang with a black console.
#
# Note $env:TEMP for the SYSTEM account IS C:\Windows\Temp, so both lines were
# hitting the same directory.
#
# Sysprep /generalize clears temp itself, so anything missed here is handled a
# moment later anyway.
Get-ChildItem -Path 'C:\Windows\Temp\*' -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'packer-*' -and $_.Name -notlike 'script-*' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
if ($env:TEMP -and $env:TEMP -ne 'C:\Windows\Temp') {
    Get-ChildItem -Path "$env:TEMP\*" -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'packer-*' -and $_.Name -notlike 'script-*' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
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

Write-Host '--- Make sure Packer can still get back in ---'
#
# LAST THING BEFORE SYSPREP, AND IT MUST STAY LAST.
#
# Client Windows disables the built-in Administrator when the answer file's
# AutoLogon LogonCount reaches 0. If that happens the account is gone before the
# next provisioner runs, and Packer dies uploading it with:
#
#   Couldn't create shell: http response error: 401 - invalid content type
#
# The actual fix is LogonCount 5 in the answer file, so the count never reaches 0
# during a build. This is the belt to that pair of braces: it costs one command
# and turns a 25-minute failed build into a non-event if anything else in Windows
# decides to disable the account. Confirmed as a real failure mode - Security
# event 4725, fired mid-cleanup, three builds in a row.
#
# Leaving the account enabled is the intended state, not a weakening: the answer
# file enables it on purpose (that is what AdministratorPassword does), Packer
# needs it to connect, and the lab logs into it afterwards.
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
