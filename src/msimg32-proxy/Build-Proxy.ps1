[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$HookPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'build'
}
if (-not $HookPath) {
    $HookPath = Join-Path $repoRoot 'skills\install-xiaomi-hyperconnect\assets\bin\common\wtsapi32.dll'
}

$gccCandidates = @(
    'C:\msys64\ucrt64\bin\gcc.exe',
    'C:\msys64\ucr64\bin\gcc.exe'
)
$gcc = $gccCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $gcc) {
    throw 'MSYS2 UCRT64 x64 GCC was not found.'
}
if (-not (Test-Path -LiteralPath $HookPath -PathType Leaf)) {
    throw "Model hook was not found: $HookPath"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$proxyDll = Join-Path $OutputDirectory 'msimg32.dll'
$hookCopy = Join-Path $OutputDirectory 'wtsapi32.dll'
$testExe = Join-Path $OutputDirectory 'proxy_smoke_test.exe'

& $gcc -shared -O2 -s -Wall -Wextra -municode -o $proxyDll `
    (Join-Path $PSScriptRoot 'msimg32_proxy.c') `
    (Join-Path $PSScriptRoot 'msimg32_proxy.def')
if ($LASTEXITCODE -ne 0) {
    throw "Proxy build failed with exit code $LASTEXITCODE."
}

& $gcc -O2 -s -Wall -Wextra -municode -o $testExe `
    (Join-Path $repoRoot 'tests\proxy_smoke_test.c')
if ($LASTEXITCODE -ne 0) {
    throw "Smoke-test build failed with exit code $LASTEXITCODE."
}

Copy-Item -LiteralPath $HookPath -Destination $hookCopy -Force
& $testExe $proxyDll
if ($LASTEXITCODE -ne 0) {
    throw "Proxy smoke test failed with exit code $LASTEXITCODE."
}

Get-FileHash -LiteralPath $proxyDll, $hookCopy -Algorithm SHA256 |
    Select-Object Path, Hash
