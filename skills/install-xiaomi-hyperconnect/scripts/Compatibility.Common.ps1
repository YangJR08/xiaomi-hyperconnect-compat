Set-StrictMode -Version Latest

$script:SkillRoot = Split-Path -Parent $PSScriptRoot
$script:ManifestPath = Join-Path $script:SkillRoot 'assets\compatibility-manifest.json'
if (-not (Test-Path -LiteralPath $script:ManifestPath -PathType Leaf)) {
    throw "Compatibility manifest is missing: $script:ManifestPath"
}
$script:CompatManifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json

function Get-CompatArtifact {
    param([Parameter(Mandatory)][string]$Name)

    $property = $script:CompatManifest.artifacts.PSObject.Properties[$Name]
    if (-not $property) {
        throw "Unknown compatibility artifact: $Name"
    }
    $property.Value
}

function Get-CompatArtifactPath {
    param([Parameter(Mandatory)][string]$Name)

    $artifact = Get-CompatArtifact -Name $Name
    Join-Path $script:SkillRoot ([string]$artifact.relative_path)
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-CompatArtifact {
    param([Parameter(Mandatory)][string]$Name)

    $artifact = Get-CompatArtifact -Name $Name
    $path = Get-CompatArtifactPath -Name $Name
    $item = Get-Item -LiteralPath $path
    $actualHash = Get-Sha256 -Path $path
    if ($actualHash -ne [string]$artifact.sha256) {
        throw "Artifact hash mismatch for $Name. Expected $($artifact.sha256); got $actualHash"
    }
    if ($item.Length -ne [int64]$artifact.size) {
        throw "Artifact size mismatch for $Name. Expected $($artifact.size); got $($item.Length)"
    }
    $path
}

function Get-CompatProduct {
    param([Parameter(Mandatory)][ValidateSet('PcManager', 'Xiaoai')][string]$Product)

    $property = $script:CompatManifest.products.PSObject.Properties[$Product]
    if (-not $property) {
        throw "Unknown product: $Product"
    }
    $property.Value
}

function Resolve-CompatInstallRoot {
    param(
        [Parameter(Mandatory)][ValidateSet('PcManager', 'Xiaoai')][string]$Product,
        [string]$InstallRoot
    )

    if ($InstallRoot) {
        $resolved = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw "Install directory does not exist: $resolved"
        }
        return $resolved
    }

    $productInfo = Get-CompatProduct -Product $Product
    $baseDirectory = [string]$productInfo.base_directory
    if (-not (Test-Path -LiteralPath $baseDirectory -PathType Container)) {
        throw "Product base directory does not exist: $baseDirectory"
    }

    $candidates = foreach ($directory in Get-ChildItem -LiteralPath $baseDirectory -Directory) {
        $parsed = $null
        if ([Version]::TryParse($directory.Name, [ref]$parsed)) {
            [pscustomobject]@{ Path = $directory.FullName; Version = $parsed }
        }
    }
    $selected = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $selected) {
        throw "No version directory was found under: $baseDirectory"
    }
    $selected.Path
}

function Assert-CompatProductLayout {
    param(
        [Parameter(Mandatory)][ValidateSet('PcManager', 'Xiaoai')][string]$Product,
        [Parameter(Mandatory)][string]$InstallRoot
    )

    $productInfo = Get-CompatProduct -Product $Product
    foreach ($relativePath in $productInfo.required_executables) {
        $path = Join-Path $InstallRoot ([string]$relativePath)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "The selected directory is not a supported $Product installation; missing: $path"
        }
    }
}

function Test-CompatAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CompatStateDirectory {
    param(
        [Parameter(Mandatory)][ValidateSet('PcManager', 'Xiaoai')][string]$Product,
        [Parameter(Mandatory)][string]$Version
    )

    Join-Path $env:ProgramData "XiaomiHyperConnectCompat\$Product\$Version"
}

function Get-CompatRuntimeTargets {
    param(
        [Parameter(Mandatory)][ValidateSet('PcManager', 'Xiaoai')][string]$Product,
        [Parameter(Mandatory)][string]$InstallRoot,
        [switch]$IncludeLegacyInfoCheckerPatch
    )

    if ($Product -eq 'PcManager') {
        return @(
            [pscustomobject]@{ Artifact = 'msimg32_proxy'; Destination = (Join-Path $InstallRoot 'msimg32.dll') },
            [pscustomobject]@{ Artifact = 'model_hook_tm2425'; Destination = (Join-Path $InstallRoot 'wtsapi32.dll') }
        )
    }

    $targets = @(
        [pscustomobject]@{ Artifact = 'model_hook_tm2425'; Destination = (Join-Path $InstallRoot 'wtsapi32.dll') },
        [pscustomobject]@{ Artifact = 'model_hook_tm2425'; Destination = (Join-Path $InstallRoot 'app\wtsapi32.dll') }
    )
    if ($IncludeLegacyInfoCheckerPatch) {
        $targets += [pscustomobject]@{
            Artifact = 'xiaoai_host_3_5_0_220'
            Destination = (Join-Path $InstallRoot 'XiaoaiHost.dll')
        }
    }
    $targets
}
