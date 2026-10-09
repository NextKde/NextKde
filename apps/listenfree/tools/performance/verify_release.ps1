param([Parameter(Mandatory=$true)][string]$ReleaseDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$release=(Resolve-Path $ReleaseDirectory).Path
$reportRoot=Join-Path $repo 'docs\validation\native-memory-2026-09-08'
$installer=Join-Path $release 'ListenFree-0.3.1-windows-x64-Setup.exe'
$zip=Join-Path $release 'ListenFree-0.3.1-windows-x64-Portable.zip'
$installRoot=Join-Path $repo 'build\release-install-0.3.1'
$uninstallKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{C9DFBE62-EA54-44D9-AE71-378F2715325D}_is1'
if((Test-Path -LiteralPath $installRoot) -or (Test-Path -LiteralPath $uninstallKey)) { throw 'An installation already exists; isolated install verification refused' }
$extractRoot=Join-Path $repo 'build\release-extract-0.3.1'
if(Test-Path -LiteralPath $extractRoot) { throw 'Extraction target must be fresh' }
& 'C:\Program Files\7-Zip\7z.exe' x $zip "-o$extractRoot" -y | Out-Null
if($LASTEXITCODE -ne 0) { throw 'ZIP extraction failed' }
$portable=Join-Path $extractRoot 'ListenFree-0.3.1-windows-x64'
if(!(Test-Path -LiteralPath (Join-Path $portable 'portable.mode')) -or (Test-Path -LiteralPath (Join-Path $portable 'data'))) { throw 'Unexpected portable profile contents' }
& (Join-Path $repo 'scripts\windows\test-portable-startup.ps1') -PackageRoot $portable -DataDirectory (Join-Path $repo 'build\release-extract-data-0.3.1')
$installLog=Join-Path $repo 'build\native-memory-20260908\installer-test.log'
$setup=Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/TASKS=',('/DIR="'+$installRoot+'"'),('/LOG="'+$installLog+'"')) -WindowStyle Hidden -PassThru
if(!$setup.WaitForExit(60000)) { throw 'Installer test exceeded its timeout' }
if($setup.ExitCode -ne 0) { throw "Installer exit $($setup.ExitCode)" }
$entry=Get-ItemProperty -LiteralPath $uninstallKey
if($entry.DisplayVersion -ne '0.3.1') { throw 'Installed version differs' }
if((Test-Path -LiteralPath (Join-Path $installRoot 'portable.mode')) -or (Test-Path -LiteralPath (Join-Path $installRoot 'data'))) { throw 'Installer includes a portable marker or data' }
& (Join-Path $repo 'scripts\windows\test-portable-startup.ps1') -PackageRoot $installRoot -DataDirectory (Join-Path $repo 'build\release-install-data-0.3.1')
# Only synthetic data in the isolated test install; no real profile is touched.
$sentinel=Join-Path $installRoot 'data\preservation-check.txt'
New-Item -ItemType Directory -Path (Split-Path $sentinel) | Out-Null
Set-Content -LiteralPath $sentinel 'Synthetic data must survive uninstall.' -Encoding utf8
$uninstaller=Join-Path $installRoot 'unins000.exe'
$remove=Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -PassThru
if(!$remove.WaitForExit(60000)) { throw 'Uninstaller test exceeded its timeout' }
if($remove.ExitCode -ne 0 -or (Test-Path -LiteralPath $uninstallKey) -or (Test-Path -LiteralPath (Join-Path $installRoot 'listenfree.exe'))) { throw 'Uninstall verification failed' }
if(!(Test-Path -LiteralPath $sentinel)) { throw 'Uninstall deleted synthetic user data' }
$result=[ordered]@{version='0.3.1';portableExtractAndCleanStartup=$true;installerExit=$setup.ExitCode;installedVersion=$entry.DisplayVersion;installedCleanStartup=$true;uninstallerExit=$remove.ExitCode;registrationRemoved=$true;syntheticUserDataPreserved=$true;realProfileUsed=$false;releaseDirectory=$release}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportRoot 'release-install-validation.json') -Encoding utf8
$result | ConvertTo-Json
