$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $repo 'build/bilibili-settings-check'
New-Item -ItemType Directory -Force (Join-Path $fixture 'pages') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'music_player_desktop/components') -Destination $fixture -Recurse -Force
New-Item -ItemType Directory -Force (Join-Path $fixture 'assets') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'music_player_desktop/assets/icons') -Destination (Join-Path $fixture 'assets') -Recurse -Force
$types = Get-ChildItem (Join-Path $fixture 'components') -Filter '*.qml' | ForEach-Object {
    if ($_.BaseName -eq 'AppTheme') { 'singleton AppTheme 1.0 AppTheme.qml' }
    else { $_.BaseName+' 1.0 '+$_.Name }
}
Set-Content -LiteralPath (Join-Path $fixture 'components/qmldir') -Value $types
foreach ($page in 'SettingsPage','SearchPage') { Copy-Item -LiteralPath (Join-Path $repo "music_player_desktop/pages/$page.qml") -Destination (Join-Path $fixture 'pages') -Force }
Copy-Item -LiteralPath (Join-Path $repo 'tests/qml/tst_bilibili_settings.qml') -Destination $fixture -Force
$env:PATH = 'F:\QT\6.11.2\mingw_64\bin;F:\QT\Tools\mingw1310_64\bin;'+$env:PATH
$env:QML_IMPORT_PATH = 'F:\QT\6.11.2\mingw_64\qml'
$env:QT_PLUGIN_PATH = 'F:\QT\6.11.2\mingw_64\plugins'
$env:QSG_RENDER_LOOP = 'basic'
$env:QT_QPA_PLATFORM = 'offscreen'
$env:QT_QUICK_CONTROLS_STYLE = 'Basic'
$result = Join-Path $fixture 'result.txt'
$process = Start-Process F:/QT/6.11.2/mingw_64/bin/qmltestrunner.exe -ArgumentList '-input',$fixture,'-o',($result+',txt') -WindowStyle Hidden -PassThru -Wait
Get-Content -LiteralPath $result
exit $process.ExitCode
