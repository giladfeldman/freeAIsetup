# Queue 7 (2026-11-08 night, zip 2026.11.8.4): the remaining edge cases after the Innsbruck case passed.
Set-Location $PSScriptRoot
& .\night.ps1 -Cases B1,F1,K1,J1,J2,H1,C1,C2 *>> results\night-log-7.txt
'########## all done ' + (Get-Date -Format HH:mm) | Add-Content results\night-log-7.txt
