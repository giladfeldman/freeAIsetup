# VS Code's add-ons (setup-windows.ps1 Install-CodeExtensions, lib\uninstall-windows.ps1): a missing add-on is added,
# one older than the version the release was tested with is updated, one that is fine is left alone; only what the
# setup added is recorded (never the student's own add-on, even one it updated, nor what that update brought); a
# failure or a VS Code too old for the tested add-ons is reported; the uninstall removes exactly the recorded ones.
#   A. a stand-in "code" command that keeps a list of add-ons with versions (fast, no network). The standard VS Code
#      folders (this account's Programs, Program Files) are pointed at scratch folders, so no case can reach a real one.
#   B. the real VS Code on this computer with a scratch add-on and settings folder (MS_TEST_CODE_DIR), downloading the
#      real add-ons (~200 MB). The VS Code profile of this account is compared before and after: it must not change.
#      Set MS_TEST_SKIP_REAL=1 to run only A; B is then reported as SKIP, never as PASS.
#   powershell -ExecutionPolicy Bypass -File tests\vscode.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$work = Join-Path $env:TEMP ("ms-vscode-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$pass = 0; $fail = 0
function Check($name, [bool]$ok, $detail = '') { if ($ok) { "PASS $name"; $script:pass++ } else { "FAIL $name $detail"; $script:fail++ } }

# the setup's own functions, taken from the script itself
$tokens = $null; $errs = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$tokens, [ref]$errs)
$names = 'Log', 'Say', 'Ok', 'Warn', 'Fail', 'Record-Install', 'Run-Native', 'Has-Part', 'Code-Iso', 'Code-Extensions',
         'Older-Than', 'Code-Cli', 'Is-VSCodeCli', 'Recorded-Exts', 'Code-Wanted', 'Install-CodeExtensions', 'Row'
$vars = '$CodeExtensions', '$CodeMinVersions', '$CodeNames'
$defs = @($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $names -contains $a.Name }, $true))
$assign = @($ast.FindAll({ param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $vars -contains $a.Left.Extent.Text -and $a.Parent.Parent -is [Management.Automation.Language.ScriptBlockAst] }, $true))
Check 'setup has every function and list the add-on step uses' ($defs.Count -eq $names.Count -and $assign.Count -eq $vars.Count) "found $($defs.Name -join ', ') / $($assign.Count) lists"
$lib = (($defs | ForEach-Object { $_.Extent.Text }) + ($assign | ForEach-Object { $_.Extent.Text })) -join "`n"
# Ok/Warn/Fail also keep each step's result for the anonymous result message (Row, $script:Rows; 2026-11-24)
$lib += "`n`$script:Rows = New-Object System.Collections.ArrayList"

$fakeLocal = Join-Path $work 'local'; $fakePF = Join-Path $work 'pf'
function Run-Step($codeDir, $state, $parts = @('r', 'vscode'), [switch]$Dry, [switch]$RealFolders) {
  # Install-CodeExtensions in a fresh PowerShell, as in the setup: Find-Tool gives the folder holding code.cmd
  $log = Join-Path $state 'setup.log'; New-Item -ItemType Directory -Force -Path $state | Out-Null
  $s = Join-Path $work 'step.ps1'
  $redirect = if ($RealFolders) { '' } else { "`$env:LOCALAPPDATA = '$fakeLocal'; `$env:ProgramFiles = '$fakePF'" }
  Set-Content -LiteralPath $s -Encoding UTF8 -Value @"
`$StateDir = '$state'; `$LogFile = '$log'; `$DryRun = `$$([bool]$Dry); `$Failed = 0; `$script:Parts = @($(($parts | ForEach-Object { "'$_'" }) -join ','))
$redirect
function Tool-Def(`$n) { @{ name = `$n } }
function Find-Tool(`$t) { '$codeDir' }
$lib
Install-CodeExtensions
"@
  $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s 2>&1
  [pscustomobject]@{ log = $(if (Test-Path $log) { Get-Content -LiteralPath $log -Raw } else { '' })
                     rec = @(if (Test-Path (Join-Path $state 'installed.tsv')) { Get-Content -LiteralPath (Join-Path $state 'installed.tsv') }) }
}

try {
  # ---------- A. stand-in code command ----------
  # versions as the real add-on store gave them on 2026-11-16; FAKE_CODE_OLD = a VS Code too old for the newest
  # (VS Code 1.95 got the R add-on 2.8.8); the Python add-on brings Pylance and the debugger, its newest also Python Environments
  $list = Join-Path $work 'list.txt'; $calls = Join-Path $work 'calls.txt'
  $fake = Join-Path $work 'fakecode.ps1'
  Set-Content -LiteralPath $fake -Encoding UTF8 -Value @"
`$list = '$list'; `$calls = '$calls'
Add-Content -LiteralPath `$calls -Value (`$args -join ' ')
if (`$args -contains '--help') { if (`$env:FAKE_CODE_NOVERSION) { exit 0 }; 'Visual Studio Code 1.139.1'; ''; 'Usage: code.exe [options][paths...]'; exit 0 }
if (`$args -contains '--version') { if (`$env:FAKE_CODE_NOVERSION) { exit 0 }; '1.139.1'; 'abc'; 'x64'; exit 0 }
`$have = [ordered]@{}; if (Test-Path `$list) { foreach (`$l in Get-Content -LiteralPath `$list) { `$p = `$l -split '@'; `$have[`$p[0]] = `$p[1] } }
function Save { Set-Content -LiteralPath `$list -Value @(foreach (`$k in `$have.Keys) { "`$k@`$(`$have[`$k])" }) }
if (`$args -contains '--list-extensions') {
  if (`$env:FAKE_CODE_LISTFAIL) { 'error'; exit 1 }
  foreach (`$k in `$have.Keys) { if (`$args -contains '--show-versions') { "`$k@`$(`$have[`$k])" } else { `$k } }; exit 0 }
`$i = [array]::IndexOf(`$args, '--install-extension')
if (`$i -ge 0) {
  `$e = `$args[`$i + 1]
  if (`$env:FAKE_CODE_FAIL -and `$e -eq `$env:FAKE_CODE_FAIL) { 'Failed Installing Extensions'; exit 1 }
  if (`$have.Contains(`$e) -and `$args -notcontains '--force') { "Extension '`$e' is already installed."; exit 0 }
  `$old = [bool]`$env:FAKE_CODE_OLD
  `$latest = @{ 'sst-dev.opencode' = '1.0.0'; 'ms-python.python' = `$(if (`$old) { '2025.2.0' } else { '2026.10.0' }); 'reditorsupport.r' = `$(if (`$old) { '2.8.8' } else { '3.4.0' }) }
  `$have[`$e] = `$latest[`$e]
  `$with = @{ 'ms-python.python' = @(@('ms-python.vscode-pylance@2026.4.1', 'ms-python.debugpy@2026.6.0') + @(if (-not `$old) { 'ms-python.vscode-python-envs@1.42.0' })); 'reditorsupport.r' = @('reditorsupport.r-syntax@0.1.5') }
  foreach (`$w in @(`$with[`$e])) { if (`$w) { `$p = `$w -split '@'; if (-not `$have.Contains(`$p[0])) { `$have[`$p[0]] = `$p[1] } } }
  Save; exit 0
}
exit 0
"@
  function Make-Code($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'code.cmd') -Encoding ASCII -Value "@powershell -NoProfile -ExecutionPolicy Bypass -File `"$fake`" %*" }
  $bin = Join-Path $work 'bin'; Make-Code $bin
  function Reset-Fake($have) { Remove-Item -LiteralPath $list, $calls -ErrorAction SilentlyContinue; if ($have) { Set-Content -LiteralPath $list -Value $have } }
  function Calls { @(if (Test-Path $calls) { Get-Content $calls }) }
  $cur = 'sst-dev.opencode@1.0.0', 'ms-python.python@2026.10.0', 'ms-python.vscode-pylance@2026.4.1', 'ms-python.debugpy@2026.6.0',
         'ms-python.vscode-python-envs@1.42.0', 'reditorsupport.r@3.4.0', 'reditorsupport.r-syntax@0.1.5'
  $seven = $cur | ForEach-Object { ($_ -split '@')[0] }

  Reset-Fake $null
  $r = Run-Step $bin (Join-Path $work 'sA1')
  Check 'A1 none there: the three add-ons installed' (@((Calls) -match '--install-extension (sst-dev\.opencode|ms-python\.python|reditorsupport\.r)$').Count -eq 3) ((Calls) -join ' | ')
  Check 'A1 none there: never with --force (nothing there to update)' (-not ((Calls) -match '--force'))
  Check 'A1 none there: all seven recorded, the companions too' (@($seven | Where-Object { $r.rec -contains "vscode`tvsext`t$_" }).Count -eq 7 -and $r.rec.Count -eq 7) ($r.rec -join ' | ')
  Check 'A1 none there: reported OK, added' ($r.log -match 'OK VS Code add-ons OpenCode, Python, R ready \(added: OpenCode, Python, R\)') $r.log

  Reset-Fake $null
  $r = Run-Step $bin (Join-Path $work 'sA1b') @('vscode')
  Check 'A1b R not chosen: no R add-on' (-not ((Calls) -match 'reditorsupport') -and -not ($r.rec -match 'reditorsupport') -and $r.log -match 'OK VS Code add-ons OpenCode, Python ready') $r.log

  Reset-Fake @('sst-dev.opencode@1.0.0', 'someone.mine@1.0.0')
  $r = Run-Step $bin (Join-Path $work 'sA2')
  Check 'A2 OpenCode add-on there and current: not installed again' (-not ((Calls) -match '--install-extension sst-dev\.opencode')) ((Calls) -join ' | ')
  Check "A2 OpenCode add-on there: only the others and their companions recorded, never the student's" ($r.rec.Count -eq 6 -and -not ($r.rec -match 'sst-dev\.opencode|someone\.mine')) ($r.rec -join ' | ')

  Reset-Fake $cur
  $r = Run-Step $bin (Join-Path $work 'sA3')
  Check 'A3 all there and current: nothing installed, nothing recorded, OK up to date' (-not ((Calls) -match '--install-extension') -and $r.rec.Count -eq 0 -and $r.log -match 'OK VS Code add-ons OpenCode, Python, R already there and up to date') $r.log

  Reset-Fake $null; $env:FAKE_CODE_FAIL = 'ms-python.python'
  try { $r = Run-Step $bin (Join-Path $work 'sA4') } finally { Remove-Item Env:\FAKE_CODE_FAIL }
  Check 'A4 Python add-on cannot be added: FAIL names it' ($r.log -match 'FAIL\s+VS Code add-ons\s+could not add ms-python\.python') $r.log
  Check 'A4 Python add-on cannot be added: the others still added and recorded' ($r.rec.Count -eq 3 -and -not ($r.rec -match 'ms-python')) ($r.rec -join ' | ')

  Reset-Fake $null
  $r = Run-Step $bin (Join-Path $work 'sA5') -Dry
  Check 'A5 dry run: VS Code not even asked, nothing recorded' (-not (Test-Path $calls) -and $r.rec.Count -eq 0 -and $r.log -match '\[dry-run\] add the VS Code add-ons that are missing or too old') $r.log

  # the student's own Python add-on, older than tested: updated, but it stays the student's
  Reset-Fake @('sst-dev.opencode@1.0.0', 'ms-python.python@2025.2.0', 'ms-python.vscode-pylance@2026.4.1', 'ms-python.debugpy@2026.6.0', 'reditorsupport.r@3.4.0', 'reditorsupport.r-syntax@0.1.5')
  $r = Run-Step $bin (Join-Path $work 'sA6')
  Check "A6 student's old Python add-on: updated with --force" (@((Calls) -match '^--install-extension ms-python\.python --force$').Count -eq 1 -and (Get-Content $list) -contains 'ms-python.python@2026.10.0') ((Calls) -join ' | ')
  Check "A6 student's old Python add-on: the current ones are not touched" (-not ((Calls) -match 'install-extension (sst-dev|reditorsupport)'))
  Check "A6 student's old Python add-on: nothing recorded, not even what the update brought" ($r.rec.Count -eq 0) ($r.rec -join ' | ')
  Check 'A6 reported OK, updated' ($r.log -match 'OK VS Code add-ons OpenCode, Python, R ready \(updated: Python\)' -and $r.log -match 'updated from 2025\.2\.0 to 2026\.10\.0') $r.log

  # the Python add-on an earlier run added, now older than tested: updated, and what the update brought is recorded
  $sA7 = Join-Path $work 'sA7'; New-Item -ItemType Directory -Force -Path $sA7 | Out-Null
  Set-Content -LiteralPath (Join-Path $sA7 'installed.tsv') -Encoding UTF8 -Value @("vscode`tvsext`tms-python.python", "vscode`tvsext`tms-python.vscode-pylance", "vscode`tvsext`tms-python.debugpy")
  Reset-Fake @('sst-dev.opencode@1.0.0', 'ms-python.python@2025.2.0', 'ms-python.vscode-pylance@2026.4.1', 'ms-python.debugpy@2026.6.0', 'reditorsupport.r@3.4.0', 'reditorsupport.r-syntax@0.1.5')
  $r = Run-Step $bin $sA7
  Check 'A7 an add-on the setup added, now old: updated, its new companion recorded, nothing twice' ($r.rec.Count -eq 4 -and $r.rec -contains "vscode`tvsext`tms-python.vscode-python-envs") ($r.rec -join ' | ')

  # a VS Code too old for the tested add-ons: the store gives older ones; a warning, not a failure, and VS Code untouched
  Reset-Fake $null; $env:FAKE_CODE_OLD = '1'
  try { $r = Run-Step $bin (Join-Path $work 'sA8') } finally { Remove-Item Env:\FAKE_CODE_OLD }
  Check 'A8 VS Code too old: WARN names the old add-ons and says to update VS Code' ($r.log -match 'WARN VS Code add-ons .*ms-python\.python 2025\.2\.0 \(tested: 2026\.10\.0\).*reditorsupport\.r 2\.8\.8 \(tested: 3\.4\.0\).*Check for Updates' -and $r.log -notmatch 'FAIL') $r.log
  Check 'A8 VS Code too old: what was added is still recorded' ($r.rec -contains "vscode`tvsext`treditorsupport.r" -and $r.rec -contains "vscode`tvsext`tms-python.python") ($r.rec -join ' | ')

  # a "code" that is not VS Code's (answers --version with no version): VS Code's own folder is used instead
  $bad = Join-Path $work 'bad'; New-Item -ItemType Directory -Force -Path $bad | Out-Null
  Set-Content -LiteralPath (Join-Path $bad 'code.cmd') -Encoding ASCII -Value "@echo not vs code"
  Make-Code (Join-Path $fakeLocal 'Programs\Microsoft VS Code\bin')
  Reset-Fake $cur
  $r = Run-Step $bad (Join-Path $work 'sA9')
  Check "A9 a code command that is not VS Code's: VS Code's own folder used" ($r.log -match 'not VS Code''s code command' -and $r.log -match 'already there and up to date') $r.log
  # another editor's code command (an editor built from VS Code): --version gives a version, but --help names that
  # editor, so it is not used (d-a09ebb)
  $fork = Join-Path $work 'fork'; New-Item -ItemType Directory -Force -Path $fork | Out-Null
  Set-Content -LiteralPath (Join-Path $fork 'code.cmd') -Encoding ASCII -Value @('@echo off', "echo %* >> `"$work\fork-calls.txt`"", 'if "%1"=="--help" (echo Cursor 1.2.3& exit /b 0)', 'if "%1"=="--version" (echo 1.2.3& echo abc& echo x64& exit /b 0)', 'echo other editor')
  Reset-Fake $null
  $r = Run-Step $fork (Join-Path $work 'sA9b')
  $forkCalls = @(if (Test-Path "$work\fork-calls.txt") { Get-Content "$work\fork-calls.txt" })
  Check "A9b another editor's code command: not used, VS Code's own folder used" ($r.log -match "its --help starts 'Cursor 1\.2\.3'" -and @($forkCalls -match 'install-extension').Count -eq 0 -and @(Calls | Where-Object { $_ -match '--install-extension sst-dev\.opencode' }).Count -ge 1) "$($r.log) | fork: $($forkCalls -join '; ')"
  # Find-Tool (the setup's own): another editor's code command on PATH is not VS Code (production 2026-11-19, a Mac with
  # Cursor and no VS Code: "VS Code already installed", then no add-ons); with VS Code in its own folder, that folder
  $ft = @($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'Have', 'Find-Tool', 'Is-VSCodeCli', 'Log' }, $true))
  function Find-VSCode($pathFirst) {
    $s = Join-Path $work 'ft.ps1'
    Set-Content -LiteralPath $s -Encoding UTF8 -Value @"
`$LogFile = '$(Join-Path $work 'ft.log')'; `$env:PATH = '$pathFirst;' + `$env:PATH
`$env:LOCALAPPDATA = '$fakeLocal'; `$env:ProgramFiles = '$fakePF'; `${env:ProgramFiles(x86)} = '$fakePF'
$(($ft | ForEach-Object { $_.Extent.Text }) -join "`n")
"[`$(Find-Tool @{ id = 'Microsoft.VisualStudioCode'; name = 'VS Code'; cmd = 'code'; exe = 'code.cmd'; dirs = @('Microsoft VS Code\bin') })]"
"@
    "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $s 2>&1)"
  }
  $got = Find-VSCode $fork
  Check "A9c Find-Tool: VS Code in its own folder, another editor's code first on PATH: VS Code's folder" ($ft.Count -eq 4 -and $got -eq "[$(Join-Path $fakeLocal 'Programs\Microsoft VS Code\bin')]") $got
  Remove-Item -LiteralPath $fakeLocal -Recurse -Force
  $got = Find-VSCode $fork
  Check "A9d Find-Tool: only another editor's code command, no VS Code: not found (so the setup installs VS Code)" ($got -eq '[]') $got
  Reset-Fake $cur
  $r = Run-Step $bad (Join-Path $work 'sA10')
  Check 'A10 no working VS Code command anywhere: FAIL, nothing recorded' ($r.log -match "FAIL\s+VS Code add-ons\s+VS Code's code command was not found" -and $r.rec.Count -eq 0) $r.log

  Reset-Fake $cur; $env:FAKE_CODE_LISTFAIL = '1'
  try { $r = Run-Step $bin (Join-Path $work 'sA11') } finally { Remove-Item Env:\FAKE_CODE_LISTFAIL }
  Check 'A11 VS Code cannot list its add-ons: FAIL, nothing installed' ($r.log -match 'FAIL\s+VS Code add-ons\s+VS Code could not list' -and -not ((Calls) -match '--install-extension')) $r.log

  # ---------- B. the real VS Code, scratch add-on folder ----------
  $real = @(Get-Command code -ErrorAction SilentlyContinue | ForEach-Object Source) + @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'))
  $real = $real | Where-Object { $_ -and $_ -like '*.cmd' -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if ($env:MS_TEST_SKIP_REAL -or -not $real) { "SKIP B real VS Code run ($(if ($real) { 'MS_TEST_SKIP_REAL set' } else { 'no VS Code on this computer' }))" }
  else {
    $own = @((& $real --list-extensions --show-versions) 2>$null)   # this account's own add-ons: must be the same afterwards
    $env:MS_TEST_CODE_DIR = Join-Path $work 'vsc'
    try {
      $iso = @('--extensions-dir', (Join-Path $env:MS_TEST_CODE_DIR 'ext'), '--user-data-dir', (Join-Path $env:MS_TEST_CODE_DIR 'data'))
      # the "student" already has an old Python add-on of their own
      # (VS Code writes warnings to its error output; with 'Stop' PowerShell 5.1 would end the test on them)
      $ErrorActionPreference = 'Continue'; $null = (& $real @iso --install-extension 'ms-python.python@2025.2.0') 2>&1; $ErrorActionPreference = 'Stop'
      $mine = @((& $real @iso --list-extensions) 2>$null | ForEach-Object { "$_".Trim().ToLowerInvariant() })
      $state = Join-Path $work 'sB'
      $r = Run-Step (Split-Path -Parent $real) $state -RealFolders
      $have = @((& $real @iso --list-extensions --show-versions) 2>$null | ForEach-Object { "$_".Trim().ToLowerInvariant() })
      Check 'B real: OpenCode and R added, Python updated to the tested version or newer' (@($have -match '^(sst-dev\.opencode|reditorsupport\.r)@').Count -eq 2 -and @($have | Where-Object { $_ -match '^ms-python\.python@(\d+)\.(\d+)' -and ([int]$Matches[1] * 100 + [int]$Matches[2]) -ge 202610 }).Count -eq 1) ($have -join ', ')
      $ids = $have | ForEach-Object { ($_ -split '@')[0] }
      $rec = @($r.rec | ForEach-Object { ($_ -split "`t")[2] })
      Check "B real: every add-on the setup added is recorded, none of the student's" (@($ids | Where-Object { $mine -notcontains $_ -and $_ -notmatch '^ms-python\.' -and $rec -notcontains $_ }).Count -eq 0 -and @($rec | Where-Object { $mine -contains $_ -or $_ -match '^ms-python\.' }).Count -eq 0 -and $rec.Count -ge 3) "have: $($ids -join ', ') | rec: $($rec -join ', ')"
      $r2 = Run-Step (Split-Path -Parent $real) $state -RealFolders
      Check 'B real, second run: nothing new recorded, OK up to date' ($r2.rec.Count -eq $r.rec.Count -and $r2.log -match 'already there and up to date') $r2.log
      # the uninstall removes exactly the recorded add-ons with VS Code's own command
      $out = Join-Path $work 'un.txt'
      $env:MS_STATE_DIR = $state
      $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'lib\uninstall-windows.ps1')`"", '-Parts', 'vscode', '-Yes') `
           -RedirectStandardOutput $out -RedirectStandardError "$out.err" -PassThru -WindowStyle Hidden
      $null = $p.Handle; $p.WaitForExit(); Remove-Item Env:\MS_STATE_DIR
      $left = @((& $real @iso --list-extensions) 2>$null | ForEach-Object { "$_".Trim().ToLowerInvariant() })
      Check 'B real uninstall: exit 0, says removed' ($p.ExitCode -eq 0 -and (Get-Content $out -Raw) -match 'OK\s+VS Code add-ons\s+removed') "exit $($p.ExitCode) $(Get-Content $out -Raw)"
      Check "B real uninstall: the recorded add-ons gone, the student's updated Python add-on kept" (@($left | Where-Object { $rec -contains $_ }).Count -eq 0 -and $left -contains 'ms-python.python') ($left -join ', ')
      Check 'B real uninstall: record has no VS Code line' (-not (@(if (Test-Path (Join-Path $state 'installed.tsv')) { Get-Content (Join-Path $state 'installed.tsv') }) -match '^vscode'))
    } finally { Remove-Item Env:\MS_TEST_CODE_DIR -ErrorAction SilentlyContinue }
    $own2 = @((& $real --list-extensions --show-versions) 2>$null)
    Check "B real: this account's own VS Code add-ons unchanged ($($own.Count))" (($own -join ',') -eq ($own2 -join ',')) "before $($own.Count), after $($own2.Count)"
  }
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
if ($fail) { exit 1 }
