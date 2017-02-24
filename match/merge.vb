Sub MergeTool()
'
' MergeTool Macro
'

'

    Dim iRow As Long
    Dim total As String
    Dim iceMatch As String
    Dim t As Long
    Dim i As Long

    iRow = 1

    Do Until IsEmpty(Cells(iRow, 3))
    
        total = Cells(iRow, 3).Value
        iceMatch = Cells(iRow, 4).Value

        If IsNumeric(total) Then
            t = CLng(total)
            i = CLng(iceMatch)
            
            If t = i Then
                Rows(CStr(iRow) & ":" & CStr(iRow)).Select
                Selection.Delete Shift:=xlUp
                GoTo ContinueLoop
            Else
                Cells(iRow, 3).Value = CStr(t - i)
                Cells(iRow, 4).Value = "0"
            End If
            
        End If

        iRow = iRow + 1
ContinueLoop:
    Loop

    MsgBox "Finished"
    
End Sub
