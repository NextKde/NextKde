[CmdletBinding()]
param([string]$SourceRoot='', [string]$QtRoot='F:\QT\6.11.2\mingw_64', [string]$QtToolsRoot='F:\QT\Tools', [string]$VendorRoot='', [switch]$SkipBuild, [string]$OutputDirectory='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$SourceRoot) { $SourceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if (!$VendorRoot) { $VendorRoot=Join-Path (Split-Path $SourceRoot -Parent) '_vendor' }
$source=[IO.Path]::GetFullPath($SourceRoot)
$vendor=[IO.Path]::GetFullPath($VendorRoot)
$buildDir=Join-Path $source 'build\portable'
$stage=if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $source 'dist\ListenFree-Portable' }
$cmake=Join-Path $QtToolsRoot 'CMake_64\bin\cmake.exe'
$compilerDir=Join-Path $QtToolsRoot 'mingw1310_64\bin'
$qmmp=Join-Path $vendor 'qmmp-stage-qt'
$qmmpUi=Join-Path $vendor 'qmmp-build-qt\src\qmmpui'
$dependencyBin=Join-Path $vendor 'qmmp-vcpkg-installed-qt\x64-mingw-dynamic\bin'
$projectDependencies=Join-Path $source '.vcpkg_installed\x64-mingw-dynamic'
function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
$previousPath=$env:PATH
try {
    $env:PATH="$compilerDir;$(Join-Path $QtRoot 'bin');$previousPath"
    # Migu and other cover providers return WebP. A minimal Qt SDK does not
    # install Qt Image Formats, so windeployqt alone can silently omit it.
    $webpPlugin=Join-Path $QtRoot 'plugins\imageformats\qwebp.dll'
    if(!(Test-Path -LiteralPath $webpPlugin)) {
        & (Join-Path $source 'scripts\build-qtimageformats.ps1') -QtRoot $QtRoot -QtToolsRoot $QtToolsRoot
        $webpPlugin=Join-Path $source 'build\qt-imageformats-6.11.2\build\plugins\imageformats\qwebp.dll'
    }
    if(!(Test-Path -LiteralPath $webpPlugin)) { throw 'Required Qt WebP image decoder is missing.' }
    if (!$SkipBuild) {
        Invoke-Checked $cmake @('-S',$source,'-B',$buildDir,'-G','Ninja',
            '-DCMAKE_BUILD_TYPE=Release',"-DCMAKE_CXX_COMPILER=$compilerDir/g++.exe",
            "-DCMAKE_MAKE_PROGRAM=$QtToolsRoot/Ninja/ninja.exe",
            "-DCMAKE_PREFIX_PATH=$QtRoot;$projectDependencies", "-Dqjs_DIR=$projectDependencies/share/qjs",
            '-DLISTENFREE_BUILD_TESTS=ON','-DLISTENFREE_BUILD_QMMP_BACKEND=ON','-DLISTENFREE_BUILD_MPV_BACKEND=OFF',
            "-DLISTENFREE_QMMP_SOURCE_ROOT=$vendor/qmmp-2.4.1",
            "-DLISTENFREE_QMMP_LIBRARY=$qmmp/libqmmp.dll.a", "-DLISTENFREE_QMMP_RUNTIME=$qmmp/libqmmp.dll",
            "-DLISTENFREE_QMMP_UI_LIBRARY=$qmmpUi/libqmmpui.dll.a", "-DLISTENFREE_QMMP_PLUGIN_ROOT=$qmmp",
            "-DLISTENFREE_LIVE_FFMPEG_ROOT=$vendor/qmmp-vcpkg-installed-qt/x64-mingw-dynamic",
            "-DLISTENFREE_WINSPARKLE_ROOT=$vendor/winsparkle-0.9.4/WinSparkle-0.9.4")
        Invoke-Checked $cmake @('--build',$buildDir,'--target','listenfree','listenfree-sourcehost','--parallel','4')
    }
    $resolvedStage=[IO.Path]::GetFullPath($stage)
    $allowedRoot=[IO.Path]::GetFullPath((Join-Path $source 'dist')).TrimEnd('\')+'\'
    if (!$resolvedStage.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe stage path' }
    $stageExe=Join-Path $resolvedStage 'listenfree.exe'
    if (Get-Process listenfree -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $stageExe }) {
        throw "Portable directory is in use: $resolvedStage"
    }
    if (Test-Path -LiteralPath $resolvedStage) {
        $stagePrefix=$resolvedStage.TrimEnd('\')+'\'
        foreach ($entry in Get-ChildItem -LiteralPath $resolvedStage -Force) {
            if ($entry.Name -eq 'data') { continue }
            $entryPath=[IO.Path]::GetFullPath($entry.FullName)
            if (!$entryPath.StartsWith($stagePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe deployment entry' }
            Remove-Item -LiteralPath $entryPath -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path $resolvedStage -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $buildDir 'listenfree.exe'),(Join-Path $buildDir 'listenfree-sourcehost.exe'),(Join-Path $qmmp 'libqmmp.dll'),(Join-Path $qmmpUi 'libqmmpui.dll') -Destination $stage
    New-Item -ItemType Directory -Path (Join-Path $stage 'qmmp') | Out-Null
    foreach ($name in 'Input','Output','Transports','Effect') { Copy-Item -LiteralPath (Join-Path $qmmp $name) -Destination (Join-Path $stage 'qmmp') -Recurse }
    Invoke-Checked (Join-Path $QtRoot 'bin\windeployqt.exe') @('--release','--compiler-runtime','--no-translations','--qmldir',(Join-Path $source 'music_player_desktop'),(Join-Path $stage 'listenfree.exe'))
    Invoke-Checked (Join-Path $QtRoot 'bin\windeployqt.exe') @('--release','--compiler-runtime','--no-translations',(Join-Path $stage 'listenfree-sourcehost.exe'))
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'imageformats') | Out-Null
    Copy-Item -LiteralPath $webpPlugin -Destination (Join-Path $stage 'imageformats\qwebp.dll') -Force
    # QLibrary dependencies are not discovered by windeployqt.
    Copy-Item -LiteralPath (Join-Path $buildDir 'WinSparkle.dll') -Destination $stage
    # The application opens QSQLITE only; unused database plugins require server SDKs.
    $sqlRoot=[IO.Path]::GetFullPath((Join-Path $stage 'sqldrivers'))
    if (!$sqlRoot.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe SQL plugin path' }
    Get-ChildItem -LiteralPath $sqlRoot -File | Where-Object { $_.Name -ne 'qsqlite.dll' } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    # Resolve actual imports, including dynamically loaded Qmmp plugins.
    $searchRoots=@($dependencyBin,(Join-Path $projectDependencies 'bin'),(Join-Path $QtRoot 'bin'),$compilerDir)
    $pending=[Collections.Generic.Queue[string]]::new()
    Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.Extension -in '.exe','.dll' } | ForEach-Object { $pending.Enqueue($_.FullName) }
    $visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($pending.Count) {
        $binary=$pending.Dequeue()
        if (!$visited.Add($binary)) { continue }
        $imports=& (Join-Path $compilerDir 'objdump.exe') -p $binary
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $binary" }
        foreach ($line in $imports) {
            if ($line -notmatch 'DLL Name:\s*(\S+)') { continue }
            $name=$Matches[1]
            if ((Test-Path -LiteralPath (Join-Path $stage $name)) -or $name -match '^(api-ms-|ext-ms-)' -or (Test-Path -LiteralPath (Join-Path "$env:SystemRoot\System32" $name))) { continue }
            $found=$null
            foreach ($root in $searchRoots) { $candidate=Join-Path $root $name; if (Test-Path -LiteralPath $candidate) { $found=$candidate; break } }
            if (!$found) { throw "Unresolved dependency $name ($binary)" }
            Copy-Item -LiteralPath $found -Destination $stage
            $pending.Enqueue((Join-Path $stage $name))
        }
    }
    New-Item -ItemType File -Path (Join-Path $stage 'portable.mode') | Out-Null
    Set-Content -LiteralPath (Join-Path $stage 'qt.conf') -Encoding ascii -Value @('[Paths]','Prefix=.','Plugins=.','QmlImports=qml')
    Copy-Item -LiteralPath (Join-Path $source 'packaging\usage.txt') -Destination (Join-Path $stage '使用说明.txt')
    $licenseDir=Join-Path $stage 'licenses'
    New-Item -ItemType Directory -Path $licenseDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $vendor 'qmmp-2.4.1\COPYING') -Destination (Join-Path $licenseDir 'Qmmp-COPYING.txt')
    Copy-Item -LiteralPath (Join-Path $source 'licenses\kawarp-MIT.txt') -Destination $licenseDir
    Copy-Item -LiteralPath (Join-Path $source 'licenses\LyricDecoder-MIT.txt') -Destination $licenseDir
    Copy-Item -LiteralPath (Join-Path $source 'licenses\LDDC-GPL-3.0.txt') -Destination $licenseDir
    Copy-Item -LiteralPath (Join-Path $source 'licenses\AMLL-AGPL-3.0.txt') -Destination $licenseDir
    Copy-Item -LiteralPath (Join-Path $source 'licenses\sylvakru-Apache-2.0.txt') -Destination $licenseDir
    Copy-Item -LiteralPath (Join-Path $source 'licenses\VLC-GPL-2.0.txt') -Destination $licenseDir
    Copy-Item -LiteralPath (Join-Path $source 'licenses\Verblib-MIT-0.txt') -Destination $licenseDir
    Copy-Item -Path (Join-Path $source 'licenses\*.txt') -Destination $licenseDir -Force
    & (Join-Path $source 'scripts\windows\test-portable-startup.ps1') -PackageRoot $stage -DataDirectory (Join-Path $buildDir 'portable-startup-profile')
    Write-Host "便携目录：$stage"
} finally { $env:PATH=$previousPath }
