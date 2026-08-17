[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PcManager', 'Xiaoai')]
    [string]$Product,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InstallerPath,

    [switch]$Launch
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

$installer = Get-Item -LiteralPath $InstallerPath
if ($installer.Extension -ne '.exe') {
    throw "Expected a Windows executable installer: $($installer.FullName)"
}

$signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
    throw "Installer signature is not valid: $($signature.Status)"
}
if (-not $signature.SignerCertificate -or
    $signature.SignerCertificate.Subject -notmatch 'Xiaomi Communications Co\., Ltd\.') {
    throw "Installer is not signed by Xiaomi Communications Co., Ltd.: $($signature.SignerCertificate.Subject)"
}

$artifactNames = @('msimg32_proxy', 'model_hook_tm2425')
$prepared = foreach ($artifactName in $artifactNames) {
    $source = Assert-CompatArtifact -Name $artifactName
    $artifact = Get-CompatArtifact -Name $artifactName
    $fileName = if ($artifactName -eq 'msimg32_proxy') { 'msimg32.dll' } else { 'wtsapi32.dll' }
    $destination = Join-Path $installer.DirectoryName $fileName

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $existingHash = Get-Sha256 -Path $destination
        if ($existingHash -ne [string]$artifact.sha256) {
            throw "Refusing to overwrite an unexpected file beside the installer: $destination ($existingHash)"
        }
        [pscustomobject]@{ File = $destination; Status = 'AlreadyPrepared'; SHA256 = $existingHash }
        continue
    }

    if ($PSCmdlet.ShouldProcess($destination, "Copy verified $artifactName")) {
        Copy-Item -LiteralPath $source -Destination $destination
        $installedHash = Get-Sha256 -Path $destination
        if ($installedHash -ne [string]$artifact.sha256) {
            throw "Post-copy hash verification failed: $destination"
        }
        [pscustomobject]@{ File = $destination; Status = 'Prepared'; SHA256 = $installedHash }
    }
    else {
        [pscustomobject]@{ File = $destination; Status = 'WhatIf'; SHA256 = [string]$artifact.sha256 }
    }
}

$prepared
[pscustomobject]@{
    Installer = $installer.FullName
    Product = $Product
    Signature = $signature.Status.ToString()
    Signer = $signature.SignerCertificate.Subject
}

if ($Launch -and $PSCmdlet.ShouldProcess($installer.FullName, 'Launch verified Xiaomi installer')) {
    Start-Process -FilePath $installer.FullName
}
