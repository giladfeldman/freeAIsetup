# Queue 5 (2026-11-08, zip 2026.11.8.2): the auto-update case first, then the rest by importance for the class.
Set-Location $PSScriptRoot
& .\night.ps1 -Cases U1,B1,F1,K1,J1,J2,H1,C1,C2 *>> results\night-log-5.txt
'########## all done ' + (Get-Date -Format HH:mm) | Add-Content results\night-log-5.txt
