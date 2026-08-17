[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Get-Location) 'generated\msimg32-proxy'
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$sourceDirectory = Join-Path $script:SkillRoot 'assets\source\msimg32-proxy'
$proxyDll = Join-Path $resolvedOutput 'msimg32.dll'
$hookCopy = Join-Path $resolvedOutput 'wtsapi32.dll'
$testExe = Join-Path $resolvedOutput 'proxy_smoke_test.exe'

foreach ($required in @('msimg32_proxy.c', 'msimg32_proxy.def', 'proxy_smoke_test.c')) {
    $path = Join-Path $sourceDirectory $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Bundled proxy source is missing: $path"
    }
}
if (-not $Force) {
    foreach ($path in @($proxyDll, $hookCopy, $testExe)) {
        if (Test-Path -LiteralPath $path) {
            throw "Output already exists. Use a new directory or pass -Force: $path"
        }
    }
}

$gccCandidates = @(
    'C:\msys64\ucrt64\bin\gcc.exe',
    'C:\msys64\ucr64\bin\gcc.exe'
)
$gcc = $gccCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $gcc) {
    $gccCommand = Get-Command gcc -ErrorAction SilentlyContinue
    if ($gccCommand) { $gcc = $gccCommand.Source }
}
if (-not $gcc) {
    throw 'An x64 GCC toolchain was not found. Install MSYS2 UCRT64 GCC before building the proxy.'
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
& $gcc -shared -O2 -s -Wall -Wextra -municode -o $proxyDll `
    (Join-Path $sourceDirectory 'msimg32_proxy.c') `
    (Join-Path $sourceDirectory 'msimg32_proxy.def')
if ($LASTEXITCODE -ne 0) { throw "Proxy build failed with exit code $LASTEXITCODE." }

& $gcc -O2 -s -Wall -Wextra -municode -o $testExe `
    (Join-Path $sourceDirectory 'proxy_smoke_test.c')
if ($LASTEXITCODE -ne 0) { throw "Smoke-test build failed with exit code $LASTEXITCODE." }

$hookSource = Assert-CompatArtifact -Name 'model_hook_tm2425'
Copy-Item -LiteralPath $hookSource -Destination $hookCopy -Force
& $testExe $proxyDll
if ($LASTEXITCODE -ne 0) { throw "Proxy smoke test failed with exit code $LASTEXITCODE." }

[pscustomobject]@{
    OutputDirectory = $resolvedOutput
    Compiler = $gcc
    ProxySHA256 = (Get-Sha256 -Path $proxyDll)
    BundledHookSHA256 = (Get-Sha256 -Path $hookCopy)
    SmokeTest = 'Passed'
    Note = 'A rebuilt PE can have a different SHA-256 from the published proxy because linker metadata is not byte-for-byte reproducible.'
}
