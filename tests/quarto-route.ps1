# Quarto when GitHub is blocked (d-e4a52e): quarto.org's download goes on to GitHub, so the setup takes the Quarto
# inside RStudio (Posit's own server). Tests the functions of setup-windows.ps1 on scratch folders, with a small
# stand-in RStudio zip; nothing real is downloaded or installed. Run: powershell -ExecutionPolicy Bypass -File tests\quarto-route.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP ("ms-qroute-{0}" -f [guid]::NewGuid())
$pass = 0; $fail = 0
function Check($name, [bool]$ok, $detail = '') { if ($ok) { "PASS $name"; $script:pass++ } else { "FAIL $name $detail"; $script:fail++ } }

$tokens = $null; $errs = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$tokens, [ref]$errs)
$want = 'Install-QuartoDirect', 'Install-QuartoFromRStudio', 'RStudio-ZipUrls', 'Find-Tool', 'Tool-Defs', 'Tool-Def', 'Run-Native', 'Log', 'Say'
$def = ($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in $want }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"
$saveLa = $env:LOCALAPPDATA; $savePf = $env:ProgramFiles; $savePf86 = ${env:ProgramFiles(x86)}; $saveTemp = $env:TEMP
try {
  # a stand-in RStudio zip: rstudio.exe, other RStudio files, and the Quarto inside it
  $src = Join-Path $work 'zipsrc'
  foreach ($f in 'rstudio.exe', 'resources\app\other.txt', 'resources\app\bin\quarto\bin\quarto.exe', 'resources\app\bin\quarto\share\version') {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $src $f)) | Out-Null; Set-Content -LiteralPath (Join-Path $src $f) -Value 'x'
  }
  $fakeZip = Join-Path $work 'RStudio-fake.zip'
  & (Join-Path $env:SystemRoot 'System32\tar.exe') -a -cf $fakeZip -C $src rstudio.exe resources
  $la = Join-Path $work 'la'; $pf = Join-Path $work 'pf'; $tmp = Join-Path $work 'tmp'
  New-Item -ItemType Directory -Force -Path $la, $pf, $tmp | Out-Null
  $env:LOCALAPPDATA = $la; $env:ProgramFiles = $pf; ${env:ProgramFiles(x86)} = ''; $env:TEMP = $tmp
  # stand-ins: GitHub blocked; quarto.org's download fails (it goes on to GitHub); Posit's zip is the stand-in zip
  $stubs = @"
`$script:Blocked = @('github.com'); `$DryRun = `$false; `$LogFile = '$work\t.log'
function Have(`$n) { `$false }
function Download(`$u, `$d) { Add-Content -LiteralPath '$work\urls.txt' -Value `$u; if (`$u -like '*rstudio*') { Copy-Item -LiteralPath '$fakeZip' -Destination `$d; return `$true }; return `$false }
function Invoke-RestMethod { throw 'offline' }
"@
  $common = "$def`n$stubs`n"

  # 1. no RStudio on the computer: the Quarto is unpacked from RStudio's zip, and only the Quarto
  $r = & ([scriptblock]::Create("$common Install-QuartoDirect"))
  $q = Join-Path $la 'Programs\Quarto'
  Check 'no RStudio: Quarto unpacked from RStudio''s zip into this account''s Programs\Quarto' ($r -eq "$q\bin" -and (Test-Path "$q\bin\quarto.exe") -and (Test-Path "$q\share\version")) "got $r"
  Check 'no RStudio: nothing else of RStudio is kept' (-not (Test-Path "$q\rstudio.exe") -and -not (Test-Path "$q\resources") -and -not (Test-Path "$q\other.txt")) ((Get-ChildItem -Recurse $q | ForEach-Object FullName) -join ', ')
  $urls = @(Get-Content -LiteralPath "$work\urls.txt")
  Check 'GitHub blocked: no download from github.com was tried' (-not ($urls -match 'github\.com')) ($urls -join ', ')
  Check 'quarto.org first, then Posit''s server' ($urls[0] -like 'https://quarto.org/*' -and ($urls -match 'download1\.rstudio\.org').Count -ge 1) ($urls -join ', ')
  Check 'the downloaded zip is deleted afterwards' (-not (Test-Path (Join-Path $tmp 'rstudio-win.zip')))

  # 2. RStudio already installed (this run, or before): its own Quarto, no download
  Remove-Item -LiteralPath $q, "$work\urls.txt" -Recurse -Force
  $rs = Join-Path $pf 'RStudio'
  New-Item -ItemType Directory -Force -Path "$rs\resources\app\bin\quarto\bin" | Out-Null
  Set-Content "$rs\rstudio.exe" 'x'; Set-Content "$rs\resources\app\bin\quarto\bin\quarto.exe" 'x'
  $r = & ([scriptblock]::Create("$common Install-QuartoDirect"))
  Check 'RStudio installed: the Quarto inside it is used' ($r -eq "$rs\resources\app\bin\quarto\bin") "got $r"
  Check 'RStudio installed: nothing downloaded from Posit' (-not ((Get-Content -LiteralPath "$work\urls.txt" -ErrorAction SilentlyContinue) -match 'rstudio'))

  # 3. the order: RStudio before Quarto, so an RStudio installed in this run can lend its Quarto
  $names = @(& ([scriptblock]::Create("$common (Tool-Defs).name")))
  Check 'tool order: RStudio before Quarto' ([array]::IndexOf($names, 'RStudio') -lt [array]::IndexOf($names, 'Quarto')) ($names -join ', ')

  # 4. the caller records an RStudio Quarto as a PATH entry only (the uninstall must not delete RStudio's files)
  $body = (Get-Content -LiteralPath (Join-Path $root 'setup-windows.ps1') -Raw)
  Check 'caller: a Quarto inside RStudio is recorded as path, its own folder as dir' ($body -match "Record-Install 'quarto' 'path' \`$qbin" -and $body -match "Record-Install 'quarto' 'dir'")
} finally {
  $env:LOCALAPPDATA = $saveLa; $env:ProgramFiles = $savePf; ${env:ProgramFiles(x86)} = $savePf86; $env:TEMP = $saveTemp
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"RESULT pass=$pass fail=$fail"
exit $fail
