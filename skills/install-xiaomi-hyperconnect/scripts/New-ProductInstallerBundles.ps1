[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidatePattern('^TM\d{4}$')]
    [string]$PcManagerModelCode = 'TM2425',

    [ValidatePattern('^TM\d{4}$')]
    [string]$XiaoaiModelCode = 'TM2430',

    [string]$OutputRoot = (Join-Path (Get-Location) 'build'),

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$generator = Join-Path $PSScriptRoot 'New-ModelCompatibilityBundle.ps1'
$resolvedOutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
$profiles = @(
    [pscustomobject]@{
        Product = 'PcManager'
        ModelCode = $PcManagerModelCode.ToUpperInvariant()
        DirectoryName = "XiaomiPCManager-$($PcManagerModelCode.ToUpperInvariant())"
    },
    [pscustomobject]@{
        Product = 'Xiaoai'
        ModelCode = $XiaoaiModelCode.ToUpperInvariant()
        DirectoryName = "SuperXiaoAI-$($XiaoaiModelCode.ToUpperInvariant())"
    }
)

foreach ($profile in $profiles) {
    $outputDirectory = Join-Path $resolvedOutputRoot $profile.DirectoryName
    & $generator `
        -Product $profile.Product `
        -ModelCode $profile.ModelCode `
        -OutputDirectory $outputDirectory `
        -Force:$Force `
        -WhatIf:$WhatIfPreference
}
