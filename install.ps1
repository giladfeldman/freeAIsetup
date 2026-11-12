# =============================================================================
#  freeAIsetup one-line installer for Windows (PowerShell 5.1 or newer)
#
#  Students paste ONE line into PowerShell (Start menu > type "PowerShell" > Enter):
#
#    irm https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.ps1 | iex
#
#  SEEING THIS TEXT IN YOUR POWERSHELL WINDOW? Then the line was pasted without its ending  | iex
#  (PowerShell only showed this file instead of running it). Copy the WHOLE line again, including  | iex
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
#  A stop here (no download, a failed check, a blocked computer) offers to send a short report to the teacher's
#  log box, like the setup itself does.
#  Options for testing: $env:MS_UPDATE_SOURCES (same format as update\update.ps1), $env:MS_SETUP_ARGS,
#  $env:MS_LOG_URL and $env:MS_LOG_ENV (log box address and "local" marker, as in setup-windows.ps1).
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

  # Everything the installer saw, for the report a student may send when it stops (a stop here used to reach
  # nobody; student 2026-11-12). Same log box, header and redaction as setup-windows.ps1.
  $notes = New-Object Collections.ArrayList
  function Note($t) { [void]$notes.Add([string]$t) }
  function Stop-WithReport($step, $why) {
    $a = ''
    try { $a = Read-Host '  Send a short report to your teacher, so they can see what went wrong? It contains no passwords; your user name is removed. [Y/n]' } catch { $a = 'n' }   # no keyboard to ask on: send nothing
    if ($a -match '^(n|no)$') { return }
    try {
      $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
      $txt = "== installer (install.ps1) ==`nFAIL  $step  $why`n`nWindows: $($os.Caption) build $($os.BuildNumber), $env:PROCESSOR_ARCHITECTURE, PowerShell $($PSVersionTable.PSVersion)`n`n" + ($notes -join "`n")
      $txt = $txt -replace [regex]::Escape($env:USERPROFILE), '~'
      foreach ($w in @($env:USERNAME, $env:COMPUTERNAME)) { if ($w -and $w.Length -ge 4) { $txt = $txt -replace [regex]::Escape($w), '<name>' } }
      $box = if ($env:MS_LOG_URL) { $env:MS_LOG_URL.TrimEnd('/') } else { 'https://freeaisetup-logs.giladfel.workers.dev' }
      $h = @{ 'x-freeaisetup' = '1' }; if ($env:MS_LOG_ENV) { $h['x-freeaisetup-env'] = $env:MS_LOG_ENV }
      $ver = if ($manifest) { $manifest.version } else { 'installer' }
      $r = Invoke-WebRequest -Uri "$box/upload?platform=windows&version=$ver&result=failed" -Method Post -UseBasicParsing -TimeoutSec 60 `
           -Headers $h -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($txt))
      $id = ([string]$r.Content).Trim()
      if ($id) { Write-Host "  Sent. Your code is $id. Tell your teacher this code." -ForegroundColor Green; return }
    } catch {}
    Write-Host '  Could not send it (no internet?). Take a photo of this window for your teacher instead.' -ForegroundColor Yellow
  }

  Write-Host ''
  Write-Host '  MetaScience course setup: downloading the setup files...' -ForegroundColor Cyan
  $manifest = $null; $fileUrl = $null
  foreach ($src in $Sources) {
    $mUrl, $fUrl = $src -split '\|'
    try {
      $mBytes = Get-Bytes $mUrl
      $sBytes = [Convert]::FromBase64String([Text.Encoding]::ASCII.GetString((Get-Bytes ($mUrl -replace 'manifest\.json$', 'manifest.sig'))).Trim())
      if (-not (Test-Signature $mBytes $sBytes)) { Note "signature check failed: $mUrl"; Write-Host "  The files at $mUrl failed the signature check; trying another source." -ForegroundColor Yellow; continue }
      $manifest = [Text.Encoding]::UTF8.GetString($mBytes) | ConvertFrom-Json; $fileUrl = $fUrl; break
    } catch { Note "could not read $mUrl : $($_.Exception.Message)"; Write-Host "  Could not reach $($mUrl -replace '/release/.*$', '') ; trying another source." -ForegroundColor Yellow }
  }
  if (-not $manifest) {
    Write-Host ''
    Write-Host '  The setup files could not be downloaded. Check the internet connection and paste the line again.' -ForegroundColor Red
    Write-Host '  If it still fails, show this window to the teacher.' -ForegroundColor Red
    Stop-WithReport 'Installer download' 'no source gave a signed file list'
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
    Stop-WithReport 'Installer files' $_.Exception.Message
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
    Stop-WithReport 'Managed computer' "PowerShell policy $pol forbids setup scripts"
    return
  }
  Write-Host "  Version $($manifest.version) downloaded and checked. Starting the setup..." -ForegroundColor Cyan
  Write-Host ''
  $setupArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dir 'setup-windows.ps1'))
  if ($env:MS_SETUP_ARGS) { $setupArgs += ($env:MS_SETUP_ARGS -split ' ') }
  & powershell.exe @setupArgs
}
# SEEING THIS TEXT IN YOUR POWERSHELL WINDOW? Then the line was pasted without its ending  | iex
# Nothing was installed. Copy the WHOLE line from the guide again, including  | iex  at the end, and press Enter.
