# =============================================================================
#  Meta-science course: remove some or all of what the setup installed (Windows)
#  Removes ONLY what the setup itself recorded installing (installed.tsv, written by setup-windows.ps1 since
#  2026-11-12). Software that was on this computer before the setup is not in that record and is never touched.
#  Your course folder is kept unless you type DELETE when asked (or pass -RemoveCourse).
#
#  Start it with:  powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MetaScience\pack\setup-windows.ps1" -Uninstall
#  (setup-windows.ps1 runs a copy of this file from the temp folder, because Windows cannot delete the pack folder
#  while a program runs from it). Options: [-Parts rstudio,quarto|all] [-Yes] [-DryRun] [-RemoveCourse]
#  Parts: rstudio, r, quarto, node, ai (the AI assistant, Git, uv, this pack and its daily update), all.
# =============================================================================
param(
  [string]$Parts = '',   # what to remove without asking for the list (all = everything except the course folder)
  [switch]$Yes,          # do not ask (needs -Parts)
  [switch]$DryRun,       # show what would be removed, change nothing
  [switch]$RemoveCourse, # also delete the course folder (only together with -Yes; otherwise you are asked)
  [int]$WaitPid = 0      # started through install-windows.cmd: that cmd runs from the pack folder, so the pack goes after it ends
)
$ErrorActionPreference = 'Continue'
$StateDir  = if ($env:MS_STATE_DIR) { $env:MS_STATE_DIR } else { Join-Path $env:LOCALAPPDATA 'MetaScience' }
$Record    = Join-Path $StateDir 'installed.tsv'
$PackDir   = Join-Path $StateDir 'pack'          # setup-windows.ps1: %LOCALAPPDATA%\MetaScience\pack
$UpdateTask = 'MetaScience pack update'
$LogFile   = Join-Path $env:TEMP ("metascience-uninstall-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Fake      = [bool]$env:MS_TEST_FAKE_UNINSTALL   # tests: other programs' uninstallers are only named, never run
$Groups = [ordered]@{
  rstudio = 'RStudio'
  r       = 'R and the course R packages'
  quarto  = 'Quarto'
  node    = 'Node.js'
  core    = 'The AI assistant and the setup''s own tools (OpenCode, Git, uv, this course pack and its daily update)'
}

function Log($t) { try { Add-Content -LiteralPath $LogFile -Value $t -Encoding UTF8 } catch {} }
function Say($t) { Write-Host $t; Log $t }
function Ok($i, $d = '')   { Write-Host '  OK    ' -ForegroundColor Green -NoNewline; Write-Host "$i  $d"; Log "OK $i $d" }
function Fail($i, $d = '') { Write-Host '  FAIL  ' -ForegroundColor Red -NoNewline; Write-Host "$i  $d"; Log "FAIL  $i  $d"; $script:Failed++ }
$script:Failed = 0

function Remove-Later($path) {
  # A folder in use (a window still works in it) cannot be deleted now, and the pack folder must outlive the
  # install-windows.cmd that started this (cmd reads its own file as it goes). A small hidden helper waits for that
  # cmd to end, then deletes the folder as soon as it is free: it tries every 5 seconds, for up to 30 minutes.
  $p = $path.Replace("'", "''")
  $wait = if ($WaitPid -gt 0) { "Wait-Process -Id $WaitPid -Timeout 1800 -ErrorAction SilentlyContinue; " } else { '' }
  $cmd = $wait + "for (`$i = 0; `$i -lt 360; `$i++) { try { Remove-Item -LiteralPath '$p' -Recurse -Force -ErrorAction Stop; break } catch { if (-not (Test-Path -LiteralPath '$p')) { break }; Start-Sleep -Seconds 5 } }"
  try { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', "`"$cmd`"") -WorkingDirectory $env:TEMP -WindowStyle Hidden | Out-Null; Log "removal later: $path"; return $true }
  catch { Log "could not start the later removal of $path : $_"; return $false }
}
function Remove-Folder($path) {   # $true when gone now or as soon as it is free
  if (-not (Test-Path -LiteralPath $path)) { return $true }
  if ($WaitPid -gt 0 -and ($path.TrimEnd('\') -eq $PackDir.TrimEnd('\') -or $path.TrimEnd('\') -eq $StateDir.TrimEnd('\'))) {
    if (Remove-Later $path) { $script:Later += $path; return $true }
  }
  try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop; return $true }
  catch {
    Log "remove $path : $($_.Exception.Message)"
    if ($_.Exception.Message -match 'in use|being used|another process' -and (Remove-Later $path)) { $script:Later += $path; return $true }
    return $false
  }
}
$script:Later = @()
function Run-Exe($exe, [string[]]$argList, $timeoutSec = 900) {
  if ($Fake) { Log "would run: $exe $($argList -join ' ')"; return 0 }
  try {
    $p = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput "$LogFile.out" -RedirectStandardError "$LogFile.err"
    $null = $p.Handle
    if (-not $p.WaitForExit($timeoutSec * 1000)) { try { $p.Kill() } catch {}; return 124 }
    foreach ($f in "$LogFile.out", "$LogFile.err") { if (Test-Path -LiteralPath $f) { Log (Get-Content -Raw -LiteralPath $f); Remove-Item -LiteralPath $f -Force } }
    return $p.ExitCode
  } catch { Log "could not start $exe : $_"; return 1 }
}

# ---- what the setup installed -------------------------------------------------------------------------------
$items = @()
if (Test-Path -LiteralPath $Record) {
  foreach ($line in @(Get-Content -LiteralPath $Record -Encoding UTF8)) {
    $f = $line -split "`t"
    if ($f.Count -ge 3 -and $f[2]) { $items += [pscustomobject]@{ part = $f[0]; kind = $f[1]; target = $f[2]; line = $line } }
  }
}
# The pack folder and its daily update task can only have come from this setup, record or not (older setups kept none).
if (-not @($items | Where-Object { $_.kind -eq 'pack' }).Count) { $items += [pscustomobject]@{ part = 'core'; kind = 'pack'; target = $PackDir; line = '' } }
if (-not @($items | Where-Object { $_.kind -eq 'task' }).Count) { $items += [pscustomobject]@{ part = 'core'; kind = 'task'; target = $UpdateTask; line = '' } }
$course = @($items | Where-Object { $_.part -eq 'course' } | Select-Object -First 1)
$present = @($Groups.Keys | Where-Object { $g = $_; @($items | Where-Object { $_.part -eq $g }).Count })

Say "MetaScience course setup: remove what the setup installed   (log: $LogFile)"
if ($DryRun) { Write-Host 'DRY RUN: nothing will be changed.' -ForegroundColor Yellow }
if (-not (Test-Path -LiteralPath $Record)) {
  Say 'This computer has no record of the programs the setup installed (setups before November 2026 kept none).'
  Say 'So only the course pack and its daily update can be removed here. To remove a program yourself:'
  Say 'Start menu > Settings > Apps > Installed apps.'
}

# ---- choose -------------------------------------------------------------------------------------------------
$chosen = @()
if ($Parts) {
  foreach ($w in @($Parts.ToLowerInvariant() -split '[,;\s]+' | Where-Object { $_ })) {
    if ($w -eq 'all') { $chosen += $present }
    elseif ($w -eq 'ai') { $chosen += 'core' }
    elseif ($Groups.Contains($w)) { $chosen += $w }
    elseif ($w -eq 'python') { }   # the Python course packages live in the course folder (asked separately)
    else { Say "Unknown part: $w. Use any of: rstudio, r, quarto, node, ai, all."; exit 2 }
  }
  $chosen = @($present | Where-Object { $chosen -contains $_ })
} elseif ($Yes) { Say 'Say what to remove with -Parts (for example -Parts rstudio,quarto, or -Parts all).'; exit 2 }
else {
  Say ''
  Say 'The setup installed these on this computer. Things that were here before the setup are not listed and are never touched.'
  for ($i = 0; $i -lt $present.Count; $i++) {
    $g = $present[$i]; $extra = ''
    if ($g -eq 'r') { $n = @($items | Where-Object { $_.kind -eq 'rpkg' }).Count; if ($n) { $extra = " ($n R packages)" } }
    Say ("  {0}. {1}{2}" -f ($i + 1), $Groups[$g], $extra)
  }
  $a = "$(Read-Host 'Type the numbers to remove (for example 1 3), A for all of them, or press Enter to cancel')".Trim()
  if ($a -match '^(a|all)$') { $chosen = $present }
  elseif ($a) {
    foreach ($n in @($a -split '[,;\s]+' | Where-Object { $_ })) {
      if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $present.Count) { $chosen += $present[[int]$n - 1] }
      else { Say "  '$n' is not a number from the list; nothing was removed."; exit 2 }
    }
    $chosen = @($present | Where-Object { $chosen -contains $_ })
  }
}
$removeCourse = $false
if ($course.Count -and (Test-Path -LiteralPath $course[0].target)) {
  if ($Yes) { $removeCourse = [bool]$RemoveCourse }
  elseif (-not $DryRun) {
    Say ''
    Say "Your course folder $($course[0].target) holds your course work, notes and the Python course packages."
    $a = "$(Read-Host 'To delete it too, type DELETE (this cannot be undone). Press Enter to keep it')".Trim()
    $removeCourse = ($a -ceq 'DELETE')
  }
}
if (-not $chosen.Count -and -not $removeCourse) { Say 'Nothing was removed.'; exit 0 }
# The course pack holds this uninstall. If other parts the setup installed stay on this computer, the pack and its
# daily update stay too, so the student can come back and remove those parts later.
$keepPack = ($chosen -contains 'core') -and [bool]@($present | Where-Object { $_ -ne 'core' -and $chosen -notcontains $_ }).Count
if ($keepPack) { Say ''; Say 'The course pack stays until the other parts are removed, so you can run the uninstall again.' }
if (-not $Yes -and -not $DryRun) {
  $what = @($chosen | ForEach-Object { $Groups[$_] }); if ($removeCourse) { $what += 'your course folder' }
  Say ''
  $a = "$(Read-Host "Remove: $($what -join '; ')? Windows may ask for permission for some programs. [y/N]")".Trim()
  if ($a -notmatch '^(y|yes)$') { Say 'Nothing was removed.'; exit 0 }
}

# ---- remove ---------------------------------------------------------------------------------------------------
# order: R packages before R, uv's own data before uv, the desktop app, the update task, programs, folders, the
# pack itself, and last the PATH entries whose folders are now gone
$order = @{ rpkg = 0; uvdata = 1; app = 2; task = 3; winget = 4; inno = 4; dir = 5; file = 5; pack = 6; path = 7 }
$todo = @($items | Where-Object { $chosen -contains $_.part -and -not ($keepPack -and $_.kind -in 'pack', 'task') } | Sort-Object { $order[$_.kind] })
if ($removeCourse) { $todo += $course[0] }
$done = @()
Say ''
$pk = @($todo | Where-Object { $_.kind -eq 'rpkg' })
if ($pk.Count) {
  $names = ($pk | ForEach-Object { "'$($_.target)'" }) -join ','
  $rs = Get-Command Rscript -ErrorAction SilentlyContinue
  if ($DryRun) { Say "  [dry-run] remove $($pk.Count) R packages" }
  elseif (-not $rs) { Fail 'R packages' 'R is not found, so its packages cannot be removed this way' }
  elseif ((Run-Exe $rs.Source @('-e', "`"suppressWarnings(remove.packages(c($names), lib=Sys.getenv('R_LIBS_USER')))`"")) -eq 0) { Ok 'R packages' "$($pk.Count) removed"; $done += $pk }
  else { Fail 'R packages' "R could not remove them; see $LogFile" }
}
foreach ($it in $todo) {
  if ($it.kind -in 'rpkg', 'path') { continue }
  $t = $it.target
  if ($DryRun) { Say "  [dry-run] remove $($it.kind) $t"; continue }
  switch ($it.kind) {
    'uvdata' {
      $uv = Get-Command uv -ErrorAction SilentlyContinue
      if ($uv) { $null = Run-Exe $uv.Source @('cache', 'clean') 600; $null = Run-Exe $uv.Source @('python', 'uninstall', '--all') 600 }
      Ok 'Python and downloads kept by uv' 'removed'; $done += $it
    }
    'app' {
      $entries = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
                   ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -like $t })
      if (-not $entries.Count) { Ok $t 'already gone'; $done += $it; break }
      $okAll = $true
      foreach ($e in $entries) {
        $cmd = if ($e.QuietUninstallString) { $e.QuietUninstallString } else { "$($e.UninstallString) /S" }
        if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $rest = $Matches[2] } else { $exe = ($cmd -split ' ', 2)[0]; $rest = ($cmd -split ' ', 2)[1] }
        if ((Run-Exe $exe @($rest) 600) -ne 0) { $okAll = $false }
      }
      if ($okAll) { Ok "$($entries[0].DisplayName)" 'removed'; $done += $it } else { Fail $t "its uninstaller reported a problem; see $LogFile" }
    }
    'task' {
      if ((Run-Exe 'schtasks.exe' @('/query', '/tn', "`"$t`"") 60) -ne 0) { $done += $it; break }
      if ((Run-Exe 'schtasks.exe' @('/delete', '/tn', "`"$t`"", '/f') 120) -eq 0) { Ok 'Daily update check' 'removed'; $done += $it } else { Fail 'Daily update check' "could not remove the task '$t'" }
    }
    'winget' {
      if (-not $Fake -and -not (Get-Command winget -ErrorAction SilentlyContinue)) { Fail $t 'winget (the Windows package installer) is missing; remove it in Settings > Apps'; break }
      $code = Run-Exe 'winget' @('uninstall', '--id', $t, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity')
      if ($code -eq 0) { Ok $t 'removed'; $done += $it } else { Fail $t "winget could not remove it (exit $code); remove it in Settings > Apps" }
    }
    'inno' {   # a program the setup installed with its maker's installer (R next to an older R): its own uninstaller
      if (-not (Test-Path -LiteralPath $t)) { $done += $it; break }
      $un = Get-ChildItem -LiteralPath $t -Filter 'unins*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($un) { $null = Run-Exe $un.FullName @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 900; Start-Sleep -Seconds $(if ($Fake) { 0 } else { 3 }) }
      try { if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction Stop }; Ok $t 'removed'; $done += $it }
      catch { Fail $t "could not remove it (is R still open?): $($_.Exception.Message)" }
    }
    { $_ -in 'dir', 'file', 'pack' } {
      if (-not (Test-Path -LiteralPath $t)) { $done += $it; break }
      if (Remove-Folder $t) { Ok $t $(if ($script:Later -contains $t) { 'removed as soon as this command has finished' } else { 'removed' }); $done += $it }
      else { Fail $t "could not remove it (is a program from it still open?); see $LogFile" }
    }
  }
}
# PATH entries the setup added, whose folders are gone now
$gonePaths = @($todo | Where-Object { $_.kind -eq 'path' -and -not (Test-Path -LiteralPath $_.target) })
$allPaths = @($items | Where-Object { $_.kind -eq 'path' -and -not (Test-Path -LiteralPath $_.target) })
foreach ($pth in $allPaths) { if ($gonePaths.target -notcontains $pth.target) { $gonePaths += $pth } }
if ($gonePaths.Count -and -not $DryRun) { try {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $kind = $key.GetValueKind('Path')
  $drop = @($gonePaths | ForEach-Object { $_.target.TrimEnd('\').ToLowerInvariant() })
  $keep = @($raw -split ';' | Where-Object { $_ -and ($drop -notcontains [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\').ToLowerInvariant()) })
  if ($keep.Count -lt @($raw -split ';' | Where-Object { $_ }).Count) {
    if ($Fake) { Log "would set user PATH to: $($keep -join ';')" } else { $key.SetValue('Path', ($keep -join ';'), $kind) }
    Ok 'PATH' "$($drop.Count) folder(s) the setup had added were taken off"
  }
  $key.Close(); $done += $gonePaths
} catch { Fail 'PATH' "could not update your PATH: $($_.Exception.Message)" } }

# ---- keep the record true ------------------------------------------------------------------------------------
if (-not $DryRun) {
  $left = @($items | Where-Object { $_.line -and ($done.line -notcontains $_.line) } | ForEach-Object { $_.line })
  # with the AI part gone (the pack, and this script with it) only a kept course folder may remain: forget the record
  if ($chosen -contains 'core' -and -not @($left | Where-Object { $_ -notmatch "^course`t" }).Count) {
    if (-not (Remove-Folder $StateDir)) { Log "could not remove $StateDir" }     # nothing of the setup is left
  } elseif (Test-Path -LiteralPath $StateDir) {
    if ($left.Count) { Set-Content -LiteralPath $Record -Value $left -Encoding UTF8 } else { Remove-Item -LiteralPath $Record -Force -ErrorAction SilentlyContinue }
    # a removed part must not come back with the next update or the next run of the setup
    $pf = Join-Path $StateDir 'parts.txt'
    if (Test-Path -LiteralPath $pf) {
      $keepParts = @((Get-Content -LiteralPath $pf -Raw) -split '\s+' | Where-Object { $_ -and $_ -ne 'none' -and ($chosen -notcontains $_) -and -not ($_ -eq 'rstudio' -and $chosen -contains 'r') })
      Set-Content -LiteralPath $pf -Value $(if ($keepParts.Count) { $keepParts -join ' ' } else { 'none' }) -Encoding ASCII
    }
  }
}
Say ''
if ($script:Failed) { Say "Some things could not be removed (see the FAIL lines). Log: $LogFile"; exit 1 }
if ($script:Later.Count -and $WaitPid -le 0) { Say 'Close this window to finish: the rest of the setup folder is removed then.' }
Say 'Done.'; exit 0
