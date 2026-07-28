# packer/win11-client/scripts/99-sysprep.ps1
#
# WHAT THIS IS
#   The LAST provisioner. It generalises the machine so that Packer can convert it
#   into a template that produces genuinely distinct VMs.
#
# WHY IT EXISTS
#   Cloning a Windows machine without generalising it produces clones that share a
#   machine SID, a machine account password, a set of WinRM credentials and a computer
#   name. On a lab whose whole point is Active Directory, duplicate SIDs are not a
#   theoretical problem: domain join, Group Policy and the Wazuh agent identity all
#   depend on the machine being unique.
#
#   sysprep /generalize strips all of that, and re-runs specialize and OOBE on the
#   next boot -- which is the hook Cloudbase-Init uses to apply the per-VM hostname
#   and address that OpenTofu handed it.
#
# ###########################################################################
# # /quit, NOT /shutdown -- AND THAT IS DELIBERATE                          #
# #                                                                          #
# # Nearly every Windows Packer example ends with                            #
# #     Sysprep.exe /generalize /oobe /shutdown                              #
# # because nearly every Windows Packer example uses a builder that has a    #
# # `shutdown_command`. proxmox-iso does not. It has never had one           #
# # (packer-plugin-proxmox issue #271, still open).                           #
# #                                                                          #
# # What proxmox-iso actually does is stop the VM out-of-band through the    #
# # Proxmox API in stepConvertToTemplate, after the last provisioner returns. #
# #                                                                          #
# # So /shutdown would pull the floor out from under the running provisioner: #
# # the guest powers off while Packer is still holding the WinRM session, the #
# # session dies mid-command, and the provisioner reports a failure on a      #
# # build that actually succeeded. That failure is intermittent, which is     #
# # worse than consistent.                                                    #
# #                                                                          #
# # /quit makes sysprep generalise and then return cleanly. The provisioner   #
# # exits 0, Packer stops the VM through the API, and the template is         #
# # created. The generalisation -- not the shutdown -- is what clears the     #
# # credential state, so nothing is lost by shutting down a different way.    #
# #                                                                          #
# # The one residual risk is a race: the API's ACPI shutdown could in         #
# # principle land before sysprep has finished flushing. The Start-Sleep and  #
# # the state check at the bottom of this script exist for that.              #
# ###########################################################################
#
# NOTHING MAY RUN AFTER THIS SCRIPT. Any provisioner added below it would execute on a
# machine whose identity has already been erased.

$ErrorActionPreference = 'Stop'

$sysprepExe = Join-Path $env:SystemRoot 'System32\Sysprep\Sysprep.exe'
if (-not (Test-Path $sysprepExe)) {
    throw "Sysprep.exe not found at $sysprepExe"
}

# ---------------------------------------------------------------------------
# CREDENTIAL HYGIENE - deliberately here, in the LAST provisioner, and not in
# 90-cleanup.ps1 where it used to live and where it looks like it belongs.
#
# The answer file's autologon leaves the build password in the registry in
# PLAINTEXT (Winlogon\DefaultPassword). It must not survive into a template that
# is cloned for every learner workstation. sysprep /generalize does NOT remove
# these values, so something has to.
#
# It cannot be 90-cleanup: on client Windows the built-in Administrator is enabled
# only for the OOBE autologon, so removing the autologon configuration makes
# Windows finalise it at the next session boundary and DISABLE the account. Every
# WinRM shell afterwards then fails with
#   Couldn't create shell: http response error: 401 - invalid content type
# and Packer dies uploading the next script. Measured at about four minutes after
# the delete, twice.
#
# Here it is safe: nothing needs to authenticate again. The template has no
# shutdown_command, so Packer stops the VM through the Proxmox API once this
# script returns.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# STOP THE ADMINISTRATOR WATCHDOG registered by 05-keep-admin-enabled.ps1.
#
# It must not survive into the template: a scheduled task that re-enables the built-in
# Administrator every three seconds is a backdoor in every learner clone, and this is
# the last chance to remove it. Nothing after this point needs WinRM, so nothing needs
# the account kept alive any more.
# ---------------------------------------------------------------------------
Write-Host '--- Removing the Administrator watchdog ---'
$watchdogDir = 'C:\ProgramData\mutaspace'
New-Item -Path $watchdogDir -ItemType Directory -Force | Out-Null
Set-Content -Path (Join-Path $watchdogDir 'stop-watchdog.flag') -Value 'stop' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Unregister-ScheduledTask -TaskName 'MutaSpaceKeepAdminEnabled' -Confirm:$false -ErrorAction SilentlyContinue
Get-Process -Name 'powershell' -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $PID -and $_.CommandLine -like '*keep-admin-enabled*' } |
    ForEach-Object { try { $_.Kill() } catch { } }
Remove-Item -Path $watchdogDir -Recurse -Force -ErrorAction SilentlyContinue

if (Get-ScheduledTask -TaskName 'MutaSpaceKeepAdminEnabled' -ErrorAction SilentlyContinue) {
    throw 'The Administrator watchdog task is still registered. It must not ship in the template.'
}
Write-Host 'Watchdog task removed and its files deleted.'

# ---------------------------------------------------------------------------
# DELETE THE `packer` BUILD ACCOUNT. It must not ship in the template.
#
# The answer file creates it as a local administrator because Packer cannot use the
# built-in Administrator: client Windows disables that account a few minutes into
# every build and no new WinRM shell can be opened afterwards. See the note beside
# the account definition in cd/Autounattend.xml.pkrtpl.
#
# This is the last moment it can be removed. A build account with a known password,
# in Administrators, in the template that every learner workstation is cloned from,
# is exactly the finding this lab exists to teach people to spot.
#
# We are almost certainly RUNNING AS this account right now - Packer's WinRM session
# is authenticated as `packer`. Deleting it does not tear down the already-running
# process or its token, so sysprep still completes below. The deletion is wrapped
# anyway: if it fails the build should still produce a template, and say loudly what
# is wrong with it, rather than throwing away a 25-minute build.
# ---------------------------------------------------------------------------
Write-Host '--- Removing the packer build account ---'
try {
    if (Get-LocalUser -Name 'packer' -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name 'packer' -ErrorAction Stop
        Write-Host 'Deleted the local account `packer`.'
    } else {
        Write-Host 'No `packer` account present (already gone).'
    }
    $profilePath = 'C:\Users\packer'
    if (Test-Path $profilePath) {
        Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPath -eq $profilePath } |
            Remove-CimInstance -ErrorAction SilentlyContinue
        Remove-Item -Path $profilePath -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "WARNING: could not delete the packer account: $($_.Exception.Message)"
    Write-Host 'WARNING: THIS TEMPLATE SHIPS A LOCAL ADMIN CALLED `packer` WITH THE BUILD'
    Write-Host 'WARNING: PASSWORD. Remove it by hand before cloning, and fix this script.'
}

Write-Host '--- Credential hygiene (autologon values) ---'
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
foreach ($name in @('AutoAdminLogon', 'DefaultUserName', 'DefaultPassword', 'DefaultDomainName', 'AutoLogonCount')) {
    if (Get-ItemProperty -Path $winlogon -Name $name -ErrorAction SilentlyContinue) {
        Write-Host "Removing Winlogon\$name"
        Remove-ItemProperty -Path $winlogon -Name $name -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Hand sysprep the Cloudbase-Init answer file if it is there.
#
# That file adds a specialize-pass command that runs Cloudbase-Init on the first boot
# of a clone. Without it, Cloudbase-Init still runs later as a service, but AFTER
# OOBE rather than during specialize -- which means the machine briefly comes up with
# the wrong hostname and then renames itself, and a rename after domain join is a
# genuinely annoying failure mode on a machine that is about to be domain-joined.
#
# If the file is missing we continue without it rather than failing the build, and say
# so, because a template with a slightly late Cloudbase-Init is still usable and a
# failed 90-minute Windows build is expensive.
# ---------------------------------------------------------------------------
$cbUnattend = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml'

$sysprepArgs = @('/generalize', '/oobe')

# /mode:vm tells sysprep the image will be redeployed on the same virtual platform, so
# it skips some of the hardware re-detection that only matters when an image moves
# between physical machines. It is valid only alongside /generalize. On a Proxmox
# template cloned onto the same host, that assumption is exactly true, and it takes a
# noticeable amount of time off first boot.
$sysprepArgs += '/mode:vm'

$errLog = 'C:\Windows\System32\Sysprep\Panther\setuperr.log'
function Show-SysprepErrorLog {
    if (Test-Path $errLog) {
        Write-Host '--- setuperr.log ---'
        Get-Content $errLog | Select-Object -Last 60 | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "(no $errLog on disk)"
    }
}

if (Test-Path $cbUnattend) {
    # -----------------------------------------------------------------------
    # STAGE THE ANSWER FILE AT A PATH WITH NO SPACES. Do not "simplify" this.
    #
    # The obvious form - adding '/unattend:"C:\Program Files\..."' as one element
    # of a -ArgumentList ARRAY - does not work. PowerShell re-quotes every array
    # element, so sysprep receives `/unattend:C:\Program` followed by a bare
    # `Files\Cloudbase`, and rejects the entire command line:
    #
    #   SYSPRP ParseCommands:Found supported command line option 'UNATTEND'
    #   SYSPRP ParseCommands:Malformed command line detected; no dash or slash present in option
    #   SYSPRP WinMain: Unable to parse command-line arguments to sysprep
    #
    # Sysprep then raises a MODAL ERROR DIALOG. This script runs over WinRM on a
    # non-interactive session, so there is nobody to dismiss it and
    # `Start-Process -Wait` waits forever. From outside that looks like: not one
    # line of output from this script, a black console, an idle guest, and a VM
    # that never shuts down - so Packer waits on a shutdown that is never coming.
    #
    # That symptom was misdiagnosed twice, first as the vTPM and then as
    # automatic BitLocker. (Preventing BitLocker is still correct and still in
    # the answer file - it just was not this.) The proof is in
    # Windows\System32\Sysprep\Panther\setuperr.log, on a disk Packer deletes
    # unless the build was started with -on-error=abort.
    #
    # Copying to a space-free path removes the quoting question entirely.
    # 90-cleanup.ps1 has already run by this point, so nothing will delete it.
    # -----------------------------------------------------------------------
    $stagedUnattend = 'C:\Windows\Temp\cloudbase-unattend.xml'
    Copy-Item -LiteralPath $cbUnattend -Destination $stagedUnattend -Force
    Write-Host "Using the Cloudbase-Init answer file: $cbUnattend"
    Write-Host "Staged for sysprep at:                $stagedUnattend"

    # -----------------------------------------------------------------------
    # INJECT SkipRearm=1 INTO THE GENERALIZE PASS. Do not remove it.
    #
    # Without it, sysprep /generalize calls SLReArmWindows and the build dies:
    #
    #   SYSPRP LaunchModule: Failure executing 'SLReArmWindows' from slc.dll;
    #                        dwRet = 0xc004f075
    #   SYSPRP Error in executing action for Microsoft-Windows-Security-SPP
    #
    # and then sysprep hangs on a dialog nobody can see, so the 15-minute deadline
    # below is what actually ends the build.
    #
    # Skipping the rearm is not a workaround here, it is the policy this repo
    # already committed to. Windows 11 Enterprise Evaluation allows only TWO
    # rearms in its entire life, and the counter decrements the moment the rearm
    # runs. A generalize that rearms would spend half the image's total runway on
    # every single build - and getting a Windows template right takes more than
    # two builds, as the last ten demonstrate. 90-cleanup.ps1 refuses to run
    # `slmgr /rearm` for exactly this reason; this is the same decision in the
    # place sysprep actually reads.
    #
    # Consequence to be aware of: clones inherit the REMAINING evaluation period
    # rather than a fresh 90 days. That is the documented trade in
    # 90-cleanup.ps1 - the fix for an expired evaluation is VL media, not rearms.
    # -----------------------------------------------------------------------
    $ns  = 'urn:schemas-microsoft-com:unattend'
    $xml = [xml](Get-Content -LiteralPath $stagedUnattend -Raw)

    $generalize = $xml.unattend.settings | Where-Object { $_.pass -eq 'generalize' }
    if (-not $generalize) {
        $generalize = $xml.CreateElement('settings', $ns)
        $generalize.SetAttribute('pass', 'generalize')
        $xml.DocumentElement.AppendChild($generalize) | Out-Null
        Write-Host 'Added a generalize pass to the staged answer file.'
    }

    $spp = $generalize.component | Where-Object { $_.name -eq 'Microsoft-Windows-Security-SPP' }
    if (-not $spp) {
        $spp = $xml.CreateElement('component', $ns)
        $spp.SetAttribute('name', 'Microsoft-Windows-Security-SPP')
        $spp.SetAttribute('processorArchitecture', 'amd64')
        $spp.SetAttribute('publicKeyToken', '31bf3856ad364e35')
        $spp.SetAttribute('language', 'neutral')
        $spp.SetAttribute('versionScope', 'nonSxS')
        $generalize.AppendChild($spp) | Out-Null
    }

    $skip = $xml.CreateElement('SkipRearm', $ns)
    $skip.InnerText = '1'
    $spp.AppendChild($skip) | Out-Null
    $xml.Save($stagedUnattend)
    Write-Host 'Injected SkipRearm=1 into the generalize pass (evaluation rearms are finite).'

    $sysprepArgs += "/unattend:$stagedUnattend"
} else {
    Write-Host "WARNING: $cbUnattend not found."
    Write-Host 'WARNING: running sysprep without /unattend. Cloudbase-Init will still run as a'
    Write-Host 'WARNING: service on first boot, but after OOBE rather than during specialize.'
}

# See the banner above. This is the load-bearing argument.
$sysprepArgs += '/quit'

# Pass ONE pre-joined string rather than the array, so PowerShell hands the
# command line to sysprep verbatim instead of re-quoting each element.
$argLine = $sysprepArgs -join ' '

# 0xC004F075 reads as "the operation cannot be completed because the service is
# stopping", and sppsvc starts on demand and stops again when idle - so sysprep can
# call into it exactly as it is winding down. SkipRearm above should mean sysprep
# never asks it for anything, but nudging the service into a running state first
# costs a second and removes the race either way.
try {
    $spp = Get-Service -Name 'sppsvc' -ErrorAction Stop
    if ($spp.Status -ne 'Running') {
        Write-Host "Starting the Software Protection service (was: $($spp.Status))"
        Start-Service -Name 'sppsvc' -ErrorAction SilentlyContinue
        $spp.WaitForStatus('Running', (New-TimeSpan -Seconds 60))
    }
    Write-Host "Software Protection service: $((Get-Service -Name 'sppsvc').Status)"
} catch {
    Write-Host "Could not check the Software Protection service: $($_.Exception.Message)"
}

Write-Host "Running: $sysprepExe $argLine"

# Deliberately NOT -Wait. A sysprep stopped on a dialog never returns, and an
# unbounded wait turns that into a build that hangs until someone notices hours
# later. Wait with a deadline instead, then kill it and print the log that says
# what happened. Generalize on this template takes a couple of minutes; 15 is
# slack, not a target.
$sysprepTimeoutSec = 900
$p = Start-Process -FilePath $sysprepExe -ArgumentList $argLine -PassThru

if (-not $p.WaitForExit($sysprepTimeoutSec * 1000)) {
    Write-Host "ERROR: sysprep has not exited after $sysprepTimeoutSec seconds."
    Write-Host 'ERROR: it is almost certainly waiting on a dialog nobody can see.'
    Show-SysprepErrorLog
    try { $p.Kill() } catch { Write-Host "(could not kill sysprep: $_)" }
    throw "Sysprep timed out after $sysprepTimeoutSec seconds."
}

Write-Host "Sysprep exit code: $($p.ExitCode)"

if ($p.ExitCode -ne 0) {
    Show-SysprepErrorLog
    throw "Sysprep failed with exit code $($p.ExitCode)."
}

# ---------------------------------------------------------------------------
# Verify the generalisation actually happened, rather than trusting exit code 0.
#
# GeneralizationState 7 is the value Windows writes once /generalize has completed.
# Checking it is the difference between "sysprep returned" and "the image is
# actually generalised", and this repository's documentation standard is explicit
# that a step is not complete just because it ran.
# ---------------------------------------------------------------------------
$genState = (Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name 'GeneralizationState' -ErrorAction SilentlyContinue).GeneralizationState
if ($genState -eq 7) {
    Write-Host 'GeneralizationState = 7 (generalize completed)'
} else {
    Write-Host "WARNING: GeneralizationState is '$genState', expected 7. Inspect C:\Windows\System32\Sysprep\Panther on the built template before trusting it."
}

$imageState = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\State' -Name 'ImageState' -ErrorAction SilentlyContinue).ImageState
Write-Host "ImageState = $imageState"

# Give sysprep a moment to flush to disk before Packer asks the API to stop the VM.
# See the race noted in the banner above.
Start-Sleep -Seconds 20

Write-Host 'Sysprep complete. Packer will now stop the VM through the Proxmox API and convert it to template 9003.'
