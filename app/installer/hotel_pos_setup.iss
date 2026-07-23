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
Name: "desktopicon";       Description: "Create a &desktop shortcut";                             GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startmenuicon";     Description: "Create a &Start Menu shortcut";                          GroupDescription: "Additional shortcuts:"; Flags: checkedonce
Name: "installnode";       Description: "Download and Install Node.js v20 LTS (Required for Server)"; GroupDescription: "Prerequisites & Environment Setup:"; Check: not IsNodeInstalled; Flags: checkedonce
Name: "installmysql";      Description: "Download and Install MySQL Server 8.0 (Required for Database)"; GroupDescription: "Prerequisites & Environment Setup:"; Check: not IsMySQLInstalled; Flags: checkedonce
Name: "autostartserver";   Description: "Automatically start Backend Server on Windows Boot"; GroupDescription: "Background Services:"; Flags: checkedonce

[Files]
; ── All files from the Flutter Windows Release build ──────
Source: "{#SourceDir}\{#AppExeName}";    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll";            DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\data\*";           DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\server\*";                DestDir: "{app}\server"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "node_modules\*, .git\*"

[Registry]
; ── Auto-start Backend Server silently on Windows Startup ──
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "HotelPOSBackendServer"; ValueData: "wscript.exe ""{app}\server\start_server.vbs"""; Tasks: autostartserver; Flags: uninsdeletevalue

[Icons]
; ── Start Menu shortcut ───────────────────────────────────
Name: "{group}\{#AppName}";             Filename: "{app}\{#AppExeName}"; Tasks: startmenuicon
Name: "{group}\Uninstall {#AppName}";   Filename: "{uninstallexe}"

; ── Desktop shortcut ─────────────────────────────────────
Name: "{autodesktop}\{#AppName}";       Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; ── Start Server silently right after setup ───────────────
Filename: "wscript.exe"; Parameters: """{app}\server\start_server.vbs"""; Flags: runhidden nowait

; ── Launch Flutter POS app post-install ──────────────────
Filename: "{app}\{#AppExeName}"; \
    Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; ── Clean up app directory on uninstall ───────────
Type: filesandordirs; Name: "{app}"

[Code]
// ── Helper: Check if Node.js is installed ────────────────────────────────────
function IsNodeInstalled(): Boolean;
begin
  Result := RegKeyExists(HKLM, 'SOFTWARE\Node.js') or
            RegKeyExists(HKLM64, 'SOFTWARE\Node.js') or
            RegKeyExists(HKLM, 'SOFTWARE\WOW6432Node\Node.js') or
            FileExists('C:\Program Files\nodejs\node.exe') or
            FileExists('C:\Program Files (x86)\nodejs\node.exe');
end;

// ── Helper: Check if MySQL / MySQL Workbench is installed ─────────────────────
function IsMySQLInstalled(): Boolean;
begin
  Result := RegKeyExists(HKLM, 'SOFTWARE\MySQL AB') or
            RegKeyExists(HKLM64, 'SOFTWARE\MySQL AB') or
            RegKeyExists(HKLM, 'SOFTWARE\WOW6432Node\MySQL AB') or
            RegKeyExists(HKLM, 'SOFTWARE\MySQL Server') or
            RegKeyExists(HKLM64, 'SOFTWARE\MySQL Server') or
            RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\MySQL') or
            RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\MySQL') or
            RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\MySQL80') or
            RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\MySQL80') or
            RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\MySQL84') or
            RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\MySQL84') or
            RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\MySQL90') or
            RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\MySQL90') or
            RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\MySQL57') or
            RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\MySQL57') or
            DirExists('C:\Program Files\MySQL') or
            DirExists('C:\Program Files (x86)\MySQL') or
            DirExists('C:\ProgramData\MySQL');
end;

// ── Check prerequisites before setup begins ──────────────────────────────────
function InitializeSetup(): Boolean;
begin
  Result := True;
end;

// ── Perform silent post-install configuration & DB initialization ────────────
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ServerDir: String;
  PsScriptPath: String;
  PrereqScriptPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    ServerDir := ExpandConstant('{app}\server');
    PsScriptPath := ExpandConstant('{app}\server\init_db.ps1');
    PrereqScriptPath := ExpandConstant('{app}\server\install_prereqs.ps1');

    // 1. Download & Install Selected Prerequisites (Node.js / MySQL)
    if WizardIsTaskSelected('installnode') and WizardIsTaskSelected('installmysql') then
    begin
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + PrereqScriptPath + '" -InstallNode -InstallMySQL', ServerDir, SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode);
    end
    else if WizardIsTaskSelected('installnode') then
    begin
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + PrereqScriptPath + '" -InstallNode', ServerDir, SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode);
    end
    else if WizardIsTaskSelected('installmysql') then
    begin
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + PrereqScriptPath + '" -InstallMySQL', ServerDir, SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode);
    end;

    // 2. Silently install Node dependencies (express, mysql2, ws, etc.)
    Exec('cmd.exe', '/c cd /d "' + ServerDir + '" && npm install --omit=dev', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // 3. Silently initialize MySQL database schema if MySQL is present
    if FileExists(PsScriptPath) then
    begin
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + PsScriptPath + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;

    // 4. Start Backend Server silently in background via VBScript
    Exec('wscript.exe', '"' + ServerDir + '\start_server.vbs"', ServerDir, SW_HIDE, ewNoWait, ResultCode);
  end;
end;
