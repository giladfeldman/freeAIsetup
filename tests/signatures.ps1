# The publisher-signature check on programs the setup downloads straight from their makers (d-4e90ed).
#   A. Signed-By from setup-windows.ps1 on files every Windows has: a signed Windows program is accepted only under
#      its own signer's name; an altered copy, an unsigned file and a text file are refused. No network.
#   B. (MS_TEST_REAL_SIGNERS=1) the real current downloads, checked against the setup's own signer list: R, Git
#      (MinGit), uv, OpenCode (command line and app). About 250 MB. Run before a release, or when a signer may have
#      changed; without the variable B is reported as SKIP, never as PASS. VS Code (290 MB), RStudio and Quarto
#      (700 MB, from RStudio's zip) are larger; their signers were read from the real downloads on 2026-11-16.
#   powershell -ExecutionPolicy Bypass -File tests\signatures.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP ("ms-sig-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$pass = 0; $fail = 0
function Check($name, [bool]$ok, $detail = '') { if ($ok) { "PASS $name"; $script:pass++ } else { "FAIL $name $detail"; $script:fail++ } }

$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-windows.ps1'), [ref]$null, [ref]$null)
$fn = @($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'Signed-By', 'Not-Signed' }, $true))
$tbl = @($ast.FindAll({ param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -eq '$Signers' }, $true))
Check 'setup has Signed-By, Not-Signed and its signer list' ($fn.Count -eq 2 -and $tbl.Count -eq 1)
$LogFile = Join-Path $work 'log.txt'; $DryRun = $false
function Log($m) { Add-Content -LiteralPath $LogFile -Value $m }
function Warn($i, $d = '') { Log "WARN $i $d" }
. ([scriptblock]::Create((($fn | ForEach-Object { $_.Extent.Text }) + $tbl[0].Extent.Text) -join "`n"))
$real = $Signers.Clone()

try {
  # ---------- A ----------
  $win = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $s = Get-AuthenticodeSignature -LiteralPath $win
  $who = $s.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
  Check 'control: Windows itself reads powershell.exe as validly signed' ("$($s.Status)" -eq 'Valid' -and $who) "$($s.Status) '$who'"
  $Signers['T'] = @($who); $Signers['Other'] = @('Posit Software, PBC')
  Check 'A signed program, under its own signer: accepted' (Signed-By $win 'T')
  Check 'A signed program, under another maker''s name: refused' (-not (Signed-By $win 'Other'))
  Check 'A a name missing from the list: refused' (-not (Signed-By $win 'Nobody'))
  $copy = Join-Path $work 'altered.exe'; $b = [IO.File]::ReadAllBytes($win); $b[$b.Length / 2] = $b[$b.Length / 2] -bxor 0xFF
  [IO.File]::WriteAllBytes($copy, $b)
  Check 'A an altered copy of a signed program: refused' (-not (Signed-By $copy 'T'))
  $txt = Join-Path $work 'x.exe'; Set-Content -LiteralPath $txt -Value 'x'
  Check 'A a file that is not a program: refused' (-not (Signed-By $txt 'T'))
  Check 'A the log names the result of each check' ((Get-Content -LiteralPath $LogFile -Raw) -match "signature of .*altered\.exe: \w+, signed by")
  Not-Signed 'Other' $txt 'Some step'
  Check 'A Not-Signed deletes the file and warns with the maker''s name' (-not (Test-Path $txt) -and (Get-Content -LiteralPath $LogFile -Raw) -match 'WARN Some step the download is not signed by Posit Software, PBC')
  $DryRun = $true; Check 'A a dry run checks nothing' (Signed-By $txt 'T'); $DryRun = $false

  # every program the setup downloads and runs or keeps is checked (a new download without a check fails here)
  $body = Get-Content -LiteralPath (Join-Path $root 'setup-windows.ps1') -Raw
  foreach ($n in 'VS Code', 'R', 'RStudio', 'Quarto', 'Git', 'uv', 'OpenCode') {
    Check "A the setup checks the $n download" ($body -match "Signed-By [^\r\n]+ '$n'")
  }

  # ---------- B ----------
  $Signers = $real
  if ($env:MS_TEST_REAL_SIGNERS -ne '1') { 'SKIP B real downloads (set MS_TEST_REAL_SIGNERS=1)' }
  else {
    $ProgressPreference = 'SilentlyContinue'
    function Get($u, $f) { Invoke-WebRequest -Uri $u -OutFile (Join-Path $work $f) -UseBasicParsing -UserAgent 'MetaScience-setup'; Join-Path $work $f }
    function Unzip($z) { $d = "$z-x"; Expand-Archive -LiteralPath $z -DestinationPath $d -Force; $d }
    $page = (Invoke-WebRequest -Uri 'https://cloud.r-project.org/bin/windows/base/release.html' -UseBasicParsing).Content
    $rn = if ($page -match 'URL=(R-[0-9.]+-win\.exe)') { $Matches[1] } else { 'R-4.6.2-win.exe' }
    Check "B R ($rn) is signed by the listed signer" (Signed-By (Get "https://cloud.r-project.org/bin/windows/base/$rn" 'r.exe') 'R') (Get-Content $LogFile -Tail 1)
    $loc = ([Net.WebRequest]::Create('https://github.com/git-for-windows/git/releases/latest')); $loc.AllowAutoRedirect = $false
    $rs = $loc.GetResponse(); $tag = ($rs.Headers['Location'] -split '/')[-1]; $rs.Close()
    $gv = if ($tag -match '^v([0-9.]+)\.windows\.([0-9]+)$') { if ($Matches[2] -eq '1') { $Matches[1] } else { "$($Matches[1]).$($Matches[2])" } }
    $g = Unzip (Get "https://github.com/git-for-windows/git/releases/download/$tag/MinGit-$gv-64-bit.zip" 'mingit.zip')
    Check "B Git (MinGit $gv) is signed by the listed signer" (Signed-By (Join-Path $g 'cmd\git.exe') 'Git') (Get-Content $LogFile -Tail 1)
    $u = Unzip (Get 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip' 'uv.zip')
    Check 'B uv (latest) is signed by the listed signer' (Signed-By (Join-Path $u 'uv.exe') 'uv') (Get-Content $LogFile -Tail 1)
    $ocv = if ($body -match "\`$OpenCodeVersion = '([0-9.]+)'") { $Matches[1] }
    $o = Unzip (Get "https://github.com/anomalyco/opencode/releases/download/v$ocv/opencode-windows-x64-baseline.zip" 'oc.zip')
    Check "B OpenCode $ocv (command line) is signed by the listed signer" (Signed-By (Join-Path $o 'opencode.exe') 'OpenCode') (Get-Content $LogFile -Tail 1)
    Check "B OpenCode $ocv (app) is signed by the listed signer" (Signed-By (Get "https://github.com/anomalyco/opencode/releases/download/v$ocv/opencode-desktop-win-x64.exe" 'ocd.exe') 'OpenCode') (Get-Content $LogFile -Tail 1)
  }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
"RESULT pass=$pass fail=$fail"
exit $fail
