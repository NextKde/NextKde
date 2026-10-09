param([string]$Label='current', [string]$SongRowSource='')
$ErrorActionPreference='Stop'
if ($Label -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Use a simple fixture label' }
$repo=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $repo "build/favorite-checks/$Label-qml"
$components=Join-Path $fixture 'Components'
New-Item -ItemType Directory -Force $components | Out-Null
New-Item -ItemType Directory -Force (Join-Path $fixture 'assets') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'music_player_desktop/assets/icons') -Destination (Join-Path $fixture 'assets') -Recurse -Force
foreach ($name in @('AppTheme','SongRow','CoverArt','IconGlyph')) {
    $source=if ($name -eq 'SongRow' -and $SongRowSource) { $SongRowSource } else { Join-Path $repo "music_player_desktop/components/$name.qml" }
    Copy-Item -LiteralPath $source -Destination $components -Force
}
[IO.File]::WriteAllText((Join-Path $components 'qmldir'), "singleton AppTheme 1.0 AppTheme.qml`nSongRow 1.0 SongRow.qml`nCoverArt 1.0 CoverArt.qml`nIconGlyph 1.0 IconGlyph.qml`n")
Copy-Item -LiteralPath (Join-Path $repo 'tests/qml/tst_song_row_favorites.qml') -Destination $fixture -Force
$env:Path='F:/QT/6.11.2/mingw_64/bin;F:/QT/Tools/mingw1310_64/bin;'+$env:Path
$env:QT_PLUGIN_PATH='F:/QT/6.11.2/mingw_64/plugins'
$env:QML_IMPORT_PATH='F:/QT/6.11.2/mingw_64/qml'
$env:QT_QPA_PLATFORM='offscreen'; $env:QSG_RENDER_LOOP='basic'
$env:QT_QUICK_BACKEND='software'
$fontDir=Join-Path $repo 'build/favorite-checks/fonts'
New-Item -ItemType Directory -Force $fontDir | Out-Null
foreach ($font in @('msyh.ttc','msyhbd.ttc','segoeui.ttf','segoeuib.ttf','seguiemj.ttf')) {
    if (-not (Test-Path (Join-Path $fontDir $font))) {
        Copy-Item -LiteralPath (Join-Path $env:WINDIR "Fonts/$font") -Destination $fontDir
    }
}
$env:QT_QPA_FONTDIR=$fontDir
$result=Join-Path $fixture 'result.txt'
& 'F:/QT/6.11.2/mingw_64/bin/qmltestrunner.exe' -input $fixture -o ($result+',txt') *> (Join-Path $fixture 'runtime.log')
$code=$LASTEXITCODE
Get-Content -LiteralPath $result
exit $code
