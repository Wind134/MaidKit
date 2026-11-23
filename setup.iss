; ==================================================
#define AppVersion "1.0.0"
#define BuildNumber "2"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=server_manager
AppVersion={#AppVersion}
AppPublisher=dev.solsynth
AppPublisherURL=https://solsynth.dev
AppUpdatesURL=https://github.com/Wind134/MaidKit/releases
AppCopyright=Copyright © 2026 dev.solsynth
VersionInfoVersion={#FullVersion}
UninstallDisplayName=server_manager
UninstallDisplayIcon={app}\server_manager.exe

DefaultDirName={commonpf}\server_manager
UsePreviousAppDir=no

OutputDir=.\Installer
OutputBaseFilename=server_manager_{#AppVersion}
SetupIconFile=.\assets\icons\icon.ico

Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin

[Files]
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\server_manager"; Filename: "{app}\server_manager.exe"; IconFilename: "{app}\server_manager.exe"
Name: "{group}\{cm:UninstallProgram,server_manager}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\server_manager"; Filename: "{app}\server_manager.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\server_manager.exe"; Description: "Launch server_manager"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\dev.solsynth\server_manager"
Type: files; Name: "{group}\server_manager.lnk"
Type: files; Name: "{autodesktop}\server_manager.lnk"
