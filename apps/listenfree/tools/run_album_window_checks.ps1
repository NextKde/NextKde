$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $repo 'build/album-window-check'
New-Item -ItemType Directory -Force (Join-Path $fixture 'pages'),(Join-Path $fixture 'assets'),(Join-Path $fixture 'components') | Out-Null
Copy-Item -Path (Join-Path $repo 'music_player_desktop/components/*.qml') -Destination (Join-Path $fixture 'components') -Force
Copy-Item -LiteralPath (Join-Path $repo 'music_player_desktop/assets/icons') -Destination (Join-Path $fixture 'assets') -Recurse -Force
Copy-Item -Path (Join-Path $repo 'music_player_desktop/assets/album_Cover_*.png') -Destination (Join-Path $fixture 'assets') -Force
$types = Get-ChildItem (Join-Path $fixture 'components') -Filter '*.qml' | ForEach-Object {
    if ($_.BaseName -eq 'AppTheme') { 'singleton AppTheme 1.0 AppTheme.qml' }
    else { $_.BaseName+' 1.0 '+$_.Name }
}
Set-Content -LiteralPath (Join-Path $fixture 'components/qmldir') -Value $types
Copy-Item -LiteralPath (Join-Path $repo 'music_player_desktop/pages/LibraryPage.qml') -Destination (Join-Path $fixture 'pages') -Force
Copy-Item -LiteralPath (Join-Path $repo 'tests/qml/tst_album_window.qml') -Destination $fixture -Force
$env:PATH = 'F:\QT\6.11.2\mingw_64\bin;F:\QT\Tools\mingw1310_64\bin;'+$env:PATH
$env:QML_IMPORT_PATH = 'F:\QT\6.11.2\mingw_64\qml'
$env:QT_PLUGIN_PATH = 'F:\QT\6.11.2\mingw_64\plugins'
$env:QSG_RENDER_LOOP = 'basic'
$env:QT_QPA_PLATFORM = 'offscreen'
$result = Join-Path $fixture 'result.txt'
& F:/QT/6.11.2/mingw_64/bin/qmltestrunner.exe -input $fixture -o ($result+',txt')
$code = $LASTEXITCODE
Get-Content -LiteralPath $result
exit $code
