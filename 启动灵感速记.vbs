Option Explicit
' Silent launcher for the inspiration note app.
' Finds the .ps1 file next to this script and starts it without a console window.
Dim fso, sh, folder, f, scriptPath, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set folder = fso.GetFolder(fso.GetParentFolderName(WScript.ScriptFullName))
scriptPath = ""
For Each f In folder.Files
    If LCase(fso.GetExtensionName(f.Name)) = "ps1" Then
        scriptPath = f.Path
        Exit For
    End If
Next
If scriptPath = "" Then
    MsgBox "Cannot find the .ps1 application file.", 16, "Lingan"
    WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """"
sh.Run cmd, 0, False
