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

$processNames = if ($Product -eq 'PcManager') {
    @('XiaomiPcManager', 'XiaomiPcHost')
}
else {
    @('XiaoaiAgent', 'XiaoaiHost', 'XiaomiAISearchBar')
}
if (-not $WhatIfPreference) {
    Get-Process -Name $processNames -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

foreach ($target in $targets) {
    $destination = [string]$target.Destination
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        [pscustomobject]@{ File = $destination; Status = 'Absent' }
        continue
    }
    $artifact = Get-CompatArtifact -Name $target.Artifact
    $actualHash = Get-Sha256 -Path $destination
    if ($actualHash -ne [string]$artifact.sha256) {
        throw "Refusing to change an unexpected installed file: $destination ($actualHash)"
    }

    $entry = if ($state) {
        $state.entries | Where-Object Destination -eq $destination | Select-Object -First 1
    }
    else {
        $null
    }

    if ($entry -and $entry.PriorState -in @('OriginalFile', 'KnownLegacyFile')) {
        if (-not $entry.BackupPath -or -not (Test-Path -LiteralPath $entry.BackupPath -PathType Leaf)) {
            throw "Verified backup is missing for: $destination"
        }
        if ((Get-Sha256 -Path $entry.BackupPath) -ne $entry.PriorHash) {
            throw "Backup hash mismatch: $($entry.BackupPath)"
        }
        if ($PSCmdlet.ShouldProcess($destination, "Restore verified backup $($entry.PriorHash)")) {
            Copy-Item -LiteralPath $entry.BackupPath -Destination $destination -Force
            [pscustomobject]@{ File = $destination; Status = 'Restored'; SHA256 = $entry.PriorHash }
        }
    }
    elseif ($entry -and $entry.PriorState -eq 'PreExistingCompatible') {
        [pscustomobject]@{ File = $destination; Status = 'LeftInPlace'; SHA256 = $actualHash }
    }
    elseif ($target.Artifact -eq 'xiaoai_host_3_5_0_220') {
        throw "Refusing to remove legacy XiaoaiHost.dll without its verified original backup: $destination"
    }
    elseif ($PSCmdlet.ShouldProcess($destination, 'Remove verified compatibility file')) {
        Remove-Item -LiteralPath $destination
        [pscustomobject]@{ File = $destination; Status = 'Removed' }
    }
}

if ($state -and -not $WhatIfPreference -and $PSCmdlet.ShouldProcess($statePath, 'Remove completed installation state')) {
    Remove-Item -LiteralPath $statePath
}
