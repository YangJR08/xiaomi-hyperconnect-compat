[CmdletBinding()]
param([switch]$Online)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'compatibility-manifest.json'
$skillManifestPath = Join-Path $repoRoot 'skills\install-xiaomi-hyperconnect\assets\compatibility-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$skillManifest = Get-Content -LiteralPath $skillManifestPath -Raw | ConvertFrom-Json

$manifestCanonical = $manifest | ConvertTo-Json -Depth 20 -Compress
$skillManifestCanonical = $skillManifest | ConvertTo-Json -Depth 20 -Compress
if ($manifestCanonical -ne $skillManifestCanonical) {
    throw 'Root and Skill compatibility manifests differ.'
}

function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not an MZ file: $Path" }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Not a PE file: $Path" }
        $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

$skillRoot = Join-Path $repoRoot 'skills\install-xiaomi-hyperconnect'
$agentsPath = Join-Path $repoRoot 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    throw 'Missing root AGENTS.md for AI agent discovery.'
}
if ((Get-Content -LiteralPath $agentsPath -Raw) -notmatch 'skills/install-xiaomi-hyperconnect/SKILL\.md') {
    throw 'AGENTS.md does not route agents to the Xiaomi compatibility Skill.'
}

$proxySourceFiles = @('msimg32_proxy.c', 'msimg32_proxy.def', 'proxy_smoke_test.c')
foreach ($sourceName in $proxySourceFiles) {
    $rootSource = if ($sourceName -eq 'proxy_smoke_test.c') {
        Join-Path $repoRoot "tests\$sourceName"
    }
    else {
        Join-Path $repoRoot "src\msimg32-proxy\$sourceName"
    }
    $skillSource = Join-Path $skillRoot "assets\source\msimg32-proxy\$sourceName"
    if (-not (Test-Path -LiteralPath $skillSource -PathType Leaf)) {
        throw "Missing self-contained Skill source: $skillSource"
    }
    if ((Get-FileHash -LiteralPath $rootSource -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $skillSource -Algorithm SHA256).Hash) {
        throw "Root and Skill proxy sources differ: $sourceName"
    }
}
$msimgProxySourceText = Get-Content -LiteralPath (Join-Path $repoRoot 'src\msimg32-proxy\msimg32_proxy.c') -Raw
if ($msimgProxySourceText -notmatch 'Uninstall\.exe' -or
    $msimgProxySourceText -notmatch 'uninstaller bypass active') {
    throw 'msimg32 proxy source is missing its PC Manager uninstaller bypass.'
}

$wtsProxySourceFiles = @('wtsapi32_proxy.c', 'wtsapi32_proxy.def', 'wtsapi32_proxy_smoke_test.c')
foreach ($sourceName in $wtsProxySourceFiles) {
    $rootSource = if ($sourceName -eq 'wtsapi32_proxy_smoke_test.c') {
        Join-Path $repoRoot "tests\$sourceName"
    }
    else {
        Join-Path $repoRoot "src\wtsapi32-proxy\$sourceName"
    }
    $skillSource = Join-Path $skillRoot "assets\source\wtsapi32-proxy\$sourceName"
    if (-not (Test-Path -LiteralPath $skillSource -PathType Leaf)) {
        throw "Missing self-contained Skill runtime-proxy source: $skillSource"
    }
    if ((Get-FileHash -LiteralPath $rootSource -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $skillSource -Algorithm SHA256).Hash) {
        throw "Root and Skill runtime-proxy sources differ: $sourceName"
    }
}
$wtsProxySourceText = Get-Content -LiteralPath (Join-Path $repoRoot 'src\wtsapi32-proxy\wtsapi32_proxy.c') -Raw
if ($wtsProxySourceText -notmatch 'Uninstall\.exe' -or
    $wtsProxySourceText -notmatch 'XiaomiHyperConnectModelHook\.dll') {
    throw 'Runtime proxy source is missing the uninstaller bypass or renamed model-hook routing.'
}

$artifactResults = foreach ($entry in $manifest.artifacts.PSObject.Properties) {
    $artifact = $entry.Value
    $path = Join-Path $skillRoot ([string]$artifact.relative_path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing artifact: $path"
    }
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ne [string]$artifact.sha256) { throw "Hash mismatch: $path" }
    if ($item.Length -ne [int64]$artifact.size) { throw "Size mismatch: $path" }
    if ((Get-PeMachine -Path $path) -ne 0x8664) { throw "Artifact is not x64: $path" }
    $signature = (Get-AuthenticodeSignature -LiteralPath $path).Status.ToString()
    if ($signature -ne [string]$artifact.signature_status) {
        throw "Unexpected signature state for $path. Expected $($artifact.signature_status); got $signature"
    }
    [pscustomobject]@{ Artifact = $entry.Name; SHA256 = $hash; Size = $item.Length; Signature = $signature }
}

$forbiddenFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
    Where-Object {
        $_.Extension -in @('.exe', '.msi', '.reg', '.log') -and
        $_.FullName -notmatch '[\\/]build[\\/]'
    }
if ($forbiddenFiles) {
    throw "Forbidden publishable files found: $($forbiddenFiles.FullName -join ', ')"
}

$secretPatterns = @(
    ('client' + 'Secret'),
    ('refresh' + 'Token'),
    ('BEGIN ' + 'PRIVATE KEY'),
    ('ghp_' + '[A-Za-z0-9]')
)
$textFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
    Where-Object Extension -in @('.md', '.ps1', '.py', '.c', '.def', '.json', '.yaml', '.yml')
foreach ($pattern in $secretPatterns) {
    $matches = $textFiles | Select-String -Pattern $pattern -CaseSensitive
    if ($matches) { throw "Potential secret pattern '$pattern' found in repository text." }
}

$scriptFiles = Get-ChildItem -LiteralPath (Join-Path $skillRoot 'scripts') -Filter '*.ps1' -File
foreach ($scriptFile in $scriptFiles) {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "PowerShell parse error in $($scriptFile.FullName): $($errors.Message -join '; ')" }
}

$generationScript = Join-Path $skillRoot 'scripts\New-ModelCompatibilityBundle.ps1'
$productGenerationScript = Join-Path $skillRoot 'scripts\New-ProductInstallerBundles.ps1'
$commonScript = Join-Path $skillRoot 'scripts\Compatibility.Common.ps1'
. $commonScript
$runtimeTargetRoot = 'C:\compat-runtime-target-test\1.0.0.0'
$pcRuntimeTargets = @(Get-CompatRuntimeTargets -Product PcManager -InstallRoot $runtimeTargetRoot)
$xiaoaiRuntimeTargets = @(Get-CompatRuntimeTargets -Product Xiaoai -InstallRoot $runtimeTargetRoot)
if (($pcRuntimeTargets.Artifact -join ',') -ne
        'msimg32_proxy,wtsapi32_runtime_proxy,model_hook_tm2425' -or
    ($xiaoaiRuntimeTargets.Artifact -join ',') -ne
        'wtsapi32_runtime_proxy,model_hook_tm2425,wtsapi32_runtime_proxy,model_hook_tm2425' -or
    @($pcRuntimeTargets.Destination + $xiaoaiRuntimeTargets.Destination |
        Where-Object { $_ -like '*model_hook_tm2425*' }).Count -ne 0 -or
    @($pcRuntimeTargets.Destination + $xiaoaiRuntimeTargets.Destination |
        Where-Object { $_ -like '*XiaomiHyperConnectModelHook.dll' }).Count -ne 3) {
    throw 'Runtime proxy/model-hook target routing is incorrect.'
}
$repositoryTestRoot = Join-Path ([IO.Path]::GetTempPath()) "xiaomi-compat-repository-test-$([Guid]::NewGuid().ToString('N'))"
try {
$generatedTestDirectory = Join-Path $repositoryTestRoot 'generic-TM2430'
$generationResult = & $generationScript -ModelCode TM2430 -OutputDirectory $generatedTestDirectory
$generatedProxy = Join-Path $generatedTestDirectory 'msimg32.dll'
$generatedHook = Join-Path $generatedTestDirectory 'wtsapi32.dll'
$generatedChecksums = Join-Path $generatedTestDirectory 'SHA256SUMS.txt'
if ($generationResult.Status -ne 'Generated') { throw 'Custom model generation did not complete.' }
if ((Get-FileHash -LiteralPath $generatedProxy -Algorithm SHA256).Hash -ne
    [string]$manifest.artifacts.msimg32_proxy.sha256) {
    throw 'Generated bundle proxy differs from the verified proxy.'
}
$generatedHookBytes = [IO.File]::ReadAllBytes($generatedHook)
$generatedHookText = [Text.Encoding]::Unicode.GetString($generatedHookBytes)
if ([regex]::Matches($generatedHookText, 'TM2430').Count -ne 1 -or
    [regex]::Matches($generatedHookText, 'TM2425').Count -ne 0) {
    throw 'Custom model generation did not perform the expected single token replacement.'
}
if (-not (Test-Path -LiteralPath $generatedChecksums -PathType Leaf)) {
    throw 'Custom model generation did not produce SHA256SUMS.txt.'
}

$legacyRuntimeRoot = Join-Path $repositoryTestRoot 'legacy-runtime\9.9.9.9'
$legacyRuntimeApp = Join-Path $legacyRuntimeRoot 'app'
New-Item -ItemType Directory -Path $legacyRuntimeApp -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $legacyRuntimeRoot 'XiaoaiHost.exe'), [byte[]]@(0))
[IO.File]::WriteAllBytes((Join-Path $legacyRuntimeApp 'XiaoaiAgent.exe'), [byte[]]@(0))
$verifiedModelHook = Assert-CompatArtifact -Name 'model_hook_tm2425'
Copy-Item -LiteralPath $verifiedModelHook -Destination (Join-Path $legacyRuntimeRoot 'wtsapi32.dll')
Copy-Item -LiteralPath $verifiedModelHook -Destination (Join-Path $legacyRuntimeApp 'wtsapi32.dll')
$runtimeInstallScript = Join-Path $skillRoot 'scripts\Install-RuntimeCompatibility.ps1'
$runtimeRemoveScript = Join-Path $skillRoot 'scripts\Remove-RuntimeCompatibility.ps1'
$runtimeTestScript = Join-Path $skillRoot 'scripts\Test-RuntimeCompatibility.ps1'
$migrationPlan = @(& $runtimeInstallScript -Product Xiaoai -InstallRoot $legacyRuntimeRoot -WhatIf) |
    Where-Object { $_.PSObject.Properties['Artifact'] }
if ($migrationPlan.Count -ne 4 -or
    @($migrationPlan | Where-Object { -not $_.InstallRequired }).Count -ne 0 -or
    @($migrationPlan | Where-Object {
        $_.Artifact -eq 'wtsapi32_runtime_proxy' -and $_.PriorState -ne 'KnownLegacyFile'
    }).Count -ne 0) {
    throw 'Legacy runtime layout did not produce the expected proxy migration plan.'
}
$null = & $runtimeRemoveScript -Product Xiaoai -InstallRoot $legacyRuntimeRoot -WhatIf

$legacyPcRuntimeRoot = Join-Path $repositoryTestRoot 'legacy-pc-runtime\9.9.9.9'
New-Item -ItemType Directory -Path $legacyPcRuntimeRoot -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $legacyPcRuntimeRoot 'XiaomiPcManager.exe'), [byte[]]@(0))
$legacyMsimgHash = [string](Get-CompatArtifact -Name 'msimg32_proxy').known_replaceable_sha256[0]
if ($legacyMsimgHash -ne '1F51F24406D8689225B1A38166C5A4F54B5542C1465D1BE87B0F39E6AAD0937B') {
    throw 'The previous msimg32 proxy is missing from the known-replaceable hash list.'
}
Copy-Item -LiteralPath (Assert-CompatArtifact -Name 'msimg32_proxy') `
    -Destination (Join-Path $legacyPcRuntimeRoot 'msimg32.dll')
Copy-Item -LiteralPath $verifiedModelHook -Destination (Join-Path $legacyPcRuntimeRoot 'wtsapi32.dll')
$pcMigrationPlan = @(& $runtimeInstallScript -Product PcManager -InstallRoot $legacyPcRuntimeRoot -WhatIf) |
    Where-Object { $_.PSObject.Properties['Artifact'] }
if ($pcMigrationPlan.Count -ne 3 -or
    @($pcMigrationPlan | Where-Object {
        $_.Artifact -eq 'msimg32_proxy' -and $_.InstallRequired
    }).Count -ne 0 -or
    @($pcMigrationPlan | Where-Object {
        $_.Artifact -eq 'wtsapi32_runtime_proxy' -and
        $_.PriorState -ne 'KnownLegacyFile'
    }).Count -ne 0) {
    throw 'Legacy PC Manager runtime layout did not produce the expected dual-proxy migration plan.'
}

$newRuntimeRoot = Join-Path $repositoryTestRoot 'new-runtime\9.9.9.9'
$newRuntimeApp = Join-Path $newRuntimeRoot 'app'
New-Item -ItemType Directory -Path $newRuntimeApp -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $newRuntimeRoot 'XiaoaiHost.exe'), [byte[]]@(0))
[IO.File]::WriteAllBytes((Join-Path $newRuntimeApp 'XiaoaiAgent.exe'), [byte[]]@(0))
$verifiedRuntimeProxy = Assert-CompatArtifact -Name 'wtsapi32_runtime_proxy'
foreach ($directory in @($newRuntimeRoot, $newRuntimeApp)) {
    Copy-Item -LiteralPath $verifiedRuntimeProxy -Destination (Join-Path $directory 'wtsapi32.dll')
    Copy-Item -LiteralPath $verifiedModelHook -Destination (Join-Path $directory 'XiaomiHyperConnectModelHook.dll')
}
$runtimeValidation = & $runtimeTestScript -Product Xiaoai -InstallRoot $newRuntimeRoot -AsJson |
    ConvertFrom-Json
if (-not $runtimeValidation.Compatible -or
    @($runtimeValidation.Files).Count -ne 4 -or
    @($runtimeValidation.Files | Where-Object { -not $_.Matches }).Count -ne 0) {
    throw 'New runtime proxy/model-hook layout validation failed.'
}

$validatedBundle = Get-CompatGeneratedBundle -Directory $generatedTestDirectory
if ($validatedBundle.ModelCode -ne 'TM2430' -or
    $validatedBundle.ProxySHA256 -ne [string]$manifest.artifacts.msimg32_proxy.sha256 -or
    $validatedBundle.HookSHA256 -ne (Get-FileHash -LiteralPath $generatedHook -Algorithm SHA256).Hash) {
    throw 'Generated bundle validation returned unexpected metadata.'
}

function Assert-BundleRejected {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$ExpectedMessage
    )

    try {
        $null = Get-CompatGeneratedBundle -Directory $Directory
    }
    catch {
        if ($_.Exception.Message -notmatch $ExpectedMessage) {
            throw "Bundle was rejected for an unexpected reason: $($_.Exception.Message)"
        }
        return
    }
    throw "Invalid compatibility bundle was accepted: $Directory"
}

$bundleTestRoot = Join-Path ([IO.Path]::GetTempPath()) "xiaomi-compat-bundle-test-$([Guid]::NewGuid().ToString('N'))"
try {
    $proxyTamperDirectory = Join-Path $bundleTestRoot 'proxy-tamper'
    $hookTamperDirectory = Join-Path $bundleTestRoot 'hook-tamper'
    $checksumTamperDirectory = Join-Path $bundleTestRoot 'checksum-tamper'
    foreach ($directory in @($proxyTamperDirectory, $hookTamperDirectory, $checksumTamperDirectory)) {
        Copy-Item -LiteralPath $generatedTestDirectory -Destination $directory -Recurse
    }

    $tamperedProxyPath = Join-Path $proxyTamperDirectory 'msimg32.dll'
    $tamperedProxyBytes = [IO.File]::ReadAllBytes($tamperedProxyPath)
    $tamperedProxyBytes[0] = $tamperedProxyBytes[0] -bxor 0x01
    [IO.File]::WriteAllBytes($tamperedProxyPath, $tamperedProxyBytes)
    Assert-BundleRejected -Directory $proxyTamperDirectory -ExpectedMessage 'proxy hash mismatch'

    $tamperedHookPath = Join-Path $hookTamperDirectory 'wtsapi32.dll'
    $tamperedHookBytes = [IO.File]::ReadAllBytes($tamperedHookPath)
    $tamperedHookBytes[0] = $tamperedHookBytes[0] -bxor 0x01
    [IO.File]::WriteAllBytes($tamperedHookPath, $tamperedHookBytes)
    Assert-BundleRejected -Directory $hookTamperDirectory -ExpectedMessage 'differs from the verified base outside the model token'

    $tamperedChecksumPath = Join-Path $checksumTamperDirectory 'SHA256SUMS.txt'
    @(
        "$($validatedBundle.ProxySHA256)  msimg32.dll",
        "$($validatedBundle.ProxySHA256)  wtsapi32.dll"
    ) | Set-Content -LiteralPath $tamperedChecksumPath -Encoding utf8NoBOM
    Assert-BundleRejected -Directory $checksumTamperDirectory -ExpectedMessage 'does not match the bundle files'
}
finally {
    if (Test-Path -LiteralPath $bundleTestRoot -PathType Container) {
        Remove-Item -LiteralPath $bundleTestRoot -Recurse -Force
    }
}

$productTestRoot = Join-Path $repositoryTestRoot 'products'
$productGenerationResults = @(& $productGenerationScript -OutputRoot $productTestRoot)
$expectedProductBundles = @(
    [pscustomobject]@{ Product = 'PcManager'; ModelCode = 'TM2425'; Directory = 'XiaomiPCManager-TM2425' },
    [pscustomobject]@{ Product = 'Xiaoai'; ModelCode = 'TM2430'; Directory = 'SuperXiaoAI-TM2430' }
)
if ($productGenerationResults.Count -ne $expectedProductBundles.Count) {
    throw 'Product bundle generation returned an unexpected number of results.'
}
foreach ($expectedBundle in $expectedProductBundles) {
    $productBundleDirectory = Join-Path $productTestRoot $expectedBundle.Directory
    $productBundle = Get-CompatGeneratedBundle -Directory $productBundleDirectory
    if ($productBundle.Product -ne $expectedBundle.Product -or
        $productBundle.ModelCode -ne $expectedBundle.ModelCode -or
        -not (Test-Path -LiteralPath $productBundle.BundleManifestPath -PathType Leaf)) {
        throw "Product bundle metadata mismatch: $productBundleDirectory"
    }
}

$metadataTamperRoot = Join-Path ([IO.Path]::GetTempPath()) "xiaomi-compat-metadata-test-$([Guid]::NewGuid().ToString('N'))"
try {
    Copy-Item -LiteralPath (Join-Path $productTestRoot 'XiaomiPCManager-TM2425') `
        -Destination $metadataTamperRoot -Recurse
    $metadataPath = Join-Path $metadataTamperRoot 'BUNDLE.json'
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $metadata.product = 'Xiaoai'
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding utf8NoBOM
    Assert-BundleRejected -Directory $metadataTamperRoot -ExpectedMessage 'does not match BUNDLE.json'
}
finally {
    if (Test-Path -LiteralPath $metadataTamperRoot -PathType Container) {
        Remove-Item -LiteralPath $metadataTamperRoot -Recurse -Force
    }
}
}
finally {
    if (Test-Path -LiteralPath $repositoryTestRoot -PathType Container) {
        Remove-Item -LiteralPath $repositoryTestRoot -Recurse -Force
    }
}

if ($Online) {
    $response = Invoke-WebRequest -Uri ([string]$manifest.official_download_page) -MaximumRedirection 5
    if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'Xiaomi HyperConnect') {
        throw 'Official Xiaomi HyperConnect landing page validation failed.'
    }
}

$artifactResults
[pscustomobject]@{
    Status = 'Passed'
    Artifacts = $artifactResults.Count
    Scripts = $scriptFiles.Count
    GeneratedModel = $generationResult.ModelCode
    OnlineCheck = [bool]$Online
}
