param(
    [ValidateSet('regression','benchmark','capture')][string]$Mode = 'regression',
    [ValidateSet('auto','offscreen','windows')][string]$Platform = 'auto',
    [string]$Label = 'current',
    [string]$ReferenceLabel = '',
    [switch]$Replay,
    [switch]$QmlProfile,
    [switch]$WordReference,
    [long]$AffinityMask = 0,
    [string]$QtRoot = 'F:/QT/6.11.2/mingw_64',
    [string]$CMake = 'F:/QT/Tools/CMake_64/bin/cmake.exe',
    [string]$MinGW = 'F:/QT/Tools/mingw1310_64/bin',
    [string]$Ninja = 'F:/QT/Tools/Ninja/ninja.exe'
)
$ErrorActionPreference = 'Stop'
if ($QmlProfile -and $Mode -ne 'benchmark') { throw 'Profiling is only supported for the benchmark scene' }
if ($WordReference -and $Mode -ne 'capture') { throw 'The word reference is only supported for capture' }
if ($Platform -eq 'auto') { $Platform = if ($Mode -eq 'regression') { 'offscreen' } else { 'windows' } }
if ($Label -notmatch '^[a-zA-Z0-9_-]+$' -or ($ReferenceLabel -and $ReferenceLabel -notmatch '^[a-zA-Z0-9_-]+$')) { throw 'Labels must be simple directory names' }
$repo = Split-Path $PSScriptRoot -Parent
$build = Join-Path $repo ('build/lyrics-checks/out' + $ReferenceLabel)
$fixture = Join-Path $repo ('build/lyrics-checks/' + $Label)
$native = if ($ReferenceLabel) { Join-Path $repo ('build/lyrics-checks/'+$ReferenceLabel) } else { Join-Path $repo 'src/qmlbridge' }
$components = if ($ReferenceLabel) { Join-Path $native 'Components' } else { Join-Path $repo 'music_player_desktop/components' }
$shaders = if ($ReferenceLabel) { Join-Path $native 'Shaders' } else { Join-Path $repo 'music_player_desktop/shaders' }
if (-not $Replay -and -not (Test-Path (Join-Path $shaders 'lyric-grapheme.frag'))) { throw 'Matched builds require saved baseline shaders as well as native/QML sources' }
$target = if ($Mode -eq 'regression') { 'listenfree_lyrics_tests' } else { 'listenfree_lyrics_render' }
New-Item -ItemType Directory -Force $build,(Join-Path $fixture 'Components') | Out-Null
$env:Path = $QtRoot + '/bin;' + $MinGW + ';' + $env:Path
$env:QT_PLUGIN_PATH = $QtRoot + '/plugins'
$env:QML_IMPORT_PATH = $QtRoot + '/qml'
$env:QT_QPA_PLATFORM = $Platform
$env:QSG_RHI_BACKEND = 'd3d11'
$env:QT_QUICK_BACKEND = if ($Mode -ne 'regression' -or $Platform -eq 'windows') { 'rhi' } else { 'software' }
if ($Platform -eq 'offscreen') {
    $env:QSG_RENDER_LOOP = 'basic'
    # The generic offscreen font database does not discover Windows fonts.
    $fontDir = Join-Path $repo 'build/lyrics-checks/fonts'
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    foreach ($font in @('msyh.ttc','msyhbd.ttc','segoeui.ttf','segoeuib.ttf','seguiemj.ttf')) {
        if (-not (Test-Path (Join-Path $fontDir $font))) {
            Copy-Item -LiteralPath (Join-Path $env:WINDIR "Fonts/$font") -Destination $fontDir
        }
    }
    $env:QT_QPA_FONTDIR = $fontDir
}
if (-not $Replay) {
    & $CMake -S (Join-Path $repo 'tests/lyrics') -B $build -G Ninja "-DCMAKE_MAKE_PROGRAM=$Ninja" "-DCMAKE_PREFIX_PATH=$QtRoot" "-DLYRIC_NATIVE_DIR=$native" "-DLYRIC_SHADER_DIR=$shaders" '-DCMAKE_BUILD_TYPE=Release' *> (Join-Path $fixture 'configure.log')
    if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $fixture 'configure.log'); throw 'Lyrics check configure failed' }
    & $CMake --build $build --target $target --parallel 4 *> (Join-Path $fixture 'build.log')
    if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $fixture 'build.log'); throw 'Lyrics check build failed' }
    Copy-Item -LiteralPath (Join-Path $build ($target+'.exe')) -Destination $fixture -Force
    foreach ($component in @('AppTheme','LyricsPanel','GlassSurface','IconGlyph','UiButton')) {
        Copy-Item -LiteralPath (Join-Path $components "$component.qml") -Destination (Join-Path $fixture 'Components') -Force
    }
    $module = "singleton AppTheme 1.0 AppTheme.qml`nLyricsPanel 1.0 LyricsPanel.qml`nGlassSurface 1.0 GlassSurface.qml`nIconGlyph 1.0 IconGlyph.qml`nUiButton 1.0 UiButton.qml`n"
    [IO.File]::WriteAllText((Join-Path $fixture 'Components/qmldir'), $module)
    $source = if ($Mode -eq 'regression') { 'tests/qml/tst_classic_lyrics.qml' } else { 'tools/performance/lyrics_scene.qml' }
    Copy-Item -LiteralPath (Join-Path $repo $source) -Destination (Join-Path $fixture 'scene.qml') -Force
    # Keep the exact sources beside each result, including the compiled C++ baseline.
    Copy-Item -LiteralPath (Join-Path $native 'spring_value.h'),(Join-Path $native 'lyric_text_metrics.h') -Destination $fixture -Force
    New-Item -ItemType Directory -Force (Join-Path $fixture 'Shaders') | Out-Null
    Copy-Item -LiteralPath (Join-Path $shaders 'lyric-word.frag'),(Join-Path $shaders 'lyric-grapheme.frag') -Destination (Join-Path $fixture 'Shaders') -Force
}
$options = @{ FilePath = (Join-Path $fixture ($target+'.exe')); WorkingDirectory = $fixture; WindowStyle = 'Hidden'; PassThru = $true; RedirectStandardOutput = (Join-Path $fixture 'stdout.log'); RedirectStandardError = (Join-Path $fixture 'runtime.log') }
if ($Mode -eq 'regression') { $options.ArgumentList = @('-input','scene.qml','-o','result.txt,txt') }
if ($Mode -eq 'capture') { $options.ArgumentList = @('--capture-motion') }
if ($WordReference) { $options.ArgumentList += '--word-reference' }
if ($QmlProfile) {
    $env:LISTENFREE_LYRIC_QML_PROFILE = '1'
    $options.FilePath = Join-Path $QtRoot 'bin/qmlprofiler.exe'
    $options.ArgumentList = @('--include','binding,javascript,creating,compiling','--output','profile.qtd',(Join-Path $fixture ($target+'.exe')))
} else { [Environment]::SetEnvironmentVariable('LISTENFREE_LYRIC_QML_PROFILE',$null) }
$process = Start-Process @options
if ($AffinityMask -gt 0) { $process.ProcessorAffinity = [IntPtr]$AffinityMask }
$timeout = if ($Mode -eq 'capture') { 120 } else { 45 }
$deadline = [DateTime]::UtcNow.AddSeconds($timeout)
while (-not $process.WaitForExit(1000)) {
    if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw "Lyrics checks exceeded $timeout seconds" }
}
$result = if ($Mode -eq 'regression') { 'result.txt' } elseif ($Mode -eq 'capture') { 'motion.json' } else { 'result.json' }
if ($process.ExitCode -ne 0) {
    Get-Content (Join-Path $fixture 'runtime.log')
    if ($Mode -eq 'regression' -and (Test-Path (Join-Path $fixture $result))) { Get-Content (Join-Path $fixture $result) }
    throw "Lyrics checks failed: $($process.ExitCode)"
}
Get-Content (Join-Path $fixture $result)
