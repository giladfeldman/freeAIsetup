# Host side: run one test case in the VM.  run-case.ps1 -Tag A1 -Snapshot student-ready -Prep {...} -User student
param(
  [string]$Tag, [string]$Snapshot = 'student-ready2', [string]$User = 'student',
  [string]$AdminPrep = '',          # PowerShell run as vmadmin before the run (may set things up)
  [switch]$Reboot,                  # reboot after AdminPrep (e.g. new autologon user, locale change)
  [string]$SetupArgs = '-Yes', [string]$Extract = '%USERPROFILE%\Downloads\metascience-setup',
  [switch]$NoExtract, [string]$CmdPath = '', [switch]$Motw,
  [int]$MaxMin = 180,   # a full install takes up to ~2 h on one virtual CPU
  [string]$During = '',             # host-side PowerShell scriptblock text run once, $DuringAfterMin minutes into the run
  [int]$DuringAfterMin = 6,
  [switch]$KeepRunning,             # do not power off at the end (to chain another run)
  [string]$NewUser = '',            # create this account (student's password), log it in automatically, run the setup as it
  [switch]$NewUserAdmin,            # ... as a member of Administrators (typical own laptop)
  [string]$Locale = '',             # e.g. de-AT or zh-HK: system locale (non-Unicode programs) + the user's formats
  [string]$UserPrep = ''            # PowerShell run as the test user (non-interactive) just before the setup
)
. "$PSScriptRoot\vmlib.ps1"
$res = Join-Path $Results $Tag
if (Test-Path -LiteralPath $res) { $old = "$res-" + (Get-Date -Format HHmm); Rename-Item -LiteralPath $res -NewName (Split-Path -Leaf $old) -ErrorAction SilentlyContinue }   # keep an earlier run of the same case
New-Item -ItemType Directory -Force $res | Out-Null
function Note($t) { $l = (Get-Date -Format HH:mm:ss) + " [$Tag] $t"; Write-Output $l; Add-Content -LiteralPath (Join-Path $res 'host.txt') -Value $l }
if ($Snapshot) { Note (VM-Restore $Snapshot); VM-Start }
elseif ((VMState) -ne 'running') { VM-Start }
function Ensure-GA($what) {
  # the guest-control link sometimes fails after a start (VERR_DUPLICATE, "not ready"): power-cycle once, then give up
  $ok = Wait-GA; Note "$what GA ready: $ok"
  if (-not $ok) { Note (VM-Cycle); $ok = Wait-GA; Note "$what GA ready after power-cycle: $ok" }
  if (-not $ok) { Note 'BLOCKED: the VM cannot be controlled (guest additions not ready); case skipped'; Shot "$Tag-blocked"; VM-Stop; exit 2 }
}
Ensure-GA 'start'
if ($NewUser) {
  $User = $NewUser; $Reboot = $true
  $grp = if ($NewUserAdmin) { 'Administrators' } else { 'Users' }
  $AdminPrep = @"
`$pw = ConvertTo-SecureString '$(Pw student)' -AsPlainText -Force
New-LocalUser -Name '$NewUser' -Password `$pw -PasswordNeverExpires | Out-Null
Add-LocalGroupMember -Group Users -Member '$NewUser' -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group $grp -Member '$NewUser' -ErrorAction SilentlyContinue
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' DefaultUserName '$NewUser'
(Get-LocalGroupMember $grp).Name
"@ + "`n" + $AdminPrep
}
if ($Locale) { $Reboot = $true; $AdminPrep += "`nSet-WinSystemLocale $Locale; Get-WinSystemLocale | % Name" }
if ($AdminPrep) { Note 'admin prep'; GA $AdminPrep 1200 | ForEach-Object { Note "  prep> $_" } }
if ($Reboot) { Note (VM-Cycle); Ensure-GA 'after reboot' }
$li = Wait-Login $User 900; Note "login $User : $li"
if (-not $li) { Note 'BLOCKED: the test user never logged in; case skipped'; Shot "$Tag-blocked"; VM-Stop; exit 2 }
Start-Sleep 20
if ($Locale) { G "Set-Culture $Locale; (Get-Culture).Name; 1234.5.ToString()" $User | ForEach-Object { Note "  culture> $_" } }
$cfg = @{ tag = $Tag; args = $SetupArgs; extract = $Extract; extractZip = (-not $NoExtract); cmdPath = $CmdPath; motw = [bool]$Motw } | ConvertTo-Json
$cf = Join-Path $env:TEMP 'case.json'; [IO.File]::WriteAllText($cf, $cfg)
Copy-In $cf 'C:\Users\Public\mstest' | Out-Null
Copy-In (Join-Path $PSScriptRoot 'runner.ps1') 'C:\Users\Public\mstest' | Out-Null
Copy-In (Join-Path (Split-Path -Parent $Kit) 'metascience-setup.zip') 'C:\Users\Public\mstest' | Out-Null
if ($UserPrep) { G $UserPrep $User 600 | ForEach-Object { Note "  userprep> $_" } }
# check in a NEW session: the session that changes culture or folders keeps showing the old values
if ($Locale -or $UserPrep) { G "'culture ' + (Get-Culture).Name + ' ' + (1234.5).ToString() + ' | docs ' + [Environment]::GetFolderPath('MyDocuments')" $User 60 | ForEach-Object { Note "  verified> $_" } }
GA @"
`$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -EncodedCommand $(Enc-Boot 'C:\Users\Public\mstest\runner.ps1')'
`$pr = New-ScheduledTaskPrincipal -UserId '$User' -LogonType Interactive
Register-ScheduledTask -TaskName 'mstest-$Tag' -Action `$a -Principal `$pr -Force | Out-Null
Start-ScheduledTask -TaskName 'mstest-$Tag'; 'task started'
"@ | ForEach-Object { Note "  $_" }
$t0 = Get-Date; $didDuring = $false; $done = $false
while (((Get-Date) - $t0).TotalMinutes -lt $MaxMin) {
  Start-Sleep 30
  if ($During -and -not $didDuring -and ((Get-Date) - $t0).TotalMinutes -ge $DuringAfterMin) { Note 'DURING action'; & ([scriptblock]::Create($During)) | ForEach-Object { Note "  during> $_" }; $didDuring = $true }
  if ((Get-PSDrive C).Free / 1GB -lt 4) { Note 'HOST DISK BELOW 4 GB - stopping the VM'; Shot "$Tag-diskstop"; break }
  $r = G "Test-Path 'C:\Users\Public\mstest\out\$Tag\DONE'" 'vmadmin' 60
  if ($r -match 'True') { $done = $true; break }
  if ([int]((Get-Date) - $t0).TotalMinutes % 10 -eq 0) {
    Shot "$Tag-progress"
    # progress line from the student's own setup log, so the watcher sees real progress (or a real stall)
    $p = GA "`$f = Get-ChildItem 'C:\Users\*\AppData\Local\Temp\metascience-setup-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1; if (`$f) { 'log ' + `$f.LastWriteTime.ToString('HH:mm') + ': ' + ((Get-Content `$f.FullName -Tail 1) -replace '\s+', ' ') }" 2>$null
    $p | Where-Object { $_ -match '^log ' } | Select-Object -First 1 | ForEach-Object { Note "  progress> $_" }
  }
}
Note "finished: $done after $([math]::Round(((Get-Date) - $t0).TotalMinutes,1)) min"
Shot "$Tag-end"
if (-not $done) {   # timed out: the runner never copied the logs, so fetch the setup logs of every account directly
  GA "New-Item -ItemType Directory -Force 'C:\Users\Public\mstest\out\$Tag' | Out-Null; Get-ChildItem -Path 'C:\Users\*\AppData\Local\Temp\metascience-setup-*.log' -ErrorAction SilentlyContinue | Copy-Item -Destination 'C:\Users\Public\mstest\out\$Tag' -PassThru | ForEach-Object Name" | ForEach-Object { Note "  rescued log> $_" }
}
Copy-Out "C:\Users\Public\mstest\out\$Tag" $Results | Out-Null
$rep = Join-Path $res 'setup-report.txt'
if (Test-Path $rep) { Note 'report:'; Get-Content $rep | ForEach-Object { Note "  $_" } }
Get-Content (Join-Path $res 'runner.txt') -ErrorAction SilentlyContinue | ForEach-Object { Note "  runner> $_" }
Select-String -Path (Join-Path $res 'console.txt') -Pattern 'FAIL|WARN|All done|Something needs' -ErrorAction SilentlyContinue | ForEach-Object { Note "  console> $($_.Line.Trim())" }
if (-not $KeepRunning) { VM-Stop }
