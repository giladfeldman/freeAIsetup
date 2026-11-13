# Host side: a real install on a fresh Windows VM, then the install record and the uninstall (d-859431), and the
# disk space of each part (d-d30643). Results in tests\vm\results\<Tag>\ (host.txt, measure-*.txt, uninstall-*.txt).
#   $env:MSVM_ACCOUNTS = "<path to vm-test-accounts.txt>"; powershell -ExecutionPolicy Bypass -File tests\vm\real-install.ps1
# Needs dist\metascience-setup.zip (python make_zip.py) copied to tests\vm\metascience-setup.zip.
param([string]$Tag = 'RI1', [int]$MaxMin = 240)
. "$PSScriptRoot\vmlib.ps1"
$res = Join-Path $Results $Tag
function Note($t) { $l = (Get-Date -Format HH:mm:ss) + " [$Tag] $t"; Write-Output $l; Add-Content -LiteralPath (Join-Path $res 'host.txt') -Value $l }

# What is on disk, as the student: free space, the install record, and the size of each part's folders.
$measure = @'
function Gb($p) { if (Test-Path -LiteralPath $p) { [math]::Round(((Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2) } else { 'absent' } }
$L = $env:LOCALAPPDATA; $P = $env:ProgramFiles; $U = $env:USERPROFILE
'free C: GB ' + [math]::Round((Get-PSDrive C).Free / 1GB, 2)
'--- installed.tsv'
Get-Content -LiteralPath "$L\MetaScience\installed.tsv" -Encoding UTF8 -ErrorAction SilentlyContinue
'--- each recorded path exists?'
foreach ($l in @(Get-Content -LiteralPath "$L\MetaScience\installed.tsv" -Encoding UTF8 -ErrorAction SilentlyContinue)) {
  $f = $l -split "`t"; if ($f[1] -in 'dir', 'file', 'inno') { "{0,-6} {1}  {2}" -f $(if (Test-Path -LiteralPath $f[2]) { 'yes' } else { 'NO' }), $f[1], $f[2] } }
'--- sizes (GB)'
foreach ($p in "$L\Programs\R", "$P\R", "$L\Programs\RStudio", "$P\RStudio", "$L\Programs\Quarto", "$P\Quarto", "$L\Programs\nodejs", "$P\nodejs",
  "$L\Microsoft\WinGet\Packages", "$L\Programs\MinGit", "$P\Git", "$L\Programs\Git", "$U\.local\bin", "$L\uv", "$U\MetaScience\.venv",
  "$L\Programs\opencode-cli", "$L\Programs\OpenCode", "$L\Programs\opencode", "$U\.local\share\opencode", "$U\.cache\opencode", "$L\MetaScience",
  "$U\MetaScience", "$L\R", "$U\Documents\R") { '{0,-8} {1}' -f (Gb $p), $p }
'--- R library folders'
foreach ($r in @(Get-ChildItem "$L\R\win-library", "$U\Documents\R\win-library" -Directory -ErrorAction SilentlyContinue)) { '{0,-8} {1}' -f (Gb $r.FullName), $r.FullName }
'--- winget list (this account and machine)'
winget list --accept-source-agreements 2>$null | Select-String 'Git|Node|uv|R for|RStudio|Quarto|OpenCode' | ForEach-Object { $_.Line.Trim() }
'--- PATH (user)'
[Environment]::GetEnvironmentVariable('Path', 'User')
'--- scheduled tasks'
Get-ScheduledTask -TaskName 'MetaScience*' -ErrorAction SilentlyContinue | ForEach-Object TaskName
'--- Python check crash codes in the setup log (d-8fb1bf)'
Get-ChildItem "$env:TEMP\metascience-setup-*.log" -ErrorAction SilentlyContinue | Select-String 'stopped unexpectedly|0xC0000' | ForEach-Object { $_.Line.Trim() }
'--- free C: GB ' + [math]::Round((Get-PSDrive C).Free / 1GB, 2)
'@

# free space and folder sizes before anything is installed
New-Item -ItemType Directory -Force $res | Out-Null
Note (VM-Restore 'student-ready2'); VM-Start
if (-not (Wait-GA)) { Note 'BLOCKED: guest additions not ready'; VM-Stop; exit 2 }
if (-not (Wait-Login 'student' 900)) { Note 'BLOCKED: student never logged in'; VM-Stop; exit 2 }
G $measure 'student' 600 | Set-Content -LiteralPath (Join-Path $res 'measure-0-before.txt') -Encoding UTF8
Note "before: $((Get-Content (Join-Path $res 'measure-0-before.txt') -TotalCount 1))"

# the real install, as a student would run it (no snapshot restore: the VM keeps running)
& "$PSScriptRoot\run-case.ps1" -Tag "$Tag-setup" -Snapshot '' -SetupArgs '-Yes' -KeepRunning -MaxMin $MaxMin | ForEach-Object { Note "  case> $_" }
G $measure 'student' 900 | Set-Content -LiteralPath (Join-Path $res 'measure-1-installed.txt') -Encoding UTF8
Note "installed: $((Get-Content (Join-Path $res 'measure-1-installed.txt') -TotalCount 1))"

# the uninstall of everything, in the student's own desktop session (a removal may show a Windows prompt)
$un = @'
$o = 'C:\Users\Public\mstest\out\uninstall'; New-Item -ItemType Directory -Force $o | Out-Null
$t0 = Get-Date
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MetaScience\pack\setup-windows.ps1" -Uninstall -Parts all -Yes *> "$o\console.txt"
"exit=$LASTEXITCODE minutes=$([math]::Round(((Get-Date) - $t0).TotalMinutes, 1))" | Set-Content "$o\runner.txt"
Start-Sleep 20   # the uninstaller runs a copy from the temp folder; let it finish
Set-Content "$o\DONE" 'done'
'@
$uf = Join-Path $env:TEMP 'un.ps1'; Set-Content -LiteralPath $uf -Value $un -Encoding UTF8; Copy-In $uf 'C:\Users\Public\mstest' | Out-Null
GA @"
`$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -EncodedCommand $(Enc-Boot 'C:\Users\Public\mstest\un.ps1')'
`$pr = New-ScheduledTaskPrincipal -UserId 'student' -LogonType Interactive
Register-ScheduledTask -TaskName 'mstest-uninstall' -Action `$a -Principal `$pr -Force | Out-Null
Start-ScheduledTask -TaskName 'mstest-uninstall'; 'uninstall task started'
"@ | ForEach-Object { Note "  $_" }
$t0 = Get-Date
while (((Get-Date) - $t0).TotalMinutes -lt 60) {
  Start-Sleep 30
  if ((G "Test-Path 'C:\Users\Public\mstest\out\uninstall\DONE'" 'vmadmin' 60) -match 'True') { break }
}
Shot "$Tag-uninstall-end"
Copy-Out 'C:\Users\Public\mstest\out\uninstall' $res | Out-Null
Get-Content (Join-Path $res 'uninstall\runner.txt') -ErrorAction SilentlyContinue | ForEach-Object { Note "  uninstall> $_" }
G $measure 'student' 600 | Set-Content -LiteralPath (Join-Path $res 'measure-2-uninstalled.txt') -Encoding UTF8
Note "after uninstall: $((Get-Content (Join-Path $res 'measure-2-uninstalled.txt') -TotalCount 1))"
VM-Stop
Note 'DONE'
