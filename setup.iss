; ==================================================
#define AppVersion "1.0.0"
#define BuildNumber "2"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppId=MaidKit
AppMutex=dev.solsynth.server_manager.single_instance
CloseApplications=yes
AppName=Server Manager
AppVersion={#AppVersion}
AppPublisher=dev.solsynth
AppPublisherURL=https://solsynth.dev
AppUpdatesURL=https://github.com/Wind134/MaidKit/releases
AppCopyright=Copyright © 2026 dev.solsynth
VersionInfoVersion={#FullVersion}
UninstallDisplayName=Server Manager
UninstallDisplayIcon={app}\server_manager.exe

DefaultDirName={commonpf}\Server Manager
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
Name: "{group}\Server Manager"; Filename: "{app}\server_manager.exe"; IconFilename: "{app}\server_manager.exe"
Name: "{group}\{cm:UninstallProgram,Server Manager}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Server Manager"; Filename: "{app}\server_manager.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\server_manager.exe"; Description: "Launch Server Manager"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\dev.solsynth\Server Manager"
Type: files; Name: "{group}\Server Manager.lnk"
Type: files; Name: "{autodesktop}\Server Manager.lnk"
