# Tests that lift functions out of setup-windows.ps1 by name (Ok, Warn, Install-QuartoDirect ...) break when a lifted
# function starts calling another setup function the test did not lift: the step then dies with "Row is not
# recognized" inside the test only (2026-11-24: Ok/Warn/Fail began calling Row; quarto-route and vscode failed).
# This check finds, for every test file, each setup function it names and each setup function those call; every
# callee must also be named in the test, or defined by the test itself (a stand-in).
#   powershell -ExecutionPolicy Bypass -File tests\lifted-helpers.ps1 [-Root <folder to check>]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { $script:pass++; "PASS $name" } else { $script:fail++; "FAIL $name  $detail" } }

$t = $null; $e = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'setup-windows.ps1'), [ref]$t, [ref]$e)
$defs = New-Object 'System.Collections.Generic.Dictionary[string,object]'   # case-sensitive: the word FAIL is not Fail
foreach ($f in $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $defs[$f.Name] = $f }
Check 'setup-windows.ps1 has functions to lift' ($defs.Count -gt 50) "found $($defs.Count)"

$tests = @(Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -Filter '*.ps1' | Where-Object { $_.Name -ne 'lifted-helpers.ps1' })
$checked = 0
foreach ($file in $tests) {
  $text = Get-Content -LiteralPath $file.FullName -Raw
  if ($text -notmatch 'setup-windows\.ps1' -or $text -notmatch 'FunctionDefinitionAst') { continue }
  $ta = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$t, [ref]$e)
  # the names this test lifts: the strings in each statement that picks FunctionDefinitionAst by name, and in the
  # assignments to the variables such a statement reads ($want = 'Log', 'Say', ...)
  $lifted = New-Object 'System.Collections.Generic.Dictionary[string,int]'
  $picks = @($ta.FindAll({ param($a) ($a -is [Management.Automation.Language.StatementAst]) -and (($a.Parent -is [Management.Automation.Language.NamedBlockAst]) -or ($a.Parent -is [Management.Automation.Language.StatementBlockAst])) }, $true) |
             Where-Object { $_.Extent.Text -match 'FunctionDefinitionAst' -and $_.Extent.Text -match '\.Name' -and $_.Extent.Text.Length -lt 600 })
  $vars = @{}
  foreach ($pk in $picks) { foreach ($v in $pk.FindAll({ param($a) $a -is [Management.Automation.Language.VariableExpressionAst] }, $true)) { $vars[$v.VariablePath.UserPath] = 1 } }
  $sources = @($picks) + @($ta.FindAll({ param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left -is [Management.Automation.Language.VariableExpressionAst] -and $vars.ContainsKey($a.Left.VariablePath.UserPath) }, $true))
  foreach ($src in $sources) {
    foreach ($s in $src.FindAll({ param($a) $a -is [Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
      if ($defs.ContainsKey($s.Value)) { $lifted[$s.Value] = 1 }
    }
  }
  if ($lifted.Count -eq 0) { continue }
  $checked++
  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($n in @($lifted.Keys)) {
    foreach ($c in $defs[$n].Body.FindAll({ param($a) $a -is [Management.Automation.Language.CommandAst] }, $true)) {
      $callee = $c.GetCommandName()
      if (-not $callee -or $callee -eq $n -or -not $defs.ContainsKey($callee) -or $lifted.ContainsKey($callee)) { continue }
      # a stand-in the test defines itself (as code or inside a here-string it runs) counts as provided
      if ($text -match ('(?im)(^|[;{])\s*function\s+' + [regex]::Escape($callee) + '\b')) { continue }
      if (-not $missing.Contains("$n -> $callee")) { $missing.Add("$n -> $callee") }
    }
  }
  Check "$($file.Name): every setup function its lifted functions call is lifted too" ($missing.Count -eq 0) ($missing -join ', ')
}
# every test that lifts from the setup must be seen: a test that drops out of the check is a false green
Check 'every lifting test was checked (exit-paths, quarto-route, r-current, signatures, uninstall, vscode)' ($checked -ge 6) "checked $checked"
"RESULT pass=$pass fail=$fail"
exit $fail
