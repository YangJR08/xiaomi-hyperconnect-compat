[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Compatibility.Common.ps1')

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Get-Location) 'generated\wtsapi32-runtime-proxy'
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$sourceDirectory = Join-Path $script:SkillRoot 'assets\source\wtsapi32-proxy'
$proxyDll = Join-Path $resolvedOutput 'wtsapi32.dll'
$modelHook = Join-Path $resolvedOutput 'XiaomiHyperConnectModelHook.dll'
$testExe = Join-Path $resolvedOutput 'wtsapi32_proxy_smoke_test.exe'

foreach ($required in @('wtsapi32_proxy.c', 'wtsapi32_proxy.def', 'wtsapi32_proxy_smoke_test.c')) {
    $path = Join-Path $sourceDirectory $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Bundled runtime-proxy source is missing: $path"
    }
}
if (-not $Force) {
    foreach ($path in @($proxyDll, $modelHook, $testExe)) {
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

$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "xiaomi-wtsapi32-build-$([Guid]::NewGuid().ToString('N'))"
$previousSourceDateEpoch = $env:SOURCE_DATE_EPOCH
try {
    $env:SOURCE_DATE_EPOCH = '0'
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceDirectory 'wtsapi32_proxy.c'), `
        (Join-Path $sourceDirectory 'wtsapi32_proxy.def'), `
        (Join-Path $sourceDirectory 'wtsapi32_proxy_smoke_test.c') -Destination $stageRoot

    $stageProxy = Join-Path $stageRoot 'wtsapi32.dll'
    $stageHook = Join-Path $stageRoot 'XiaomiHyperConnectModelHook.dll'
    $stageTest = Join-Path $stageRoot 'wtsapi32_proxy_smoke_test.exe'
    $stageUninstallerTest = Join-Path $stageRoot 'Uninstall.exe'

    & $gcc -shared -O2 -s -Wall -Wextra -municode `
        '-frandom-seed=xiaomi-hyperconnect-wtsapi32' `
        '-Wl,--no-insert-timestamp' `
        '-Wl,--image-base,0x180000000' `
        -o $stageProxy `
        (Join-Path $stageRoot 'wtsapi32_proxy.c') `
        (Join-Path $stageRoot 'wtsapi32_proxy.def')
    if ($LASTEXITCODE -ne 0) { throw "Runtime proxy build failed with exit code $LASTEXITCODE." }

    & $gcc -O2 -s -Wall -Wextra -Wno-cast-function-type -municode -o $stageTest `
        (Join-Path $stageRoot 'wtsapi32_proxy_smoke_test.c')
    if ($LASTEXITCODE -ne 0) { throw "Smoke-test build failed with exit code $LASTEXITCODE." }

    $hookSource = Assert-CompatArtifact -Name 'model_hook_tm2425'
    Copy-Item -LiteralPath $hookSource -Destination $stageHook
    & $stageTest $stageProxy load
    if ($LASTEXITCODE -ne 0) { throw "Runtime model-hook smoke test failed with exit code $LASTEXITCODE." }

    Copy-Item -LiteralPath $stageTest -Destination $stageUninstallerTest
    & $stageUninstallerTest $stageProxy skip
    if ($LASTEXITCODE -ne 0) { throw "Uninstaller bypass smoke test failed with exit code $LASTEXITCODE." }

    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
    Copy-Item -LiteralPath $stageProxy -Destination $proxyDll -Force
    Copy-Item -LiteralPath $stageHook -Destination $modelHook -Force
    Copy-Item -LiteralPath $stageTest -Destination $testExe -Force
}
finally {
    if ($null -eq $previousSourceDateEpoch) {
        Remove-Item Env:SOURCE_DATE_EPOCH -ErrorAction SilentlyContinue
    }
    else {
        $env:SOURCE_DATE_EPOCH = $previousSourceDateEpoch
    }
    $resolvedStage = [IO.Path]::GetFullPath($stageRoot).TrimEnd('\')
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ($resolvedStage.StartsWith($resolvedTemp + '\', [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedStage -PathType Container)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}

[pscustomobject]@{
    OutputDirectory = $resolvedOutput
    Compiler = $gcc
    ProxySHA256 = (Get-Sha256 -Path $proxyDll)
    ModelHookSHA256 = (Get-Sha256 -Path $modelHook)
    RuntimeSmokeTest = 'Passed'
    UninstallerBypassSmokeTest = 'Passed'
    Note = 'The build fixes the PE timestamp, preferred image base, and compiler random seed for reproducible output with the same toolchain.'
}
