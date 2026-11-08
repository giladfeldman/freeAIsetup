# Host-side helpers to drive the VirtualBox test VM "MS-Test-Win11". Dot-source this file.
$VB   = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$VM   = "MS-Test-Win11"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Kit  = Split-Path -Parent (Split-Path -Parent $Here)          # student-setup
$Acct = Join-Path (Split-Path -Parent $Kit) 'vm-test-accounts.txt'
$Results = Join-Path $Here 'results'
New-Item -ItemType Directory -Force $Results | Out-Null
function Pw($user) {
  # extra test users get the student password
  if ($user -eq 'Administrator') { $user = 'vmadmin' }    # built-in Administrator: same password as vmadmin
  elseif ($user -ne 'vmadmin') { $user = 'student' }
  (Select-String -LiteralPath $Acct -Pattern "$user / (\S+)").Matches[0].Groups[1].Value
}

function VMState { $l = & $VB showvminfo $VM --machinereadable | Select-String '^VMState='; ([string]$l) -replace '.*="(.*)"', '$1' }
function VM-Stop {
  if ((VMState) -eq 'running') { & $VB controlvm $VM poweroff 2>$null | Out-Null }
  $t = Get-Date; while ((VMState) -notin 'poweroff', 'aborted', 'saved' -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 2 }
  Start-Sleep 3
}
$CPUS = if ($env:MSVM_CPUS) { [int]$env:MSVM_CPUS } else { 1 }   # several cores freeze this VM in VirtualBox's Hyper-V mode
function VM-Restore($snap) { VM-Stop; & $VB snapshot $VM restore $snap 2>&1 | Out-Null; & $VB modifyvm $VM --cpus $CPUS 2>&1 | Out-Null; "restored $snap ($CPUS cpu)" }
function VM-Start {
  # the VM process needs a few seconds to release its lock after a shutdown: retry
  for ($i = 0; $i -lt 12; $i++) {
    & $VB startvm $VM --type headless 2>&1 | Out-Null
    Start-Sleep 5
    if ((VMState) -eq 'running') { return }
    Start-Sleep 5
  }
}
function VM-Cycle {
  # Windows "restart" sometimes freezes in this VirtualBox mode; a full shutdown + cold start is reliable
  G 'shutdown.exe /s /t 1 /f' | Out-Null
  $t = Get-Date; while ((VMState) -eq 'running' -and ((Get-Date) - $t).TotalSeconds -lt 300) { Start-Sleep 5 }
  if ((VMState) -eq 'running') { & $VB controlvm $VM poweroff 2>$null | Out-Null; Start-Sleep 5; $how = 'forced off' } else { $how = 'shut down' }
  VM-Start; "VM $how and started again"
}

# a script-signing policy (case J1) blocks -File; a short encoded bootstrap that reads the file is not blocked
function Enc-Boot($path) { [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("iex ([IO.File]::ReadAllText('$path'))")) }
function G([string]$ps, $user = 'vmadmin', [int]$timeoutSec = 600) {
  # run PowerShell code inside the guest as $user (non-interactive logon). Returns output lines.
  $f = Join-Path $env:TEMP ("g-{0}.ps1" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
  Set-Content -LiteralPath $f -Value $ps -Encoding UTF8
  $dest = "C:\Users\Public\mstest\" + (Split-Path -Leaf $f)
  & $VB guestcontrol $VM mkdir --username vmadmin --password (Pw vmadmin) --parents "C:\Users\Public\mstest" 2>$null | Out-Null
  & $VB guestcontrol $VM copyto --username vmadmin --password (Pw vmadmin) --target-directory "C:\Users\Public\mstest\" $f 2>&1 | Out-Null
  Remove-Item -LiteralPath $f
  & $VB guestcontrol $VM run --username $user --password (Pw $user) --timeout ($timeoutSec * 1000) --exe "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -- powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand (Enc-Boot $dest) 2>&1
}
function GA([string]$ps, [int]$timeoutSec = 900) {
  # run PowerShell code inside the guest WITH administrator rights: the built-in Administrator account gets a full token
  G $ps 'Administrator' $timeoutSec
}
function Wait-GA([int]$maxSec = 900) {
  $t = Get-Date
  while (((Get-Date) - $t).TotalSeconds -lt $maxSec) {
    $r = G 'Write-Output GUEST-OK-4711' 'vmadmin' 30
    if ($r -ccontains 'GUEST-OK-4711') { return $true }
    Start-Sleep 10
  }
  return $false
}
function Wait-Login($user, [int]$maxSec = 900) {
  $t = Get-Date
  while (((Get-Date) - $t).TotalSeconds -lt $maxSec) {
    $u = & $VB guestproperty get $VM /VirtualBox/GuestInfo/OS/LoggedInUsersList
    if ($u -match [regex]::Escape($user)) { return $true }
    if ($user -match '[^\x00-\x7F]' -and $u -match 'Value: ' -and $u -notmatch 'vmadmin') { return $true }   # non-ASCII names may not survive the console
    Start-Sleep 10
  }
  return $false
}
function Copy-In($hostFile, $guestDir) {
  & $VB guestcontrol $VM mkdir --username vmadmin --password (Pw vmadmin) --parents $guestDir 2>$null | Out-Null
  & $VB guestcontrol $VM copyto --username vmadmin --password (Pw vmadmin) --target-directory "$guestDir\" $hostFile 2>&1
}
function Copy-Out($guestPath, $hostDir) {
  New-Item -ItemType Directory -Force $hostDir | Out-Null
  & $VB guestcontrol $VM copyfrom --recursive --username vmadmin --password (Pw vmadmin) --target-directory "$hostDir/" $guestPath 2>&1
}
function Shot($name) { & $VB controlvm $VM screenshotpng (Join-Path $Results "$name.png") 2>$null | Out-Null }
