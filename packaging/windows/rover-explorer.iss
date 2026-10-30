; Inno Setup script for Rover Explorer (Dhiva Labs)
;
; Build the app first:
;   flutter build windows --release
; then compile this script with Inno Setup 6.3 or newer:
;   iscc packaging\windows\rover-explorer.iss
;
; Output: dist\RoverExplorer-<version>-setup.exe
;
; For Windows on ARM, build on an ARM64 machine and compile with /DArch=arm64:
;   iscc /DArch=arm64 packaging\windows\rover-explorer.iss
; Output: dist\RoverExplorer-<version>-arm64-setup.exe, which installs only on
; ARM64 Windows. /DAppVersion=<version> overrides the version below.

#ifndef Arch
  #define Arch "x64"
#endif
#ifndef AppVersion
  #define AppVersion   "1.0.1"
#endif

#if Arch == "arm64"
  #define ArchSuffix   "-arm64"
  #define InstallArch  "arm64"
#elif Arch == "x64"
  #define ArchSuffix   ""
  ; x64compatible also lets the x64 build run on ARM64 Windows by emulation.
  #define InstallArch  "x64compatible"
#else
  #error Arch must be x64 or arm64
#endif

#define AppName        "Rover Explorer"
#define AppPublisher   "Dhiva Labs"
#define AppURL         "https://github.com/Dhiva-Labs/rover_explorer"
#define AppExeName     "rover_explorer.exe"
#define BuildDir       "..\..\build\windows\" + Arch + "\runner\Release"

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
OutputBaseFilename=RoverExplorer-{#AppVersion}{#ArchSuffix}-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed={#InstallArch}
ArchitecturesInstallIn64BitMode={#InstallArch}
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
