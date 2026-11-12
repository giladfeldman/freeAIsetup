# Runs INSIDE the VM, in the student's interactive desktop session (started by a scheduled task).
$base = 'C:\Users\Public\mstest'
$cfg  = Get-Content -LiteralPath "$base\case.json" -Raw | ConvertFrom-Json
$out  = "$base\out\$($cfg.tag)"; New-Item -ItemType Directory -Force $out | Out-Null
"start $(Get-Date -f s) user=$env:USERNAME profile=$env:USERPROFILE" | Set-Content -LiteralPath "$out\runner.txt"
$dest = [Environment]::ExpandEnvironmentVariables($cfg.extract)
if ($cfg.extractZip) {
  New-Item -ItemType Directory -Force $dest | Out-Null
  Expand-Archive -Force -LiteralPath "$base\metascience-setup.zip" -DestinationPath $dest
  if ($cfg.motw) {   # mark every file as downloaded from the internet, like Explorer's "Extract all" does
    Get-ChildItem -LiteralPath $dest -Recurse -File | ForEach-Object { Set-Content -LiteralPath $_.FullName -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" }
  }
}
$cmd = Join-Path $dest 'student-setup\install-windows.cmd'
if ($cfg.cmdPath) { $cmd = [Environment]::ExpandEnvironmentVariables($cfg.cmdPath) }
$env:MS_LOG_ENV = 'local'   # test runs never count as real installs or send real alerts
$t0 = Get-Date
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c echo.| `"$cmd`" $($cfg.args) > `"$out\console.txt`" 2>&1" -PassThru -WindowStyle Normal
$null = $p.Handle; $p.WaitForExit()
"exit=$($p.ExitCode) minutes=$([math]::Round(((Get-Date) - $t0).TotalMinutes, 1)) end=$(Get-Date -f s)" | Add-Content -LiteralPath "$out\runner.txt"
Copy-Item "$env:TEMP\metascience-setup-*.log" $out -ErrorAction SilentlyContinue
$cd = if ($env:METASCIENCE_DIR) { $env:METASCIENCE_DIR } else { Join-Path $env:USERPROFILE 'MetaScience' }
Copy-Item (Join-Path $cd 'setup-report.txt') $out -ErrorAction SilentlyContinue
[Environment]::GetEnvironmentVariable('Path', 'User') | Set-Content -LiteralPath "$out\userpath.txt"
if ($cfg.updateTest) {
  # The real automatic update, as Windows would run it: fire the daily task the setup created, then check
  # that the installed pack moved to the newer version published on GitHub, and that rollback works.
  $u = "$out\update-test.txt"
  $pk = Join-Path $env:LOCALAPPDATA 'MetaScience\pack'
  function V { (Get-Content -LiteralPath (Join-Path $pk 'VERSION') -TotalCount 1 -ErrorAction SilentlyContinue) }
  function W($t) { Add-Content -LiteralPath $u -Value $t -Encoding UTF8 }
  W "installed pack version: $(V)"
  $task = Get-ScheduledTask -TaskName 'MetaScience pack update' -ErrorAction SilentlyContinue
  W "daily update task: $(if ($task) { 'present, starts ' + (($task.Triggers | ForEach-Object { $_.StartBoundary }) -join ' ') } else { 'MISSING' })"
  if ($task) {
    $t1 = Get-Date
    Start-ScheduledTask -TaskName 'MetaScience pack update'
    Start-Sleep 20
    while ((Get-ScheduledTask -TaskName 'MetaScience pack update').State -eq 'Running' -and ((Get-Date) - $t1).TotalMinutes -lt 90) { Start-Sleep 15 }
    $ti = Get-ScheduledTaskInfo -TaskName 'MetaScience pack update'
    W "task finished after $([math]::Round(((Get-Date) - $t1).TotalMinutes, 1)) min, last result $($ti.LastTaskResult)"
  }
  W "pack version after update: $(V)"
  W "previous version kept: $(Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'MetaScience\pack-previous\VERSION') -TotalCount 1 -ErrorAction SilentlyContinue)"
  $cd2 = if ($env:METASCIENCE_DIR) { $env:METASCIENCE_DIR } else { Join-Path $env:USERPROFILE 'MetaScience' }
  Get-Content -LiteralPath (Join-Path $cd2 'UPDATES.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "UPDATES.txt: $_" }
  Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'MetaScience\update-log.txt') -Tail 6 -ErrorAction SilentlyContinue | ForEach-Object { W "update-log: $_" }
  $up = Join-Path $pk 'update\update.ps1'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $up -Rollback *> $null
  W "after rollback: $(V)"
  $env:MS_UPDATE_NO_SETUP = '1'; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $up *> $null; Remove-Item Env:\MS_UPDATE_NO_SETUP
  W "after updating again: $(V)"
  Copy-Item (Join-Path $env:LOCALAPPDATA 'MetaScience\update-log.txt') $out -ErrorAction SilentlyContinue
}
'done' | Set-Content -LiteralPath "$out\DONE"
