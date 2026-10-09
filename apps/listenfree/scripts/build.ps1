[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [switch]$SkipQtMultimediaPatch,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter-dev-shell.ps1') -Quiet

if (-not $SkipQtMultimediaPatch) {
    & (Join-Path $PSScriptRoot 'build-patched-qtmultimedia.ps1') -Deploy
    if ($LASTEXITCODE -ne 0) { throw 'Patched Qt Multimedia build failed' }
}

$preset = "windows-$($Configuration.ToLowerInvariant())"
cmake --preset $preset
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $preset" }
cmake --build --preset $preset
if ($LASTEXITCODE -ne 0) { throw "CMake build failed for $preset" }
if (-not $SkipTests) {
    ctest --test-dir "build\windows-$($Configuration.ToLowerInvariant())" --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw "CTest failed for $preset" }
}
