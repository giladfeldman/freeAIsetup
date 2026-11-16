# The uninstall removes what the setup recorded installing and nothing else, keeps the course folder unless the
# student types DELETE, and keeps its record and the chosen parts true afterwards. Runs on this computer and removes
# nothing real: the record points at scratch folders, and other programs' uninstallers (winget, R, the update task)
# are only named in the log (MS_TEST_FAKE_UNINSTALL). Also checks the setup's own Record-Install.
#   powershell -ExecutionPolicy Bypass -File tests\uninstall.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$work = Join-Path $env:TEMP ("ms-uninstall-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$state = Join-Path $work 'state'
$env:MS_STATE_DIR = $state; $env:MS_TEST_FAKE_UNINSTALL = '1'
$pass = 0; $fail = 0
function Check($name, [bool]$ok, $detail = '') { if ($ok) { "PASS $name"; $script:pass++ } else { "FAIL $name $detail"; $script:fail++ } }
function D($n) { Join-Path $work $n }
function Make-State([switch]$NoRecord) {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  foreach ($d in 'rstudio', 'quarto\bin', 'mingit', 'opencode-cli', 'R-4.6.2', 'course', 'was-here-before', 'state\pack\lib') { New-Item -ItemType Directory -Force -Path (D $d) | Out-Null }
  foreach ($f in 'rstudio.lnk', 'uv.exe', 'R-4.6.2\unins000.exe', 'was-here-before\keep.txt', 'course\my-notes.txt') { Set-Content -LiteralPath (D $f) -Value 'x' }
  Set-Content -LiteralPath (Join-Path $state 'parts.txt') -Value 'r rstudio quarto python node' -Encoding ASCII
  if (-not $NoRecord) {
    $rec = @("rstudio`tdir`t$(D 'rstudio')", "rstudio`tfile`t$(D 'rstudio.lnk')", "quarto`tdir`t$(D 'quarto')",
             "r`twinget`tRProject.R", "r`tinno`t$(D 'R-4.6.2')", "r`trpkg`tstatcheck", "r`trpkg`tmetafor", "node`twinget`tOpenJS.NodeJS.LTS",
             "core`tdir`t$(D 'mingit')", "core`tdir`t$(D 'opencode-cli')", "core`tfile`t$(D 'uv.exe')", "core`tapp`tNoSuchAppForThisTest*",
             "core`tpack`t$(Join-Path $state 'pack')", "core`ttask`tMetaScience pack update", "core`tpath`t$(D 'quarto')\bin",
             "course`tdir`t$(D 'course')")
    Set-Content -LiteralPath (Join-Path $state 'installed.tsv') -Value $rec -Encoding UTF8
  }
}
function Run-Un([string[]]$a, $answers = @()) {
  $in = D 'in.txt'; Set-Content -LiteralPath $in -Value $answers -Encoding ASCII
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'lib\uninstall-windows.ps1')`"") + $a) `
       -RedirectStandardInput $in -RedirectStandardOutput (D 'out.txt') -RedirectStandardError (D 'err.txt') -PassThru -WindowStyle Hidden
  $null = $p.Handle; $p.WaitForExit(); return $p.ExitCode
}
function Out { Get-Content -LiteralPath (D 'out.txt') -Raw }
function Rec { if (Test-Path -LiteralPath (Join-Path $state 'installed.tsv')) { @(Get-Content -LiteralPath (Join-Path $state 'installed.tsv')) } else { @() } }
function LogOf { $l = [regex]::Match((Out), 'log: (\S+\.log)').Groups[1].Value; if ($l -and (Test-Path -LiteralPath $l)) { Get-Content -LiteralPath $l -Raw } else { '' } }

try {
  # 1. one part, no questions: only that part goes; the record and the chosen parts follow
  Make-State
  $code = Run-Un @('-Parts', 'rstudio', '-Yes')
  Check 'rstudio only: exit 0' ($code -eq 0) "exit $code $(Out)"
  Check 'rstudio only: its folder and shortcut removed' (-not (Test-Path (D 'rstudio')) -and -not (Test-Path (D 'rstudio.lnk')))
  Check 'rstudio only: other parts untouched' ((Test-Path (D 'quarto')) -and (Test-Path (D 'mingit')) -and (Test-Path (Join-Path $state 'pack')))
  Check 'rstudio only: record no longer lists it' (-not ((Rec) -match '^rstudio')) ((Rec) -join ' | ')
  Check 'rstudio only: record still lists the rest' (@(Rec | Where-Object { $_ -match '^(quarto|r|node|core|course)\t' }).Count -eq 14) "$(@(Rec).Count) lines"
  Check 'rstudio only: not reinstalled by the next update (parts.txt)' ((Get-Content (Join-Path $state 'parts.txt') -Raw).Trim() -eq 'r quarto python node')

  # 2. everything, no questions: all recorded things go, the course folder and what was here before stay
  Make-State
  $code = Run-Un @('-Parts', 'all', '-Yes')
  $log = LogOf
  Check 'all: exit 0' ($code -eq 0) "exit $code $(Out)"
  Check 'all: every recorded folder and file removed' (-not (@('rstudio', 'rstudio.lnk', 'quarto', 'mingit', 'opencode-cli', 'uv.exe') | Where-Object { Test-Path (D $_) }))
  Check 'all: the pack removed' (-not (Test-Path (Join-Path $state 'pack')))
  Check 'all: winget asked to remove R and Node.js (by exact id)' ($log -match 'would run: winget uninstall --id RProject\.R --exact' -and $log -match 'would run: winget uninstall --id OpenJS\.NodeJS\.LTS --exact')
  Check 'all: R packages removed from the user library, before R' ($log -match "remove\.packages\(c\('statcheck','metafor'\)" -and $log.IndexOf('remove.packages') -lt $log.IndexOf('RProject.R'))
  Check 'all: an R the setup installed next to an older R: its own uninstaller ran, its folder is gone' ($log -match 'would run: .*R-4\.6\.2\\unins000\.exe /VERYSILENT' -and -not (Test-Path (D 'R-4.6.2')))
  Check 'all: daily update task removed' ($log -match 'would run: schtasks\.exe /delete /tn "MetaScience pack update" /f')
  Check 'all: something that was here before is untouched' (Test-Path (D 'was-here-before\keep.txt'))
  Check 'all: course folder kept (no -RemoveCourse)' (Test-Path (D 'course\my-notes.txt'))
  Check 'all: the state folder is gone (nothing of the setup left)' (-not (Test-Path $state))

  # 2b. -RemoveCourse with -Yes deletes the course folder (a variable of the same name, in other letters, had overwritten
  #     the switch: PowerShell names ignore case; found 2026-11-15). A folder the setup put on PATH goes once it is empty
  #     (VM 2026-11-15: uv's .local\bin stayed, and so did its PATH entry); one holding anything else stays.
  Make-State
  foreach ($d in 'localbin', 'keepbin') { New-Item -ItemType Directory -Force -Path (D $d) | Out-Null }
  Set-Content -LiteralPath (D 'localbin\uv2.exe') -Value 'x'; Set-Content -LiteralPath (D 'keepbin\other.exe') -Value 'x'
  Add-Content -LiteralPath (Join-Path $state 'installed.tsv') -Value @("core`tfile`t$(D 'localbin\uv2.exe')", "core`tpath`t$(D 'localbin')", "core`tpath`t$(D 'keepbin')") -Encoding UTF8
  $code = Run-Un @('-Parts', 'all', '-Yes', '-RemoveCourse')
  Check 'all -RemoveCourse: exit 0' ($code -eq 0) "exit $code $(Out)"
  Check 'all -RemoveCourse: the course folder is deleted' (-not (Test-Path (D 'course'))) (Out)
  Check 'all: a PATH folder the setup made, empty now, is removed' (-not (Test-Path (D 'localbin'))) (Out)
  Check 'all: a PATH folder holding something else stays' (Test-Path (D 'keepbin\other.exe'))
  Check 'all -RemoveCourse: something that was here before is untouched' (Test-Path (D 'was-here-before\keep.txt'))

  # 2c. winget says "no installed package found" (-1978335212) for Node.js although it is installed (VM 2026-11-15):
  #     one more try, then the entry winget wrote into Windows' list of programs; with no such entry it stays a FAIL
  $arp = "HKCU:\Software\MetaScienceUninstallTest-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
  $env:MS_TEST_FAKE_EXIT = 'uninstall --id OpenJS.NodeJS.LTS=-1978335212'; $env:MS_TEST_ARP_ROOT = $arp
  try {
    New-Item -Path "$arp\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe" -Force | Out-Null
    Make-State; $code = Run-Un @('-Parts', 'node', '-Yes'); $log = LogOf
    Check 'node not found by id: tried twice, then by its entry in the programs list' (([regex]::Matches($log, 'would run: winget uninstall --id OpenJS\.NodeJS\.LTS')).Count -eq 2 -and $log -match 'would run: winget uninstall --product-code OpenJS\.NodeJS\.LTS_Microsoft\.Winget\.Source_8wekyb3d8bbwe') $log
    Check 'node not found by id, removed by its entry: exit 0, no FAIL, record forgets it' ($code -eq 0 -and (Out) -notmatch 'FAIL' -and -not ((Rec) -match '^node')) "exit $code $(Out)"
    Remove-Item -LiteralPath $arp -Recurse -Force
    Make-State; $code = Run-Un @('-Parts', 'node', '-Yes')
    Check 'node not found and no entry in the programs list: still a FAIL, record keeps it' ($code -ne 0 -and (Out) -match 'FAIL\s+OpenJS\.NodeJS\.LTS' -and ((Rec) -match '^node')) "exit $code $(Out)"
  } finally { Remove-Item Env:\MS_TEST_FAKE_EXIT, Env:\MS_TEST_ARP_ROOT -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $arp -Recurse -Force -ErrorAction SilentlyContinue }

  # 3. asked: pick 2 (R), keep the course folder, confirm
  Make-State
  $code = Run-Un @() @('2', '', 'y')
  Check 'asked: lists only recorded parts, in order' ((Out) -match '1\. RStudio' -and (Out) -match '2\. R and the course R packages \(2 R packages\)' -and (Out) -match '5\. The AI assistant')
  Check 'asked: R removed, RStudio untouched' ((LogOf) -match 'RProject\.R' -and (Test-Path (D 'rstudio')))
  Check 'asked: removing R also drops RStudio from the parts (RStudio needs R)' ((Get-Content (Join-Path $state 'parts.txt') -Raw).Trim() -eq 'quarto python node')
  Check 'asked: course folder kept on Enter' (Test-Path (D 'course\my-notes.txt'))

  # 4. asked: the course folder goes only on DELETE (exact, capitals)
  Make-State
  $null = Run-Un @() @('', 'delete', 'y')
  Check 'course: "delete" in small letters keeps it' (Test-Path (D 'course\my-notes.txt'))
  Make-State
  $null = Run-Un @() @('', 'DELETE', 'y')
  Check 'course: DELETE removes it' (-not (Test-Path (D 'course')))
  Check 'course: nothing else removed with it' ((Test-Path (D 'rstudio')) -and (Test-Path (Join-Path $state 'pack')))

  # 5. answers that must remove nothing
  Make-State
  $code = Run-Un @() @('1', '', 'n')
  Check 'confirm no: nothing removed' ((Test-Path (D 'rstudio')) -and $code -eq 0)
  $code = Run-Un @() @('', '')
  Check 'Enter at the list: nothing removed' ((Test-Path (D 'rstudio')) -and (Out) -match 'Nothing was removed')
  $code = Run-Un @() @('9')
  Check 'a number not in the list: nothing removed, exit 2' ((Test-Path (D 'rstudio')) -and $code -eq 2)
  $code = Run-Un @('-Parts', 'rstudoi', '-Yes')
  Check 'unknown part: nothing removed, exit 2' ((Test-Path (D 'rstudio')) -and $code -eq 2)
  $code = Run-Un @('-Yes')
  Check '-Yes without -Parts: nothing removed, exit 2' ((Test-Path (D 'rstudio')) -and $code -eq 2)
  $code = Run-Un @('-Parts', 'all', '-Yes', '-DryRun')
  Check '-DryRun: nothing removed' ((Test-Path (D 'rstudio')) -and (Test-Path (Join-Path $state 'pack')) -and $code -eq 0)

  # 6. no record (older setups): only the pack and its update task are offered
  Make-State -NoRecord
  $code = Run-Un @() @('', '')
  Check 'no record: says so and offers only the AI part (pack, update)' ((Out) -match 'no record' -and (Out) -match '1\. The AI assistant' -and (Out) -notmatch '(?m)^\s*2\. ') (Out)

  # 9. only the AI part while RStudio stays: the pack (which holds the uninstall) and its update task stay too,
  #    so the student can remove RStudio later; a later run with all removes everything
  Make-State
  Set-Content -LiteralPath (Join-Path $state 'installed.tsv') -Encoding UTF8 -Value @("rstudio`tdir`t$(D 'rstudio')", "rstudio`tfile`t$(D 'rstudio.lnk')",
    "core`tdir`t$(D 'mingit')", "core`tfile`t$(D 'uv.exe')", "core`tpack`t$(Join-Path $state 'pack')", "core`ttask`tMetaScience pack update", "course`tdir`t$(D 'course')")
  $code = Run-Un @('-Parts', 'ai', '-Yes')
  Check 'ai only, RStudio stays: exit 0' ($code -eq 0) "exit $code $(Out)"
  Check 'ai only, RStudio stays: the rest of the AI part removed' (-not (Test-Path (D 'mingit')) -and -not (Test-Path (D 'uv.exe')))
  Check 'ai only, RStudio stays: RStudio, the pack and the update task stay' ((Test-Path (D 'rstudio')) -and (Test-Path (Join-Path $state 'pack')) -and (LogOf) -notmatch 'schtasks\.exe /delete')
  Check 'ai only, RStudio stays: record still lists RStudio and the pack' (((Rec) -match '^rstudio\t').Count -eq 2 -and ((Rec) -match '^core\tpack\t').Count -eq 1 -and ((Rec) -match '^core\ttask\t').Count -eq 1 -and -not ((Rec) -match 'mingit')) ((Rec) -join ' | ')
  Check 'ai only, RStudio stays: says the pack stays' ((Out) -match 'The course pack stays until the other parts are removed') (Out)
  $code = Run-Un @('-Parts', 'all', '-Yes')
  Check 'ai only, then all: RStudio, the pack and the state folder gone' ($code -eq 0 -and -not (Test-Path (D 'rstudio')) -and -not (Test-Path $state) -and (Test-Path (D 'course\my-notes.txt'))) "exit $code $(Out)"

  # 8a. the uninstaller started directly also takes the setup's word, -Components
  Make-State
  $code = Run-Un @('-Components', 'rstudio', '-Yes')
  Check 'direct, -Components rstudio: RStudio gone, the rest stays' ($code -eq 0 -and -not (Test-Path (D 'rstudio')) -and (Test-Path $state)) "exit $code $(Out)"
  Make-State
  $code = Run-Un @('-Yes')
  Check '-Yes without parts: the message names -Components, the word install-windows.cmd takes' ($code -eq 2 -and (Out) -match '-Components') "exit $code $(Out)"

  # 8. the real route, from an installed pack: Windows cannot delete a folder a window works in (install-windows.cmd
  #    works in the pack folder), so the setup runs a copy from the temp folder and the rest goes when the window closes
  #    ('cmd, -Uninstall not first': the cmd must find -Uninstall in any place, not only as the first word)
  # 'powershell -Parts' / 'cmd -Parts': the uninstaller's own word for it works through the setup too (it was ignored, and
  #  the uninstaller then asked for -Parts again: a loop; found 2026-11-13)
  foreach ($route in 'powershell', 'cmd', 'cmd, -Uninstall not first', 'powershell -Parts', 'cmd -Parts') {
    Make-State
    $pack = Join-Path $state 'pack'
    foreach ($f in 'install-windows.cmd', 'setup-windows.ps1', 'VERSION') { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $pack }
    Copy-Item -LiteralPath (Join-Path $root 'lib\uninstall-windows.ps1') -Destination (Join-Path $pack 'lib')
    Set-Content -LiteralPath (Join-Path $state 'installed.tsv') -Value @("core`tpack`t$pack") -Encoding UTF8
    $in = D 'in.txt'; Set-Content -LiteralPath $in -Value @('', '') -Encoding ASCII
    $argv = if ($route -eq 'cmd') { @('/c', "`"`"$pack\install-windows.cmd`" -Uninstall -Components ai -Yes`"") }
            elseif ($route -eq 'cmd -Parts') { @('/c', "`"`"$pack\install-windows.cmd`" -Uninstall -Parts ai -Yes`"") }
            elseif ($route -eq 'powershell -Parts') { @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$pack\setup-windows.ps1`"", '-Uninstall', '-Parts', 'ai', '-Yes') }
            elseif ($route -like 'cmd*') { @('/c', "`"`"$pack\install-windows.cmd`" -Yes -Uninstall -Components ai`"") }
            else { @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$pack\setup-windows.ps1`"", '-Uninstall', '-Components', 'ai', '-Yes') }
    $exe = if ($route -like 'cmd*') { 'cmd.exe' } else { 'powershell.exe' }
    $p = Start-Process -FilePath $exe -ArgumentList $argv -WorkingDirectory $(if ($route -like 'cmd*') { $env:TEMP } else { $env:USERPROFILE }) `
         -RedirectStandardInput $in -RedirectStandardOutput (D 'out.txt') -RedirectStandardError (D 'err.txt') -PassThru -WindowStyle Hidden
    $null = $p.Handle; $p.WaitForExit()
    for ($i = 0; $i -lt 12 -and (Test-Path -LiteralPath $state); $i++) { Start-Sleep -Seconds 5 }   # the later removal
    $o = (Get-Content -LiteralPath (D 'out.txt') -Raw) + (Get-Content -LiteralPath (D 'err.txt') -Raw)
    Check "uninstall started with $route from the installed pack: the pack and the state folder are gone" (-not (Test-Path -LiteralPath $state)) $o
    Check "uninstall started with $route : no FAIL line, no 'batch file cannot be found'" ($o -notmatch 'FAIL' -and $o -notmatch 'cannot be found') $o
    Check "uninstall started with $route : exit code 0 passed on" ($p.ExitCode -eq 0) "exit $($p.ExitCode)"
  }
  # 8b. -RemoveCourse reaches the uninstaller through the setup (it was not passed on; found 2026-11-15)
  Make-State
  $pack = Join-Path $state 'pack'
  foreach ($f in 'install-windows.cmd', 'setup-windows.ps1', 'VERSION') { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $pack }
  Copy-Item -LiteralPath (Join-Path $root 'lib\uninstall-windows.ps1') -Destination (Join-Path $pack 'lib')
  Set-Content -LiteralPath (Join-Path $state 'installed.tsv') -Value @("core`tpack`t$pack", "course`tdir`t$(D 'course')") -Encoding UTF8
  $in = D 'in.txt'; Set-Content -LiteralPath $in -Value @('', '') -Encoding ASCII
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$pack\setup-windows.ps1`"", '-Uninstall', '-Components', 'ai', '-Yes', '-RemoveCourse') `
       -WorkingDirectory $env:USERPROFILE -RedirectStandardInput $in -RedirectStandardOutput (D 'out.txt') -RedirectStandardError (D 'err.txt') -PassThru -WindowStyle Hidden
  $null = $p.Handle; $p.WaitForExit()
  for ($i = 0; $i -lt 12 -and (Test-Path -LiteralPath $state); $i++) { Start-Sleep -Seconds 5 }
  Check 'setup -Uninstall -RemoveCourse -Yes: the course folder is deleted' (-not (Test-Path (D 'course'))) ((Get-Content -LiteralPath (D 'out.txt') -Raw) + (Get-Content -LiteralPath (D 'err.txt') -Raw))

  # 10. VS Code (added 2026-11-16): its add-ons go with VS Code's own command, before VS Code itself; the parts follow
  Make-State
  New-Item -ItemType Directory -Force -Path (D 'dotvscode') | Out-Null
  Set-Content -LiteralPath (Join-Path $state 'parts.txt') -Value 'r rstudio quarto python node vscode' -Encoding ASCII
  Add-Content -LiteralPath (Join-Path $state 'installed.tsv') -Encoding UTF8 -Value @("vscode`tvsext`tsst-dev.opencode", "vscode`tvsext`tms-python.python",
    "vscode`tvsext`tms-python.vscode-pylance", "vscode`twinget`tMicrosoft.VisualStudioCode", "vscode`tdir`t$(D 'dotvscode')")
  $code = Run-Un @('-Parts', 'vscode', '-Yes'); $log = LogOf
  Check 'vscode: exit 0' ($code -eq 0) "exit $code $(Out)"
  Check 'vscode: each recorded add-on removed with VS Code''s own command' (([regex]::Matches($log, 'would run: code --uninstall-extension (sst-dev\.opencode|ms-python\.python|ms-python\.vscode-pylance)')).Count -eq 3) $log
  Check 'vscode: the add-ons before VS Code itself' ($log.IndexOf('--uninstall-extension') -ge 0 -and $log.IndexOf('--uninstall-extension') -lt $log.IndexOf('Microsoft.VisualStudioCode')) $log
  Check 'vscode: VS Code removed by winget (exact id), its folder too' ($log -match 'would run: winget uninstall --id Microsoft\.VisualStudioCode --exact' -and -not (Test-Path (D 'dotvscode')))
  Check 'vscode: everything else untouched' ((Test-Path (D 'rstudio')) -and (Test-Path (D 'mingit')) -and (Test-Path (Join-Path $state 'pack')))
  Check 'vscode: record and parts no longer list it' (-not ((Rec) -match '^vscode') -and (Get-Content (Join-Path $state 'parts.txt') -Raw).Trim() -eq 'r rstudio quarto python node') ((Rec) -join ' | ')
  Make-State
  $code = Run-Un @() @('', '')
  Check 'vscode: not offered when the setup did not add anything to VS Code' ((Out) -notmatch 'VS Code') (Out)

  # 10b. VS Code was here before and is gone now: only the add-on folders the setup recorded are deleted
  Make-State
  $vsc = D 'vsc'; foreach ($d in 'sst-dev.opencode-1.0.0', 'ms-python.python-2026.10.0', 'someone.mine-1.0.0') { New-Item -ItemType Directory -Force -Path (Join-Path $vsc "ext\$d") | Out-Null }
  Add-Content -LiteralPath (Join-Path $state 'installed.tsv') -Encoding UTF8 -Value @("vscode`tvsext`tsst-dev.opencode", "vscode`tvsext`tms-python.python")
  $env:MS_TEST_CODE_DIR = $vsc; $env:MS_TEST_NO_CODE = '1'
  try { $code = Run-Un @('-Parts', 'vscode', '-Yes'); $log = LogOf } finally { Remove-Item Env:\MS_TEST_CODE_DIR, Env:\MS_TEST_NO_CODE -ErrorAction SilentlyContinue }
  Check 'vscode gone: exit 0, the recorded add-on folders deleted' ($code -eq 0 -and -not (Test-Path (Join-Path $vsc 'ext\sst-dev.opencode-1.0.0')) -and -not (Test-Path (Join-Path $vsc 'ext\ms-python.python-2026.10.0'))) "exit $code $(Out)"
  Check 'vscode gone: an add-on the student added stays' (Test-Path (Join-Path $vsc 'ext\someone.mine-1.0.0'))
  Check 'vscode gone: VS Code itself was not the setup''s, so winget is not asked' ($log -notmatch 'VisualStudioCode') $log

  # 7. the setup's own Record-Install: one line per thing, no duplicates, nothing in a dry run
  $tokens = $null; $errs = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$tokens, [ref]$errs)
  $def = ($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'Record-Install', 'Log' }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"
  $rs = Join-Path $work 'recstate'
  & ([scriptblock]::Create("$def`n`$StateDir = '$rs'; `$LogFile = '$work\r.log'; `$DryRun = `$false; Record-Install 'quarto' 'dir' 'C:\x'; Record-Install 'quarto' 'dir' 'C:\x'; Record-Install 'r' 'rpkg' 'irr'"))
  & ([scriptblock]::Create("$def`n`$StateDir = '$rs'; `$LogFile = '$work\r.log'; `$DryRun = `$true; Record-Install 'node' 'winget' 'X'"))
  $lines = @(Get-Content -LiteralPath (Join-Path $rs 'installed.tsv'))
  Check 'Record-Install: tab-separated lines, no duplicate, nothing in a dry run' ($lines.Count -eq 2 -and $lines[0] -eq "quarto`tdir`tC:\x" -and $lines[1] -eq "r`trpkg`tirr") ($lines -join ' | ')
} finally {
  foreach ($v in 'MS_STATE_DIR', 'MS_TEST_FAKE_UNINSTALL') { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
if ($fail) { exit 1 }
