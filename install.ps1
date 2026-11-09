# =============================================================================
#  freeAIsetup one-line installer for Windows (PowerShell 5.1 or newer)
#
#  Students paste ONE line into PowerShell (Start menu > type "PowerShell" > Enter):
#
#    irm https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.ps1 | iex
#
#  If GitHub is blocked, the same file comes from jsDelivr (a free public mirror of GitHub):
#
#    irm https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/install.ps1 | iex
#
#  Why a pasted line instead of the zip: files a browser downloads are marked "from the internet",
#  and Windows Smart App Control blocks marked scripts that carry no paid code-signing certificate,
#  with no "run anyway" button. Files this installer downloads itself carry no such mark.
#
#  What it does: downloads the signed list of the current release (manifest), checks its signature
#  against the public key below, downloads every file in that list and checks each file's SHA-256,
#  then starts the normal setup (setup-windows.ps1). A file that fails a check stops the install.
#  Options for testing: $env:MS_UPDATE_SOURCES (same format as update\update.ps1), $env:MS_SETUP_ARGS.
# =============================================================================
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $PubKey = '<RSAKeyValue><Modulus>6GBNEcoCRllHdfOkRQwk9Z82PoqIo5MyTvsPHBro9g2Mrm/nyCc0mllmRKljYcX/o67z4yYsKpYycQsuZczgCsIxHDe/ks4CQp1UwXAihkarJfsX3oI77Kj7Cp+R9tBmZw9OTxGrclmtMVTGVeGLMPRU69NthpxlIznQoYPRu1DikktWAr+kmhbQMlV4zY4OMRjzj4suuODZTkdrETkyj2MTH3y/Xi0VRtu2JJ3O6nPfNg8VU3IUJPXh3102ZR7F77hcUxMyhR1meVb7XRewiZ3TxHJ2G++qnS4rdZohxs4BSYrh5Q5c6geNzNZh0FNWEoeOdVqg5qInGgBIIjC6vvO4oM3wDl33lsD59GKvP2VZvv2hWTx6uvbmBoRzIR6D1ynvk4J4FQW8Cl3769KbCV0KHKp94sa+RS3R8jjDk7QL9Wseo0CQOXsiK7IYitawCcpffLtzdeo5fvHiGZHlfYLUKs+KlwabPzetzAsEq4vOZazV0eyeYWRWuNSATmUN</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
  $Sources = if ($env:MS_UPDATE_SOURCES) { $env:MS_UPDATE_SOURCES -split ';' } else { @(
    'https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/release/manifest.json|https://raw.githubusercontent.com/giladfeldman/freeAIsetup/v{V}/{P}',
    'https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/release/manifest.json|https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@v{V}/{P}'
  ) }

  function Get-Bytes($url) {
    $u = if ($url -match '^https?://') { $url + $(if ($url -match '\?') { '&' } else { '?' }) + 't=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } else { $url }
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = 'freeAIsetup-installer'
    return $wc.DownloadData($u)
  }
  function Sha256Bytes([byte[]]$b) { $h = [Security.Cryptography.SHA256]::Create(); return (-join ($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') })) }
  function Test-Signature([byte[]]$data, [byte[]]$sig) {
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    $rsa.FromXmlString($PubKey)
    return $rsa.VerifyData($data, [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'), $sig)
  }

  Write-Host ''
  Write-Host '  MetaScience course setup: downloading the setup files...' -ForegroundColor Cyan
  $manifest = $null; $fileUrl = $null
  foreach ($src in $Sources) {
    $mUrl, $fUrl = $src -split '\|'
    try {
      $mBytes = Get-Bytes $mUrl
      $sBytes = [Convert]::FromBase64String([Text.Encoding]::ASCII.GetString((Get-Bytes ($mUrl -replace 'manifest\.json$', 'manifest.sig'))).Trim())
      if (-not (Test-Signature $mBytes $sBytes)) { Write-Host "  The files at $mUrl failed the signature check; trying another source." -ForegroundColor Yellow; continue }
      $manifest = [Text.Encoding]::UTF8.GetString($mBytes) | ConvertFrom-Json; $fileUrl = $fUrl; break
    } catch { Write-Host "  Could not reach $($mUrl -replace '/release/.*$', '') ; trying another source." -ForegroundColor Yellow }
  }
  if (-not $manifest) {
    Write-Host ''
    Write-Host '  The setup files could not be downloaded. Check the internet connection and paste the line again.' -ForegroundColor Red
    Write-Host '  If it still fails, show this window to the teacher.' -ForegroundColor Red
    return
  }

  $dir = Join-Path $env:LOCALAPPDATA ("MetaScience\installer\" + $manifest.version)
  try {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($p in $manifest.files.PSObject.Properties) {
      $rel = $p.Name
      if ($rel -match '(^|/)\.\.(/|$)' -or $rel -match '^[/\\]' -or $rel -match ':') { throw "unsafe path in the file list: $rel" }
      $b = Get-Bytes (($fileUrl -replace '\{V\}', $manifest.version) -replace '\{P\}', $rel)
      if ((Sha256Bytes $b) -ne $p.Value) { throw "the file $rel failed its checksum" }
      $dest = Join-Path $dir ($rel -replace '/', '\')
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      [IO.File]::WriteAllBytes($dest, $b)
    }
  } catch {
    Write-Host ''
    Write-Host "  Download stopped: $($_.Exception.Message). Paste the line again; if it fails twice, show this window to the teacher." -ForegroundColor Red
    return
  }
  # An organisation can forbid scripts on its computers (group policy); then the setup cannot run here.
  $pol = Get-ExecutionPolicy -Scope MachinePolicy
  if ($pol -eq 'Undefined') { $pol = Get-ExecutionPolicy -Scope UserPolicy }
  if ($pol -eq 'AllSigned' -or $pol -eq 'Restricted') {
    Write-Host ''
    Write-Host "  This computer is managed by an organisation (for example a university or employer), and its" -ForegroundColor Red
    Write-Host "  rules forbid running setup scripts (PowerShell policy: $pol)." -ForegroundColor Red
    Write-Host '  Please use your own laptop for the course, or ask IT to install: Git, Node.js, uv, R, RStudio,' -ForegroundColor Red
    Write-Host '  Quarto and OpenCode. Show this message to the teacher.' -ForegroundColor Red
    return
  }
  Write-Host "  Version $($manifest.version) downloaded and checked. Starting the setup..." -ForegroundColor Cyan
  Write-Host ''
  $setupArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dir 'setup-windows.ps1'))
  if ($env:MS_SETUP_ARGS) { $setupArgs += ($env:MS_SETUP_ARGS -split ' ') }
  & powershell.exe @setupArgs
}
