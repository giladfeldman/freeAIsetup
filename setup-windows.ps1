# =============================================================================
#  Meta-science course: one-step setup for Windows 10/11
#  Installs: OpenCode (desktop + command line), Git, Node.js, uv + Python,
#            R + course packages, RStudio, Quarto; creates %USERPROFILE%\MetaScience;
#            runs a real end-to-end check that uses every installed tool.
#  Safe to run again: it skips what is already installed and repairs the rest.
#
#  Start it by double-clicking install-windows.cmd (recommended), or:
#    powershell -ExecutionPolicy Bypass -File setup-windows.ps1 [-Check] [-Keys] [-Fix] [-DryRun] [-SkipAI]
#                [-Choose] [-Components r,rstudio,quarto,python,node|all|none] [-Uninstall]
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
  [switch]$FromUpdate, # internal: run by the updater after new files arrived (quiet, no AI check)
  [switch]$Choose,    # ask again which parts to install
  [Alias('Parts')][string]$Components = '', # the parts to install (or with -Uninstall: to remove), without asking: r,rstudio,quarto,python,node (or all / none)
  [switch]$Uninstall  # remove some or all of what this setup installed (lib\uninstall-windows.ps1)
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'      # makes downloads much faster in PowerShell 5.1
# uv (Python packages) on slow or crowded Wi-Fi: wait longer per download, fewer at once, retry.
# With uv's defaults (30 s, many parallel downloads) a 12 MB package timed out in the VM test.
$env:UV_HTTP_TIMEOUT = '300'; $env:UV_CONCURRENT_DOWNLOADS = '4'; $env:UV_HTTP_RETRIES = '5'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$OpenCodeVersion = '1.19.5'
$ScriptDir0 = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupVersion = if (Test-Path -LiteralPath (Join-Path $ScriptDir0 'VERSION')) { (Get-Content -LiteralPath (Join-Path $ScriptDir0 'VERSION') -TotalCount 1).Trim() } else { 'dev' }
$PackDir   = Join-Path $env:LOCALAPPDATA 'MetaScience\pack'      # installed copy of this pack (updated automatically)
$PackItems = @('install-windows.cmd', 'setup-windows.ps1', 'setup-mac.sh', 'VERSION', 'lib', 'course-kit', 'doctor', 'guide', 'update')
$UpdateTask = 'MetaScience pack update'
# What this setup remembers for this account: the chosen parts and a record of what it installed (tests: MS_STATE_DIR)
$StateDir  = if ($env:MS_STATE_DIR) { $env:MS_STATE_DIR } else { Join-Path $env:LOCALAPPDATA 'MetaScience' }
$CourseDir = if ($env:METASCIENCE_DIR) { $env:METASCIENCE_DIR } else { Join-Path $env:USERPROFILE 'MetaScience' }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KitDir    = Join-Path $ScriptDir 'course-kit'
$LogFile   = Join-Path $env:TEMP ("metascience-setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$RPackages = 'rmarkdown knitr readr dplyr tidyr ggplot2 metafor statcheck irr here mcptools'
$script:Failed = 0
if ($FromUpdate) { $Yes = $true }

# ---------- output helpers ---------------------------------------------------
# another program reading the log (antivirus, an editor) can lock it for a moment: retry, never stop the setup
function Log($t)  { for ($i = 0; $i -lt 5; $i++) { try { Add-Content -LiteralPath $LogFile -Value $t -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 } } }
function Say($t)  { Write-Host $t; Log $t }
function Step($t) { Say ''; Write-Host "== $t ==" -ForegroundColor Cyan; Log "== $t ==" }
function Ok($i, $d = '')   { Write-Host '  OK    ' -ForegroundColor Green -NoNewline; Write-Host "$i  $d"; Log "OK $i $d" }
function Warn($i, $d = '') { Write-Host '  WARN  ' -ForegroundColor Yellow -NoNewline; Write-Host "$i  $d"; Log "WARN $i $d" }
function Fail($i, $d = '') { Write-Host '  FAIL  ' -ForegroundColor Red -NoNewline; Write-Host "$i  $d"; Log "FAIL  $i  $d"; $script:Failed++ }
function Skip($i, $d = 'not chosen') { Write-Host '  SKIP  ' -ForegroundColor DarkGray -NoNewline; Write-Host "$i  $d"; Log "SKIP $i $d" }
function Have($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }

# What this setup itself installed, one line each: part <TAB> kind <TAB> target. The uninstall (lib\uninstall-windows.ps1)
# removes only what is listed here, so software that was on this computer before the setup is never touched.
function Record-Install($part, $kind, $target) {
  if ($DryRun -or -not $target) { return }
  $line = "$part`t$kind`t$target"
  try {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $f = Join-Path $StateDir 'installed.tsv'
    if (-not ((Test-Path -LiteralPath $f) -and (@(Get-Content -LiteralPath $f -Encoding UTF8) -contains $line))) {
      Add-Content -LiteralPath $f -Value $line -Encoding UTF8
    }
  } catch { Log "could not record '$line': $_" }
}

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
    Record-Install 'core' 'path' $dir
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
  $scopes = @(@('--scope', 'user'), @())   # first try an install just for this account (no admin needed)
  # RStudio: winget's "--scope user" run never finishes (VM test: cut off after 60 min), while the normal run
  # installs it for the current user anyway (/currentuser) without admin. So skip straight to the normal run.
  if ($id -eq 'Posit.RStudio') { $scopes = @(, @()) }
  # uv and Quarto: the all-users run pops up an admin prompt (VM test 2026-11-09, student account). Their direct
  # download installs for this account with no prompt, so after the per-account try, go straight there.
  if ($id -in 'astral-sh.uv', 'Posit.Quarto') { $scopes = @(, @('--scope', 'user')) }
  foreach ($scope in $scopes) {
    for ($try = 1; $try -le 4; $try++) {
      $code = Run-Native 'winget' ($base + $scope) 3600   # RStudio alone is ~500 MB: on shared class Wi-Fi 30 min is not enough
      # winget updates itself in the background (Microsoft Store); while it does, it cannot be started for
      # a minute or two ("The file cannot be accessed by the system"). Wait and try again.
      if ($code -ne 126) { break }
      Log "winget could not be started (try $try); waiting 45 s"; Start-Sleep -Seconds 45; Refresh-Path
    }
    # 0 = installed; 0x8A15002B (no applicable upgrade) and 0x8A150061 (already installed) also count as done
    # only exit 0 means THIS run installed it; "already installed" must never reach installed.tsv, or the uninstall
    # would later remove a program that was here before the setup
    if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) { $script:WingetFresh = ($code -eq 0); Refresh-Path; return $true }
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
function Install-RStudioDirect {
  # Second route for RStudio: Posit's official zip (no installer), unpacked into this account's own Programs
  # folder, plus a Start-menu entry. Needs no admin and no winget (winget often cannot start for minutes on a
  # fresh laptop, and RStudio's installer only installs for the whole computer).
  $dest = Join-Path $env:LOCALAPPDATA 'Programs\RStudio'
  $urls = @()
  try {
    $j = Invoke-RestMethod -Uri 'https://www.rstudio.com/wp-content/downloads.json' -UseBasicParsing -UserAgent 'MetaScience-setup' -TimeoutSec 30
    $a = $j.rstudio.open_source.stable.desktop.archive.windows
    if ($a.url) { $urls += $a.url }; if ($a.s3_url) { $urls += $a.s3_url }
  } catch { Log "RStudio version lookup failed: $_" }
  if (-not $urls.Count) { $urls = @('https://download1.rstudio.org/electron/windows/RStudio-2026.10.1-239.zip',
                                    'https://s3.amazonaws.com/rstudio-desktop/electron/windows/RStudio-2026.10.1-239.zip') }
  $zip = Join-Path $env:TEMP 'rstudio-win.zip'
  Say '  Downloading RStudio for this account only (about 700 MB; on slow Wi-Fi this can take 20 minutes)...'
  foreach ($u in $urls) {
    if (-not (Download $u $zip)) { continue }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    $code = if (Test-Path -LiteralPath $tar) { Run-Native $tar @('-xf', "`"$zip`"", '-C', "`"$dest`"") 1800 } else { 1 }
    if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $dest 'rstudio.exe'))) {
      try { Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force } catch { Log "RStudio unpack failed: $_" }
    }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    $exe = Join-Path $dest 'rstudio.exe'
    if (Test-Path -LiteralPath $exe) {
      try {   # Start-menu entry for this account, so students find RStudio as usual
        $lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'RStudio.lnk'
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = $exe; $s.WorkingDirectory = $dest; $s.Save()
      } catch { Log "RStudio shortcut failed: $_" }
      return $true
    }
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

function Get-SacState {
  # Smart App Control: 'On' blocks program files (.exe/.dll/.pyd) that Microsoft's cloud does not know, file by
  # file. Measured 2026-11-09 on a Windows 11 test computer: with it On, every tool installs, but it blocks single
  # files inside R and Python packages (R tzdb.dll -> readr; a pandas .pyd), so course work fails at random.
  # Neither we nor the package authors can sign those files. 'Eval' (evaluation) only watches and blocks nothing.
  $s = $null
  try { $s = [string](Get-MpComputerStatus -ErrorAction Stop).SmartAppControlState } catch {}
  if (-not $s) {
    $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
    $s = switch ($v) { 0 { 'Off' } 1 { 'On' } 2 { 'Eval' } default { '' } }
  }
  return $s
}
function Check-SmartAppControl {
  $s = Get-SacState
  if ($s -ne 'On') {
    if ($s -eq 'Eval') { Ok 'Smart App Control' 'evaluation mode (blocks nothing)' }
    elseif ($s -eq 'Off') { Ok 'Smart App Control' 'off' }
    return
  }
  Warn 'Smart App Control' 'is ON. It will block parts of R and Python that the course needs.'
  Say ''
  Say '  Smart App Control is a Windows protection that blocks any program file Microsoft does not yet know.'
  Say '  The course tools install, but it then blocks single files inside the R and Python packages, so your'
  Say '  analyses fail at random. Your normal virus protection (Microsoft Defender) stays on either way.'
  Say ''
  Say '  To use this computer for the course, switch Smart App Control off (your choice):'
  Say '    1. Windows Security opens now (or: Start > Windows Security > App & browser control).'
  Say '    2. Click "Smart App Control settings", choose "Off", and confirm.'
  Say '    Note: Windows may not let you switch it back on later without resetting Windows.'
  Say '  If you prefer not to, stop here and ask your teacher about the browser-only option (GitHub Codespaces).'
  if ($Yes -or $DryRun) { return }
  Start-Process 'windowsdefender://appbrowser' -ErrorAction SilentlyContinue
  while ((Get-SacState) -eq 'On') {
    $a = Read-Host '  When it shows Off, press Enter. To stop the setup, type Q. To continue anyway, type C'
    if ($a -match '^[Qq]') { Say '  Setup stopped. Nothing was installed.'; exit 2 }
    if ($a -match '^[Cc]') { Warn 'Smart App Control' 'still ON: expect the Python and R checks to fail'; return }
  }
  Ok 'Smart App Control' 'now off'
}
function Precheck {
  Step '1/9  Checking this computer'
  # test hook: a stop in step 1 must still reach the offer to send the report (tests\exit-paths.ps1)
  if ($env:MS_TEST_FAIL_AT -eq 'precheck') { Fail 'Test stop' 'MS_TEST_FAIL_AT=precheck'; return $false }
  $os = Get-CimInstance Win32_OperatingSystem
  $arch = $env:PROCESSOR_ARCHITECTURE
  Ok 'System' "$($os.Caption) build $($os.BuildNumber), $arch"
  if ([int]$os.BuildNumber -lt 17763) { Fail 'Windows version' 'Windows 10 version 1809 or newer is needed'; return $false }
  Check-SmartAppControl
  $drive = (Get-Item -LiteralPath $env:USERPROFILE).PSDrive
  $freeGb = [math]::Floor((Get-PSDrive $drive.Name).Free / 1GB)
  # The chosen parts that are not here yet, plus 2 GB for the downloads while installing; 3 GB more leaves room
  # for course work. Before 2026-11-12 this was a flat 8 GB for every computer.
  $needGb = Estimate-Gb; $minGb = [math]::Ceiling($needGb + 2)
  if ($freeGb -lt $minGb) { Fail 'Free disk space' "$freeGb GB free; this setup needs about $needGb GB, plus 2 GB while it installs. Free up space (or install fewer parts: install-windows.cmd -Choose), then run it again"; return $false }
  elseif ($freeGb -lt $minGb + 3) { Warn 'Free disk space' "$freeGb GB free; the setup will use about $needGb GB, which leaves little room for your course work" }
  elseif ($needGb -lt 0.1) { Ok 'Free disk space' "$freeGb GB free; what you chose is already on this computer" }
  else { Ok 'Free disk space' "$freeGb GB free; this setup will use about $needGb GB" }
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

# ---------- R older than 4.5 (d-872f0e) ------------------------------------------------
# The course packages no longer come ready-built for R older than 4.5, so all of them fail there (class
# 2026-11-09, a Mac with R 4.0.0). winget --no-upgrade rightly keeps an old R, so the current R is installed NEXT
# to it, for this account only (CRAN's installer, /CURRENTUSER: no admin; tested 2026-11-12 with R 4.6.2), and put
# first on this account's PATH. The old R stays.
$RMin = [version]'4.5'
function R-Version($bin) {   # the version of the R in this bin folder: from its folder name (R-4.6.2), else by asking it
  $n = Split-Path -Leaf (Split-Path -Parent $bin)
  if ($n -match '^R-(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
  try { $v = "$((& (Join-Path $bin 'Rscript.exe') -e 'cat(as.character(getRversion()))') 2>$null)".Trim(); if ($v) { return [version]$v } } catch { Log "R version of $bin unknown: $_" }
  return $null
}
function Find-CurrentR {   # the bin folder of the newest R 4.5 or newer on this computer, or $null
  $c = @()
  if (Have 'Rscript') { $c += Split-Path -Parent (Get-Command Rscript).Source }
  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ }) {
    $c += @(Get-Item -Path (Join-Path $root 'R\R-*\bin') -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  }
  foreach ($k in 'HKCU:\SOFTWARE\R-core\R', 'HKLM:\SOFTWARE\R-core\R') {   # an R in a folder of its own choosing
    $ip = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).InstallPath; if ($ip) { $c += Join-Path $ip 'bin' }
  }
  $best = $null; $bv = $null
  foreach ($b in @($c | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath (Join-Path $b 'Rscript.exe'))) { continue }
    $v = R-Version $b
    if ($v -and $v -ge $RMin -and (-not $bv -or $v -gt $bv)) { $best = $b; $bv = $v }
  }
  return $best
}
function Put-PathFirst($dir) {   # this folder first on this account's PATH and in this window (an older R further down stays)
  $parts = @(Split-PathList (Get-UserPathRaw))
  $key = $dir.TrimEnd('\').ToLowerInvariant()
  $norm = @($parts | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\').ToLowerInvariant() })
  if (-not $norm.Count -or $norm[0] -ne $key) {
    if ($DryRun) { Say "  [dry-run] put $dir first on your PATH" }
    else {
      $rest = @(); for ($i = 0; $i -lt $parts.Count; $i++) { if ($norm[$i] -ne $key) { $rest += $parts[$i] } }
      Set-UserPathRaw ((@($dir) + $rest) -join ';'); Log "put first on user PATH: $dir"
      if ($norm -notcontains $key) { Record-Install 'core' 'path' $dir }
    }
  }
  $env:Path = (@($dir) + @($env:Path.Split(';') | Where-Object { $_ -and $_.TrimEnd('\').ToLowerInvariant() -ne $key })) -join ';'
  $m = @(([Environment]::GetEnvironmentVariable('Path', 'Machine')).Split(';') | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'Rscript.exe')) })
  if ($m.Count) { Warn 'R on PATH' "the computer-wide PATH lists another R first ($($m[0])); new windows may start that one. In RStudio, choose R under Tools > Global Options > General." }
}
function Install-RDirect {   # the current R from CRAN, for this account only; returns its folder, or $null
  $name = $null
  try {   # CRAN's release page points to the current installer, e.g. R-4.6.2-win.exe
    $page = (Invoke-WebRequest -Uri "$($script:Cran)/bin/windows/base/release.html" -UseBasicParsing -UserAgent 'MetaScience-setup' -TimeoutSec 30).Content
    if ($page -match 'URL=(R-[0-9.]+-win\.exe)') { $name = $Matches[1] }
  } catch { Log "R version lookup failed: $_" }
  if (-not $name) { $name = 'R-4.6.2-win.exe' }   # fallback if the page cannot be read
  $exe = Join-Path $env:TEMP $name
  Say "  Downloading $($name -replace '-win\.exe$','') for this account only (about 90 MB)..."
  if (-not (Download "$($script:Cran)/bin/windows/base/$name" $exe)) { return $null }
  $dir = Join-Path $env:LOCALAPPDATA ("Programs\R\" + ($name -replace '-win\.exe$', ''))
  $code = Run-Native $exe @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS', "/DIR=`"$dir`"") 1800
  Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
  if ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $dir 'bin\Rscript.exe'))) { return $dir }
  Log "R installer exit $code"; return $null
}

# ---------- parts the student chooses (owner request 2026-11-12) ---------------------
# The AI assistant (OpenCode), Git and uv (which runs the setup's own Python helper) are always installed.
$AllParts = @('r', 'rstudio', 'quarto', 'python', 'node')
# gb: installed size, measured on one Windows 11 computer on 2026-11-12 (not yet on a fresh computer)
$PartInfo = @{
  r       = @{ name = 'R and the course R packages';              gb = 0.4 }
  rstudio = @{ name = 'RStudio (an editor for R; needs R)';       gb = 1.9 }
  quarto  = @{ name = 'Quarto (turns an analysis into a report)'; gb = 0.5 }
  python  = @{ name = 'Python course packages';                   gb = 0.5 }
  node    = @{ name = 'Node.js (a few optional AI tools need it)'; gb = 0.2 }
}
$script:Parts = $AllParts
function Has-Part($p) { $script:Parts -contains $p }
function Tool-Defs {
  @(
    @{ id = 'Git.Git';           name = 'Git';     part = 'core';    cmd = 'git';     exe = 'git.exe';     dirs = @('Git\cmd', 'MinGit\cmd') },
    @{ id = 'OpenJS.NodeJS.LTS'; name = 'Node.js'; part = 'node';    cmd = 'node';    exe = 'node.exe';    dirs = @('nodejs') },
    @{ id = 'astral-sh.uv';      name = 'uv';      part = 'core';    cmd = 'uv';      exe = 'uv.exe';      dirs = @() },
    @{ id = 'RProject.R';        name = 'R';       part = 'r';       cmd = 'Rscript'; exe = 'Rscript.exe'; dirs = @('R\R-*\bin') },
    @{ id = 'Posit.Quarto';      name = 'Quarto';  part = 'quarto';  cmd = 'quarto';  exe = 'quarto.exe';  dirs = @('Quarto\bin') },
    @{ id = 'Posit.RStudio';     name = 'RStudio'; part = 'rstudio'; cmd = '';        exe = 'rstudio.exe'; dirs = @('RStudio') }
  )
}
function Tool-Def($name) { Tool-Defs | Where-Object { $_.name -eq $name } | Select-Object -First 1 }
function Part-Gb($p) {   # what a part still needs on this computer: 0 when it is already there
  switch ($p) {
    'r'       { if (Find-CurrentR) { return 0.2 } }          # the course R packages may still be missing; an R older than 4.5 gets a new one
    'rstudio' { if (Find-Tool (Tool-Def 'RStudio')) { return 0 } }
    'quarto'  { if (Find-Tool (Tool-Def 'Quarto')) { return 0 } }
    'node'    { if (Find-Tool (Tool-Def 'Node.js')) { return 0 } }
    'python'  { if (Test-Path -LiteralPath (Join-Path $CourseDir '.venv')) { return 0 } }
  }
  return $PartInfo[$p].gb
}
function Estimate-Gb {   # disk space this run will use: only the chosen parts that are not on this computer yet
  $gb = 0.0
  if (-not (Have 'opencode')) { $gb += 0.6 }                          # OpenCode: command line + desktop app
  if (-not (Find-Tool (Tool-Def 'Git'))) { $gb += 0.4 }
  if (-not (Find-Tool (Tool-Def 'uv'))) { $gb += 0.2 }                # uv and its Python
  foreach ($p in $script:Parts) { $gb += (Part-Gb $p) }
  return [math]::Round($gb, 1)
}
function Parse-Parts([string]$text) {
  $want = @(); $bad = @()
  foreach ($w in @("$text" -split '[,;\s]+' | Where-Object { $_ })) {
    $w = $w.ToLowerInvariant()
    if ($w -eq 'all') { $want += $AllParts } elseif ($w -eq 'none') { } elseif ($AllParts -contains $w) { $want += $w } else { $bad += $w }
  }
  if ($want -contains 'rstudio' -and $want -notcontains 'r') { $want += 'r' }   # RStudio does not work without R
  return @{ want = @($AllParts | Where-Object { $want -contains $_ }); bad = $bad }
}
function Save-Parts {
  if ($DryRun) { return }
  $txt = if ($script:Parts.Count) { $script:Parts -join ' ' } else { 'none' }
  try { New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
        Set-Content -LiteralPath (Join-Path $StateDir 'parts.txt') -Value $txt -Encoding ASCII } catch { Log "could not save the parts: $_" }
}
function Load-Parts {   # the parts chosen last time; everything when nothing was chosen (older setups installed all)
  $f = Join-Path $StateDir 'parts.txt'
  $script:Parts = if (Test-Path -LiteralPath $f) { (Parse-Parts (Get-Content -LiteralPath $f -Raw)).want } else { $AllParts }
  if ($NoGui) { $script:Parts = @($script:Parts | Where-Object { $_ -ne 'rstudio' }) }
}
function Choose-Parts {
  $f = Join-Path $StateDir 'parts.txt'
  if ($Components) {
    $x = Parse-Parts $Components
    if ($x.bad.Count) { Say "Unknown part: $($x.bad -join ', '). Use any of: $($AllParts -join ', '), or all, or none."; exit 2 }
    $script:Parts = $x.want; Save-Parts
  } elseif ((Test-Path -LiteralPath $f) -and -not $Choose) { Load-Parts }
  elseif ($Yes -or $FromUpdate) { $script:Parts = $AllParts }
  else {
    Say ''
    Say 'What should the setup install? The AI assistant (OpenCode), Git and uv (for Python) are always installed.'
    for ($i = 0; $i -lt $AllParts.Count; $i++) {
      $p = $AllParts[$i]; $g = Part-Gb $p
      Say ('  {0}. {1,-44} {2}' -f ($i + 1), $PartInfo[$p].name, $(if ($g -eq 0) { 'already on this computer' } else { "about $g GB" }))
    }
    for ($try = 0; $try -lt 3; $try++) {
      $a = "$(Read-Host 'Press Enter to install all of them (recommended), or type the numbers you want, for example 1 3 (0 = none)')".Trim()
      if (-not $a) { $script:Parts = $AllParts; break }
      $nums = @($a -split '[,;\s]+' | Where-Object { $_ })
      if (@($nums | Where-Object { $_ -notmatch '^[0-5]$' }).Count) { Say '  Please type only numbers from the list (0 to 5).'; continue }
      $picked = @($nums | Where-Object { $_ -ne '0' } | ForEach-Object { $AllParts[[int]$_ - 1] })
      $script:Parts = (Parse-Parts ($picked -join ' ')).want
      if ($picked -contains 'rstudio' -and $picked -notcontains 'r') { Say '  RStudio needs R, so R is installed too.' }
      break
    }
    Save-Parts
  }
  if ($NoGui) { $script:Parts = @($script:Parts | Where-Object { $_ -ne 'rstudio' }) }
  $names = @($script:Parts | ForEach-Object { $PartInfo[$_].name })
  Say "  Installing: the AI assistant$(if ($names.Count) { ', ' + ($names -join ', ') })  (to change this: install-windows.cmd -Choose)"
}

# ---------- 3. core tools ----------------------------------------------------
function Install-Tools {
  Step '3/9  Core tools: Git, Node.js, uv (Python), R, Quarto, RStudio'
  if ($env:MS_TEST_CRASH -eq 'tools') { throw 'test crash in step 3 (MS_TEST_CRASH)' }   # test hook: a crash mid-run
  Say '  Rule: this setup never upgrades or removes software that is already on this computer.'
  Say '  Windows may ask "Do you want to allow this app to make changes?" - click Yes each time.'
  $tools = @()
  foreach ($t in (Tool-Defs)) {
    if ($t.part -eq 'core' -or (Has-Part $t.part)) { $tools += $t } elseif (-not ($NoGui -and $t.part -eq 'rstudio')) { Skip $t.name }
  }
  Add-UserPath (Join-Path $env:USERPROFILE '.local\bin')     # uv's own folder
  foreach ($t in $tools) {
    $found = Find-Tool $t
    if ($found -and $t.name -eq 'R') {
      $rv = R-Version $found
      if ($rv -and $rv -lt $RMin) {   # too old for the course packages: use or install a current R next to it
        $cur = Find-CurrentR
        if ($cur) { Put-PathFirst $cur; Ok 'R' "R $(R-Version $cur) is used ($cur); your older R $rv stays"; continue }
        Say "  Your R ($rv) is too old for the course packages. Installing the current R next to it, for this account only (your old R stays)."
        if ($DryRun) { Say '  [dry-run] download the current R from CRAN and install it for this account'; continue }
        $rdir = Install-RDirect
        if ($rdir) { Record-Install 'r' 'inno' $rdir; Put-PathFirst (Join-Path $rdir 'bin'); Ok 'R' "installed R $(R-Version (Join-Path $rdir 'bin')) for this account; your older R $rv stays" }
        else { Fail 'R' "could not install the current R next to R $rv; see $LogFile" }
        continue
      }
    }
    if ($found) {
      if ($t.cmd -and -not (Have $t.cmd)) { Add-UserPath $found; Ok $t.name "already on this computer, now usable from this account ($found)" }
      else { Ok $t.name 'already installed' }
      continue
    }
    if ($DryRun) { Say "  [dry-run] winget install $($t.id) (just for this account if possible)"; continue }
    $ghOnly = $t.name -in 'Git', 'Quarto', 'uv'   # winget fetches these from GitHub
    $script:WingetFresh = $false
    $wingetOk = (-not ($ghOnly -and $script:Blocked -contains 'github.com')) -and (Winget-Install $t.id)
    if ($wingetOk) { $found = Find-Tool $t }
    if ($wingetOk -and $found) { if ($script:WingetFresh) { Record-Install $t.part 'winget' $t.id }; if ($t.cmd) { Add-UserPath $found }; Ok $t.name 'installed' }
    elseif ($wingetOk -and $t.name -notin 'uv', 'Git', 'Quarto', 'RStudio') { Fail $t.name "winget reported success but $($t.exe) was not found; see $LogFile" }
    # winget failed, or said "installed" but the program is missing: try the direct download
    elseif ($t.name -eq 'uv' -and (Install-UvDirect)) {
      foreach ($e in 'uv.exe', 'uvx.exe', 'uvw.exe') { Record-Install 'core' 'file' (Join-Path $env:USERPROFILE ".local\bin\$e") }
      Add-UserPath (Join-Path $env:USERPROFILE '.local\bin'); Ok 'uv' 'installed (direct download)' }
    elseif ($t.name -eq 'Git' -and (Install-GitDirect)) { Record-Install 'core' 'dir' (Join-Path $env:LOCALAPPDATA 'Programs\MinGit'); Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\MinGit\cmd'); Ok 'Git' 'installed for this account (MinGit, direct download)' }
    elseif ($t.name -eq 'RStudio' -and (Install-RStudioDirect)) {
      Record-Install 'rstudio' 'dir' (Join-Path $env:LOCALAPPDATA 'Programs\RStudio')
      Record-Install 'rstudio' 'file' (Join-Path ([Environment]::GetFolderPath('Programs')) 'RStudio.lnk')
      Ok 'RStudio' 'installed for this account (direct download; in the Start menu)' }
    elseif ($t.name -eq 'R' -and ($rdir = Install-RDirect)) { Record-Install 'r' 'inno' $rdir; Add-UserPath (Join-Path $rdir 'bin'); Ok 'R' 'installed for this account (direct download from CRAN)' }
    elseif ($t.name -eq 'Quarto' -and (Install-QuartoDirect)) { Record-Install 'quarto' 'dir' (Join-Path $env:LOCALAPPDATA 'Programs\Quarto'); Add-UserPath (Join-Path $env:LOCALAPPDATA 'Programs\Quarto\bin'); Ok 'Quarto' 'installed for this account (direct download)' }
    else { Fail $t.name "winget could not install $($t.id); see $LogFile" }
  }
  if ($DryRun) { return }
  if ((Find-Tool (Tool-Def 'uv')) -and @(Get-Content -LiteralPath (Join-Path $StateDir 'installed.tsv') -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "^core`t(winget`tastral-sh\.uv|file`t.*\\uv\.exe)$" }).Count) {
    Record-Install 'core' 'uvdata' 'Python and downloads kept by uv'
  }
  if (-not (Has-Part 'r')) { return }
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
  if (-not $current -and -not (Test-Path -LiteralPath $binDir)) {
    # a first OpenCode on this account: the uninstall may remove it and the settings and chats it keeps
    Record-Install 'core' 'dir' $binDir
    foreach ($d in '.local\share\opencode', '.config\opencode', '.cache\opencode', '.local\state\opencode') {
      if (-not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE $d))) { Record-Install 'core' 'dir' (Join-Path $env:USERPROFILE $d) }
    }
  }
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
    if ($code -eq 0) { Record-Install 'core' 'app' 'OpenCode*'; Ok 'OpenCode desktop app' 'installed (Start menu: OpenCode)' } else { Fail 'OpenCode desktop app' "installer exit code $code" }
  } else { Fail 'OpenCode desktop app' 'download failed' }
}

# ---------- 5. R packages ------------------------------------------------------
function Install-RPackages {
  Step '5/9  R packages for the course'
  if (-not (Has-Part 'r')) { Skip 'R packages'; return }
  if ($DryRun) { Say '  [dry-run] install missing course R packages into this account''s R library'; return }
  if (-not (Have 'Rscript')) { Fail 'R packages' 'R is not installed'; return }
  $listLib = "cat(rownames(installed.packages(lib.loc=Sys.getenv('R_LIBS_USER'))))"
  $before = @("$((& Rscript -e $listLib) 2>$null)" -split '\s+' | Where-Object { $_ })
  $expr = "lib <- Sys.getenv('R_LIBS_USER'); dir.create(lib, recursive=TRUE, showWarnings=FALSE); .libPaths(c(lib,.libPaths())); pk <- strsplit('$RPackages',' ')[[1]]; miss <- pk[!vapply(pk, function(p) suppressWarnings(suppressMessages(requireNamespace(p, quietly=TRUE))), NA)]; if (length(miss)) install.packages(miss, lib=lib, repos='$($script:Cran)', type='binary')"
  # a package counts as ready only when it loads (its folder can be there while a package it needs is missing)
  Run-Native 'Rscript' @('-e', "`"$expr`"") 1800 | Out-Null
  $missing = (& Rscript -e "pk <- strsplit('$RPackages',' ')[[1]]; miss <- pk[!vapply(pk, function(p) suppressWarnings(suppressMessages(requireNamespace(p, quietly=TRUE))), NA)]; cat(miss)") 2>$null
  foreach ($pk in @("$((& Rscript -e $listLib) 2>$null)" -split '\s+' | Where-Object { $_ })) { if ($before -notcontains $pk) { Record-Install 'r' 'rpkg' $pk } }
  if ($DryRun) { return }
  if (-not $missing) { Ok 'R packages' "$(($RPackages -split ' ').Count) packages ready" } else { Fail 'R packages' "missing or not loading: $missing" }
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
  if (-not (Test-Path -LiteralPath $CourseDir)) { Record-Install 'course' 'dir' $CourseDir }
  New-Item -ItemType Directory -Force -Path $CourseDir | Out-Null
  # what the pack installed last time, so an update can tell a student's own edit from an old course file
  $kitHashFile = Join-Path $CourseDir '.metascience\kit-hashes.json'
  $kitHashes = @{}
  if (Test-Path -LiteralPath $kitHashFile) { try { (Get-Content -Raw -LiteralPath $kitHashFile | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $kitHashes[$_.Name] = $_.Value } } catch {} }
  Get-ChildItem -LiteralPath $KitDir -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($KitDir.Length + 1)
    $dest = Join-Path $CourseDir $rel
    $courseFile = ($rel -eq 'AGENTS.md') -or ($rel -eq 'pyproject.toml') -or $rel.StartsWith('check\') -or $rel.StartsWith('.opencode\plugins\')
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
  if (-not (Has-Part 'python')) { Skip 'Python course packages' }
  else {
  for ($try = 1; $try -le 3; $try++) {   # a dropped download is resumed from uv's cache on the next try
    $code = Run-Native 'uv' @('sync', '--directory', "`"$CourseDir`"", '--python', '3.12') 1800
    if ($code -eq 0) { break }
    Log "uv sync try $try failed (exit $code)"; Start-Sleep -Seconds 10
  }
  if ($code -eq 0) { Ok 'Python environment' 'Python 3.12 + course packages' } else { Fail 'Python environment' "uv sync failed; see $LogFile" }
  # pymupdf needs MSVCP140.dll, which Python does not bring and a fresh Windows lacks (VM 2026-11-09: "DLL load failed
  # while importing _extra"). msvc-runtime puts it in the .venv folder, where Windows does not look when Python loads
  # pymupdf; it is found only next to pymupdf's own files.
  $venv = Join-Path $CourseDir '.venv'; $pm = Join-Path $venv 'Lib\site-packages\pymupdf'; $dll = Join-Path $venv 'msvcp140.dll'
  if ((Test-Path -LiteralPath $pm) -and (Test-Path -LiteralPath $dll) -and -not (Test-Path -LiteralPath (Join-Path $pm 'msvcp140.dll'))) {
    try { Copy-Item -LiteralPath $dll -Destination $pm -ErrorAction Stop; Log 'copied msvcp140.dll next to pymupdf' } catch { Log "msvcp140 copy failed: $_" }
  }
  }
  if ((Py @('config')) -eq 0) { Ok 'OpenCode settings' 'free model as default, 6 MCP tools (off)' } else { Fail 'OpenCode settings' 'could not write opencode.json' }
}

function Run-Check {
  Step '8/9  Real-task check (uses every installed tool)'
  if (-not (Have 'uv')) { Fail 'uv' 'not installed, cannot run the check'; return }
  $a = @('check', '--log', $LogFile, '--parts', $(if ($script:Parts.Count) { $script:Parts -join ',' } else { 'none' })); if ($SkipAI) { $a += '--skip-ai' }
  $rc = Py $a
  # A Windows crash code (negative, e.g. 0xC000070A seen once on a fresh VM; the re-run passed) is Python itself
  # failing, not a failed check: run the check once more, and log the code (d-8fb1bf)
  if ($rc -lt 0) {
    Warn 'Check' ("Python stopped unexpectedly (code 0x{0:X8}); running the check once more" -f $rc)
    $rc = Py $a
  }
  if ($rc -ne 0) { $script:Failed++ }
}

# ---------- AI setup helper ------------------------------------------------------
function Start-Doctor {
  # When something failed, OpenCode itself (free model) reads the log and guides the student.
  # It runs fix commands by itself; deleting files and admin commands are denied (class 2026-11-09: the Allow prompt froze the keyboard).
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
         '"permission": { "edit": "allow", "webfetch": "allow", "external_directory": "allow", "bash": { "*": "allow", "rm *": "deny", "*rm -rf*": "deny", "sudo *": "deny", "chmod *": "deny", "chown *": "deny", "dd *": "deny", "mkfs*": "deny", "diskutil *": "deny", "Remove-Item*": "deny", "del *": "deny", "rd *": "deny", "rmdir *": "deny", "format *": "deny", "reg *": "deny", "Set-ExecutionPolicy*": "deny" } }' + $(if ($model) { ", `"model`": `"$model`"" } else { '' }) + ' }'
  [IO.File]::WriteAllText((Join-Path $help 'opencode.json'), $cfg, (New-Object Text.UTF8Encoding($false)))
  Say ''
  Say '  The AI helper starts now. It has read nothing on your laptop except the setup log.'
  Say '  It runs its fix commands by itself (it is not allowed to delete files or use admin rights) and explains each one.'
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
      Record-Install 'core' 'pack' $PackDir
      Ok 'Pack copy' $PackDir
    } catch { Warn 'Pack copy' "could not copy the pack to $PackDir ($($_.Exception.Message)); updates will not work"; return }
  }
  $updater = Join-Path $PackDir 'update\update.ps1'
  if (-not (Test-Path -LiteralPath $updater)) { Warn 'Automatic updates' 'this copy of the pack has no updater'; return }
  if ($NoAutoUpdate) {
    $null = Run-Native 'schtasks.exe' @('/delete', '/tn', "`"$UpdateTask`"", '/f') 120
    Ok 'Automatic updates' 'off (you can update by hand: install-windows.cmd -Update)'; return
  }
  if (-not $Yes -and (Run-Native 'schtasks.exe' @('/query', '/tn', "`"$UpdateTask`"") 120) -ne 0) {
    $a = Read-Host 'Keep this course pack up to date automatically (a short daily check)? Recommended. [Y/n]'
    if ($a -match '^(n|no)$') { Ok 'Automatic updates' 'off (you can update by hand: install-windows.cmd -Update)'; return }
  }
  # Register with schtasks.exe and a time limit: the PowerShell task cmdlets (Register-ScheduledTask) hung for
  # 10+ minutes in the Hong Kong VM test, and this optional step must never hold up the setup.
  $esc = [Security.SecurityElement]::Escape($updater); $tmpDir = [Security.SecurityElement]::Escape($env:TEMP)
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Checks for a newer version of the MetaScience course pack (freeAIsetup) and installs it.</Description></RegistrationInfo>
  <Triggers><CalendarTrigger><StartBoundary>2026-01-01T12:30:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><StartWhenAvailable>true</StartWhenAvailable><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>PT2H</ExecutionTimeLimit><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><Enabled>true</Enabled></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$esc" -Auto</Arguments><WorkingDirectory>$tmpDir</WorkingDirectory></Exec></Actions>
</Task>
"@
  $xf = Join-Path $env:TEMP 'metascience-update-task.xml'
  try { [IO.File]::WriteAllText($xf, $xml, [Text.Encoding]::Unicode) } catch { Warn 'Automatic updates' "could not prepare the daily check ($_); update by hand: install-windows.cmd -Update"; return }
  $code = Run-Native 'schtasks.exe' @('/create', '/tn', "`"$UpdateTask`"", '/xml', "`"$xf`"", '/f') 300
  Remove-Item -LiteralPath $xf -Force -ErrorAction SilentlyContinue
  if ($code -eq 0) { Record-Install 'core' 'task' $UpdateTask; Ok 'Automatic updates' 'on: a short check once a day (turn off: install-windows.cmd -NoAutoUpdate)' }
  else { Warn 'Automatic updates' "could not add the daily check (schtasks exit $code); update by hand: install-windows.cmd -Update" }
}

# The file to show the teacher: the report of the check (step 8), or the log when setup stopped before the check
function Report-File { $r = Join-Path $CourseDir 'setup-report.txt'; if (Test-Path -LiteralPath $r) { return $r }; return $LogFile }
function Summary {
  Step '9/9  Summary'
  if ($DryRun) { Write-Host 'Dry run finished: the lines above show what a real run would do.' -ForegroundColor Yellow }
  elseif ($script:Failed -eq 0) { Write-Host 'All done. Everything works.' -ForegroundColor Green }
  else {
    Write-Host 'Something needs attention (see the FAIL lines above). Run the setup again first; it repairs most problems.' -ForegroundColor Red
    Say "If it still fails, show the teacher: $(Report-File)"
  }
  Say "Full log: $LogFile"
  Say "Next: open OpenCode from the Start menu, choose the folder $CourseDir, and follow the guide."
}

# ---------- reporting to the teacher's log box ------------------------------------
# One address for both messages; tests point it at a local copy (MS_LOG_URL) and mark themselves (MS_LOG_ENV=local).
$LogBox = if ($env:MS_LOG_URL) { $env:MS_LOG_URL.TrimEnd('/') } else { 'https://freeaisetup-logs.giladfel.workers.dev' }
function LogBox-Headers { $h = @{ 'x-freeaisetup' = '1' }; if ($env:MS_LOG_ENV) { $h['x-freeaisetup-env'] = $env:MS_LOG_ENV }; return $h }
function Send-Log {
  # With the student's yes: send the log to the teacher's private log box (write-only address, kept 180 days).
  try {
    $rep = Join-Path $CourseDir 'setup-report.txt'
    $txt = "== setup-report.txt ==`n" + $(if (Test-Path -LiteralPath $rep) { [IO.File]::ReadAllText($rep) } else { '' }) +
           "`n== setup log ==`n" + [IO.File]::ReadAllText($LogFile)
    $txt = $txt -replace [regex]::Escape($env:USERPROFILE), '~'
    foreach ($w in @($env:USERNAME, $env:COMPUTERNAME)) { if ($w -and $w.Length -ge 4) { $txt = $txt -replace [regex]::Escape($w), '<name>' } }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $url = "$LogBox/upload?platform=windows&version=$SetupVersion&result=failed"
    $r = Invoke-WebRequest -Uri $url -Method Post -UseBasicParsing -TimeoutSec 60 -Headers (LogBox-Headers) `
         -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($txt))
    $id = ([string]$r.Content).Trim()
    if ($id) { Write-Host '  Sent. ' -ForegroundColor Green -NoNewline; Say "Your code is $id. Tell your teacher this code."; return }
  } catch { Log "upload failed: $($_.Exception.Message)" }
  Say "  Could not send it (no internet?). Show your teacher this file instead: $(Report-File)"
}
function Send-SuccessCount {
  # Owner request 2026-11-12: count successful installs, nothing else. The message carries only the platform and the
  # pack version: no name, no computer details, no log. Sent once per account (a marker file remembers it).
  $mark = Join-Path $StateDir 'install-counted'
  if ($env:MS_NO_COUNT -or (Test-Path -LiteralPath $mark)) { return }   # MS_NO_COUNT=1 switches it off (README, Privacy)
  try {
    $null = Invoke-WebRequest -Uri "$LogBox/count?platform=windows&version=$SetupVersion" -Method Post -UseBasicParsing -TimeoutSec 20 `
            -Headers (LogBox-Headers) -Body ''
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mark) | Out-Null
    Set-Content -LiteralPath $mark -Value (Get-Date -Format 'yyyy-MM-dd') -Encoding ASCII
    Log 'success count sent (platform and version only)'
  } catch { Log "success count not sent: $($_.Exception.Message)" }   # never matters to the student
}
function Offer-Help {
  # Every failing run ends here, however it stopped: a check that failed, a stop in step 1, or an unexpected error.
  if ($script:Failed -eq 0 -or $DryRun -or $Yes -or $FromUpdate) { return }
  Say ''
  $a = Read-Host '  Send this setup report to your teacher, so they can see what went wrong? It contains no passwords and no course work; your user name is removed. [Y/n]'
  if ($a -notmatch '^(n|no)$') { Send-Log }
  $a = Read-Host 'Some steps failed. Start the AI setup helper? It reads the setup log and fixes what it can, explaining each step. [Y/n]'
  if ($a -notmatch '^(n|no)$') { Start-Doctor }
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
if ($Uninstall) {
  # The uninstaller removes this pack folder, and Windows cannot delete a folder that a program is working in or
  # running from (tested 2026-11-12: "it is in use"). So a copy runs from the temp folder, working there.
  $unCopy = Join-Path $env:TEMP 'metascience-uninstall.ps1'
  Copy-Item -LiteralPath (Join-Path $ScriptDir 'lib\uninstall-windows.ps1') -Destination $unCopy -Force
  Set-Location -LiteralPath $env:TEMP; [Environment]::CurrentDirectory = $env:TEMP
  $un = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $unCopy)
  if ($Components) { $un += @('-Parts', $Components) }; if ($Yes) { $un += '-Yes' }; if ($DryRun) { $un += '-DryRun' }
  if ($env:MS_FROM_CMD) {   # started by install-windows.cmd, which runs from the pack folder: the pack goes once it has ended
    try { $cmdPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId; if ($cmdPid) { $un += @('-WaitPid', "$cmdPid") } } catch { Log "parent process unknown: $_" }
  }
  & powershell.exe @un; exit $LASTEXITCODE
}
try {
  if ($env:MS_TEST_CRASH -eq 'main') { throw 'test crash (MS_TEST_CRASH)' }   # test hook: proves a crash still reaches the offer
  if ($Check) { Load-Parts; Run-Check; Summary }
  elseif ($Keys) { Load-Parts; Step 'Optional: free AI keys'; Py @('keys') | Out-Null; Run-Check; Summary }
  else {
    # A stop in step 1 (old Windows, full disk, no internet, no winget) skips the installs but still ends with the
    # summary and the offer to send the report (it used to exit here, so the teacher never heard of it).
    Choose-Parts
    if (Precheck) {
      Install-Tools; Install-OpenCode; Install-RPackages; Fix-Pandoc; Setup-CourseFolder
      if (-not $FromUpdate) { Install-Pack }
      if (-not $DryRun -and -not $FromUpdate) {
        if (-not $Yes) {
          $a = Read-Host 'Connect a free OpenRouter account as a backup for the AI (about 2 minutes, opens your browser)? You can also do it later with install-windows.cmd -Keys [y/N]'
          if ($a -match '^(y|yes)$') { Py @('keys') | Out-Null }
        }
        Run-Check
        if ($script:Failed -eq 0) { Send-SuccessCount }
      }
    }
    Summary
  }
} catch {
  # an unexpected error: record it like a failed step, so the student is offered the report and the helper
  Fail 'Setup stopped' "an unexpected error: $($_.Exception.Message)"
  Log ($_ | Out-String); Log $_.ScriptStackTrace
  try { Summary } catch {}
}
Offer-Help
if ($script:Failed -eq 0) { exit 0 } else { exit 1 }
