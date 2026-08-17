[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^TM\d{4}$')]
    [string]$ModelCode,

    [string]$OutputDirectory,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

$ModelCode = $ModelCode.ToUpperInvariant()
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Get-Location) "generated\$ModelCode"
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$assetRoot = [IO.Path]::GetFullPath((Join-Path $script:SkillRoot 'assets')).TrimEnd('\')
$windowsRoot = [IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\')
if ($resolvedOutput.StartsWith($assetRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to generate files inside the Skill assets directory.'
}
if ($resolvedOutput.StartsWith($windowsRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to generate files inside the Windows directory.'
}

$proxySource = Assert-CompatArtifact -Name 'msimg32_proxy'
$hookSource = Assert-CompatArtifact -Name 'model_hook_tm2425'
$proxyArtifact = Get-CompatArtifact -Name 'msimg32_proxy'
$hookBytes = [IO.File]::ReadAllBytes($hookSource)
$oldToken = [Text.Encoding]::Unicode.GetBytes('TM2425')
$newToken = [Text.Encoding]::Unicode.GetBytes($ModelCode)

function Find-ByteSequence {
    param([byte[]]$Data, [byte[]]$Needle)

    for ($offset = 0; $offset -le $Data.Length - $Needle.Length; $offset++) {
        $matches = $true
        for ($index = 0; $index -lt $Needle.Length; $index++) {
            if ($Data[$offset + $index] -ne $Needle[$index]) {
                $matches = $false
                break
            }
        }
        if ($matches) { $offset }
    }
}

$hits = @(Find-ByteSequence -Data $hookBytes -Needle $oldToken)
if ($hits.Count -ne 1) {
    throw "Expected exactly one TM2425 token in the verified base hook; found $($hits.Count)."
}

$customBytes = [byte[]]::new($hookBytes.Length)
[Array]::Copy($hookBytes, $customBytes, $hookBytes.Length)
[Array]::Copy($newToken, 0, $customBytes, $hits[0], $newToken.Length)
$customHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($customBytes))

$proxyDestination = Join-Path $resolvedOutput 'msimg32.dll'
$hookDestination = Join-Path $resolvedOutput 'wtsapi32.dll'
$checksumPath = Join-Path $resolvedOutput 'SHA256SUMS.txt'
$expectedFiles = @(
    [pscustomobject]@{ Path = $proxyDestination; Hash = [string]$proxyArtifact.sha256 },
    [pscustomobject]@{ Path = $hookDestination; Hash = $customHash }
)

foreach ($entry in $expectedFiles) {
    if (Test-Path -LiteralPath $entry.Path -PathType Leaf) {
        $existingHash = Get-Sha256 -Path $entry.Path
        if (-not $Force -and $existingHash -ne $entry.Hash) {
            throw "Refusing to overwrite an unexpected generated file: $($entry.Path) ($existingHash)"
        }
    }
}

if ($PSCmdlet.ShouldProcess($resolvedOutput, "Generate TIMI/$ModelCode compatibility bundle")) {
    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
    Copy-Item -LiteralPath $proxySource -Destination $proxyDestination -Force
    [IO.File]::WriteAllBytes($hookDestination, $customBytes)

    foreach ($entry in $expectedFiles) {
        if ((Get-Sha256 -Path $entry.Path) -ne $entry.Hash) {
            throw "Generated file verification failed: $($entry.Path)"
        }
    }

    @(
        "$($proxyArtifact.sha256)  msimg32.dll",
        "$customHash  wtsapi32.dll"
    ) | Set-Content -LiteralPath $checksumPath -Encoding utf8NoBOM
}

[pscustomobject]@{
    ModelCode = $ModelCode
    OutputDirectory = $resolvedOutput
    ProxySHA256 = [string]$proxyArtifact.sha256
    HookSHA256 = $customHash
    Status = if ($WhatIfPreference) { 'WhatIf' } else { 'Generated' }
    Warning = 'The generated wtsapi32.dll is unsigned and should be used only with an explicitly selected supported TM model code.'
}
