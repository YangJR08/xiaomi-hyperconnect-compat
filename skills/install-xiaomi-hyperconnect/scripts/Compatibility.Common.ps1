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

function Get-CompatKnownReplaceableHashes {
    param([Parameter(Mandatory)]$Artifact)

    $property = $Artifact.PSObject.Properties['known_replaceable_sha256']
    if (-not $property) { return @() }
    @($property.Value | ForEach-Object { [string]$_ })
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

function Find-CompatByteSequence {
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [Parameter(Mandatory)][byte[]]$Needle
    )

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

function Test-CompatByteArrayEqual {
    param(
        [Parameter(Mandatory)][byte[]]$Left,
        [Parameter(Mandatory)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    $true
}

function Get-CompatGeneratedBundle {
    param([Parameter(Mandatory)][string]$Directory)

    $resolvedDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $resolvedDirectory -PathType Container)) {
        throw "Compatibility bundle directory does not exist: $resolvedDirectory"
    }

    $proxyPath = Join-Path $resolvedDirectory 'msimg32.dll'
    $hookPath = Join-Path $resolvedDirectory 'wtsapi32.dll'
    $checksumPath = Join-Path $resolvedDirectory 'SHA256SUMS.txt'
    foreach ($requiredPath in @($proxyPath, $hookPath, $checksumPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Compatibility bundle is missing a required file: $requiredPath"
        }
    }

    $proxyArtifact = Get-CompatArtifact -Name 'msimg32_proxy'
    $proxyHash = Get-Sha256 -Path $proxyPath
    if ($proxyHash -ne [string]$proxyArtifact.sha256) {
        throw "Compatibility bundle proxy hash mismatch: $proxyPath ($proxyHash)"
    }
    if ((Get-Item -LiteralPath $proxyPath).Length -ne [int64]$proxyArtifact.size) {
        throw "Compatibility bundle proxy size mismatch: $proxyPath"
    }

    $baseHookPath = Assert-CompatArtifact -Name 'model_hook_tm2425'
    $baseHookBytes = [IO.File]::ReadAllBytes($baseHookPath)
    $hookBytes = [IO.File]::ReadAllBytes($hookPath)
    if ($hookBytes.Length -ne $baseHookBytes.Length) {
        throw "Compatibility bundle hook size mismatch: $hookPath"
    }

    $baseToken = [Text.Encoding]::Unicode.GetBytes('TM2425')
    $baseTokenHits = @(Find-CompatByteSequence -Data $baseHookBytes -Needle $baseToken)
    if ($baseTokenHits.Count -ne 1) {
        throw "Verified base hook must contain exactly one TM2425 token; found $($baseTokenHits.Count)."
    }

    $tokenOffset = $baseTokenHits[0]
    $modelCode = [Text.Encoding]::Unicode.GetString($hookBytes, $tokenOffset, $baseToken.Length)
    if ($modelCode -notmatch '^TM\d{4}$') {
        throw "Compatibility bundle contains an invalid model token at the verified offset: $modelCode"
    }

    $expectedHookBytes = [byte[]]::new($baseHookBytes.Length)
    [Array]::Copy($baseHookBytes, $expectedHookBytes, $baseHookBytes.Length)
    $modelToken = [Text.Encoding]::Unicode.GetBytes($modelCode)
    [Array]::Copy($modelToken, 0, $expectedHookBytes, $tokenOffset, $modelToken.Length)
    if (-not (Test-CompatByteArrayEqual -Left $hookBytes -Right $expectedHookBytes)) {
        throw "Compatibility bundle hook differs from the verified base outside the model token: $hookPath"
    }

    $hookHash = Get-Sha256 -Path $hookPath
    $bundleManifestPath = Join-Path $resolvedDirectory 'BUNDLE.json'
    $bundleProduct = $null
    if (Test-Path -LiteralPath $bundleManifestPath -PathType Leaf) {
        try {
            $bundleManifest = Get-Content -LiteralPath $bundleManifestPath -Raw | ConvertFrom-Json
        }
        catch {
            throw "Compatibility bundle metadata is not valid JSON: $bundleManifestPath"
        }
        if ($bundleManifest.schema_version -ne 1 -or
            [string]$bundleManifest.purpose -ne 'installer' -or
            [string]$bundleManifest.product -notin @('PcManager', 'Xiaoai') -or
            [string]$bundleManifest.model_code -ne $modelCode) {
            throw "Compatibility bundle metadata does not match its validated model: $bundleManifestPath"
        }
        $bundleProduct = [string]$bundleManifest.product
    }

    $checksumEntries = @{}
    foreach ($line in Get-Content -LiteralPath $checksumPath) {
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+([^\\/]+)$') {
            throw "Invalid SHA256SUMS entry in compatibility bundle: $line"
        }
        $fileName = $Matches[2].ToLowerInvariant()
        if ($checksumEntries.ContainsKey($fileName)) {
            throw "Duplicate SHA256SUMS entry in compatibility bundle: $fileName"
        }
        $checksumEntries[$fileName] = $Matches[1].ToUpperInvariant()
    }
    $expectedChecksumNames = @('msimg32.dll', 'wtsapi32.dll')
    if ($bundleProduct) { $expectedChecksumNames += 'bundle.json' }
    if ($checksumEntries.Count -ne $expectedChecksumNames.Count -or
        @($expectedChecksumNames | Where-Object { -not $checksumEntries.ContainsKey($_) }).Count -ne 0) {
        throw "Compatibility bundle SHA256SUMS.txt must contain exactly: $($expectedChecksumNames -join ', ')."
    }
    if ($checksumEntries['msimg32.dll'] -ne $proxyHash -or
        $checksumEntries['wtsapi32.dll'] -ne $hookHash) {
        throw 'Compatibility bundle SHA256SUMS.txt does not match the bundle files.'
    }
    if ($bundleProduct -and
        $checksumEntries['bundle.json'] -ne (Get-Sha256 -Path $bundleManifestPath)) {
        throw 'Compatibility bundle SHA256SUMS.txt does not match BUNDLE.json.'
    }

    [pscustomobject]@{
        Directory = $resolvedDirectory
        Product = $bundleProduct
        ModelCode = $modelCode
        ProxyPath = $proxyPath
        ProxySHA256 = $proxyHash
        HookPath = $hookPath
        HookSHA256 = $hookHash
        ChecksumPath = $checksumPath
        BundleManifestPath = if ($bundleProduct) { $bundleManifestPath } else { $null }
    }
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

function Stop-CompatProcessesInRoot {
    param([Parameter(Mandatory)][string]$InstallRoot)

    Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and
        $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($InstallRoot, [StringComparison]::OrdinalIgnoreCase)
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Suspend-CompatRuntime {
    param([Parameter(Mandatory)][string]$InstallRoot)

    $services = @(Get-CimInstance Win32_Service | Where-Object {
        $_.PathName -and
        $_.PathName.IndexOf($InstallRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            State = [string]$_.State
            StartMode = [string]$_.StartMode
            DelayedAutoStart = if ($_.PSObject.Properties['DelayedAutoStart']) {
                [bool]$_.DelayedAutoStart
            }
            else {
                $false
            }
        }
    })

    try {
        foreach ($service in $services) {
            & sc.exe config $service.Name start= disabled | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not temporarily disable service: $($service.Name)"
            }
            & sc.exe stop $service.Name | Out-Null
        }
        foreach ($attempt in 1..3) {
            Start-Sleep -Milliseconds 500
            Stop-CompatProcessesInRoot -InstallRoot $InstallRoot
        }
    }
    catch {
        Resume-CompatRuntime -Services $services
        throw
    }
    $services
}

function Resume-CompatRuntime {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Services)

    $restoreFailures = @()
    foreach ($service in $Services) {
        $startValue = if ($service.StartMode -eq 'Auto' -and $service.DelayedAutoStart) {
            'delayed-auto'
        }
        elseif ($service.StartMode -eq 'Auto') {
            'auto'
        }
        elseif ($service.StartMode -eq 'Manual') {
            'demand'
        }
        else {
            'disabled'
        }
        & sc.exe config $service.Name start= $startValue | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $restoreFailures += [string]$service.Name
            Write-Warning "Could not restore service startup mode: $($service.Name)"
            continue
        }
        if ($service.State -eq 'Running') {
            & sc.exe start $service.Name | Out-Null
        }
    }
    if ($restoreFailures.Count -gt 0) {
        throw "Could not restore service startup mode for: $($restoreFailures -join ', ')"
    }
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
            [pscustomobject]@{ Artifact = 'wtsapi32_runtime_proxy'; Destination = (Join-Path $InstallRoot 'wtsapi32.dll') },
            [pscustomobject]@{ Artifact = 'model_hook_tm2425'; Destination = (Join-Path $InstallRoot 'XiaomiHyperConnectModelHook.dll') }
        )
    }

    $targets = @(
        [pscustomobject]@{ Artifact = 'wtsapi32_runtime_proxy'; Destination = (Join-Path $InstallRoot 'wtsapi32.dll') },
        [pscustomobject]@{ Artifact = 'model_hook_tm2425'; Destination = (Join-Path $InstallRoot 'XiaomiHyperConnectModelHook.dll') },
        [pscustomobject]@{ Artifact = 'wtsapi32_runtime_proxy'; Destination = (Join-Path $InstallRoot 'app\wtsapi32.dll') },
        [pscustomobject]@{ Artifact = 'model_hook_tm2425'; Destination = (Join-Path $InstallRoot 'app\XiaomiHyperConnectModelHook.dll') }
    )
    if ($IncludeLegacyInfoCheckerPatch) {
        $targets += [pscustomobject]@{
            Artifact = 'xiaoai_host_3_5_0_220'
            Destination = (Join-Path $InstallRoot 'XiaoaiHost.dll')
        }
    }
    $targets
}
