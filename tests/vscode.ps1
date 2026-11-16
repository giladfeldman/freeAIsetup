# VS Code's add-ons (setup-windows.ps1 Install-CodeExtensions, lib\uninstall-windows.ps1): only missing add-ons are
# added, one already there is never updated, each one the run added is recorded (with the ones the Python add-on
# brings), a failure is reported, and the uninstall removes exactly the recorded ones.
#   A. a stand-in "code" command that keeps a list (fast, no network)
#   B. the real VS Code on this computer with a scratch add-on and settings folder (MS_TEST_CODE_DIR), downloading the
#      real add-ons (~165 MB). The VS Code profile of this account is compared before and after: it must not change.
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
$names = 'Log', 'Say', 'Ok', 'Fail', 'Record-Install', 'Run-Native', 'Code-Iso', 'Code-Extensions', 'Install-CodeExtensions'
$defs = @($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $names -contains $a.Name }, $true))
$assign = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -eq '$CodeExtensions' }, $true) | Select-Object -First 1
Check 'setup has every function the add-on step uses' ($defs.Count -eq $names.Count -and $assign) "found $($defs.Name -join ', ')"
$lib = (($defs | ForEach-Object { $_.Extent.Text }) + $assign.Extent.Text) -join "`n"

function Run-Step($codeDir, $state, [switch]$Dry) {
  # Install-CodeExtensions in a fresh PowerShell, as in the setup: Find-Tool gives the folder holding code.cmd
  $log = Join-Path $state 'setup.log'; New-Item -ItemType Directory -Force -Path $state | Out-Null
  $s = Join-Path $work 'step.ps1'
  Set-Content -LiteralPath $s -Encoding UTF8 -Value @"
`$StateDir = '$state'; `$LogFile = '$log'; `$DryRun = `$$([bool]$Dry); `$Failed = 0
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
  $bin = Join-Path $work 'bin'; New-Item -ItemType Directory -Force -Path $bin | Out-Null
  $list = Join-Path $work 'list.txt'; $calls = Join-Path $work 'calls.txt'
  Set-Content -LiteralPath (Join-Path $bin 'fakecode.ps1') -Encoding UTF8 -Value @"
`$list = '$list'; `$calls = '$calls'
Add-Content -LiteralPath `$calls -Value (`$args -join ' ')
`$have = @(if (Test-Path `$list) { Get-Content -LiteralPath `$list })
if (`$args -contains '--list-extensions') { `$have; exit 0 }
`$i = [array]::IndexOf(`$args, '--install-extension')
if (`$i -ge 0) {
  `$e = `$args[`$i + 1]
  if (`$env:FAKE_CODE_FAIL -and `$e -eq `$env:FAKE_CODE_FAIL) { 'Failed Installing Extensions'; exit 1 }
  if (`$have -contains `$e) { "Extension '`$e' is already installed."; exit 0 }
  `$add = @(`$e); if (`$e -eq 'ms-python.python') { `$add += 'ms-python.vscode-pylance', 'ms-python.debugpy', 'ms-python.vscode-python-envs' }
  Add-Content -LiteralPath `$list -Value `$add; exit 0
}
exit 0
"@
  Set-Content -LiteralPath (Join-Path $bin 'code.cmd') -Encoding ASCII -Value "@powershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fakecode.ps1`" %*"
  function Reset-Fake($have) { Remove-Item -LiteralPath $list, $calls -ErrorAction SilentlyContinue; if ($have) { Set-Content -LiteralPath $list -Value $have } }
  $five = 'sst-dev.opencode', 'ms-python.python', 'ms-python.vscode-pylance', 'ms-python.debugpy', 'ms-python.vscode-python-envs'

  Reset-Fake $null
  $r = Run-Step $bin (Join-Path $work 'sA1')
  Check 'A1 none there: both add-ons installed' (((Get-Content $calls) -match '--install-extension sst-dev\.opencode').Count -eq 1 -and ((Get-Content $calls) -match '--install-extension ms-python\.python$').Count -eq 1) ((Get-Content $calls) -join ' | ')
  Check 'A1 none there: never with --force (an add-on is never updated)' (-not ((Get-Content $calls) -match '--force'))
  Check 'A1 none there: all five recorded, the Python companions too' (@($five | Where-Object { $r.rec -contains "vscode`tvsext`t$_" }).Count -eq 5 -and $r.rec.Count -eq 5) ($r.rec -join ' | ')
  Check 'A1 none there: reported OK' ($r.log -match 'OK VS Code add-ons OpenCode and Python added') $r.log

  Reset-Fake @('sst-dev.opencode', 'someone.mine')
  $r = Run-Step $bin (Join-Path $work 'sA2')
  Check 'A2 OpenCode add-on already there: not installed again' (-not ((Get-Content $calls) -match '--install-extension sst-dev\.opencode')) ((Get-Content $calls) -join ' | ')
  Check 'A2 OpenCode add-on already there: only the Python add-on and its companions recorded' ($r.rec.Count -eq 4 -and -not ($r.rec -match 'sst-dev\.opencode|someone\.mine')) ($r.rec -join ' | ')

  Reset-Fake $five
  $r = Run-Step $bin (Join-Path $work 'sA3')
  Check 'A3 both there: nothing installed, nothing recorded, OK' (-not ((Get-Content $calls) -match '--install-extension') -and $r.rec.Count -eq 0 -and $r.log -match 'OK VS Code add-ons OpenCode and Python already there') $r.log

  Reset-Fake $null; $env:FAKE_CODE_FAIL = 'ms-python.python'
  try { $r = Run-Step $bin (Join-Path $work 'sA4') } finally { Remove-Item Env:\FAKE_CODE_FAIL }
  Check 'A4 Python add-on cannot be added: FAIL names it' ($r.log -match 'FAIL\s+VS Code add-ons\s+could not add ms-python\.python') $r.log
  Check 'A4 Python add-on cannot be added: only the OpenCode add-on recorded' ($r.rec.Count -eq 1 -and $r.rec[0] -eq "vscode`tvsext`tsst-dev.opencode") ($r.rec -join ' | ')

  Reset-Fake $null
  $r = Run-Step $bin (Join-Path $work 'sA5') -Dry
  Check 'A5 dry run: VS Code not even asked, nothing recorded' (-not (Test-Path $calls) -and $r.rec.Count -eq 0 -and $r.log -match '\[dry-run\] add the VS Code add-ons') $r.log

  # ---------- B. the real VS Code, scratch add-on folder ----------
  $real = @(Get-Command code -ErrorAction SilentlyContinue | ForEach-Object Source) + @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'))
  $real = $real | Where-Object { $_ -and $_ -like '*.cmd' -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if ($env:MS_TEST_SKIP_REAL -or -not $real) { "SKIP B real VS Code run ($(if ($real) { 'MS_TEST_SKIP_REAL set' } else { 'no VS Code on this computer' }))" }
  else {
    $own = @((& $real --list-extensions) 2>$null)   # this account's own add-ons: must be the same afterwards
    $env:MS_TEST_CODE_DIR = Join-Path $work 'vsc'
    try {
      $state = Join-Path $work 'sB'
      $r = Run-Step (Split-Path -Parent $real) $state
      $iso = @('--extensions-dir', (Join-Path $env:MS_TEST_CODE_DIR 'ext'), '--user-data-dir', (Join-Path $env:MS_TEST_CODE_DIR 'data'))
      $have = @((& $real @iso --list-extensions) 2>$null | ForEach-Object { "$_".Trim().ToLowerInvariant() })
      Check 'B real: both add-ons in the scratch VS Code' ($have -contains 'sst-dev.opencode' -and $have -contains 'ms-python.python') ($have -join ', ')
      Check 'B real: everything VS Code added is recorded' ($have.Count -ge 2 -and @($have | Where-Object { $r.rec -notcontains "vscode`tvsext`t$_" }).Count -eq 0) "have: $($have -join ', ') | rec: $($r.rec -join ' | ')"
      $r2 = Run-Step (Split-Path -Parent $real) $state
      Check 'B real, second run: nothing new recorded, OK already there' ($r2.rec.Count -eq $r.rec.Count -and $r2.log -match 'OpenCode and Python already there') $r2.log
      # the uninstall removes exactly the recorded add-ons with VS Code's own command
      $out = Join-Path $work 'un.txt'
      $env:MS_STATE_DIR = $state
      $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'lib\uninstall-windows.ps1')`"", '-Parts', 'vscode', '-Yes') `
           -RedirectStandardOutput $out -RedirectStandardError "$out.err" -PassThru -WindowStyle Hidden
      $null = $p.Handle; $p.WaitForExit(); Remove-Item Env:\MS_STATE_DIR
      $left = @((& $real @iso --list-extensions) 2>$null)
      Check 'B real uninstall: exit 0, says removed' ($p.ExitCode -eq 0 -and (Get-Content $out -Raw) -match 'OK\s+VS Code add-ons\s+removed') "exit $($p.ExitCode) $(Get-Content $out -Raw)"
      Check 'B real uninstall: no add-on left in the scratch VS Code' ($left.Count -eq 0) ($left -join ', ')
      Check 'B real uninstall: record has no VS Code line' (-not (@(if (Test-Path (Join-Path $state 'installed.tsv')) { Get-Content (Join-Path $state 'installed.tsv') }) -match '^vscode'))
    } finally { Remove-Item Env:\MS_TEST_CODE_DIR -ErrorAction SilentlyContinue }
    $own2 = @((& $real --list-extensions) 2>$null)
    Check "B real: this account's own VS Code add-ons unchanged ($($own.Count))" (($own -join ',') -eq ($own2 -join ',')) "before $($own.Count), after $($own2.Count)"
  }
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
if ($fail) { exit 1 }
