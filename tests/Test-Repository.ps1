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
$generatedTestDirectory = Join-Path $repoRoot 'build\repository-test-TM2430'
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
