[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Version,
    [string]$SigningKeyFile=(Join-Path $env:LOCALAPPDATA 'ListenFree\ReleaseSigning\winsparkle-private.key'),
    [string]$WinSparkleTool='',
    [string]$OutputFile='',
    [string]$ReleaseNotes=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Only stable numeric releases are supported by this feed' }
$installerFile=Get-Item -LiteralPath $Installer
if ($installerFile.Name -ne "ListenFree-$Version-windows-x64-Setup.exe") { throw 'Installer name/version mismatch' }
if (!$WinSparkleTool) { $WinSparkleTool=Join-Path $source '..\_vendor\winsparkle-0.9.4\WinSparkle-0.9.4\bin\winsparkle-tool.exe' }
if (!$OutputFile) { $OutputFile=Join-Path $installerFile.DirectoryName 'appcast.xml' }
if (!(Test-Path -LiteralPath $SigningKeyFile -PathType Leaf)) { throw 'Signing key is missing. Restore the original private key; do not generate a replacement for an existing release channel.' }
$keyPath=[IO.Path]::GetFullPath($SigningKeyFile)
if ($keyPath.StartsWith($source.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'The signing key must be stored outside the source tree' }
$publicHeader=Get-Content -LiteralPath (Join-Path $source 'src\app\update_public_key.h') -Raw
$publicKey=[regex]::Match($publicHeader,'kUpdatePublicKey\[\]\s*=\s*"([A-Za-z0-9+/=]+)"').Groups[1].Value
if (!$publicKey) { throw 'Missing embedded verification key' }
$keyInfo=& $WinSparkleTool public-key --private-key-file $keyPath
if ($LASTEXITCODE -ne 0 -or !($keyInfo -match [regex]::Escape("Public key: $publicKey"))) { throw 'Signing key does not match the public key embedded in this release' }
$signature=(& $WinSparkleTool sign --private-key-file $keyPath $installerFile.FullName | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $signature -notmatch '^[A-Za-z0-9+/]{86}==$') { throw 'Update signing failed' }
& $WinSparkleTool verify --public-key $publicKey --signature $signature $installerFile.FullName
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
$notes=if($ReleaseNotes){Get-Content -LiteralPath $ReleaseNotes -Raw -Encoding utf8}else{"ListenFree $Version"}
$settings=[Xml.XmlWriterSettings]::new()
$settings.Indent=$true
$settings.Encoding=[Text.UTF8Encoding]::new($false)
$writer=[Xml.XmlWriter]::Create([IO.Path]::GetFullPath($OutputFile),$settings)
$ns='http://www.andymatuschak.org/xml-namespaces/sparkle'
try {
    $writer.WriteStartDocument()
    $writer.WriteStartElement('rss')
    $writer.WriteAttributeString('version','2.0')
    $writer.WriteAttributeString('xmlns','sparkle',$null,$ns)
    $writer.WriteStartElement('channel')
    $writer.WriteElementString('title','ListenFree Windows 更新')
    $writer.WriteElementString('language','zh-cn')
    $writer.WriteStartElement('item')
    $writer.WriteElementString('title',"ListenFree $Version")
    $writer.WriteElementString('sparkle','version',$ns,$Version)
    $writer.WriteElementString('pubDate',[DateTime]::UtcNow.ToString('r',[Globalization.CultureInfo]::InvariantCulture))
    $writer.WriteStartElement('description')
    $writer.WriteCData('<p>'+[Net.WebUtility]::HtmlEncode($notes).Replace("`r`n","`n").Replace("`n",'<br>')+'</p>')
    $writer.WriteEndElement()
    $writer.WriteStartElement('enclosure')
    $writer.WriteAttributeString('url',"https://github.com/Tabris-Ayanami/ListenFree-desktop/releases/download/v$Version/$($installerFile.Name)")
    $writer.WriteAttributeString('length',$installerFile.Length.ToString([Globalization.CultureInfo]::InvariantCulture))
    $writer.WriteAttributeString('type','application/octet-stream')
    $writer.WriteAttributeString('sparkle','os',$ns,'windows-x64')
    $writer.WriteAttributeString('sparkle','edSignature',$ns,$signature)
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndDocument()
} finally { $writer.Dispose() }
Write-Output "已签名的更新信息：$OutputFile"
