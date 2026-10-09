[CmdletBinding()]
param(
    [string]$QtRoot = $env:LISTENFREE_QT_ROOT,
    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [string]$WorkRoot,
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
    $WorkRoot = Join-Path $repositoryRoot 'build\qt-multimedia-6.11.2-mmcss-fix'
}

$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot)
$workRootFull = [IO.Path]::GetFullPath($WorkRoot)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'build')) + [IO.Path]::DirectorySeparatorChar
if (-not $workRootFull.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Patched Qt work root must stay below '$allowedRoot': '$workRootFull'."
}

. (Join-Path $PSScriptRoot 'enter-dev-shell.ps1') -QtRoot $QtRoot -VcpkgRoot $VcpkgRoot -Quiet

$qtTag = 'v6.11.2'
$qtCommit = '6f162ccac1425edbd7b4d1582fabab5973b43d6c'
$vulkanTag = 'v1.4.357'
$vulkanCommit = 'e3b1eec08173d6b825cd3ac88c885a63b621504a'
$sourceDirectory = Join-Path $workRootFull 'src'
$buildDirectory = Join-Path $workRootFull 'build'
$vulkanDirectory = Join-Path $workRootFull 'Vulkan-Headers'
$runtimeDirectory = Join-Path $workRootFull 'runtime\bin'
$runtimeDll = Join-Path $runtimeDirectory 'Qt6Multimedia.dll'
$patchPath = Join-Path $repositoryRoot 'patches\qt\6.11.2\0001-wasapi-revert-mmcss-registration.patch'

function Invoke-CheckedNative([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

function Assert-GitCommit([string]$Directory, [string]$ExpectedCommit) {
    $actualCommit = (& git -C $Directory rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $ExpectedCommit) {
        throw "Unexpected source commit in '$Directory': expected $ExpectedCommit, got $actualCommit."
    }
}

New-Item -ItemType Directory -Force -Path $workRootFull | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory '.git') -PathType Container)) {
    Invoke-CheckedNative git @('clone', '--depth', '1', '--branch', $qtTag,
        'https://github.com/qt/qtmultimedia.git', $sourceDirectory)
}
Assert-GitCommit $sourceDirectory $qtCommit

& git -C $sourceDirectory apply --unidiff-zero --reverse --check $patchPath 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-CheckedNative git @('-C', $sourceDirectory, 'apply', '--unidiff-zero', '--check', $patchPath)
    Invoke-CheckedNative git @('-C', $sourceDirectory, 'apply', '--unidiff-zero', $patchPath)
}

$vulkanHeader = Join-Path $QtRoot 'include\vulkan\vulkan.h'
if (-not (Test-Path -LiteralPath $vulkanHeader -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath (Join-Path $vulkanDirectory '.git') -PathType Container)) {
        Invoke-CheckedNative git @('clone', '--depth', '1', '--branch', $vulkanTag,
            'https://github.com/KhronosGroup/Vulkan-Headers.git', $vulkanDirectory)
    }
    Assert-GitCommit $vulkanDirectory $vulkanCommit
    $vulkanInclude = (Join-Path $vulkanDirectory 'include').Replace('\', '/')
} else {
    $vulkanInclude = (Join-Path $QtRoot 'include').Replace('\', '/')
}

$configureArguments = @(
    '-S', $sourceDirectory,
    '-B', $buildDirectory,
    '-G', 'Ninja',
    "-DCMAKE_PREFIX_PATH=$QtRoot",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DQT_BUILD_TESTS=OFF',
    '-DQT_BUILD_EXAMPLES=OFF',
    "-DCMAKE_CXX_FLAGS=-I$vulkanInclude"
)
Invoke-CheckedNative cmake $configureArguments
Invoke-CheckedNative cmake @('--build', $buildDirectory, '--target', 'Multimedia', '-j', '6')

$builtDll = Join-Path $buildDirectory 'bin\Qt6Multimedia.dll'
if (-not (Test-Path -LiteralPath $builtDll -PathType Leaf)) {
    throw "Patched Qt Multimedia DLL was not produced: '$builtDll'."
}
New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
Copy-Item -LiteralPath $builtDll -Destination $runtimeDll -Force

if ($Deploy) {
    foreach ($configuration in @('windows-debug', 'windows-release')) {
        $destinationDirectory = Join-Path $repositoryRoot "build\$configuration"
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
        Copy-Item -LiteralPath $runtimeDll -Destination (Join-Path $destinationDirectory 'Qt6Multimedia.dll') -Force
    }
}

$hash = (Get-FileHash -LiteralPath $runtimeDll -Algorithm SHA256).Hash
Write-Output "PatchedQtMultimedia=$runtimeDll"
Write-Output "PatchedQtMultimediaSHA256=$hash"
Write-Output "PatchedQtSource=$qtCommit"
Write-Output "PatchedQtDeployment=$([bool]$Deploy)"
