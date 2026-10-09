[CmdletBinding()]
param(
    [string]$SourceRoot='',
    [string]$Version='0.3.8',
    [string]$OutputDirectory='',
    [string]$RuntimeDirectory='',
    [string]$VendorRoot='',
    [string]$InnoCompiler='C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    [string]$SevenZip='C:\Program Files\7-Zip\7z.exe',
    [string]$SigningKeyFile=(Join-Path $env:LOCALAPPDATA 'ListenFree\ReleaseSigning\winsparkle-private.key'),
    [switch]$PortableOnly,
    [switch]$InstallerOnly,
    [switch]$SkipChecksums
)
$ErrorActionPreference='Stop'
if ($PortableOnly -and $InstallerOnly) { throw 'PortableOnly and InstallerOnly are mutually exclusive' }
Set-StrictMode -Version Latest
if (!$SourceRoot) { $SourceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$') { throw 'Invalid release version' }
$source=[IO.Path]::GetFullPath($SourceRoot)
$vendor=if($VendorRoot){[IO.Path]::GetFullPath($VendorRoot)}else{[IO.Path]::GetFullPath((Join-Path $source '..\_vendor'))}
$runtime=if($RuntimeDirectory){[IO.Path]::GetFullPath($RuntimeDirectory)}else{Join-Path $source 'dist\ListenFree-Portable'}
if (!(Test-Path -LiteralPath (Join-Path $runtime 'qt.conf'))) { throw "Missing deployed runtime: $runtime" }
$releaseRoot=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $source "dist\releases\$Version"}
$stage=Join-Path $releaseRoot "ListenFree-$Version-windows-x64"
# A fresh directory prevents an earlier smoke test's data from entering a ZIP.
if (Test-Path -LiteralPath $stage) { throw "Release stage already exists: $stage" }
$requiredInputs=@((Join-Path $source 'build\portable\listenfree.exe'),(Join-Path $source 'build\portable\listenfree-sourcehost.exe'),(Join-Path $source 'packaging\usage.txt'))
if (!$PortableOnly) { $requiredInputs += $InnoCompiler }
if (!$InstallerOnly) { $requiredInputs += $SevenZip }
foreach ($required in $requiredInputs) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing release input: $required" }
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
# Copy only deployed runtime binaries and known runtime directories. Never copy
# data/, loose JSON/INI, source scripts, histories, diagnostics or local media.
Get-ChildItem -LiteralPath $runtime -File -Filter '*.dll' | Copy-Item -Destination $stage
foreach ($name in 'generic','iconengines','imageformats','multimedia','networkinformation','platforms','qml','qmmp','sqldrivers','styles','tls') {
    $directory=Join-Path $runtime $name
    if (Test-Path -LiteralPath $directory) { Copy-Item -LiteralPath $directory -Destination $stage -Recurse }
}
foreach ($name in 'listenfree.exe','listenfree-sourcehost.exe','WinSparkle.dll') {
    Copy-Item -LiteralPath (Join-Path $source "build\portable\$name") -Destination $stage
}
Copy-Item -LiteralPath (Join-Path $vendor 'qmmp-build-qt\src\plugins\Transports\http\http.dll') -Destination (Join-Path $stage 'qmmp\Transports\http.dll') -Force
# The tested runtime carries patched Qt/Qmmp DLLs; do not replace them with SDK originals.
Copy-Item -LiteralPath (Join-Path $runtime 'qt.conf') -Destination $stage
Copy-Item -LiteralPath (Join-Path $runtime 'licenses') -Destination $stage -Recurse
Copy-Item -Path (Join-Path $source 'licenses\*.txt') -Destination (Join-Path $stage 'licenses') -Force
foreach ($pair in @(@((Join-Path $source '.vcpkg_installed\x64-mingw-dynamic\share'),'qjs'),@((Join-Path $source '.vcpkg_installed\x64-mingw-dynamic\share'),'taglib'),@((Join-Path $source '.vcpkg_installed\x64-mingw-dynamic\share'),'zlib'),@((Join-Path $source '.vcpkg_installed\x64-mingw-dynamic\share'),'utf8cpp'),@((Join-Path $vendor 'qmmp-vcpkg-installed-qt\x64-mingw-dynamic\share'),'ffmpeg'),@((Join-Path $vendor 'qmmp-vcpkg-installed-qt\x64-mingw-dynamic\share'),'curl'))) {
    $copyright=Join-Path $pair[0] ($pair[1]+'\copyright')
    if (Test-Path -LiteralPath $copyright) { Copy-Item -LiteralPath $copyright -Destination (Join-Path $stage ('licenses\'+$pair[1]+'-copyright.txt')) }
}
Copy-Item -LiteralPath (Join-Path $source 'licenses\THIRD-PARTY-NOTICES.txt') -Destination (Join-Path $stage 'licenses\THIRD-PARTY-NOTICES.txt') -Force
Copy-Item -LiteralPath (Join-Path $source 'packaging\usage.txt') -Destination (Join-Path $stage '使用说明.txt')
$releaseNotes=Join-Path $source "packaging\release-notes-$Version.txt"
if (Test-Path -LiteralPath $releaseNotes) { Copy-Item -LiteralPath $releaseNotes -Destination (Join-Path $stage '更新说明.txt') }
New-Item -ItemType File -Path (Join-Path $stage 'portable.mode') | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse) {
    $relative=$file.FullName.Substring($stage.Length+1)
    if ($relative -match '(^|[\\/])(data|cache|logs|sources)([\\/]|$)' -or $file.Extension -in '.sqlite','.db','.log','.mp3','.flac','.m4a','.mp4') {
        throw "Unexpected personal-data candidate: $relative"
    }
}
$smokeData=Join-Path $source "build\release-smoke-$Version"
& (Join-Path $PSScriptRoot 'test-portable-startup.ps1') -PackageRoot $stage -DataDirectory $smokeData
if (!$PortableOnly) {
    & $InnoCompiler "/DStageDir=$stage" "/DOutputDir=$releaseRoot" "/DReleaseVersion=$Version" (Join-Path $PSScriptRoot 'listenfree.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
    & (Join-Path $PSScriptRoot 'new-update-appcast.ps1') -Installer (Join-Path $releaseRoot "ListenFree-$Version-windows-x64-Setup.exe") -Version $Version -SigningKeyFile $SigningKeyFile -WinSparkleTool (Join-Path $vendor 'winsparkle-0.9.4\WinSparkle-0.9.4\bin\winsparkle-tool.exe') -ReleaseNotes $releaseNotes
}
if (!$InstallerOnly) {
$zip=Join-Path $releaseRoot "ListenFree-$Version-windows-x64-Portable.zip"
& $SevenZip a -tzip -mx=7 $zip $stage
if ($LASTEXITCODE -ne 0) { throw 'Portable archive creation failed' }
& $SevenZip t $zip
if ($LASTEXITCODE -ne 0) { throw 'Portable archive integrity check failed' }
}
if (!$SkipChecksums) {
    $artifacts=Get-ChildItem -LiteralPath $releaseRoot -File | Where-Object Extension -In '.exe','.zip'
    $checksums=foreach ($file in $artifacts) { "{0}  {1}" -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),$file.Name }
    [IO.File]::WriteAllLines((Join-Path $releaseRoot 'SHA256SUMS.txt'),$checksums,[Text.UTF8Encoding]::new($false))
}
Write-Output "发布包：$releaseRoot"
