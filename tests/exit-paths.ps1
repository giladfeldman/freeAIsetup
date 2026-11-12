# Every way a Windows setup can stop must offer the report to the teacher's log box, and a success must send the
# anonymous count once. Runs on this computer and installs NOTHING: each case stops before any install (test hooks
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
New-Item -ItemType Directory -Force -Path $env:MS_STATE_DIR | Out-Null
Set-Content -LiteralPath (Join-Path $env:MS_STATE_DIR 'parts.txt') -Value 'all' -Encoding ASCII   # no parts question
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
function Reset-Env { foreach ($v in 'MS_TEST_FAIL_AT', 'MS_TEST_CRASH') { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue } }

try {
  # ---- setup-windows.ps1: three ways to stop, each must offer the upload (answer: yes to send, no to the helper)
  foreach ($case in @(@{ n = 'stop in step 1 (precheck)'; v = 'MS_TEST_FAIL_AT'; x = 'precheck'; step = 'Test stop' },
                      @{ n = 'crash before any step';     v = 'MS_TEST_CRASH';   x = 'main';     step = 'Setup stopped' },
                      @{ n = 'crash in step 3';           v = 'MS_TEST_CRASH';   x = 'tools';    step = 'Setup stopped' })) {
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
    $named = [regex]::Match((Get-Content (Join-Path $work 'out.txt') -Raw), 'show the teacher: (.+?)\r?\n').Groups[1].Value.Trim()
    Check "$($case.n): the file named in the summary exists" ($named -and (Test-Path -LiteralPath $named)) "named: '$named'"
  }
  # the student says no: nothing is sent
  Reset-Env; $env:MS_TEST_FAIL_AT = 'precheck'; Clear-Content -LiteralPath $rec
  $null = Run-Setup @('n', 'n')
  Check 'student says no: nothing sent' ((Records).Count -eq 0)
  # -Yes (the AI helper's own re-runs, tests): no question, nothing sent
  Clear-Content -LiteralPath $rec; $code = Run-Setup @() @('-Yes')
  Check '-Yes: no question, nothing sent, exit 1' ((Records).Count -eq 0 -and $code -eq 1)
  Reset-Env

  # ---- success count: the function itself, with its state folder pointed at a scratch folder
  $tokens = $null; $errs = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$tokens, [ref]$errs)
  $defs = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'Send-SuccessCount', 'LogBox-Headers', 'Log' }, $true) | ForEach-Object { $_.Extent.Text }
  Clear-Content -LiteralPath $rec
  & ([scriptblock]::Create(($defs -join "`n") + "`n`$StateDir = '$work\countstate'; `$LogBox = '$($env:MS_LOG_URL)'; `$SetupVersion = '9.9.9'; `$LogFile = '$work\count.log'; Send-SuccessCount; Send-SuccessCount"))
  $c = @(Records | Where-Object { $_.path -like '/count*' })
  Check 'success count: sent once for two successful runs' ($c.Count -eq 1) "got $($c.Count)"
  if ($c.Count) {
    Check 'success count: only platform and version in the address' ($c[0].path -eq '/count?platform=windows&version=9.9.9') $c[0].path
    Check 'success count: empty body' ([string]::IsNullOrEmpty($c[0].body))
  }

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
  }
  Remove-Item Env:\MS_UPDATE_SOURCES, Env:\MS_SETUP_ARGS -ErrorAction SilentlyContinue
} finally {
  Reset-Env
  foreach ($v in 'MS_LOG_URL', 'MS_LOG_ENV', 'METASCIENCE_DIR', 'MS_STATE_DIR', 'MS_UPDATE_SOURCES', 'MS_SETUP_ARGS') { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue }
  try { $box.Kill() } catch {}
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
if ($fail) { exit 1 }
