[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InstallerPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

$installer = Get-Item -LiteralPath $InstallerPath
$files = @(
    [pscustomobject]@{ Name = 'msimg32.dll'; Artifact = 'msimg32_proxy' },
    [pscustomobject]@{ Name = 'wtsapi32.dll'; Artifact = 'model_hook_tm2425' }
)

foreach ($entry in $files) {
    $path = Join-Path $installer.DirectoryName $entry.Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [pscustomobject]@{ File = $path; Status = 'Absent' }
        continue
    }
    $expected = [string](Get-CompatArtifact -Name $entry.Artifact).sha256
    $actual = Get-Sha256 -Path $path
    if ($actual -ne $expected) {
        throw "Refusing to remove an unexpected installer-side file: $path ($actual)"
    }
    if ($PSCmdlet.ShouldProcess($path, 'Remove verified installer compatibility file')) {
        Remove-Item -LiteralPath $path
        [pscustomobject]@{ File = $path; Status = 'Removed' }
    }
}
