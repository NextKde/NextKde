$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $repo 'build/navigation-budget-check'
New-Item -ItemType Directory -Force (Join-Path $fixture 'components'),(Join-Path $fixture 'assets') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'music_player_desktop/components/NavigationCache.qml') -Destination (Join-Path $fixture 'components') -Force
Copy-Item -Path (Join-Path $repo 'music_player_desktop/assets/album_Cover_*.png') -Destination (Join-Path $fixture 'assets') -Force
Copy-Item -LiteralPath (Join-Path $repo 'tests/qml/tst_navigation_budget.qml') -Destination $fixture -Force
$env:PATH='F:\QT\6.11.2\mingw_64\bin;F:\QT\Tools\mingw1310_64\bin;'+$env:PATH
$env:QML_IMPORT_PATH='F:\QT\6.11.2\mingw_64\qml'
$env:QT_PLUGIN_PATH='F:\QT\6.11.2\mingw_64\plugins'
$env:QSG_RENDER_LOOP='basic'
$env:QT_QPA_PLATFORM='offscreen'
$result=Join-Path $fixture 'result.txt'
& F:/QT/6.11.2/mingw_64/bin/qmltestrunner.exe -input $fixture -o ($result+',txt')
$code=$LASTEXITCODE
Get-Content -LiteralPath $result
exit $code
