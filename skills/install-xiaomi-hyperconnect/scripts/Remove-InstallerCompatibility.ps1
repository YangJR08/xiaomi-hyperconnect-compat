[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InstallerPath,

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$BundleDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

$installer = Get-Item -LiteralPath $InstallerPath
$bundle = if ($BundleDirectory) {
    Get-CompatGeneratedBundle -Directory $BundleDirectory
}
else {
    [pscustomobject]@{
        ProxySHA256 = [string](Get-CompatArtifact -Name 'msimg32_proxy').sha256
        HookSHA256 = [string](Get-CompatArtifact -Name 'model_hook_tm2425').sha256
    }
}
$files = @(
    [pscustomobject]@{ Name = 'msimg32.dll'; SHA256 = $bundle.ProxySHA256 },
    [pscustomobject]@{ Name = 'wtsapi32.dll'; SHA256 = $bundle.HookSHA256 }
)

foreach ($entry in $files) {
    $path = Join-Path $installer.DirectoryName $entry.Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [pscustomobject]@{ File = $path; Status = 'Absent' }
        continue
    }
    $actual = Get-Sha256 -Path $path
    if ($actual -ne $entry.SHA256) {
        throw "Refusing to remove an unexpected installer-side file: $path ($actual)"
    }
    if ($PSCmdlet.ShouldProcess($path, 'Remove verified installer compatibility file')) {
        Remove-Item -LiteralPath $path
        [pscustomobject]@{ File = $path; Status = 'Removed' }
    }
}
