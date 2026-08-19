[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PcManager', 'Xiaoai')]
    [string]$Product,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InstallerPath,

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$BundleDirectory,

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

$bundle = if ($BundleDirectory) {
    Get-CompatGeneratedBundle -Directory $BundleDirectory
}
else {
    $proxySource = Assert-CompatArtifact -Name 'msimg32_proxy'
    $hookSource = Assert-CompatArtifact -Name 'model_hook_tm2425'
    $proxyArtifact = Get-CompatArtifact -Name 'msimg32_proxy'
    $hookArtifact = Get-CompatArtifact -Name 'model_hook_tm2425'
    [pscustomobject]@{
        Directory = $null
        Product = $null
        ModelCode = 'TM2425'
        ProxyPath = $proxySource
        ProxySHA256 = [string]$proxyArtifact.sha256
        HookPath = $hookSource
        HookSHA256 = [string]$hookArtifact.sha256
        ChecksumPath = $null
    }
}
if ($bundle.Product -and $bundle.Product -ne $Product) {
    throw "Compatibility bundle is for $($bundle.Product), not $Product`: $($bundle.Directory)"
}

$bundleFiles = @(
    [pscustomobject]@{ Name = 'msimg32.dll'; Source = $bundle.ProxyPath; SHA256 = $bundle.ProxySHA256 },
    [pscustomobject]@{ Name = 'wtsapi32.dll'; Source = $bundle.HookPath; SHA256 = $bundle.HookSHA256 }
)
$prepared = foreach ($bundleFile in $bundleFiles) {
    $destination = Join-Path $installer.DirectoryName $bundleFile.Name

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $existingHash = Get-Sha256 -Path $destination
        if ($existingHash -ne $bundleFile.SHA256) {
            throw "Refusing to overwrite an unexpected file beside the installer: $destination ($existingHash)"
        }
        [pscustomobject]@{ File = $destination; Status = 'AlreadyPrepared'; SHA256 = $existingHash }
        continue
    }

    if ($PSCmdlet.ShouldProcess($destination, "Copy verified $($bundleFile.Name) for TIMI/$($bundle.ModelCode)")) {
        Copy-Item -LiteralPath $bundleFile.Source -Destination $destination
        $installedHash = Get-Sha256 -Path $destination
        if ($installedHash -ne $bundleFile.SHA256) {
            throw "Post-copy hash verification failed: $destination"
        }
        [pscustomobject]@{ File = $destination; Status = 'Prepared'; SHA256 = $installedHash }
    }
    else {
        [pscustomobject]@{ File = $destination; Status = 'WhatIf'; SHA256 = $bundleFile.SHA256 }
    }
}

$prepared
[pscustomobject]@{
    Installer = $installer.FullName
    Product = $Product
    Signature = $signature.Status.ToString()
    Signer = $signature.SignerCertificate.Subject
    ModelCode = $bundle.ModelCode
    BundleProduct = $bundle.Product
    BundleDirectory = $bundle.Directory
}

if ($Launch -and $PSCmdlet.ShouldProcess($installer.FullName, 'Launch verified Xiaomi installer')) {
    Start-Process -FilePath $installer.FullName
}
