# B1 resume, then the remaining cases; detached from the Claude shell so it survives that shell being stopped
Set-Location $PSScriptRoot
& .\resume-case.ps1 -Tag B1-standard-user *>> results\night-log-3.txt
& .\night.ps1 -Cases F1,H1,E1,K1,J1,J2,C1,C2 *>> results\night-log-3.txt
'########## all done ' + (Get-Date -Format HH:mm) | Add-Content results\night-log-3.txt
