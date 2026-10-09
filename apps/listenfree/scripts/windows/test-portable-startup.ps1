param(
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [string]$DataDirectory
)
$ErrorActionPreference='Stop'
$package=(Resolve-Path -LiteralPath $PackageRoot).Path
$executable=Join-Path $package 'listenfree.exe'
if(!(Test-Path -LiteralPath (Join-Path $package 'imageformats\qwebp.dll'))) {
    throw '便携包缺少 WebP 图片解码插件，咪咕等平台的歌曲封面无法显示。'
}
$names=@('PATH','QT_PLUGIN_PATH','QML2_IMPORT_PATH','QML_IMPORT_PATH','QT_QPA_PLATFORM_PLUGIN_PATH','QMMP_PLUGINS')
$previous=@{}
foreach($name in $names) { $previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
try {
    # No SDK paths: a portable package must carry its own Qt/Qmmp dependencies.
    $env:PATH="$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
    foreach($name in $names | Where-Object { $_ -ne 'PATH' }) {
        [Environment]::SetEnvironmentVariable($name,$null,'Process')
    }
    $arguments=@('--portable-smoke')
    if($DataDirectory) { $arguments+=@('--data-dir',('"'+[IO.Path]::GetFullPath($DataDirectory)+'"')) }
    # Without -DataDirectory this deliberately exercises the shipped data profile,
    # including upgrade compatibility, instead of checking only an empty database.
    $process=Start-Process -FilePath $executable -WorkingDirectory $package -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if(-not $process.WaitForExit(15000)) {
        $process.Kill()
        throw '便携版启动检查超时。'
    }
    if($process.ExitCode -ne 0) { throw "便携版启动失败，退出码：$($process.ExitCode)" }
    Write-Output '便携版启动通过：独立依赖路径、数据打开与升级、Qt 界面加载均成功。'
} finally {
    foreach($name in $names) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
}
