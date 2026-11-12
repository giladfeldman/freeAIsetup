# An R older than 4.5 on Windows (d-872f0e): the setup must find a current R next to it, or install one, and put
# it first on this account's PATH, keeping the old R. Tests the functions of setup-windows.ps1 on scratch folders:
# no real R, PATH or registry is read or changed. Run: powershell -ExecutionPolicy Bypass -File tests\r-current.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP ("ms-rcur-{0}" -f [guid]::NewGuid())
$pass = 0; $fail = 0
function Check($name, [bool]$ok, $detail = '') { if ($ok) { "PASS $name"; $script:pass++ } else { "FAIL $name $detail"; $script:fail++ } }

$tokens = $null; $errs = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$tokens, [ref]$errs)
$want = 'R-Version', 'Find-CurrentR', 'Put-PathFirst', 'Split-PathList', 'Record-Install', 'Log', 'Say', 'Warn'
$def = ($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in $want }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"
# stand-ins: no command on PATH, no registry, the user PATH is a variable
$stubs = @'
$RMin = [version]'4.5'
function Have($n) { $false }
function Get-ItemProperty { $null }
function Get-UserPathRaw { $script:FakeUserPath }
function Set-UserPathRaw([string]$v) { $script:FakeUserPath = $v }
'@
$savePath = $env:Path; $savePf = $env:ProgramFiles; $savePf86 = ${env:ProgramFiles(x86)}; $saveLa = $env:LOCALAPPDATA
try {
  $pf = Join-Path $work 'pf'; $la = Join-Path $work 'la'
  function Mk($d) { New-Item -ItemType Directory -Force -Path $d | Out-Null; Set-Content -LiteralPath (Join-Path $d 'Rscript.exe') -Value '' }
  Mk "$pf\R\R-4.4.0\bin"; Mk "$pf\R\R-4.5.0\bin"; Mk "$la\Programs\R\R-4.6.1\bin"
  New-Item -ItemType Directory -Force -Path "$la\Programs\R\R-9.9.9\bin" | Out-Null   # no Rscript.exe: not an R
  $env:ProgramFiles = $pf; ${env:ProgramFiles(x86)} = ''; $env:LOCALAPPDATA = $la
  $common = "$def`n$stubs`n`$StateDir = '$work\state'; `$LogFile = '$work\t.log'; `$DryRun = `$false`n"

  $r = & ([scriptblock]::Create("$common Find-CurrentR"))
  Check 'Find-CurrentR: the newest R 4.5 or newer (this account''s R 4.6.1, not 4.5.0, not the old 4.4.0)' ($r -eq "$la\Programs\R\R-4.6.1\bin") "got $r"
  $v = & ([scriptblock]::Create("$common R-Version '$pf\R\R-4.4.0\bin'"))
  Check 'R-Version: read from the folder name' ($v -eq [version]'4.4.0') "got $v"

  Remove-Item -LiteralPath "$pf\R\R-4.5.0", "$la\Programs\R\R-4.6.1" -Recurse -Force
  $r = & ([scriptblock]::Create("$common Find-CurrentR"))
  Check 'Find-CurrentR: only an old R -> none (so a current R is installed)' (-not $r) "got $r"

  $new = 'C:\Users\x\AppData\Local\Programs\R\R-4.6.2\bin'
  $env:Path = 'C:\Windows;C:\Program Files\R\R-4.4.0\bin'
  $out = & ([scriptblock]::Create("$common `$script:FakeUserPath = 'C:\a;C:\Program Files\R\R-4.4.0\bin;%USERPROFILE%\x'; Put-PathFirst '$new'; Put-PathFirst '$new'; `$script:FakeUserPath; '---'; `$env:Path"))
  $userPath = $out[0]; $sessPath = $out[2]
  Check 'Put-PathFirst: the new R first on the user PATH, every other entry kept in order (old R stays)' ($userPath -eq "$new;C:\a;C:\Program Files\R\R-4.4.0\bin;%USERPROFILE%\x") $userPath
  Check 'Put-PathFirst: the new R first in this window too' ($sessPath -like "$new;*" -and $sessPath -like '*R-4.4.0\bin*') $sessPath
  $rec = @(Get-Content -LiteralPath "$work\state\installed.tsv" -ErrorAction SilentlyContinue)
  Check 'Put-PathFirst: the PATH entry is recorded once (for the uninstall)' ($rec.Count -eq 1 -and $rec[0] -eq "core`tpath`t$new") ($rec -join ' | ')

  Remove-Item -LiteralPath "$work\state" -Recurse -Force
  $out = & ([scriptblock]::Create("$common `$script:FakeUserPath = 'C:\a;$new'; Put-PathFirst '$new'; `$script:FakeUserPath"))
  Check 'Put-PathFirst: an entry already on the PATH is moved first, not recorded as added by the setup' ($out -eq "$new;C:\a" -and -not (Test-Path "$work\state\installed.tsv")) "$out"

  $text = Get-Content -LiteralPath (Join-Path $root 'setup-windows.ps1') -Raw
  Check 'Install-RDirect: one-account install switches (no admin), into this account''s Programs folder' ($text -match "'/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER'" -and $text -match "Programs\\R\\")
  Check 'Install-Tools: the R it installs is recorded for the uninstall (inno)' ($text -match "Record-Install 'r' 'inno' \`$rdir")
} finally {
  $env:Path = $savePath; $env:ProgramFiles = $savePf; ${env:ProgramFiles(x86)} = $savePf86; $env:LOCALAPPDATA = $saveLa
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
if ($fail) { exit 1 }
