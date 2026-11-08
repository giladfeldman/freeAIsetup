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
$t0 = Get-Date
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c echo.| `"$cmd`" $($cfg.args) > `"$out\console.txt`" 2>&1" -PassThru -WindowStyle Normal
$null = $p.Handle; $p.WaitForExit()
"exit=$($p.ExitCode) minutes=$([math]::Round(((Get-Date) - $t0).TotalMinutes, 1)) end=$(Get-Date -f s)" | Add-Content -LiteralPath "$out\runner.txt"
Copy-Item "$env:TEMP\metascience-setup-*.log" $out -ErrorAction SilentlyContinue
$cd = if ($env:METASCIENCE_DIR) { $env:METASCIENCE_DIR } else { Join-Path $env:USERPROFILE 'MetaScience' }
Copy-Item (Join-Path $cd 'setup-report.txt') $out -ErrorAction SilentlyContinue
[Environment]::GetEnvironmentVariable('Path', 'User') | Set-Content -LiteralPath "$out\userpath.txt"
'done' | Set-Content -LiteralPath "$out\DONE"
