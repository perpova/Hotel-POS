; ============================================================
;  Hotel POS  -  Inno Setup Installer Script
;  Tool: Inno Setup 6  (https://jrsoftware.org/isinfo.php)
;
;  HOW TO USE:
;    1. Install Inno Setup 6 from https://jrsoftware.org/isdl.php
;    2. Build the Flutter app:  flutter build windows --release
;    3. Open THIS file in Inno Setup Compiler and click Build > Compile
;    4. The finished Setup.exe will be saved in:
;       e:\Perpova\hotel-pos\app\installer\Output\
; ============================================================

#define AppName      "Hotel POS"
#define AppVersion   "1.0.0"
#define AppPublisher "Perpova"
#define AppURL       "https://github.com/Perpova/hotel-pos"
#define AppExeName   "hotel_pos.exe"
#define SourceDir    "..\build\windows\x64\runner\Release"
#define OutputDir    "Output"

[Setup]
; ── Identity ──────────────────────────────────────────────
AppId={{B3A1E2C4-7F9D-4E8B-A123-0F2D5C6E7B8A}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}/releases

; ── Install location ───────────────────────────────────────
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin

; ── Output ────────────────────────────────────────────────
OutputDir={#OutputDir}
OutputBaseFilename=HotelPOS_Setup_v{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico

; ── Compression ───────────────────────────────────────────
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes

; ── Appearance ────────────────────────────────────────────
WizardStyle=modern
WizardResizable=no

; ── Misc ──────────────────────────────────────────────────
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Installer
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";    Description: "Create a &desktop shortcut";         GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startmenuicon";  Description: "Create a &Start Menu shortcut";      GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Files]
; ── All files from the Flutter Windows Release build ──────
Source: "{#SourceDir}\{#AppExeName}";    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll";            DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\data\*";           DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; ── Start Menu shortcut ───────────────────────────────────
Name: "{group}\{#AppName}";             Filename: "{app}\{#AppExeName}"; Tasks: startmenuicon
Name: "{group}\Uninstall {#AppName}";   Filename: "{uninstallexe}"

; ── Desktop shortcut ─────────────────────────────────────
Name: "{autodesktop}\{#AppName}";       Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; ── Launch after install ──────────────────────────────────
Filename: "{app}\{#AppExeName}"; \
    Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; ── Clean up app data on uninstall (optional) ─────────────
Type: filesandordirs; Name: "{app}"
