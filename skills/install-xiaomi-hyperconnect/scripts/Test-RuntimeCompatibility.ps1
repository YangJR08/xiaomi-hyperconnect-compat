[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PcManager', 'Xiaoai')]
    [string]$Product,

    [string]$InstallRoot,

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

$resolvedRoot = Resolve-CompatInstallRoot -Product $Product -InstallRoot $InstallRoot
Assert-CompatProductLayout -Product $Product -InstallRoot $resolvedRoot
$version = Split-Path -Leaf $resolvedRoot
$targets = Get-CompatRuntimeTargets -Product $Product -InstallRoot $resolvedRoot
$fileResults = foreach ($target in $targets) {
    $artifact = Get-CompatArtifact -Name $target.Artifact
    $exists = Test-Path -LiteralPath $target.Destination -PathType Leaf
    $actualHash = if ($exists) { Get-Sha256 -Path $target.Destination } else { $null }
    [pscustomobject]@{
        Path = [string]$target.Destination
        Exists = $exists
        SHA256 = $actualHash
        ExpectedSHA256 = [string]$artifact.sha256
        Matches = $exists -and $actualHash -eq [string]$artifact.sha256
    }
}

$legacyPath = Join-Path $resolvedRoot 'XiaoaiHost.dll'
$legacyResult = $null
if ($Product -eq 'Xiaoai' -and (Test-Path -LiteralPath $legacyPath -PathType Leaf)) {
    $legacyArtifact = Get-CompatArtifact -Name 'xiaoai_host_3_5_0_220'
    $legacyHash = Get-Sha256 -Path $legacyPath
    $legacyResult = [pscustomobject]@{
        Path = $legacyPath
        SHA256 = $legacyHash
        State = if ($legacyHash -eq [string]$legacyArtifact.sha256) {
            'PatchedLegacyFile'
        }
        elseif ($legacyHash -eq [string]$legacyArtifact.original_sha256) {
            'OriginalSupportedLegacyFile'
        }
        else {
            'OtherVersionOrUnknown'
        }
    }
}

$processNames = if ($Product -eq 'PcManager') {
    @('XiaomiPcManager', 'XiaomiPcHost')
}
else {
    @('XiaoaiAgent', 'XiaoaiHost', 'XiaomiAISearchBar', 'AIBroker')
}
$processResults = Get-Process -Name $processNames -ErrorAction SilentlyContinue |
    Select-Object ProcessName, Id, Responding

$pcModel = if ($Product -eq 'Xiaoai') {
    Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\MI\XiaoaiAgent\Cache' `
        -Name PCModel -ErrorAction SilentlyContinue
}
else {
    $null
}

$result = [pscustomobject]@{
    Product = $Product
    Version = $version
    InstallRoot = $resolvedRoot
    Files = @($fileResults)
    LegacyXiaoaiHost = $legacyResult
    CachedPCModel = $pcModel
    Processes = @($processResults)
    Compatible = (@($fileResults | Where-Object { -not $_.Matches }).Count -eq 0)
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}
