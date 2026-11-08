# =============================================================================
#  Meta-science course: one-step setup for Windows 10/11
#  Installs: OpenCode (desktop + command line), Git, Node.js, uv + Python,
#            R + course packages, RStudio, Quarto; creates %USERPROFILE%\MetaScience;
#            runs a real end-to-end check that uses every installed tool.
#  Safe to run again: it skips what is already installed and repairs the rest.
#
#  Start it by double-clicking install-windows.cmd (recommended), or:
#    powershell -ExecutionPolicy Bypass -File setup-windows.ps1 [-Check] [-Keys] [-Fix] [-DryRun] [-SkipAI]
#  Written for Windows PowerShell 5.1 (the Windows default).
# =============================================================================
param(
  [switch]$Check,     # only run the check (doctor)
  [switch]$Keys,      # add optional free AI keys
  [switch]$DryRun,    # show what would be done, change nothing
  [switch]$SkipAI,    # run the check without calling the AI
  [switch]$NoGui,     # skip RStudio and the OpenCode desktop app
  [switch]$Yes,       # do not ask questions
  [switch]$Fix,       # start the AI setup helper on the last setup log
  [switch]$Update,    # check for a newer version of this pack now and install it
  [switch]$Rollback,  # go back to the previous version of this pack
  [switch]$NoAutoUpdate, # do not set up (or remove) the automatic daily update check
  [switch]$FromUpdate # internal: run by the updater after new files arrived (quiet, no AI check)
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'      # makes downloads much faster in PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$OpenCodeVersion = '1.19.5'
$ScriptDir0 = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupVersion = if (Test-Path -LiteralPath (Join-Path $ScriptDir0 'VERSION')) { (Get-Content -LiteralPath (Join-Path $ScriptDir0 'VERSION') -TotalCount 1).Trim() } else { 'dev' }
$PackDir   = Join-Path $env:LOCALAPPDATA 'MetaScience\pack'      # installed copy of this pack (updated automatically)
$PackItems = @('install-windows.cmd', 'setup-windows.ps1', 'setup-mac.sh', 'VERSION', 'lib', 'course-kit', 'doctor', 'guide', 'update')
$UpdateTask = 'MetaScience pack update'
$CourseDir = if ($env:METASCIENCE_DIR) { $env:METASCIENCE_DIR } else { Join-Path $env:USERPROFILE 'MetaScience' }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KitDir    = Join-Path $ScriptDir 'course-kit'
$LogFile   = Join-Path $env:TEMP ("metascience-setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$RPackages = 'rmarkdown knitr readr dplyr tidyr ggplot2 metafor statcheck irr here mcptools'
$script:Failed = 0
if ($FromUpdate) { $Yes = $true }

# ---------- output helpers ---------------------------------------------------
function Log($t)  { Add-Content -LiteralPath $LogFile -Value $t -Encoding UTF8 }
function Say($t)  { Write-Host $t; Log $t }
function Step($t) { Say ''; Write-Host "== $t ==" -ForegroundColor Cyan; Log "== $t ==" }
function Ok($i, $d = '')   { Write-Host '  OK    ' -ForegroundColor Green -NoNewline; Write-Host "$i  $d"; Log "OK $i $d" }
function Warn($i, $d = '') { Write-Host '  WARN  ' -ForegroundColor Yellow -NoNewline; Write-Host "$i  $d"; Log "WARN $i $d" }
function Fail($i, $d = '') { Write-Host '  FAIL  ' -ForegroundColor Red -NoNewline; Write-Host "$i  $d"; Log "FAIL $i $d"; $script:Failed++ }
function Have($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }

function Refresh-Path {
  # pick up PATH changes made by installers, without restarting the window
  $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $u = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$m;$u"
}
function Get-UserPathRaw {
  # the user PATH exactly as stored (keeps entries like %USERPROFILE%\... unexpanded)
  $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
  if (-not $k) { return '' }
  $v = $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $k.Close()
  return [string]$v
}
function Set-UserPathRaw([string]$value) {
  $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
  $k.SetValue('Path', $value, [Microsoft.Win32.RegistryValueKind]::ExpandString); $k.Close()
  try {   # tell Windows, so programs started from the Start menu see the change without logging out
    if (-not ('MsSetup.Env' -as [type])) {
      Add-Type -Namespace MsSetup -Name Env -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r);'
    }
    $r = [UIntPtr]::Zero; [void][MsSetup.Env]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r)
  } catch { Log "PATH broadcast failed: $_" }
}
function Split-PathList([string]$value) {
  # one entry per folder; also splits entries that an older setup version glued together without ';'
  $out = @()
  foreach ($e in $value.Split(';')) {
    $e = $e.Trim(); if (-not $e) { continue }
    $out += [regex]::Split($e, '(?<=[^;])(?=[A-Za-z]:\\)')
  }
  return $out
}
function Repair-UserPath {
  $raw = Get-UserPathRaw; if (-not $raw) { return }
  $seen = @{}; $new = @()
  foreach ($d in @(Split-PathList $raw)) { $k = $d.TrimEnd('\').ToLowerInvariant(); if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $new += $d } }
  $fixed = $new -join ';'
  $plain = @($raw.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ';'
  if ($fixed -ne $plain) {      # only real problems (glued or repeated entries); an empty entry or trailing ';' is harmless
    Log "user PATH before repair: $raw"
    if ($DryRun) { Say '  [dry-run] repair the user PATH list (glued or duplicate entries)'; return }
    Set-UserPathRaw $fixed; Say '  Repaired the PATH list of this account (some entries were glued together or repeated).'
  }
}
function Add-UserPath($dir) {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  $parts = @(Split-PathList (Get-UserPathRaw))      # @() matters: one entry must stay a list, not become a string
  $have = @($parts | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\').ToLowerInvariant() })
  if ($have -notcontains $dir.TrimEnd('\').ToLowerInvariant()) {
    if ($DryRun) { Say "  [dry-run] add $dir to your PATH"; return }
    Set-UserPathRaw ((@($parts) + @($dir)) -join ';')
    Log "added to user PATH: $dir"
  }
  if (($env:Path.Split(';')) -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}
function Download($url, $dest) {
  for ($i = 1; $i -le 3; $i++) {
    try { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -UserAgent 'MetaScience-setup'; return $true }
    catch { Log "download attempt $i failed: $url $_"; Start-Sleep -Seconds 5 }
  }
  if ($url -match '^https://(github\.com|[a-z0-9.-]*githubusercontent\.com)/' -and $script:Blocked -notcontains 'github.com') {
    $script:Blocked += 'github.com'   # GitHub is down or blocked right now: later steps go straight to the other sources
    Warn 'GitHub' 'downloads from GitHub are failing right now; using other download sites where they exist'
  }
  return $false
}
function Run-Native($exe, [string[]]$argList, $timeoutSec = 1800) {
  # run a program, log its output, return its exit code (or 124 on timeout)
  if ($DryRun) { Say "  [dry-run] $exe $($argList -join ' ')"; return 0 }
  Log "> $exe $($argList -join ' ')"
  $out = Join-Path $env:TEMP ("ms-out-{0}.txt" -f [guid]::NewGuid())
  $err = "$out.err"
  try {
    $p = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle   # without this line PowerShell 5.1 loses the exit code
    if (-not $p.WaitForExit($timeoutSec * 1000)) { try { $p.Kill() } catch {}; Log 'TIMEOUT'; return 124 }
    $p.WaitForExit()
    foreach ($f in @($out, $err)) { if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Encoding UTF8 | ForEach-Object { Log $_ }; Remove-Item -LiteralPath $f -Force } }
    if ($null -eq $p.ExitCode) { Log 'exit code unavailable'; return -999 }
    return $p.ExitCode
  } catch { Log "could not start $exe : $_"; return 126 }
}
function Winget-Install($id) {
  # --no-upgrade: if winget sees ANY installed version (even one for another account), it must not touch it.
  # Without it, "winget install" silently upgrades: it UNINSTALLS the existing version first.
  $base = @('install', '--id', $id, '--exact', '--silent', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--source', 'winget')
  foreach ($scope in @(@('--scope', 'user'), @())) {     # first try an install just for this account (no admin needed)
    for ($try = 1; $try -le 4; $try++) {
      $code = Run-Native 'winget' ($base + $scope)
      # winget updates itself in the background (Microsoft Store); while it does, it cannot be started for
      # a minute or two ("The file cannot be accessed by the system"). Wait and try again.
      if ($code -ne 126) { break }
      Log "winget could not be started (try $try); waiting 45 s"; Start-Sleep -Seconds 45; Refresh-Path
    }
    # 0 = installed; 0x8A15002B (no applicable upgrade) and 0x8A150061 (already installed) also count as done
    if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { Refresh-Path; return $true }
    Log "winget $id $($scope -join ' ') exit $code"
  }
  return $false
}
function Install-QuartoDirect {
  # Second route for Quarto: its official zip, unpacked into this account's own Programs folder.
  # Needed because Quarto's Windows installer only installs for the whole computer, which a
  # standard (non-admin) account cannot do. First source quarto.org (not GitHub), then GitHub.
  $dest = Join-Path $env:LOCALAPPDATA 'Programs\Quarto'
  $zip = Join-Path $env:TEMP 'quarto-win.zip'
  $urls = @('https://quarto.org/download/latest/quarto-win.zip')
  if ($script:Blocked -notcontains 'github.com') {
    $ver = '1.11.9'   # fallback if the latest version cannot be looked up
    try {
      $rq = [Net.HttpWebRequest]::Create('https://github.com/quarto-dev/quarto-cli/releases/latest')
      $rq.AllowAutoRedirect = $false; $rq.UserAgent = 'MetaScience-setup'; $rq.Timeout = 20000
      $rs = $rq.GetResponse(); $loc = $rs.Headers['Location']; $rs.Close()
      if ($loc -match '/tag/v([0-9.]+)$') { $ver = $Matches[1] }
    } catch { Log "Quarto latest version lookup failed: $_" }
    $urls += "https://github.com/quarto-dev/quarto-cli/releases/download/v$ver/quarto-$ver-win.zip"
  }
  Say '  Downloading Quarto for this account only (about 140 MB)...'
  foreach ($u in $urls) {
    if (-not (Download $u $zip)) { continue }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    $code = if (Test-Path -LiteralPath $tar) { Run-Native $tar @('-xf', "`"$zip`"", '-C', "`"$dest`"") 900 } else { 1 }
    if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $dest 'bin\quarto.exe'))) {
      try { Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force } catch { Log "Quarto unpack failed: $_" }
    }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath (Join-Path $dest 'bin\quarto.exe')) { return $true }
  }
  return $false
}
function Install-GitDirect {
  # Second route for Git: "MinGit", the official small zip edition of Git for Windows (no installer, no admin).
  # It comes from GitHub, or from the npmmirror copy when GitHub is blocked (common in mainland China).
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { '64-bit' }
  $urls = @()
  if ($script:Blocked -notcontains 'github.com') {
    try {
      $rq = [Net.HttpWebRequest]::Create('https://github.com/git-for-windows/git/releases/latest')
      $rq.AllowAutoRedirect = $false; $rq.UserAgent = 'MetaScience-setup'; $rq.Timeout = 20000
      $rs = $rq.GetResponse(); $loc = $rs.Headers['Location']; $rs.Close()
      if ($loc -match '/tag/(v([0-9.]+)\.windows\.([0-9]+))$') {
        $v = if ($Matches[3] -eq '1') { $Matches[2] } else { "$($Matches[2]).$($Matches[3])" }
        $urls += "https://github.com/git-for-windows/git/releases/download/$($Matches[1])/MinGit-$v-$arch.zip"
      }
    } catch { Log "Git latest version lookup failed: $_" }
  }
  try {
    $list = (Invoke-WebRequest -Uri 'https://registry.npmmirror.com/-/binary/git-for-windows/' -UseBasicParsing -UserAgent 'MetaScience-setup' -TimeoutSec 30).Content | ConvertFrom-Json
    $tag = @($list | Where-Object { $_.name -match '^v[0-9]+\.[0-9]+\.[0-9]+\.windows\.[0-9]+/$' } |
             Sort-Object { [version](($_.name -replace '^v|/$', '') -replace '\.windows', '') } | Select-Object -Last 1)
    if ($tag) {
      $files = (Invoke-WebRequest -Uri $tag[0].url -UseBasicParsing -UserAgent 'MetaScience-setup' -TimeoutSec 30).Content | ConvertFrom-Json
      $f = @($files | Where-Object { $_.name -match "^MinGit-[0-9.]+-$arch\.zip$" } | Select-Object -First 1)
      if ($f) { $urls += $f[0].url }
    }
  } catch { Log "Git mirror lookup failed: $_" }
  $dest = Join-Path $env:LOCALAPPDATA 'Programs\MinGit'
  $zip = Join-Path $env:TEMP 'mingit.zip'
  foreach ($u in $urls) {
    Log "MinGit from $u"
    if (-not (Download $u $zip)) { continue }
    try { Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force } catch { Log "MinGit unpack failed: $_" }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath (Join-Path $dest 'cmd\git.exe')) { return $true }
  }
  return $false
}
function Install-UvDirect {
  # Second route for uv: its official download is a plain zip holding uv.exe. Needed because winget's
  # "portable" install fails for account names with non-English letters (seen with a Chinese name).
  # If GitHub is blocked, the same uv.exe comes from the Python package site (or its mirror).
  $bin = Join-Path $env:USERPROFILE '.local\bin'
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
  $tmp = Join-Path $env:TEMP ("ms-uv-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'uv.zip'
  $got = $false
  if ($script:Blocked -notcontains 'github.com') {
    $got = Download "https://github.com/astral-sh/uv/releases/latest/download/uv-$arch-pc-windows-msvc.zip" $zip
  }
  if (-not $got) {
    $tag = if ($arch -eq 'aarch64') { 'win_arm64' } else { 'win_amd64' }
    foreach ($idx in @('https://pypi.org/simple', 'https://mirrors.aliyun.com/pypi/simple', 'https://pypi.tuna.tsinghua.edu.cn/simple')) {
      try {
        $page = (Invoke-WebRequest -Uri "$idx/uv/" -UseBasicParsing -UserAgent 'MetaScience-setup' -TimeoutSec 30).Content
        $links = [regex]::Matches($page, 'href="([^"]*uv-[0-9.]+-py3-none-' + $tag + '\.whl[^"]*)"')
        if (-not $links.Count) { continue }
        $best = $links | Sort-Object { [version](([regex]::Match($_.Groups[1].Value, 'uv-([0-9.]+)-py3')).Groups[1].Value) } | Select-Object -Last 1   # newest, whatever order the page lists
        $u = $best.Groups[1].Value -replace '&amp;', '&'
        $u = ([Uri]::new([Uri]"$idx/uv/", $u)).AbsoluteUri
        Log "uv wheel: $u"
        if (Download $u $zip) { $got = $true; break }
      } catch { Log "uv index $idx failed: $_" }
    }
  }
  if ($got) {
    try {
      Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
      $exes = @(Get-ChildItem -LiteralPath $tmp -Recurse -File | Where-Object { $_.Name -in 'uv.exe', 'uvx.exe', 'uvw.exe' })
      foreach ($e in $exes) { Copy-Item -LiteralPath $e.FullName -Destination $bin -Force }
    } catch { Log "uv unpack failed: $_" }
  }
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Refresh-Path
  return (Test-Path -LiteralPath (Join-Path $bin 'uv.exe'))
}
# ---------- network: proxy, blocked sites, mirror sites ------------------------
# Some networks block sites (university firewalls, some countries), and some laptops have a proxy or VPN
# app configured. The setup then uses mirror sites that carry the very same files.
$script:Cran = 'https://cloud.r-project.org'
$script:Blocked = @(); $script:DeadProxy = $null
function Test-Site($url, $t = 12) {
  try { Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec $t -UserAgent 'MetaScience-setup' | Out-Null; return $true }
  catch { return [bool]$_.Exception.Response }    # an HTTP error still proves the site is reachable
}
function Setup-Proxy {
  $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
  if ($is.AutoConfigURL) { Log "proxy auto-config script set: $($is.AutoConfigURL)" }
  $proxy = $env:HTTPS_PROXY
  if (-not $proxy -and $is.ProxyEnable -eq 1 -and $is.ProxyServer) {
    $proxy = [string]$is.ProxyServer
    if ($proxy -match 'https=([^;]+)') { $proxy = $Matches[1] } elseif ($proxy -match '(^|;)http=([^;]+)') { $proxy = $Matches[2] }
  }
  if (-not $proxy) { return }
  if ($proxy -notmatch '^[a-zA-Z]+://') { $proxy = "http://$proxy" }
  Log "proxy: $proxy"
  $open = $false
  try { $u = [Uri]$proxy; $c = New-Object Net.Sockets.TcpClient; $ar = $c.BeginConnect($u.Host, $u.Port, $null, $null)
        $open = $ar.AsyncWaitHandle.WaitOne(4000) -and $c.Connected; $c.Close() } catch {}
  if (-not $open) {
    Warn 'Proxy' "Windows is set to send internet traffic through $proxy, but nothing answers there."
    $script:DeadProxy = $proxy
    Say  '        If you use a VPN or proxy app (for example Clash or v2rayN), start it. If you do not,'
    Say  '        open Settings > Network & internet > Proxy and switch off "Use a proxy server". Then run this again.'
    return
  }
  foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY') { if (-not [Environment]::GetEnvironmentVariable($n)) { Set-Item "env:$n" $proxy } }
  if (-not $env:NO_PROXY) { $env:NO_PROXY = 'localhost,127.0.0.1' }
  Ok 'Proxy' "downloads go through the proxy set in Windows ($proxy)"
}
function Setup-Network {
  # what each site is needed for; a blocked site is replaced by a mirror where one exists
  $sites = [ordered]@{
    'github.com'          = 'OpenCode, Git, Quarto, Python'
    'opencode.ai'         = 'the free AI models'
    'cloud.r-project.org' = 'R and R packages'
    'pypi.org'            = 'Python packages'
    'registry.npmjs.org'  = 'OpenCode (second source)'
    'cdn.winget.microsoft.com' = 'the Windows package installer (winget)'
  }
  $script:Blocked = @($sites.Keys | Where-Object { -not (Test-Site "https://$_") })
  if ($script:Blocked.Count -eq $sites.Count) {
    Fail 'Internet access' 'no download site can be reached'
    if ($script:DeadProxy) { Say "        Most likely cause: the proxy setting above ($($script:DeadProxy)). Start the VPN app or switch the proxy off, then run this again."; return $false }
    Say  '        Check that Wi-Fi is connected and that a browser can open https://github.com .'
    Say  '        University or hotel Wi-Fi may first need a login page in the browser. A VPN or proxy app can also block traffic.'
    return $false
  }
  if (-not $script:Blocked.Count) { Ok 'Internet access' 'all download sites reachable'; return $true }
  foreach ($b in $script:Blocked) { Warn 'Blocked site' "$b cannot be reached from this network (needed for $($sites[$b]))" }
  if ($script:Blocked -contains 'github.com' -and (Test-Site 'https://registry.npmmirror.com')) {
    $env:UV_PYTHON_INSTALL_MIRROR = 'https://registry.npmmirror.com/-/binary/python-build-standalone'
    Say '        Python will be downloaded from a mirror site instead of GitHub.'
  }
  if ($script:Blocked -contains 'pypi.org') {
    foreach ($m in 'https://mirrors.aliyun.com/pypi/simple', 'https://pypi.tuna.tsinghua.edu.cn/simple') {
      if (Test-Site "$m/") { $env:UV_DEFAULT_INDEX = $m; Say "        Python packages will come from the mirror $m"; break }
    }
  }
  if ($script:Blocked -contains 'cloud.r-project.org') {
    foreach ($m in 'https://cran.wu.ac.at', 'https://mirrors.tuna.tsinghua.edu.cn/CRAN', 'https://cran.ms.unimelb.edu.au') {
      if (Test-Site "$m/") { $script:Cran = $m; Say "        R packages will come from the mirror $m"; break }
    }
  }
  Say '        If something below fails, connect to a different network (e.g. a phone hotspot) or turn on your VPN, and run this again.'
  return $true
}

function Precheck {
  Step '1/9  Checking this computer'
  $os = Get-CimInstance Win32_OperatingSystem
  $arch = $env:PROCESSOR_ARCHITECTURE
  Ok 'System' "$($os.Caption) build $($os.BuildNumber), $arch"
  if ([int]$os.BuildNumber -lt 17763) { Fail 'Windows version' 'Windows 10 version 1809 or newer is needed'; return $false }
  $drive = (Get-Item -LiteralPath $env:USERPROFILE).PSDrive
  $freeGb = [math]::Floor((Get-PSDrive $drive.Name).Free / 1GB)
  if ($freeGb -lt 8) { Fail 'Free disk space' "$freeGb GB free, 8 GB needed"; return $false } else { Ok 'Free disk space' "$freeGb GB" }
  Setup-Proxy
  if (-not (Setup-Network)) { return $false }
  if (-not (Have 'winget')) {
    # winget is often installed but its folder is missing from PATH in some windows: add it
    $wa = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    if (Test-Path -LiteralPath (Join-Path $wa 'winget.exe')) { $env:Path = "$env:Path;$wa" }
  }
  if (-not (Have 'winget')) {
    Fail 'winget' 'the Windows package installer is missing: install "App Installer" from Microsoft Store, then run this again'
    if (-not $DryRun) { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' -ErrorAction SilentlyContinue }
    return $false
  }
  Ok 'winget' ((& winget --version) -join '')
  return $true
}

function Find-Tool($t) {
  # Looks for a tool on PATH and in the standard install folders, for ANY account on this computer
  # (machine-wide in Program Files, or per-user in this account). Returns the folder to put on PATH, or $null.
  if ($t.cmd -and (Have $t.cmd)) { return (Split-Path -Parent (Get-Command $t.cmd).Source) }
  $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ }
  foreach ($root in $roots) {
    foreach ($rel in $t.dirs) {
      foreach ($d in @(Get-Item -Path (Join-Path $root $rel) -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        if (Test-Path -LiteralPath (Join-Path $d.FullName $t.exe)) { return $d.FullName }
      }
    }
  }
  # winget "portable" packages (uv, Node.js for one account) are unpacked under WinGet\Packages\<id>_...; winget
  # then links them into WinGet\Links, which fails for account names with non-English letters (e.g. "Jürgen").
  # The program itself is there and works, so use its own folder.
  if ($t.id) {
    $wp = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    foreach ($pkg in @(Get-ChildItem -LiteralPath $wp -Directory -Filter "$($t.id)_*" -ErrorAction SilentlyContinue)) {
      $hit = @(Get-ChildItem -LiteralPath $pkg.FullName -Recurse -Depth 2 -File -Filter $t.exe -ErrorAction SilentlyContinue) | Select-Object -First 1
      if ($hit) { return $hit.DirectoryName }
    }
  }
  if ($t.name -eq 'R') {   # R also records its location in the registry
    foreach ($k in 'HKLM:\SOFTWARE\R-core\R', 'HKCU:\SOFTWARE\R-core\R') {
      $p = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).InstallPath
      if ($p -and (Test-Path -LiteralPath (Join-Path $p 'bin\Rscript.exe'))) { return (Join-Path $p 'bin') }
    }
  }
  return $null
}

# ---------- 3. core tools ----------------------------------------------------
function Install-Tools {
  Step '3/9  Core tools: Git, Node.js, uv (Python), R, Quarto, RStudio'
  Say '  Rule: this setup never upgrades or removes software that is already on this computer.'
  Say '  Windows may ask "Do you want to allow this app to make changes?" - click Yes each time.'
  $tools = @(
    @{ id = 'Git.Git';           name = 'Git';     cmd = 'git';     exe = 'git.exe';     dirs = @('Git\cmd', 'MinGit\cmd') },
    @{ id = 'OpenJS.NodeJS.LTS'; name = 'Node.js'; cmd = 'node';    exe = 'node.exe';    dirs = @('nodejs') },
    @{ id = 'astral-sh.uv';      name = 'uv';      cmd = 'uv';      exe = 'uv.exe';      dirs = @() },
    @{ id = 'RProject.R';        name = 'R';       cmd = 'Rscript'; exe = 'Rscript.exe'; dirs = @('R\R-*\bin') },
    @{ id = 'Posit.Quarto';      name = 'Quarto';  cmd = 'quarto';  exe = 'quarto.exe';  dirs = @('Quarto\bin') }
  )
  if (-not $NoGui) { $tools += @{ id = 'Posit.RStudio'; name = 'RStudio'; cmd = ''; exe = 'rstudio.exe'; dirs = @('RStudio') } }
  Add-UserPath (Join-Path $env:USERPROFILE '.local\bin')     # uv's own folder
  foreach ($t in $tools) {
    $found = Find-Tool $t
    if ($found) {
      if ($t.cmd -and -not (Have $t.cmd)) { Add-UserPath $found; Ok $t.name "already on this computer, now usable from this account ($found)" }
      else { Ok $t.name 'already installed' }
      continue
    }
    if ($DryRun) { Say "  [dry-run] winget install $($t.id) (just for this account if possible)"; continue }
    $ghOnly = $t.name -in 'Git', 'Quarto', 'uv'   # winget fetches these from GitHub
    $wingetOk = (-not ($ghOnly -and $script:Blocked -contains 'github.com')) -and (Winget-Install $t.id)
    if ($wingetOk) { $found = Find-Tool $t }
    if ($wingetOk -and $found) { if ($t.cmd) { Add-UserPath $found }; Ok $t.name 'installed' }
    elseif ($wingetOk -and $t.name -notin 'uv', 'Git', 'Quarto') { Fail $t.name "winget reported success but $($t.exe) was not found; see $LogFile" }
    # winget failed, or said "installed" but the program is missing: try the direct download
    elseif ($t.name -eq 'uv' -and (Install-UvDirect)) { Add-UserPath (Join-Path $env:USERPROFILE '.local\bin'); Ok 'uv' 'installed (direct download)' }
    elseif ($t.name -eq 'Git' -and (Install-GitDirect)) { Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\MinGit\cmd'); Ok 'Git' 'installed for this account (MinGit, direct download)' }
    elseif ($t.name -eq 'Quarto' -and (Install-QuartoDirect)) { Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\Quarto\bin'); Ok 'Quarto' 'installed for this account (direct download)' }
    else { Fail $t.name "winget could not install $($t.id); see $LogFile" }
  }
  if ($DryRun) { return }
  if (Have 'Rscript') { Ok 'R on PATH' (Get-Command Rscript).Source } else { Fail 'R on PATH' 'Rscript not found' }
}

# ---------- 4. OpenCode -------------------------------------------------------
function Install-OpenCode {
  Step "4/9  OpenCode $OpenCodeVersion (AI assistant)"
  $base = "https://github.com/anomalyco/opencode/releases/download/v$OpenCodeVersion"
  $isArm = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
  $binDir = Join-Path $env:LOCALAPPDATA 'Programs\opencode-cli'
  $current = ''
  if (Have 'opencode') { $current = ((& opencode --version) 2>$null | Select-Object -First 1) }
  if ($current -eq $OpenCodeVersion) { Ok 'OpenCode command line' "version $OpenCodeVersion already installed" }
  else {
    $asset = if ($isArm) { 'opencode-windows-arm64.zip' } else { 'opencode-windows-x64-baseline.zip' }
    $zip = Join-Path $env:TEMP $asset
    $x = Join-Path $env:TEMP 'opencode-x'; Remove-Item -Recurse -Force -LiteralPath $x -ErrorAction SilentlyContinue
    $got = $false
    if ($DryRun) { Say "  [dry-run] download $base/$asset to $binDir" }
    elseif ($script:Blocked -notcontains 'github.com' -and (Download "$base/$asset" $zip)) {
      try { Expand-Archive -LiteralPath $zip -DestinationPath $x -Force; $got = $true } catch { Log "unzip failed: $_" }
    }
    if (-not $DryRun -and -not $got) {
      # same program, published as an npm package: npm's own site, then a mirror reachable from China
      $pkg = if ($isArm) { 'opencode-windows-arm64' } else { 'opencode-windows-x64-baseline' }
      $tgz = Join-Path $env:TEMP "$pkg.tgz"
      foreach ($reg in 'https://registry.npmjs.org', 'https://registry.npmmirror.com') {
        if (Download "$reg/$pkg/-/$pkg-$OpenCodeVersion.tgz" $tgz) {
          New-Item -ItemType Directory -Force -Path $x | Out-Null
          & tar.exe -xzf $tgz -C $x 2>&1 | ForEach-Object { Log $_ }
          if (Get-ChildItem -LiteralPath $x -Recurse -Filter 'opencode.exe') { $got = $true; Log "OpenCode from $reg"; break }
        }
      }
    }
    if ($got) {
      New-Item -ItemType Directory -Force -Path $binDir | Out-Null
      $exe = Get-ChildItem -LiteralPath $x -Recurse -Filter 'opencode.exe' | Select-Object -First 1
      if ($exe) { Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $binDir 'opencode.exe') -Force }
      Add-UserPath $binDir
      $v = ''; try { $v = ((& (Join-Path $binDir 'opencode.exe') --version) 2>$null | Select-Object -First 1) } catch {}
      if ($v -eq $OpenCodeVersion) { Ok 'OpenCode command line' "installed $OpenCodeVersion" } else { Fail 'OpenCode command line' 'installed but does not start' }
    } elseif (-not $DryRun) { Fail 'OpenCode command line' "download failed from GitHub and from npm; see $LogFile" }
  }
  if ($NoGui) { return }
  $installed = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
               ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -like 'OpenCode*' }
  if ($installed) { Ok 'OpenCode desktop app' 'already installed'; return }
  $app = if ($isArm) { 'opencode-desktop-win-arm64.exe' } else { 'opencode-desktop-win-x64.exe' }
  $setup = Join-Path $env:TEMP $app
  if ($DryRun) { Say "  [dry-run] install $app"; return }
  if ($script:Blocked -contains 'github.com') { Warn 'OpenCode desktop app' 'GitHub is blocked here, so only the command-line OpenCode is installed (type opencode in a terminal). Run this again on another network to add the app.'; return }
  if (Download "$base/$app" $setup) {
    $code = Run-Native $setup @('/S') 600     # per-user silent install, no administrator needed
    if ($code -eq 0) { Ok 'OpenCode desktop app' 'installed (Start menu: OpenCode)' } else { Fail 'OpenCode desktop app' "installer exit code $code" }
  } else { Fail 'OpenCode desktop app' 'download failed' }
}

# ---------- 5. R packages ------------------------------------------------------
function Install-RPackages {
  Step '5/9  R packages for the course'
  if ($DryRun) { Say '  [dry-run] install missing course R packages into this account''s R library'; return }
  if (-not (Have 'Rscript')) { Fail 'R packages' 'R is not installed'; return }
  $expr = "lib <- Sys.getenv('R_LIBS_USER'); dir.create(lib, recursive=TRUE, showWarnings=FALSE); .libPaths(c(lib,.libPaths())); pk <- strsplit('$RPackages',' ')[[1]]; miss <- pk[!pk %in% rownames(installed.packages())]; if (length(miss)) install.packages(miss, lib=lib, repos='$($script:Cran)', type='binary')"
  Run-Native 'Rscript' @('-e', "`"$expr`"") 1800 | Out-Null
  $missing = (& Rscript -e "pk <- strsplit('$RPackages',' ')[[1]]; cat(pk[!pk %in% rownames(installed.packages())])") 2>$null
  if ($DryRun) { return }
  if (-not $missing) { Ok 'R packages' "$(($RPackages -split ' ').Count) packages ready" } else { Fail 'R packages' "missing: $missing" }
}
function Fix-Pandoc {
  # R must find a working pandoc to make reports. If the first pandoc on PATH is broken for this
  # account (e.g. a shortcut to another user's copy), R is pointed at Quarto's own pandoc instead.
  if ($DryRun -or -not (Have 'Rscript') -or -not (Have 'quarto')) { return }
  $qbin = Split-Path -Parent (Get-Command quarto).Source
  $out = (& Rscript (Join-Path $ScriptDir 'lib\fix_pandoc.R') $qbin) 2>&1 | Out-String
  Log "fix_pandoc: $out"
  if ($out -match '^FIXED') { Ok 'Pandoc for R' 'a broken pandoc was in the way; R now uses Quarto''s own copy' }
  elseif ($out -match '^OK') { Ok 'Pandoc for R' 'works' }
  else { Fail 'Pandoc for R' $out.Trim() }
}

# ---------- 6. course folder + Python environment ----------------------------
function Py([string[]]$a) {
  $helper = Join-Path $ScriptDir 'lib\course_setup.py'
  $env:PYTHONUNBUFFERED = '1'; $env:PYTHONIOENCODING = 'utf-8'
  & uv run --no-project --python 3.12 --quiet python $helper @a --course $CourseDir | Out-Host
  return $LASTEXITCODE
}
function Setup-CourseFolder {
  Step "6/9  Course folder: $CourseDir"
  if (-not (Test-Path -LiteralPath $KitDir)) { Fail 'Course kit' 'folder course-kit is missing next to this script'; return }
  if ($DryRun) { Say "  [dry-run] copy course-kit to $CourseDir, create Python environment, write opencode.json"; return }
  New-Item -ItemType Directory -Force -Path $CourseDir | Out-Null
  # what the pack installed last time, so an update can tell a student's own edit from an old course file
  $kitHashFile = Join-Path $CourseDir '.metascience\kit-hashes.json'
  $kitHashes = @{}
  if (Test-Path -LiteralPath $kitHashFile) { try { (Get-Content -Raw -LiteralPath $kitHashFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $kitHashes[$_.Name] = $_.Value } } catch {} }
  Get-ChildItem -LiteralPath $KitDir -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($KitDir.Length + 1)
    $dest = Join-Path $CourseDir $rel
    $courseFile = ($rel -eq 'AGENTS.md') -or ($rel -eq 'pyproject.toml') -or $rel.StartsWith('check\')
    $newHash = (Get-FileHash -LiteralPath $_.FullName).Hash
    if (-not (Test-Path -LiteralPath $dest)) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $_.FullName -Destination $dest
    } else {
      $have = (Get-FileHash -LiteralPath $dest).Hash
      if ($have -ne $newHash) {
        if ($courseFile -or ($kitHashes.ContainsKey($rel) -and $kitHashes[$rel] -eq $have)) {
          # a course file, or a file the student never changed: replace it (course files keep a .bak)
          if ($courseFile) { Copy-Item -LiteralPath $dest -Destination "$dest.bak" -Force }
          Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        } else {
          Copy-Item -LiteralPath $_.FullName -Destination "$dest.new" -Force   # the student changed it: keep theirs
          Say "  Kept your version of $rel; the new course version is saved next to it as $rel.new"
        }
      }
    }
    $kitHashes[$rel] = $newHash
  }
  try { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $kitHashFile) | Out-Null
        $kitHashes | ConvertTo-Json | Set-Content -LiteralPath $kitHashFile -Encoding UTF8 } catch {}
  Ok 'Course folder' $CourseDir
  if (-not (Have 'uv')) { Fail 'Python environment' 'uv is not installed'; return }
  $code = Run-Native 'uv' @('sync', '--directory', "`"$CourseDir`"", '--python', '3.12') 1800
  if ($code -eq 0) { Ok 'Python environment' 'Python 3.12 + course packages' } else { Fail 'Python environment' "uv sync failed; see $LogFile" }
  if ((Py @('config')) -eq 0) { Ok 'OpenCode settings' 'free model as default, 6 MCP tools (off)' } else { Fail 'OpenCode settings' 'could not write opencode.json' }
}

function Run-Check {
  Step '8/9  Real-task check (uses every installed tool)'
  if (-not (Have 'uv')) { Fail 'uv' 'not installed, cannot run the check'; return }
  $a = @('check', '--log', $LogFile); if ($SkipAI) { $a += '--skip-ai' }
  if ((Py $a) -ne 0) { $script:Failed++ }
}

# ---------- AI setup helper ------------------------------------------------------
function Start-Doctor {
  # When something failed, OpenCode itself (free model) reads the log and guides the student.
  # Every command it wants to run is shown to the student first ("permission": "ask").
  Step 'AI setup helper'
  if (-not (Have 'opencode')) { Say '  The AI helper needs OpenCode, which is not installed yet. Run the setup again, or show the teacher the log.'; return }
  $help = Join-Path $env:USERPROFILE 'MetaScience-help'
  New-Item -ItemType Directory -Force -Path $help | Out-Null
  Copy-Item -LiteralPath (Join-Path $ScriptDir 'doctor\AGENTS.md') -Destination (Join-Path $help 'AGENTS.md') -Force
  # the log to diagnose: this run's log, or (with -Fix alone) the newest earlier setup log
  $src = $LogFile
  if ($Fix -and $script:Failed -eq 0) {
    $prev = Get-ChildItem -Path (Join-Path $env:TEMP 'metascience-setup-*.log') -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $LogFile } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($prev) { $src = $prev.FullName }
  }
  Copy-Item -LiteralPath $src -Destination (Join-Path $help 'setup-log.txt') -Force
  $rep = Join-Path $CourseDir 'setup-report.txt'
  if (Test-Path -LiteralPath $rep) { Copy-Item -LiteralPath $rep -Destination (Join-Path $help 'setup-report.txt') -Force }
  $ps = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $ScriptDir 'setup-windows.ps1')`""
  $info = @(
    "Computer: Windows, $env:PROCESSOR_ARCHITECTURE, user account $env:USERNAME"
    "Setup scripts folder: $ScriptDir"
    "Course folder: $CourseDir"
    "Log being diagnosed: $src"
    ''
    'Re-run the whole setup (safe; skips what works; can take up to 30 minutes, use a long timeout):'
    "  $ps -Yes"
    'Re-run only the final check (up to 10 minutes):'
    "  $ps -Check -Yes"
    'Both write a new log to %TEMP%\metascience-setup-<date>.log and a new report to the course folder.'
  )
  Set-Content -LiteralPath (Join-Path $help 'SETUP-INFO.txt') -Value $info -Encoding UTF8
  $models = @((& opencode models opencode) 2>$null)
  $model = @('opencode/glm-5.3-flash-free', 'opencode/deepseek-v4.1-flash-free') | Where-Object { $models -contains $_ } | Select-Object -First 1
  if (-not $model) { $model = $models | Where-Object { $_ -like 'opencode/*-free' -and $_ -notmatch 'inkling|crouton' } | Select-Object -First 1 }
  $cfg = '{ "$schema": "https://opencode.ai/config.json", "share": "disabled", "autoupdate": false, ' +
         '"permission": { "edit": "ask", "bash": "ask" }' + $(if ($model) { ", `"model`": `"$model`"" } else { '' }) + ' }'
  [IO.File]::WriteAllText((Join-Path $help 'opencode.json'), $cfg, (New-Object Text.UTF8Encoding($false)))
  Say ''
  Say '  The AI helper starts now. It has read nothing on your laptop except the setup log.'
  Say '  Before it runs any command, it shows you the command: choose Allow only if its explanation makes sense.'
  Say '  To stop the helper: type /exit and press Enter (or press Ctrl+C twice).'
  if (-not $Yes) { Read-Host '  Press Enter to start' | Out-Null }
  & opencode $help --prompt 'Please read AGENTS.md, SETUP-INFO.txt, setup-report.txt and setup-log.txt in this folder. Then explain in simple words what went wrong in my course setup, and help me fix it step by step.'
  Say "Helper notes (if any) are in $help"
}

function Install-Pack {
  # Keep an installed copy of this pack in the account's own folder, so the updater can refresh it later.
  # Then (unless the student says no) add a daily update check for this account only (no admin needed).
  Step '7/9  Updates for this pack'
  if ($DryRun) { Say "  [dry-run] copy the pack to $PackDir and add the daily update check"; return }
  $src = (Resolve-Path -LiteralPath $ScriptDir).Path.TrimEnd('\')
  if ($src -ne $PackDir.TrimEnd('\')) {
    try {
      New-Item -ItemType Directory -Force -Path $PackDir | Out-Null
      foreach ($i in $PackItems) {
        $from = Join-Path $src $i
        if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $PackDir -Recurse -Force }
      }
      Ok 'Pack copy' $PackDir
    } catch { Warn 'Pack copy' "could not copy the pack to $PackDir ($($_.Exception.Message)); updates will not work"; return }
  }
  $updater = Join-Path $PackDir 'update\update.ps1'
  if (-not (Test-Path -LiteralPath $updater)) { Warn 'Automatic updates' 'this copy of the pack has no updater'; return }
  if ($NoAutoUpdate) {
    Unregister-ScheduledTask -TaskName $UpdateTask -Confirm:$false -ErrorAction SilentlyContinue
    Ok 'Automatic updates' 'off (you can update by hand: install-windows.cmd -Update)'; return
  }
  if (-not $Yes -and -not (Get-ScheduledTask -TaskName $UpdateTask -ErrorAction SilentlyContinue)) {
    $a = Read-Host 'Keep this course pack up to date automatically (a short daily check)? Recommended. [Y/n]'
    if ($a -match '^(n|no)$') { Ok 'Automatic updates' 'off (you can update by hand: install-windows.cmd -Update)'; return }
  }
  try {
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $env:TEMP `
      -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updater`" -Auto"
    $trg = New-ScheduledTaskTrigger -Daily -At '12:30'
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskName $UpdateTask -Action $act -Trigger $trg -Settings $set -Description 'Checks for a newer version of the MetaScience course pack (freeAIsetup) and installs it.' -Force | Out-Null
    Ok 'Automatic updates' 'on: a short check once a day (turn off: install-windows.cmd -NoAutoUpdate)'
  } catch { Warn 'Automatic updates' "could not add the daily check ($($_.Exception.Message)); update by hand: install-windows.cmd -Update" }
}

function Summary {
  Step '9/9  Summary'
  if ($DryRun) { Write-Host 'Dry run finished: the lines above show what a real run would do.' -ForegroundColor Yellow }
  elseif ($script:Failed -eq 0) { Write-Host 'All done. Everything works.' -ForegroundColor Green }
  else {
    Write-Host 'Something needs attention (see the FAIL lines above). Run the setup again first; it repairs most problems.' -ForegroundColor Red
    Say "If it still fails, show the teacher: $(Join-Path $CourseDir 'setup-report.txt')"
  }
  Say "Full log: $LogFile"
  Say "Next: open OpenCode from the Start menu, choose the folder $CourseDir, and follow the guide."
}

# ---------- main ---------------------------------------------------------------
Say "MetaScience course setup $SetupVersion  (Windows, $env:PROCESSOR_ARCHITECTURE)  log: $LogFile"
if ($DryRun) { Write-Host 'DRY RUN: nothing will be changed.' -ForegroundColor Yellow }
Repair-UserPath
Refresh-Path
Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\opencode-cli')
if ($Fix) { Start-Doctor; exit 0 }
$updaterHere = Join-Path $PackDir 'update\update.ps1'
if (-not (Test-Path -LiteralPath $updaterHere)) { $updaterHere = Join-Path $ScriptDir 'update\update.ps1' }
if ($Update)   { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updaterHere; exit $LASTEXITCODE }
if ($Rollback) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updaterHere -Rollback; exit $LASTEXITCODE }
if ($Check) { Run-Check; Summary }
elseif ($Keys) { Step 'Optional: free AI keys'; Py @('keys') | Out-Null; Run-Check; Summary }
else {
  if (-not (Precheck)) { Summary; exit 1 }
  Install-Tools; Install-OpenCode; Install-RPackages; Fix-Pandoc; Setup-CourseFolder
  if (-not $FromUpdate) { Install-Pack }
  if (-not $DryRun -and -not $FromUpdate) {
    if (-not $Yes) {
      $a = Read-Host 'Add optional free AI keys now? You can also do it later with install-windows.cmd -Keys [y/N]'
      if ($a -match '^(y|yes)$') { Py @('keys') | Out-Null }
    }
    Run-Check
  }
  Summary
}
if ($script:Failed -gt 0 -and -not $DryRun -and -not $Yes -and -not $FromUpdate) {
  $a = Read-Host 'Some steps failed. Start the AI setup helper? It reads the setup log and guides you to a fix; you approve every command. [Y/n]'
  if ($a -notmatch '^(n|no)$') { Start-Doctor }
}
if ($script:Failed -eq 0) { exit 0 } else { exit 1 }
