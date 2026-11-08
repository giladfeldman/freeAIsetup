# Queue 4 (2026-11-08 evening, zip 2026.11.8.1): Innsbruck case first, then the rest by importance for the class.
# Detached from the Claude shell so it survives that shell being stopped.
Set-Location $PSScriptRoot
& .\night.ps1 -Cases E1,B1,F1,K1,J1,J2,H1,C1,C2 *>> results\night-log-4.txt
'########## all done ' + (Get-Date -Format HH:mm) | Add-Content results\night-log-4.txt
