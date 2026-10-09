[CmdletBinding()]
param(
    [string]$QtRoot='F:\QT\6.11.2\mingw_64',
    [string]$QtToolsRoot='F:\QT\Tools'
)
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path $PSScriptRoot -Parent
$work=Join-Path $repositoryRoot 'build\qt-imageformats-6.11.2'
$source=Join-Path $work 'qtimageformats-6.11.2'
$build=Join-Path $work 'build'
$archive=Join-Path $work 'qtimageformats-v6.11.2.tar.gz'
$expectedHash='76f5477d0216f37a5f44ddbca1decd4df245c2db39baccb1025eb66cfe50d8f8'
$cmake=Join-Path $QtToolsRoot 'CMake_64\bin\cmake.exe'
$compiler=Join-Path $QtToolsRoot 'mingw1310_64\bin'
function Invoke-Checked([string]$Executable,[string[]]$Arguments) {
    & $Executable @Arguments
    if($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
New-Item -ItemType Directory -Force -Path $work | Out-Null
if(!(Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -Uri 'https://codeload.github.com/qt/qtimageformats/tar.gz/refs/tags/v6.11.2' -OutFile $archive
}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Qt Image Formats archive checksum mismatch.'
}
if(!(Test-Path -LiteralPath (Join-Path $source 'CMakeLists.txt'))) {
    Push-Location $work
    try { Invoke-Checked $cmake @('-E','tar','xzf',$archive) }
    finally { Pop-Location }
}
$previousPath=$env:PATH
try {
    $env:PATH="$compiler;$(Join-Path $QtRoot 'bin');$previousPath"
    Invoke-Checked $cmake @('-S',$source,'-B',$build,'-G','Ninja',
        '-DCMAKE_BUILD_TYPE=Release',"-DCMAKE_PREFIX_PATH=$QtRoot",
        "-DCMAKE_MAKE_PROGRAM=$QtToolsRoot/Ninja/ninja.exe",
        "-DCMAKE_C_COMPILER=$compiler/gcc.exe","-DCMAKE_CXX_COMPILER=$compiler/g++.exe",
        '-DQT_BUILD_TESTS=OFF','-DQT_BUILD_EXAMPLES=OFF',
        '-DQT_FEATURE_webp=ON','-DQT_FEATURE_system_webp=OFF')
    # Use Qt's unmodified decoder and bundled libwebp; no separate codec runtime.
    Invoke-Checked $cmake @('--build',$build,'--target','QWebpPlugin','-j','6')
    $plugin=Join-Path $build 'plugins\imageformats\qwebp.dll'
    if(!(Test-Path -LiteralPath $plugin)) { throw "WebP plugin was not produced: $plugin" }
    Write-Output "WebPPlugin=$plugin"
} finally { $env:PATH=$previousPath }
