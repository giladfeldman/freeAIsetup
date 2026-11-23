# Every way a Windows setup can stop must offer the report to the teacher's log box, and every run must send one
# anonymous result (POST /result) with nothing personal in it. Runs on this computer and installs NOTHING: each case stops before any install (test hooks
# MS_TEST_FAIL_AT / MS_TEST_CRASH), the installer cases stop at their download checks, and the log box is a local
# fake (tests\fake_logbox.py). Needs Python on PATH.
#   powershell -ExecutionPolicy Bypass -File tests\exit-paths.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$work = Join-Path $env:TEMP ("ms-exit-paths-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$rec = Join-Path $work 'record.jsonl'; New-Item -ItemType File -Path $rec | Out-Null
$port = Get-Random -Minimum 20000 -Maximum 40000
$box = Start-Process -FilePath 'python' -ArgumentList @("`"$(Join-Path $root 'tests\fake_logbox.py')`"", $port, "`"$rec`"") -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$env:MS_LOG_URL = "http://127.0.0.1:$port"; $env:MS_LOG_ENV = 'local'
$env:METASCIENCE_DIR = Join-Path $work 'MetaScience'      # never the real course folder
$env:MS_STATE_DIR = Join-Path $work 'state'               # never the real record of parts and installs
$env:MS_TEST_NO_JOBS = '1'                                 # never this computer's real scheduled tasks
New-Item -ItemType Directory -Force -Path $env:MS_STATE_DIR | Out-Null
Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Value 'all' -Encoding ASCII   # no parts question
Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'asked.txt') -Value 'web codex claude' -Encoding ASCII   # nor the extras questions
$pass = 0; $fail = 0
function Check($name, [bool]$ok, $detail = '') { if ($ok) { "PASS $name"; $script:pass++ } else { "FAIL $name $detail"; $script:fail++ } }
function Records { @(Get-Content -LiteralPath $rec -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
function Run-Setup($answers, [string[]]$extra = @()) {
  # answers go to the keyboard prompts (Read-Host reads them from the redirected input)
  $in = Join-Path $work 'in.txt'; Set-Content -LiteralPath $in -Value $answers -Encoding ASCII
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'setup-windows.ps1')`"") + $extra) `
       -RedirectStandardInput $in -RedirectStandardOutput (Join-Path $work 'out.txt') -RedirectStandardError (Join-Path $work 'err.txt') -PassThru -WindowStyle Hidden
  $null = $p.Handle   # without this PowerShell 5.1 loses the exit code
  $p.WaitForExit(); return $p.ExitCode
}
function Results { @(Records | Where-Object { $_.path -eq '/result' } | ForEach-Object { $_.body | ConvertFrom-Json }) }
function Private-Free($text) { -not ($text -match [regex]::Escape($env:USERPROFILE)) -and ($env:USERNAME.Length -lt 4 -or -not ($text -match [regex]::Escape($env:USERNAME))) -and ($env:COMPUTERNAME.Length -lt 4 -or -not ($text -match [regex]::Escape($env:COMPUTERNAME))) }
function Reset-Env { foreach ($v in 'MS_TEST_FAIL_AT', 'MS_TEST_CRASH') { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue } }

try {
  # ---- setup-windows.ps1: three ways to stop, each must offer the upload (answer: yes to send, no to the helper)
  foreach ($case in @(@{ n = 'stop in step 1 (precheck)'; v = 'MS_TEST_FAIL_AT'; x = 'precheck'; step = 'Test stop' },
                      @{ n = 'crash before any step';     v = 'MS_TEST_CRASH';   x = 'main';     step = 'Setup stopped'; st = 'crash' },
                      @{ n = 'crash in step 3';           v = 'MS_TEST_CRASH';   x = 'tools';    step = 'Setup stopped'; st = 'crash' })) {
    Reset-Env; Set-Item "Env:\$($case.v)" $case.x; Clear-Content -LiteralPath $rec
    $code = Run-Setup @('y', 'n')
    $r = @(Records | Where-Object { $_.path -like '/upload*' })
    Check "$($case.n): exit code 1" ($code -eq 1) "got $code"
    Check "$($case.n): report uploaded" ($r.Count -eq 1) "uploads: $($r.Count); output: $((Get-Content (Join-Path $work 'out.txt') -Raw))"
    if ($r.Count) {
      Check "$($case.n): report has the FAIL line" ($r[0].body -match "(?m)^FAIL  $([regex]::Escape($case.step))  ")
      Check "$($case.n): result=failed, platform=windows" ($r[0].path -match 'platform=windows' -and $r[0].path -match 'result=failed')
      Check "$($case.n): header and local marker sent" ($r[0].'x-freeaisetup' -eq '1' -and $r[0].env -eq 'local')
      Check "$($case.n): home folder and user name removed" (-not ($r[0].body -match [regex]::Escape($env:USERPROFILE)) -and ($env:USERNAME.Length -lt 4 -or -not ($r[0].body -match [regex]::Escape($env:USERNAME))))
      Check "$($case.n): student told the code" ((Get-Content (Join-Path $work 'out.txt') -Raw) -match 'Your code is TESTID')
    }
    # the file the summary tells the student to show the teacher must exist (it named setup-report.txt, which only
    # the check in step 8 writes, also when the setup stopped earlier)
    # the anonymous result: one per run, failed, the stopping step named, nothing personal
    $res = @(Results)
    Check "$($case.n): one anonymous result sent" ($res.Count -eq 1) "results: $($res.Count)"
    if ($res.Count) {
      $want = if ($case.st) { $case.st } else { 'precheck' }
      Check "$($case.n): result says failed, windows, stage $want" ($res[0].outcome -eq 'failed' -and $res[0].platform -eq 'windows' -and $res[0].stage -eq $want -and $res[0].v -eq 1) "$($res[0] | ConvertTo-Json -Compress)"
      Check "$($case.n): result names the failed step" (@($res[0].issues | Where-Object { $_[0] -eq 'FAIL' -and $_[1] -eq $case.step }).Count -ge 1) "$($res[0].issues | ConvertTo-Json -Compress)"
      Check "$($case.n): result has no home folder, user or computer name" (Private-Free ((Records | Where-Object { $_.path -eq '/result' })[0].body))
    }
    $named = [regex]::Match((Get-Content (Join-Path $work 'out.txt') -Raw), 'show the teacher: (.+?)\r?\n').Groups[1].Value.Trim()
    Check "$($case.n): the file named in the summary exists" ($named -and (Test-Path -LiteralPath $named)) "named: '$named'"
  }
  # the student says no: no report; only the anonymous result (owner decision 2026-11-24: automatic, anonymous)
  Reset-Env; $env:MS_TEST_FAIL_AT = 'precheck'; Clear-Content -LiteralPath $rec
  $null = Run-Setup @('n', 'n')
  Check 'student says no: no report sent, one anonymous result' (@(Records | Where-Object { $_.path -like '/upload*' }).Count -eq 0 -and @(Results).Count -eq 1) "posts: $((Records | ForEach-Object { $_.path }) -join ', ')"
  # -Yes (the AI helper's own re-runs, tests): no question, no report, one result
  Clear-Content -LiteralPath $rec; $code = Run-Setup @() @('-Yes')
  Check '-Yes: no question, no report, one result, exit 1' (@(Records | Where-Object { $_.path -like '/upload*' }).Count -eq 0 -and @(Results).Count -eq 1 -and $code -eq 1) "exit $code; posts: $((Records | ForEach-Object { $_.path }) -join ', ')"
  # MS_NO_COUNT=1 switches the result off
  Clear-Content -LiteralPath $rec; $env:MS_NO_COUNT = '1'; $null = Run-Setup @() @('-Yes'); Remove-Item Env:\MS_NO_COUNT
  Check 'MS_NO_COUNT=1: no result sent' (@(Results).Count -eq 0)
  # the older count message is gone: no setup sends /count any more
  Check 'no run sent the old /count' (@(Records | Where-Object { $_.path -like '/count*' }).Count -eq 0)
  Reset-Env

  # ---- a parts list saved by an older setup ("all", no answers to the three extras yet): asked once, and only a yes
  #      counts; Codex and Claude Code never come from the saved "all" (they did before this check, 2026-11-17)
  Reset-Env; $env:MS_TEST_FAIL_AT = 'precheck'; Remove-Item -LiteralPath (Join-Path $env:MS_STATE_DIR 'asked.txt')
  $null = Run-Setup @('yes', 'no', '', '', '', 'n', 'n')
  $o = Get-Content (Join-Path $work 'out.txt') -Raw
  $line = [regex]::Match($o, '(?m)^\s*Installing: .*$').Value
  Check 'older "all", answers yes/no/(Enter x3): asked once' ($o -match 'offers three more optional parts') "$line"
  Check 'older "all": the website tools installed (yes)' ($line -match 'Website tools') "$line"
  Check 'older "all": Codex and Claude Code not installed (no, no answer)' ($line -and $line -notmatch 'Codex' -and $line -notmatch 'Claude Code') "$line"
  Check 'older "all": the answers are remembered' (Test-Path -LiteralPath (Join-Path $env:MS_STATE_DIR 'asked.txt'))
  Remove-Item -LiteralPath (Join-Path $env:MS_STATE_DIR 'asked.txt'); Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Value 'all' -Encoding ASCII
  $null = Run-Setup @() @('-Yes')
  $line = [regex]::Match((Get-Content (Join-Path $work 'out.txt') -Raw), '(?m)^\s*Installing: .*$').Value
  Check 'older "all" with -Yes: not asked, no Codex or Claude Code' ($line -and $line -match 'Website tools' -and $line -notmatch 'Codex|Claude Code') "$line"
  # an unattended first run saves its parts, so a later check and update know them (VS Code and the website tools
  # were checked by neither before 2026-11-17)
  Remove-Item -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt')
  $null = Run-Setup @() @('-Yes')
  Check '-Yes, first run: its parts are saved' ((Get-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Raw).Trim() -eq 'r rstudio quarto python node vscode web') "$(Get-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Raw)"
  Remove-Item -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt')
  $null = Run-Setup @() @('-Yes', '-NoGui')
  Check '-Yes -NoGui, first run: saved without RStudio and VS Code' ((Get-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Raw).Trim() -eq 'r quarto python node web')
  # a saved list with the website tools, the student now answers no to all three: the answers decide
  Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Value 'r web' -Encoding ASCII
  $null = Run-Setup @('no', 'no', 'no', 'n', 'n')
  $line = [regex]::Match((Get-Content (Join-Path $work 'out.txt') -Raw), '(?m)^\s*Installing: .*$').Value
  Check 'saved "r web", answers no/no/no: the website tools are not kept' ($line -and $line -notmatch 'Website tools' -and $line -match 'R and the course') "$line"
  Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Value 'all' -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'asked.txt') -Value 'web codex claude' -Encoding ASCII
  Reset-Env
  # ---- the result message itself (Send-Result), as at the end of a run: one FAIL row with the home folder in it,
  #      and one WARN row from the check's file. ONE issue of each kind on purpose: PowerShell 5.1 flattens a
  #      one-element list of lists, which would send ["FAIL","R step",...] instead of [["FAIL","R step",...]].
  $tokens = $null; $errs = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$tokens, [ref]$errs)
  $defs = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'Send-Result', 'Scrub', 'LogBox-Headers', 'Log' }, $true) | ForEach-Object { $_.Extent.Text }
  foreach ($k in @(@{ n = 'one FAIL'; check = $false }, @{ n = 'one FAIL and one check WARN'; check = $true })) {
    Clear-Content -LiteralPath $rec
    $lf = Join-Path $work 'res.log'
    if ($k.check) { Set-Content -LiteralPath (Join-Path $work 'res.check.tsv') -Value "WARN`tVS Code`tnot on PATH in $env:USERPROFILE" -Encoding UTF8 }
    $setup = "`$script:ResultSent = `$false; `$LogBox = '$($env:MS_LOG_URL)'; `$SetupVersion = '9.9.9'; `$LogFile = '$lf'; `$DryRun = `$false; `$script:Failed = 1; " +
             "`$script:RunStart = (Get-Date).AddMinutes(-12); `$script:RunMode = 'first'; `$script:Parts = @('r', 'python'); " +
             "`$script:Rows = New-Object System.Collections.ArrayList; [void]`$script:Rows.Add(@('OK', 'Git', 'fine')); " +
             "[void]`$script:Rows.Add(@('FAIL', 'R step', ('not found in ' + `$env:USERPROFILE + ' on ' + `$env:COMPUTERNAME + ' via http://bob:s3cretpw@proxy.example:8080 jane.doe@uni.example C:\Users\Other Person\x'))); Send-Result 'done'; Send-Result 'done'"
    # (the parentheses matter: PowerShell's comma binds tighter than +, so without them the row's detail was only
    #  'not found in ' and the privacy checks below passed without any name in the text: found 2026-11-24)
    & ([scriptblock]::Create(($defs -join "`n") + "`n" + $setup))
    $res = @(Results)
    Check "result ($($k.n)): sent once" ($res.Count -eq 1) "got $($res.Count)"
    if ($res.Count) {
      $x = $res[0]
      Check "result ($($k.n)): fields" ($x.v -eq 1 -and $x.platform -eq 'windows' -and $x.version -eq '9.9.9' -and $x.outcome -eq 'failed' -and $x.stage -eq 'done' -and $x.mode -eq 'first' -and $x.parts -eq 'r,python' -and $x.minutes -eq 12 -and $x.os -match '^Windows 1[01] ') "$($x | ConvertTo-Json -Compress)"
      $want = if ($k.check) { 2 } else { 1 }
      Check "result ($($k.n)): issues is a list of $want [status, step, reason, source]" (@($x.issues).Count -eq $want -and $x.issues[0][0] -eq 'FAIL' -and $x.issues[0][1] -eq 'R step' -and $x.issues[0][3] -eq 'setup') "$($x.issues | ConvertTo-Json -Compress)"
      if ($k.check) { Check "result ($($k.n)): the check's WARN row, marked as from the check" ($x.issues[1][0] -eq 'WARN' -and $x.issues[1][1] -eq 'VS Code' -and $x.issues[1][3] -eq 'check'); Check "result ($($k.n)): the check's file is removed after reading" (-not (Test-Path (Join-Path $work 'res.check.tsv'))) }
      $rb = (Records | Where-Object { $_.path -eq '/result' })[0].body
      Check "result ($($k.n)): the failed step's reason arrived (with the names replaced)" ($x.issues[0][2] -match '^not found in ~ on \S+ via ') "$rb"
      Check "result ($($k.n)): no home folder, user or computer name" (Private-Free $rb)
      # Sol review 2026-11-24: a proxy's password, an e-mail address and another account's folder were sent as written
      Check "result ($($k.n)): no proxy password, e-mail address or other account's folder" (-not ($rb -match 's3cretpw|bob:|jane\.doe|Other|Person') -and $x.issues[0][2] -match '<login>@proxy' -and $x.issues[0][2] -match '<e-mail> C:\\Users\\<name>\\x') "$rb"
    }
  }
  # the installer's own result (install.ps1 Send-InstallerResult) removes the same things (Sol review 2026-11-24)
  Clear-Content -LiteralPath $rec
  $iast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'install.ps1'), [ref]$tokens, [ref]$errs)
  $idef = $iast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Send-InstallerResult' }, $true) | ForEach-Object { $_.Extent.Text }
  & ([scriptblock]::Create("$idef`n`$manifest = `$null; Send-InstallerResult 'Installer files' ('could not write ' + `$env:USERPROFILE + '\x on ' + `$env:COMPUTERNAME + ' via http://bob:s3cretpw@proxy.example:8080 jane.doe@uni.example C:\Users\Other Person\x')"))
  $ib = @(Records | Where-Object { $_.path -eq '/result' })
  Check 'installer result (in-process): sent, no names, no proxy password, e-mail address or other account''s folder' ($ib.Count -eq 1 -and (Private-Free $ib[0].body) -and -not ($ib[0].body -match 's3cretpw|bob:|jane\.doe|Other|Person')) "$($ib | ConvertTo-Json -Compress)"
  # Sol review 2026-11-24: with the result switched off, the check's rows file was left behind
  Clear-Content -LiteralPath $rec; $ctf = Join-Path $work 'res.check.tsv'
  Set-Content -LiteralPath $ctf -Value "WARN`tVS Code`tx" -Encoding UTF8; $env:MS_NO_COUNT = '1'
  & ([scriptblock]::Create(($defs -join "`n") + "`n" + "`$script:ResultSent = `$false; `$LogBox = '$($env:MS_LOG_URL)'; `$LogFile = '$(Join-Path $work 'res.log')'; `$DryRun = `$false; Send-Result 'done'"))
  Remove-Item Env:\MS_NO_COUNT
  Check 'result off (MS_NO_COUNT): nothing sent, the check''s rows file removed' (@(Results).Count -eq 0 -and -not (Test-Path -LiteralPath $ctf))

  # ---- install.ps1: a stop at the download checks offers the report too
  $env:MS_SETUP_ARGS = ''
  foreach ($case in @(@{ n = 'installer: no source reachable'; src = "http://127.0.0.1:1/release/manifest.json|http://127.0.0.1:1/{P}"; step = 'Installer download'; ver = 'installer' },
                      @{ n = 'installer: a file fails its checksum'; src = "http://127.0.0.1:$port/m/manifest.json|http://127.0.0.1:$port/bad/{P}"; step = 'Installer files'; ver = '2026.' })) {
    $env:MS_UPDATE_SOURCES = $case.src; Clear-Content -LiteralPath $rec
    $in = Join-Path $work 'in.txt'; Set-Content -LiteralPath $in -Value 'y' -Encoding ASCII
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "iex ([IO.File]::ReadAllText('$(Join-Path $root 'install.ps1')'))") `
         -RedirectStandardInput $in -RedirectStandardOutput (Join-Path $work 'out.txt') -RedirectStandardError (Join-Path $work 'err.txt') -PassThru -WindowStyle Hidden
  $null = $p.Handle   # without this PowerShell 5.1 loses the exit code
    $p.WaitForExit()
    $r = @(Records | Where-Object { $_.path -like '/upload*' })
    Check "$($case.n): report uploaded" ($r.Count -eq 1) "output: $((Get-Content (Join-Path $work 'out.txt') -Raw)) $((Get-Content (Join-Path $work 'err.txt') -Raw))"
    if ($r.Count) {
      Check "$($case.n): FAIL line names the step" ($r[0].body -match "(?m)^FAIL  $([regex]::Escape($case.step))  ")
      Check "$($case.n): version in the address" ($r[0].path -match "version=$([regex]::Escape($case.ver))")
    }
    $res = @(Results)
    Check "$($case.n): one anonymous result, stage installer, the step named" ($res.Count -eq 1 -and $res[0].stage -eq 'installer' -and $res[0].outcome -eq 'failed' -and @($res[0].issues | Where-Object { $_[1] -eq $case.step }).Count -eq 1) "$(($res | ConvertTo-Json -Compress -Depth 4))"
  }
  Remove-Item Env:\MS_UPDATE_SOURCES, Env:\MS_SETUP_ARGS -ErrorAction SilentlyContinue
} finally {
  Reset-Env
  foreach ($v in 'MS_LOG_URL', 'MS_LOG_ENV', 'METASCIENCE_DIR', 'MS_STATE_DIR', 'MS_UPDATE_SOURCES', 'MS_SETUP_ARGS', 'MS_TEST_NO_JOBS', 'MS_NO_COUNT') { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue }
  try { $box.Kill() } catch {}
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
if ($fail) { exit 1 }
