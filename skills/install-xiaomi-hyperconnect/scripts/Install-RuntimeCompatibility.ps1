[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PcManager', 'Xiaoai')]
    [string]$Product,

    [string]$InstallRoot,

    [switch]$EnableLegacyInfoCheckerPatch
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

if (-not $WhatIfPreference -and -not (Test-CompatAdministrator)) {
    throw 'Run this script from an elevated PowerShell 7 terminal. Use -WhatIf for an unprivileged dry run.'
}
if ($EnableLegacyInfoCheckerPatch -and $Product -ne 'Xiaoai') {
    throw '-EnableLegacyInfoCheckerPatch is valid only with -Product Xiaoai.'
}

$resolvedRoot = Resolve-CompatInstallRoot -Product $Product -InstallRoot $InstallRoot
Assert-CompatProductLayout -Product $Product -InstallRoot $resolvedRoot
$version = Split-Path -Leaf $resolvedRoot

if ($EnableLegacyInfoCheckerPatch) {
    $legacyArtifact = Get-CompatArtifact -Name 'xiaoai_host_3_5_0_220'
    if ($version -ne [string]$legacyArtifact.source_version) {
        throw "The legacy XiaoaiHost patch supports only $($legacyArtifact.source_version); selected version is $version."
    }
}

$targets = Get-CompatRuntimeTargets -Product $Product -InstallRoot $resolvedRoot `
    -IncludeLegacyInfoCheckerPatch:$EnableLegacyInfoCheckerPatch
$stateDirectory = Get-CompatStateDirectory -Product $Product -Version $version
$statePath = Join-Path $stateDirectory 'state.json'
$existingState = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $existingState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($existingState.product -ne $Product -or $existingState.install_root -ne $resolvedRoot) {
        throw "Existing state file does not match this installation: $statePath"
    }
}

$plan = foreach ($target in $targets) {
    $artifact = Get-CompatArtifact -Name $target.Artifact
    $source = Assert-CompatArtifact -Name $target.Artifact
    $destination = [string]$target.Destination
    $priorState = 'Absent'
    $priorHash = $null
    $backupPath = $null
    $trackedEntry = if ($existingState) {
        $existingState.entries | Where-Object Destination -eq $destination | Select-Object -First 1
    }
    else {
        $null
    }

    if ($trackedEntry) {
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "A tracked compatibility file is missing: $destination"
        }
        $currentHash = Get-Sha256 -Path $destination
        if ($currentHash -ne [string]$artifact.sha256) {
            throw "A tracked compatibility file changed unexpectedly: $destination ($currentHash)"
        }
        $priorState = [string]$trackedEntry.PriorState
        $priorHash = $trackedEntry.PriorHash
        $backupPath = $trackedEntry.BackupPath
    }
    elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
        $priorHash = Get-Sha256 -Path $destination
        if ($priorHash -eq [string]$artifact.sha256) {
            $priorState = 'PreExistingCompatible'
        }
        elseif ($target.Artifact -eq 'xiaoai_host_3_5_0_220' -and
                $priorHash -eq [string]$artifact.original_sha256) {
            $priorState = 'OriginalFile'
        }
        elseif ($target.Artifact -eq 'model_hook_tm2425' -and
                $artifact.known_replaceable_sha256 -contains $priorHash) {
            $priorState = 'KnownLegacyFile'
        }
        else {
            throw "Refusing to overwrite an unexpected file: $destination ($priorHash)"
        }
    }

    if ($priorState -in @('OriginalFile', 'KnownLegacyFile')) {
        $safeRelative = ($destination.Substring($resolvedRoot.Length).TrimStart('\') -replace '[\\/:*?"<>|]', '_')
        $backupPath = Join-Path $stateDirectory "backups\$safeRelative"
    }

    [pscustomobject]@{
        Artifact = [string]$target.Artifact
        Source = $source
        Destination = $destination
        ExpectedHash = [string]$artifact.sha256
        PriorState = $priorState
        PriorHash = $priorHash
        BackupPath = $backupPath
    }
}

$plan | Select-Object Artifact, Destination, PriorState, ExpectedHash
if ($WhatIfPreference) {
    foreach ($entry in $plan) {
        $null = $PSCmdlet.ShouldProcess($entry.Destination, "Install $($entry.Artifact)")
    }
    return
}

$processNames = if ($Product -eq 'PcManager') {
    @('XiaomiPcManager', 'XiaomiPcHost')
}
else {
    @('XiaoaiAgent', 'XiaoaiHost', 'XiaomiAISearchBar')
}
Get-Process -Name $processNames -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
foreach ($entry in $plan) {
    if ($entry.BackupPath) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $entry.BackupPath) -Force | Out-Null
        if (-not (Test-Path -LiteralPath $entry.BackupPath -PathType Leaf)) {
            Copy-Item -LiteralPath $entry.Destination -Destination $entry.BackupPath
        }
        if ((Get-Sha256 -Path $entry.BackupPath) -ne $entry.PriorHash) {
            throw "Backup verification failed: $($entry.BackupPath)"
        }
    }
    if ($entry.PriorState -ne 'PreExistingCompatible' -and
        $PSCmdlet.ShouldProcess($entry.Destination, "Install $($entry.Artifact)")) {
        Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination -Force
    }
    if ((Get-Sha256 -Path $entry.Destination) -ne $entry.ExpectedHash) {
        throw "Installed file verification failed: $($entry.Destination)"
    }
}

$stateEntries = @()
if ($existingState) {
    $stateEntries += @($existingState.entries)
}
foreach ($entry in $plan) {
    if (-not ($stateEntries | Where-Object Destination -eq $entry.Destination)) {
        $stateEntries += $entry | Select-Object Artifact, Destination, ExpectedHash, PriorState, PriorHash, BackupPath
    }
}

$state = [ordered]@{
    schema_version = 1
    product = $Product
    version = $version
    install_root = $resolvedRoot
    installed_at = if ($existingState) { $existingState.installed_at } else { (Get-Date).ToString('o') }
    updated_at = (Get-Date).ToString('o')
    entries = @($stateEntries)
}
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding utf8
[pscustomobject]@{ Status = 'Installed'; Product = $Product; Version = $version; StateFile = $statePath }
