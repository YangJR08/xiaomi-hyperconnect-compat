[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$skillBuildScript = Join-Path $repoRoot 'skills\install-xiaomi-hyperconnect\scripts\Build-Wtsapi32Proxy.ps1'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'build\wtsapi32-runtime-proxy'
}

& $skillBuildScript -OutputDirectory $OutputDirectory -Force:$Force
