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
Source: "..\..\server\*";                DestDir: "{app}\server"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "node_modules\*, .git\*"

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

[Code]
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
            DirExists('C:\ProgramData\MySQL') or
            FileExists('C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Server 9.0\bin\mysql.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Workbench 8.0 CE\MySQLWorkbench.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Workbench 8.0\MySQLWorkbench.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Workbench 8.4 CE\MySQLWorkbench.exe') or
            FileExists('C:\Program Files\MySQL\MySQL Workbench 9.0 CE\MySQLWorkbench.exe');
end;

// ── Check MySQL status before setup begins ────────────────────────────────────
function InitializeSetup(): Boolean;
begin
  Result := True;
  if not IsMySQLInstalled() then
  begin
    if MsgBox('MySQL Server / MySQL Workbench was not detected on this computer.' + #13#10 + #13#10 +
              'Hotel POS requires MySQL to store orders, products, customers, and sales reports.' + #13#10 + #13#10 +
              'Please install MySQL Workbench or MySQL Server before running Hotel POS.' + #13#10 + #13#10 +
              'Do you want to continue installing Hotel POS anyway?',
              mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
    end;
  end;
end;

// ── Find installed mysql.exe path ─────────────────────────────────────────────
function FindMySqlExe(): String;
var
  Paths: Array of String;
  I: Integer;
begin
  SetArrayLength(Paths, 10);
  Paths[0] := 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe';
  Paths[1] := 'C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe';
  Paths[2] := 'C:\Program Files\MySQL\MySQL Server 9.0\bin\mysql.exe';
  Paths[3] := 'C:\Program Files\MySQL\MySQL Server 8.1\bin\mysql.exe';
  Paths[4] := 'C:\Program Files\MySQL\MySQL Server 8.2\bin\mysql.exe';
  Paths[5] := 'C:\Program Files\MySQL\MySQL Server 8.3\bin\mysql.exe';
  Paths[6] := 'C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe';
  Paths[7] := 'C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysql.exe';
  Paths[8] := 'C:\Program Files (x86)\MySQL\MySQL Server 8.4\bin\mysql.exe';
  Paths[9] := 'C:\Program Files (x86)\MySQL\MySQL Server 5.7\bin\mysql.exe';

  for I := 0 to 9 do
  begin
    if FileExists(Paths[I]) then
    begin
      Result := Paths[I];
      Exit;
    end;
  end;

  Result := 'mysql.exe';
end;

// ── Automatically Create Database and Tables after installation ───────────────
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PsScriptPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    PsScriptPath := ExpandConstant('{app}\server\init_db.ps1');
    if FileExists(PsScriptPath) then
    begin
      Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + PsScriptPath + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
