# Test watcher: prints one line per event so the Claude Monitor tool wakes on each.
# Events: every new case, every finished/FAIL/rescued line, a heartbeat every 15 min (case + minutes + last log
# line age), a STALL alarm if the log has not changed for 25 min, a TOO LONG alarm past 160 min per case,
# and WATCHER DEAD if the detached run-rest/night process is gone before "all done".
param([string]$Log = "$PSScriptRoot\results\night-log-3.txt", [int]$Minutes = 29)
$seen = 0; $end = (Get-Date).AddMinutes($Minutes); $lastBeat = Get-Date; $lastChange = Get-Date; $lastLen = -1
$case = ''; $caseStart = Get-Date
# start from now: remember the current case and its start time, do not replay old lines
$init = @(Get-Content -LiteralPath $Log -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
$seen = $init.Count; $lastLen = $init.Count
$hdr = @($init | Where-Object { $_ -match '^########## (\S+)\s+(\d\d:\d\d)' } | Select-Object -Last 1)
if ($hdr -and $hdr[0] -match '^########## (\S+)\s+(\d\d:\d\d)') { $case = $Matches[1]; $caseStart = [datetime]::ParseExact($Matches[2], 'HH:mm', $null); if ($caseStart -gt (Get-Date)) { $caseStart = $caseStart.AddDays(-1) } }
Write-Output "BEAT watching: case=$case running $([int]((Get-Date) - $caseStart).TotalMinutes) min"
while ((Get-Date) -lt $end) {
  $lines = @(Get-Content -LiteralPath $Log -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
  if ($lines.Count -ne $lastLen) { $lastLen = $lines.Count; $lastChange = Get-Date }
  for ($i = $seen; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '^########## (\S+)') { $case = $Matches[1]; $caseStart = Get-Date }
    if ($l -match '##########|finished:|FAIL|rescued log|DISK|all done|Exception|error') { Write-Output "EVENT $l" }
  }
  $seen = $lines.Count
  if ($lines -match 'all done') { Write-Output 'EVENT queue all done'; break }
  $alive = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'run-rest[-0-9]*.ps1|night.ps1|run-case.ps1|resume-case.ps1' })
  if (-not $alive.Count) { Write-Output 'ALARM WATCHER DEAD: no run-rest/night/run-case process is running'; break }
  $idle = [int]((Get-Date) - $lastChange).TotalMinutes
  $caseMin = [int]((Get-Date) - $caseStart).TotalMinutes
  if ($idle -ge 25 -and $idle % 25 -eq 0) { Write-Output "ALARM STALL: log unchanged for $idle min (case $case, $caseMin min)" }
  if ($caseMin -ge 160 -and $caseMin % 20 -eq 0) { Write-Output "ALARM TOO LONG: case $case running $caseMin min" }
  if (((Get-Date) - $lastBeat).TotalMinutes -ge 15) { $lastBeat = Get-Date; Write-Output "BEAT case=$case minutes=$caseMin log-idle=$idle min" }
  Start-Sleep 60
}
