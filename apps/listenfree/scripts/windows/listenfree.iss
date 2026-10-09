#ifndef StageDir
  #error StageDir is required
#endif
#ifndef ReleaseVersion
  #define ReleaseVersion "0.3.8"
#endif
[Setup]
AppId={{C9DFBE62-EA54-44D9-AE71-378F2715325D}
AppName=ListenFree
AppVersion={#ReleaseVersion}
AppPublisher=ListenFree
DefaultDirName={localappdata}\Programs\ListenFree
DefaultGroupName=ListenFree
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ListenFree-{#ReleaseVersion}-windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\music_player_desktop\assets\icons\app.ico
UninstallDisplayIcon={app}\listenfree.exe
CloseApplications=yes
RestartApplications=no
DisableProgramGroupPage=yes
Uninstallable=not IsPortable
CreateUninstallRegKey=not IsPortable
UsePreviousAppDir=not IsPortable

[Languages]
Name: chinesesimplified; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: desktopicon; Description: "创建桌面快捷方式"; Flags: unchecked; Check: not IsPortable

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Excludes: "portable.mode"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\portable.mode"; DestDir: "{app}"; Flags: ignoreversion; Check: IsPortable

[Icons]
Name: "{group}\ListenFree"; Filename: "{app}\listenfree.exe"; WorkingDir: "{app}"; AppUserModelID: "ListenFree.Desktop"; Check: not IsPortable
Name: "{autodesktop}\ListenFree"; Filename: "{app}\listenfree.exe"; WorkingDir: "{app}"; AppUserModelID: "ListenFree.Desktop"; Tasks: desktopicon; Check: not IsPortable

[Run]
Filename: "{app}\listenfree.exe"; Description: "启动 ListenFree"; Flags: nowait postinstall skipifsilent

; Uninstall removes only installed files. User databases and credentials are
; managed by the application and deliberately absent from the installer.
[Code]
function IsPortable: Boolean;
begin
  Result := ExpandConstant('{param:PORTABLE|0}') = '1';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpSelectDir) and (ExpandConstant('{param:UPDATE|0}') = '1');
end;
