# Queue 6 (2026-11-08 evening, zip 2026.11.8.4): Innsbruck case again, then the rest (U1 auto-update already passed in queue 5).
Set-Location $PSScriptRoot
& .\night.ps1 -Cases E1,B1,F1,K1,J1,J2,H1,C1,C2 *>> results\night-log-6.txt
'########## all done ' + (Get-Date -Format HH:mm) | Add-Content results\night-log-6.txt
