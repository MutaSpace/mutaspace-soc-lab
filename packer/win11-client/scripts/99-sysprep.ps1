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

if (Test-Path $cbUnattend) {
    Write-Host "Using the Cloudbase-Init answer file: $cbUnattend"
    $sysprepArgs += ('/unattend:"{0}"' -f $cbUnattend)
} else {
    Write-Host "WARNING: $cbUnattend not found."
    Write-Host 'WARNING: running sysprep without /unattend. Cloudbase-Init will still run as a'
    Write-Host 'WARNING: service on first boot, but after OOBE rather than during specialize.'
}

# See the banner above. This is the load-bearing argument.
$sysprepArgs += '/quit'

Write-Host "Running: $sysprepExe $($sysprepArgs -join ' ')"
$p = Start-Process -FilePath $sysprepExe -ArgumentList $sysprepArgs -Wait -PassThru
Write-Host "Sysprep exit code: $($p.ExitCode)"

if ($p.ExitCode -ne 0) {
    $errLog = 'C:\Windows\System32\Sysprep\Panther\setuperr.log'
    if (Test-Path $errLog) {
        Write-Host '--- setuperr.log ---'
        Get-Content $errLog | Select-Object -Last 60 | ForEach-Object { Write-Host $_ }
    }
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
