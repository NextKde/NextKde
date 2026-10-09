$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $repo 'build/cover-placeholder-check'
$components = Join-Path $fixture 'Components'
New-Item -ItemType Directory -Force $components | Out-Null
New-Item -ItemType Directory -Force (Join-Path $fixture 'assets/icons') | Out-Null
foreach ($name in @('CoverArt', 'AppTheme', 'IconGlyph', 'SongRow')) {
    Copy-Item -LiteralPath (Join-Path $repo "music_player_desktop/components/$name.qml") -Destination $components -Force
}
$shaderDirectory=Join-Path $fixture 'shaders'
New-Item -ItemType Directory -Force $shaderDirectory | Out-Null
& F:/QT/6.11.2/mingw_64/bin/qsb.exe --glsl '150,300es' --hlsl 50 --msl 12 -o (Join-Path $shaderDirectory 'cover-rounded.frag.qsb') (Join-Path $repo 'music_player_desktop/shaders/cover-rounded.frag')
if($LASTEXITCODE -ne 0) { throw 'Cover shader compilation failed.' }
# qmltestrunner does not link the application's resource collection.
$fixtureCover=Join-Path $components 'CoverArt.qml'
$coverText=[IO.File]::ReadAllText($fixtureCover).Replace('qrc:/shaders/cover-rounded.frag.qsb','../shaders/cover-rounded.frag.qsb')
[IO.File]::WriteAllText($fixtureCover,$coverText,[Text.UTF8Encoding]::new($false))
Copy-Item -Path (Join-Path $repo 'music_player_desktop/assets/icons/*.svg') -Destination (Join-Path $fixture 'assets/icons') -Force
Set-Content -LiteralPath (Join-Path $components 'qmldir') -Value "singleton AppTheme 1.0 AppTheme.qml`nCoverArt 1.0 CoverArt.qml`nIconGlyph 1.0 IconGlyph.qml`nSongRow 1.0 SongRow.qml"
Copy-Item -LiteralPath (Join-Path $repo 'tests/qml/tst_cover_placeholder.qml') -Destination $fixture -Force
Add-Type -AssemblyName System.Drawing
foreach ($entry in @(@('transparent', 1, [Drawing.Color]::Transparent), @('opaque', 16, [Drawing.Color]::FromArgb(186,64,80)))) {
    $bitmap = [Drawing.Bitmap]::new($entry[1], $entry[1])
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try { $graphics.Clear($entry[2]); $bitmap.Save((Join-Path $fixture ($entry[0]+'.png')), [Drawing.Imaging.ImageFormat]::Png) }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}
$env:PATH = 'F:\QT\6.11.2\mingw_64\bin;F:\QT\Tools\mingw1310_64\bin;'+$env:PATH
$env:QML_IMPORT_PATH = 'F:\QT\6.11.2\mingw_64\qml'
$env:QT_PLUGIN_PATH = 'F:\QT\6.11.2\mingw_64\plugins'
$env:QSG_RENDER_LOOP = 'basic'
$env:QT_QPA_PLATFORM = 'offscreen'
$result = Join-Path $fixture 'result.txt'
$process = Start-Process F:/QT/6.11.2/mingw_64/bin/qmltestrunner.exe -ArgumentList '-input',$fixture,'-o',($result+',txt') -WindowStyle Hidden -PassThru -Wait
Get-Content -LiteralPath (Join-Path $fixture 'result.txt')
exit $process.ExitCode
