. "$PSScriptRoot\vmlib.ps1"
VM-Restore 'fresh-windows'; VM-Start
"GA ready: " + (Wait-GA)
$spw = Pw student
G @"
`$w = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty `$w AutoAdminLogon '1'; Set-ItemProperty `$w DefaultUserName 'student'; Set-ItemProperty `$w DefaultPassword '$spw'; Set-ItemProperty `$w DefaultDomainName 'MSTEST'
New-Item -Force 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' DisablePrivacyExperience 1 -Type DWord
New-Item -Force 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' EnableFirstLogonAnimation 0 -Type DWord
powercfg -change standby-timeout-ac 0; powercfg -change monitor-timeout-ac 0
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType Disabled
Write-Output 'prep done'
"@
G 'Restart-Computer -Force' | Out-Null
Start-Sleep 30
"student logged in: " + (Wait-Login 'student' 900)
Start-Sleep 240
G 'whoami; Get-Command winget -ErrorAction SilentlyContinue | % Source; try { winget --version } catch { "winget error $_" }; $env:LOCALAPPDATA; Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"' 'student'
Shot 'student-ready'
