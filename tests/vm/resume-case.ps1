# Resume watching a case whose setup is still running in the VM (the host-side watcher was killed).
# Runs the polling and result-collection tail of run-case.ps1 without restoring or re-preparing the VM.
# Usage: resume-case.ps1 -Tag B1-standard-user [-MaxMin 150] [-KeepRunning]
param([Parameter(Mandatory)][string]$Tag, [int]$MaxMin = 150, [switch]$KeepRunning)
. "$PSScriptRoot\vmlib.ps1"
$res = Join-Path $Results $Tag
New-Item -ItemType Directory -Force $res | Out-Null
function Note($t) { $l = (Get-Date -Format HH:mm:ss) + " [$Tag] $t"; Write-Output $l; Add-Content -LiteralPath (Join-Path $res 'host.txt') -Value $l }
$During = ''; $DuringAfterMin = 0
Note 'resumed watching (watcher had stopped)'
$src = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'run-case.ps1')
$tail = $src.Substring($src.IndexOf('$t0 = Get-Date'))
. ([scriptblock]::Create($tail))
