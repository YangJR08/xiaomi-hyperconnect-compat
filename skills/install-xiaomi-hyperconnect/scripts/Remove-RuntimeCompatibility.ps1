[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PcManager', 'Xiaoai')]
    [string]$Product,

    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

if (-not $WhatIfPreference -and -not (Test-CompatAdministrator)) {
    throw 'Run this script from an elevated PowerShell 7 terminal. Use -WhatIf for an unprivileged dry run.'
}

$resolvedRoot = Resolve-CompatInstallRoot -Product $Product -InstallRoot $InstallRoot
Assert-CompatProductLayout -Product $Product -InstallRoot $resolvedRoot
$version = Split-Path -Leaf $resolvedRoot
$stateDirectory = Get-CompatStateDirectory -Product $Product -Version $version
$statePath = Join-Path $stateDirectory 'state.json'
$state = if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}
else {
    $null
}

$legacyPath = Join-Path $resolvedRoot 'XiaoaiHost.dll'
$includeLegacy = (Test-Path -LiteralPath $legacyPath -PathType Leaf) -and
    ((Get-Sha256 -Path $legacyPath) -eq
        [string](Get-CompatArtifact -Name 'xiaoai_host_3_5_0_220').sha256)
$targets = Get-CompatRuntimeTargets -Product $Product -InstallRoot $resolvedRoot `
    -IncludeLegacyInfoCheckerPatch:$includeLegacy

$plan = foreach ($target in $targets) {
    $destination = [string]$target.Destination
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        [pscustomobject]@{ File = $destination; Action = 'None'; Status = 'Absent' }
        continue
    }

    $artifact = Get-CompatArtifact -Name $target.Artifact
    $actualHash = Get-Sha256 -Path $destination
    $allowedHashes = @([string]$artifact.sha256) +
        @(Get-CompatKnownReplaceableHashes -Artifact $artifact)
    $entry = if ($state) {
        $state.entries | Where-Object Destination -eq $destination | Select-Object -First 1
    }
    else {
        $null
    }
    if ($entry -and $entry.ExpectedHash) {
        $allowedHashes += [string]$entry.ExpectedHash
    }
    if ($actualHash -notin $allowedHashes) {
        throw "Refusing to change an unexpected installed file: $destination ($actualHash)"
    }

    if ($entry -and $entry.PriorState -in @('OriginalFile', 'KnownLegacyFile')) {
        if (-not $entry.BackupPath -or -not (Test-Path -LiteralPath $entry.BackupPath -PathType Leaf)) {
            throw "Verified backup is missing for: $destination"
        }
        if ((Get-Sha256 -Path $entry.BackupPath) -ne $entry.PriorHash) {
            throw "Backup hash mismatch: $($entry.BackupPath)"
        }
        [pscustomobject]@{
            File = $destination
            Action = 'Restore'
            Status = 'Restored'
            BackupPath = [string]$entry.BackupPath
            SHA256 = [string]$entry.PriorHash
        }
    }
    elseif ($entry -and $entry.PriorState -eq 'PreExistingCompatible') {
        [pscustomobject]@{ File = $destination; Action = 'None'; Status = 'LeftInPlace'; SHA256 = $actualHash }
    }
    elseif ($target.Artifact -eq 'xiaoai_host_3_5_0_220') {
        throw "Refusing to remove legacy XiaoaiHost.dll without its verified original backup: $destination"
    }
    else {
        [pscustomobject]@{ File = $destination; Action = 'Remove'; Status = 'Removed'; SHA256 = $actualHash }
    }
}

$results = @()
if ($WhatIfPreference) {
    foreach ($entry in $plan) {
        if ($entry.Action -eq 'Restore') {
            if ($PSCmdlet.ShouldProcess($entry.File, "Restore verified backup $($entry.SHA256)")) {}
        }
        elseif ($entry.Action -eq 'Remove') {
            if ($PSCmdlet.ShouldProcess($entry.File, 'Remove verified compatibility file')) {}
        }
        else {
            $results += $entry | Select-Object File, Status, SHA256
        }
    }
    $results
    return
}

$serviceSnapshot = @(Suspend-CompatRuntime -InstallRoot $resolvedRoot)
try {
    foreach ($entry in $plan) {
        if ($entry.Action -eq 'Restore') {
            if ($PSCmdlet.ShouldProcess($entry.File, "Restore verified backup $($entry.SHA256)")) {
                foreach ($attempt in 1..20) {
                    Stop-CompatProcessesInRoot -InstallRoot $resolvedRoot
                    try {
                        Copy-Item -LiteralPath $entry.BackupPath -Destination $entry.File -Force -ErrorAction Stop
                        break
                    }
                    catch {
                        if ($attempt -eq 20) { throw }
                        Start-Sleep -Milliseconds 100
                    }
                }
                if ((Get-Sha256 -Path $entry.File) -ne $entry.SHA256) {
                    throw "Restored file verification failed: $($entry.File)"
                }
                $results += $entry | Select-Object File, Status, SHA256
            }
        }
        elseif ($entry.Action -eq 'Remove') {
            if ($PSCmdlet.ShouldProcess($entry.File, 'Remove verified compatibility file')) {
                foreach ($attempt in 1..20) {
                    Stop-CompatProcessesInRoot -InstallRoot $resolvedRoot
                    try {
                        Remove-Item -LiteralPath $entry.File -ErrorAction Stop
                        break
                    }
                    catch {
                        if ($attempt -eq 20) { throw }
                        Start-Sleep -Milliseconds 100
                    }
                }
                $results += $entry | Select-Object File, Status
            }
        }
        else {
            $results += $entry | Select-Object File, Status, SHA256
        }
    }

    if ($state -and $PSCmdlet.ShouldProcess($statePath, 'Remove completed installation state')) {
        Remove-Item -LiteralPath $statePath
    }
}
finally {
    Resume-CompatRuntime -Services $serviceSnapshot
}
$results
