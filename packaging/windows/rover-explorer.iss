; Inno Setup script for Rover Explorer (Dhiva Labs)
;
; Build the app first:
;   flutter build windows --release
; then compile this script with Inno Setup 6:
;   iscc packaging\windows\rover-explorer.iss
;
; Output: dist\RoverExplorer-<version>-setup.exe

#define AppName        "Rover Explorer"
#define AppVersion     "1.0.0"
#define AppPublisher   "Dhiva Labs"
#define AppURL         "https://github.com/Dhiva-Labs/rover_explorer"
#define AppExeName     "rover_explorer.exe"
#define BuildDir       "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{8F2C5B41-9D3A-4E77-B6C2-1A9F4D7E2C08}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir=..\..\dist
OutputBaseFilename=RoverExplorer-{#AppVersion}-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll";         DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*";        DestDir: "{app}\data"; \
  Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE";             DestDir: "{app}"; DestName: "LICENSE.txt"; \
  Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";            Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}";  Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";      Filename: "{app}\{#AppExeName}"; \
  Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
  Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent
