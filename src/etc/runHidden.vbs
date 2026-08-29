' Method provided by Tobias J by https://superuser.com/questions/140047/how-to-run-a-batch-file-without-launching-a-command-window
Function QuoteArg(ByVal Arg)
    Dim Result, Slashes, I, Ch
    Result = Chr(34)
    Slashes = 0

    For I = 1 To Len(Arg)
        Ch = Mid(Arg, I, 1)
        If Ch = Chr(92) Then
            Slashes = Slashes + 1
        ElseIf Ch = Chr(34) Then
            Result = Result & String(Slashes * 2 + 1, Chr(92)) & Chr(34)
            Slashes = 0
        Else
            If Slashes > 0 Then Result = Result & String(Slashes, Chr(92))
            Result = Result & Ch
            Slashes = 0
        End If
    Next

    If Slashes > 0 Then Result = Result & String(Slashes * 2, Chr(92))
    QuoteArg = Result & Chr(34)
End Function

If WScript.Arguments.Count >= 1 Then
    ReDim arr(WScript.Arguments.Count-1)
    For i = 0 To WScript.Arguments.Count-1
        Arg = WScript.Arguments(i)
        arr(i) = QuoteArg(Arg)
    Next

    RunCmd = Join(arr)
    Set Wmi = GetObject("winmgmts:\\.\root\cimv2")
    Set Startup = Wmi.Get("Win32_ProcessStartup").SpawnInstance_
    Startup.ShowWindow = 0
    Set Process = Wmi.Get("Win32_Process")
    Result = Process.Create(RunCmd, Null, Startup, ProcessId)
    If Result <> 0 Then WScript.Quit Result

    Do
        Set Running = Wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE ProcessId = " & ProcessId)
        If Running.Count = 0 Then Exit Do
        WScript.Sleep 100
    Loop
End If