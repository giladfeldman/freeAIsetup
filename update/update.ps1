# =============================================================================
#  freeAIsetup pack updater (Windows PowerShell 5.1)
#  Checks the published release, verifies its signature, downloads only the files that changed,
#  keeps the previous version for rollback, then re-runs the setup quietly so new tools get installed.
#  The setup never upgrades or removes software that is already installed, and never touches the
#  student's own files (changed course files are kept; the new version is saved as name.new).
#
#    update.ps1            check and update now (shows what happens)
#    update.ps1 -Auto      quiet run from the scheduled task (skips while OpenCode or RStudio is open)
#    update.ps1 -Rollback  go back to the previous version
#    update.ps1 -CheckOnly say whether an update is available, change nothing
# =============================================================================
param([switch]$Auto, [switch]$Rollback, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Pack = Split-Path -Parent $PSScriptRoot                         # ...\MetaScience\pack
$Prev = Join-Path (Split-Path -Parent $Pack) 'pack-previous'
$State = Join-Path (Split-Path -Parent $Pack) 'update-log.txt'
$CourseDir = if ($env:METASCIENCE_DIR) { $env:METASCIENCE_DIR } else { Join-Path $env:USERPROFILE 'MetaScience' }
# Where releases come from: GitHub first, jsDelivr (a free mirror of GitHub files) second.
# Each source = manifest URL | file URL ({V} = version, {P} = file path). Tests override with MS_UPDATE_SOURCES.
$Sources = if ($env:MS_UPDATE_SOURCES) { $env:MS_UPDATE_SOURCES -split ';' } else { @(
  'https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/release/manifest.json|https://raw.githubusercontent.com/giladfeldman/freeAIsetup/v{V}/{P}',
  'https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/release/manifest.json|https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@v{V}/{P}'
) }

function Note($t) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $t
  try { Add-Content -LiteralPath $State -Value $line -Encoding UTF8 } catch {}
  if (-not $Auto) { Write-Host "  $t" }
}
function Get-Bytes($url) {
  $u = if ($url -match '^https?://') { $url + $(if ($url -match '\?') { '&' } else { '?' }) + 't=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } else { $url }
  $wc = New-Object Net.WebClient
  $wc.Headers['User-Agent'] = 'freeAIsetup-updater'
  return $wc.DownloadData($u)
}
function Sha256Bytes([byte[]]$b) { $h = [Security.Cryptography.SHA256]::Create(); return (-join ($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') })) }
function Sha256File($p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Test-Signature([byte[]]$data, [byte[]]$sig) {
  $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
  $rsa.FromXmlString((Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'pubkey.xml')))
  return $rsa.VerifyData($data, [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'), $sig)
}
function Version-Of($s) { try { return [version]($s.Trim()) } catch { return [version]'0.0' } }

# Files are copied in place (never renaming the pack folder, which this script runs from).
function Sync-Folder($from, $to) {
  New-Item -ItemType Directory -Force -Path $to | Out-Null
  Get-ChildItem -LiteralPath $to -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($to.Length + 1)
    if (-not (Test-Path -LiteralPath (Join-Path $from $rel))) { Remove-Item -LiteralPath $_.FullName -Force }
  }
  Get-ChildItem -LiteralPath $from -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($from.Length + 1); $d = Join-Path $to $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $d -Force
  }
}
if ($Rollback) {
  if (-not (Test-Path -LiteralPath (Join-Path $Prev 'VERSION'))) { Write-Host 'No previous version is stored.'; exit 1 }
  Sync-Folder $Prev $Pack
  Note "rolled back to $((Get-Content -LiteralPath (Join-Path $Pack 'VERSION')).Trim())"
  exit 0
}

$current = Version-Of (Get-Content -Raw -LiteralPath (Join-Path $Pack 'VERSION'))
# 1. the newest manifest whose signature is valid
$manifest = $null; $fileUrl = $null
foreach ($src in $Sources) {
  $mUrl, $fUrl = $src -split '\|'
  try {
    $mBytes = Get-Bytes $mUrl
    $sBytes = [Convert]::FromBase64String([Text.Encoding]::ASCII.GetString((Get-Bytes ($mUrl -replace 'manifest\.json$', 'manifest.sig'))).Trim())
    if (-not (Test-Signature $mBytes $sBytes)) { Note "REFUSED: the update from $mUrl has an invalid signature"; continue }
    $manifest = [Text.Encoding]::UTF8.GetString($mBytes) | ConvertFrom-Json; $fileUrl = $fUrl; break
  } catch { Note "could not reach $($mUrl -replace '/release/.*$', '') : $($_.Exception.Message)" }
}
if (-not $manifest) { Note 'no update source reachable; nothing changed'; exit 0 }
$latest = Version-Of $manifest.version
if ($latest -le $current) { Note "up to date ($current)"; exit 0 }
if ($CheckOnly) { Note "update available: $current -> $latest"; exit 0 }
if ($Auto -and (Get-Process -Name 'opencode*', 'rstudio', 'OpenCode*' -ErrorAction SilentlyContinue)) {
  Note "update $latest waits: OpenCode or RStudio is open"; exit 0
}

# 2. download every changed file into a staging copy, checking each SHA-256 against the signed manifest
$stage = "$Pack.staging"
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $Pack -Destination $stage -Recurse
$want = @{}
foreach ($p in $manifest.files.PSObject.Properties) { $want[$p.Name] = $p.Value }
$changed = 0
try {
  foreach ($rel in $want.Keys) {
    if ($rel -match '(^|/)\.\.(/|$)' -or $rel -match '^[/\\]' -or $rel -match ':') { throw "unsafe path in manifest: $rel" }
    $dest = Join-Path $stage ($rel -replace '/', '\')
    if ((Test-Path -LiteralPath $dest) -and (Sha256File $dest) -eq $want[$rel]) { continue }
    $b = Get-Bytes (($fileUrl -replace '\{V\}', $manifest.version) -replace '\{P\}', $rel)
    if ((Sha256Bytes $b) -ne $want[$rel]) { throw "checksum mismatch for $rel" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    [IO.File]::WriteAllBytes($dest, $b); $changed++
  }
  # files that the new version no longer has
  Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length + 1) -replace '\\', '/'
    if (-not $want.ContainsKey($rel)) { Remove-Item -LiteralPath $_.FullName -Force }
  }
} catch {
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  Note "update $latest NOT applied: $($_.Exception.Message)"; exit 1
}
# 3. keep the current version for rollback, then copy the new files in
Remove-Item -LiteralPath $Prev -Recurse -Force -ErrorAction SilentlyContinue
Sync-Folder $Pack $Prev
Sync-Folder $stage $Pack
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Note "updated $current -> $latest ($changed files)"
# 4. re-run the setup quietly so new tools and course files arrive
$ps = Join-Path $Pack 'setup-windows.ps1'
if ($env:MS_UPDATE_NO_SETUP) { Note 'test mode: setup re-run skipped'; exit 0 }
$p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ps`"", '-Yes', '-FromUpdate') -PassThru -Wait -WindowStyle $(if ($Auto) { 'Hidden' } else { 'Normal' })
Note "setup after update finished (exit $($p.ExitCode))"
try {
  New-Item -ItemType Directory -Force -Path $CourseDir | Out-Null
  Add-Content -LiteralPath (Join-Path $CourseDir 'UPDATES.txt') -Encoding UTF8 -Value ("{0}  updated the course pack to {1}. Notes: {2}" -f (Get-Date -Format 'yyyy-MM-dd'), $latest, $manifest.notes)
} catch {}
exit 0
