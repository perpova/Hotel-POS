' ============================================================
'  Hotel POS - Silent Background Backend Server Launcher
' ============================================================
Dim fso, wshShell, scriptDir

Set fso = CreateObject("Scripting.FileSystemObject")
Set wshShell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Run node server.js in hidden background window (0 = SW_HIDE)
wshShell.Run "cmd /c cd /d """ & scriptDir & """ && node server.js", 0, False
