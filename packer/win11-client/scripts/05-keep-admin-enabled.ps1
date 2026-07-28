# packer/win11-client/scripts/05-keep-admin-enabled.ps1
#
# WHAT THIS IS
#   A watchdog that keeps the built-in Administrator account enabled for the rest of
#   the build. It is the FIRST provisioner, because the thing it defends against
#   happens on Windows' schedule, not ours.
#
# WHY IT EXISTS
#   Client Windows disables the built-in Administrator partway through the build. Packer
#   authenticates to WinRM as that account, so from the moment it happens every shell
#   Packer opens is rejected and the build dies wherever it happens to be:
#
#     Error uploading script: Error uploading file to $env:TEMP\winrmcp-<uuid>.tmp:
#     Couldn't create shell: http response error: 401 - invalid content type
#
#   Measured at t+21m, t+21m and t+22m in three consecutive builds - Security event
#   4725, subject and target both the built-in Administrator (RID 500). It lands
#   between 90-cleanup finishing and 99-sysprep being uploaded, which is why it reads
#   as a sysprep problem and is not one.
#
#   Two theories were tested against the box and BOTH were wrong:
#     * "the AutoLogon LogonCount reached 0"  - raised 2 -> 5, confirmed the CD really
#       carried LogonCount 5, and Windows expired the autologon anyway.
#     * "90-cleanup deleting the autologon registry values triggers it" - moved that
#       deletion into 99-sysprep, and Windows deleted the values ITSELF at the same
#       t+21m and disabled the account exactly as before.
#
#   The likeliest remaining explanation is the documented client behaviour that the
#   built-in Administrator is disabled once another enabled local admin exists - the
#   Cloudbase-Init installer used to create one. 10-cloudbase-init.ps1 now installs with
#   RUN_SERVICE_AS_LOCAL_SYSTEM=1 so it does not.
#
#   THIS SCRIPT DOES NOT DEPEND ON THAT BEING RIGHT. It re-enables the account whatever
#   disabled it, which is the property worth having after three wrong diagnoses and
#   five failed 26-minute builds.
#
# HOW IT WORKS
#   Registers a scheduled task running as SYSTEM that polls every 3 seconds and
#   re-enables the account if it finds it disabled. 99-sysprep.ps1 removes the task and
#   its files before generalising, so NOTHING of this survives into the template -
#   verify that if you ever change either script.
#
#   The 3-second poll leaves a small window in which Packer could still hit a disabled
#   account. It is not zero. If that ever bites, the next step is an event-triggered
#   task bound to Security event 4725 rather than a poll.

$ErrorActionPreference = 'Stop'

$dir      = 'C:\ProgramData\mutaspace'
$script   = Join-Path $dir 'keep-admin-enabled.ps1'
$stopFlag = Join-Path $dir 'stop-watchdog.flag'
$taskName = 'MutaSpaceKeepAdminEnabled'

# NOT under C:\Windows\Temp: 90-cleanup.ps1 empties that directory mid-build, which
# would delete the watchdog while it is still needed.
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Remove-Item -Path $stopFlag -Force -ErrorAction SilentlyContinue

# Self-terminating: the stop flag, or 90 minutes, whichever comes first. A build that
# dies without running 99-sysprep must not leave this looping forever.
$watchdog = @'
$deadline = (Get-Date).AddMinutes(90)
$stopFlag = 'C:\ProgramData\mutaspace\stop-watchdog.flag'
$log      = 'C:\ProgramData\mutaspace\watchdog.log'
while ((Get-Date) -lt $deadline -and -not (Test-Path $stopFlag)) {
    try {
        $a = Get-LocalUser -Name 'Administrator' -ErrorAction Stop
        if (-not $a.Enabled) {
            Enable-LocalUser -Name 'Administrator'
            "$((Get-Date).ToString('s')) re-enabled the built-in Administrator" |
                Add-Content -Path $log
        }
    } catch {
        "$((Get-Date).ToString('s')) watchdog error: $($_.Exception.Message)" |
            Add-Content -Path $log
    }
    Start-Sleep -Seconds 3
}
'@
Set-Content -Path $script -Value $watchdog -Encoding UTF8

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
# New-ScheduledTaskSettingsSet, NOT New-ScheduledTaskSettings. The shorter name does
# not exist and cost a build: a parse check validates syntax, not cmdlet names, so it
# passed every check and then failed with CommandNotFoundException on the guest.
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName

Start-Sleep -Seconds 3
$state = (Get-ScheduledTask -TaskName $taskName).State
Write-Host "Watchdog task '$taskName' registered and started (state: $state)."
Write-Host "It re-enables the built-in Administrator every 3s until 99-sysprep.ps1 stops it."
