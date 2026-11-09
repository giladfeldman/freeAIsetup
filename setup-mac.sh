#!/bin/bash
# =============================================================================
#  Meta-science course: one-step setup for macOS (and Linux, used for testing)
#  Installs: OpenCode (desktop + command line), Git, Node.js, uv + Python,
#            R + course packages, RStudio, Quarto; creates ~/MetaScience;
#            runs a real end-to-end check that uses every installed tool.
#  Safe to run again: it skips what is already installed and repairs the rest.
#
#  Usage:  bash setup-mac.sh            full setup (asks for your Mac password once)
#          bash setup-mac.sh --check    only run the check (doctor)
#          bash setup-mac.sh --keys     add optional free AI keys (OpenRouter, Groq, ...)
#          bash setup-mac.sh --fix      start the AI setup helper on the last setup log
#          bash setup-mac.sh --dry-run  show what would be done, change nothing
#          bash setup-mac.sh --help
#  Written for bash 3.2 (the macOS default): no associative arrays, no ${x,,}.
# =============================================================================
set -u

OPENCODE_VERSION="1.19.5"
COURSE_DIR="${METASCIENCE_DIR:-$HOME/MetaScience}"
KEY_DIR="$HOME/.config/metascience/keys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$SCRIPT_DIR/course-kit"
export UV_HTTP_TIMEOUT=300 UV_CONCURRENT_DOWNLOADS=4 UV_HTTP_RETRIES=5   # slow or crowded Wi-Fi: wait longer, fewer at once
SETUP_VERSION="$(head -1 "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '\r ')"; SETUP_VERSION="${SETUP_VERSION:-dev}"
if [ "$(uname -s)" = Darwin ]; then PACK_DIR="$HOME/Library/Application Support/MetaScience/pack"
else PACK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/metascience/pack"; fi   # installed copy of this pack (kept up to date)
PACK_ITEMS="install-windows.cmd setup-windows.ps1 setup-mac.sh VERSION lib course-kit doctor guide update"
LOG_FILE="${TMPDIR:-/tmp}/metascience-setup-$(date +%Y%m%d-%H%M%S).log"
R_PACKAGES="rmarkdown knitr readr dplyr tidyr ggplot2 metafor statcheck irr here mcptools"

DRY_RUN=0; MODE="full"; ASSUME_YES=0; SKIP_AI=0; SKIP_GUI=0; NO_AUTO_UPDATE=0; FROM_UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --check)   MODE="check" ;;
    --keys)    MODE="keys" ;;
    --fix)     MODE="fix" ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --skip-ai) SKIP_AI=1 ;;
    --no-gui)  SKIP_GUI=1 ;;
    --update)  MODE="update" ;;
    --rollback) MODE="rollback" ;;
    --no-auto-update) NO_AUTO_UPDATE=1 ;;
    --from-update) FROM_UPDATE=1; ASSUME_YES=1 ;;   # internal: run by the updater after new files arrived
    --help|-h) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
  esac
done

# ---------- output helpers ---------------------------------------------------
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'; else G=""; R=""; Y=""; B=""; N=""; fi
RESULTS=""          # lines of "STATUS|item|detail"
FAILED=0
say()   { printf '%s\n' "$*" | tee -a "$LOG_FILE"; }
step()  { say ""; say "${B}== $* ==${N}"; }
ok()    { say "  ${G}OK${N}    $1${2:+  ($2)}"; RESULTS="${RESULTS}OK|$1|${2:-}"$'\n'; }
warn()  { say "  ${Y}WARN${N}  $1${2:+  ($2)}"; RESULTS="${RESULTS}WARN|$1|${2:-}"$'\n'; }
fail()  { say "  ${R}FAIL${N}  $1${2:+  ($2)}"; RESULTS="${RESULTS}FAIL|$1|${2:-}"$'\n'; FAILED=$((FAILED+1)); }
run()   { # run a command, log its output; in dry-run only print it
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] $*"; return 0; fi
  echo "\$ $*" >> "$LOG_FILE"; "$@" >> "$LOG_FILE" 2>&1
}
have()  { command -v "$1" >/dev/null 2>&1; }
retry() { # retry a command up to 3 times (flaky Wi-Fi)
  local n=1; while :; do run "$@" && return 0; [ $n -ge 3 ] && return 1; say "  retrying ($n/3)..."; n=$((n+1)); sleep 5; done
}

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in Darwin) PLATFORM="mac" ;; Linux) PLATFORM="linux" ;; *) echo "This script is for macOS (or Linux). On Windows use install-windows.cmd."; exit 2 ;; esac
case "$ARCH" in arm64|aarch64) ARCH_ID="arm64" ;; x86_64|amd64) ARCH_ID="x64" ;; *) echo "Unsupported processor: $ARCH"; exit 2 ;; esac
SUDO=""; if [ "$(id -u)" != 0 ]; then SUDO="sudo"; fi

add_path() { # add a directory to PATH now and in the shell start-up files (once)
  case ":$PATH:" in *":$1:"*) ;; *) export PATH="$1:$PATH" ;; esac
  [ "$DRY_RUN" = 1 ] && return 0
  local f; for f in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    touch "$f"; grep -qF "$1" "$f" 2>/dev/null || printf '\nexport PATH="%s:$PATH"  # added by MetaScience setup\n' "$1" >> "$f"
  done
}

# ---------- network: proxy, blocked sites, mirror sites ------------------------
# Some networks block sites (university firewalls, some countries) and some laptops have a proxy or
# VPN app configured. The setup then uses mirror sites that carry the very same files.
CRAN="https://cloud.r-project.org"
BLOCKED=" "
site_ok() { # reachable = any HTTP answer within 12 s (an HTTP error still proves the site is there)
  local code; code="$(curl -s -m 12 -o /dev/null -w '%{http_code}' -A "MetaScience-setup" "$1" 2>/dev/null)"
  [ -n "$code" ] && [ "$code" != "000" ]
}
uv_from_pypi() { # second route for uv: the same uv program is published on the Python package site (and its mirrors)
  local plat idx page url tmp
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) plat='macosx_[0-9_]+_arm64' ;; Darwin-*) plat='macosx_[0-9_]+_x86_64' ;;
    Linux-aarch64) plat='manylinux[0-9_a-z.]*aarch64' ;; *) plat='manylinux[0-9_a-z.]*x86_64' ;;
  esac
  for idx in https://pypi.org/simple https://mirrors.aliyun.com/pypi/simple https://pypi.tuna.tsinghua.edu.cn/simple; do
    page="$(curl -fsSL -m 30 -A "MetaScience-setup" "$idx/uv/" 2>/dev/null)" || continue
    url="$(printf '%s' "$page" | grep -oE 'href="[^"]*uv-[0-9.]+-py3-none-'"$plat"'\.whl[^"]*"' | awk '{ v = $0; sub(/.*uv-/, "", v); sub(/-py3.*/, "", v); n = split(v, a, "."); printf "%06d%06d%06d %s\n", a[1], a[2], a[3], $0 }' | sort | tail -1 | cut -d' ' -f2- | sed 's/^href="//; s/"$//; s/&amp;/\&/g')"
    [ -n "$url" ] || continue
    case "$url" in http*) ;; /*) url="$(printf '%s' "$idx" | sed -E 's#(https?://[^/]+).*#\1#')$url" ;; *) url="$idx/uv/$url" ;; esac
    echo "uv wheel: $url" >> "$LOG_FILE"
    tmp="$(mktemp -d)"
    if curl -fsSL -m 300 -o "$tmp/uv.zip" "${url%%#*}" && { unzip -q -o "$tmp/uv.zip" -d "$tmp" || python3 -m zipfile -e "$tmp/uv.zip" "$tmp"; } >> "$LOG_FILE" 2>&1; then
      mkdir -p "$HOME/.local/bin"; find "$tmp" -type f \( -name uv -o -name uvx \) -path '*scripts*' -exec cp {} "$HOME/.local/bin/" \;
      chmod +x "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" 2>/dev/null; rm -rf "$tmp"; add_path "$HOME/.local/bin"
      have uv && return 0
    fi
    rm -rf "$tmp"
  done
  return 1
}
setup_proxy() {
  [ -n "${HTTPS_PROXY:-}${https_proxy:-}" ] && { say "  Proxy from environment: ${HTTPS_PROXY:-$https_proxy}"; return 0; }
  have scutil || return 0
  local p host port
  p="$(scutil --proxy 2>/dev/null)"
  echo "$p" | grep -q 'HTTPSEnable : 1' || return 0
  host="$(echo "$p" | awk '/HTTPSProxy :/ {print $3}')"; port="$(echo "$p" | awk '/HTTPSPort :/ {print $3}')"
  [ -n "$host" ] || return 0
  echo "proxy: $host:$port" >> "$LOG_FILE"
  if nc -z -G 4 "$host" "${port:-80}" >/dev/null 2>&1; then
    export HTTPS_PROXY="http://$host:${port:-80}" HTTP_PROXY="http://$host:${port:-80}" NO_PROXY="localhost,127.0.0.1"
    ok "Proxy" "downloads go through the proxy set on this Mac ($host:$port)"
  else
    warn "Proxy" "this Mac sends internet traffic through $host:$port, but nothing answers there"
    say "        If you use a VPN or proxy app (for example ClashX), start it. If you do not, open"
    say "        System Settings > Network > (your Wi-Fi) > Details > Proxies, switch the proxies off, and run this again."
  fi
}
setup_network() {
  local h need bad=0 total=0
  for h in github.com opencode.ai cloud.r-project.org pypi.org registry.npmjs.org; do
    total=$((total+1))
    site_ok "https://$h" && continue
    bad=$((bad+1)); BLOCKED="$BLOCKED$h "
    case "$h" in
      github.com) need="OpenCode, Homebrew, Quarto, Python" ;; opencode.ai) need="the free AI models" ;;
      cloud.r-project.org) need="R and R packages" ;; pypi.org) need="Python packages" ;; *) need="OpenCode (second source)" ;;
    esac
    warn "Blocked site" "$h cannot be reached from this network (needed for $need)"
  done
  if [ "$bad" = "$total" ]; then
    fail "Internet access" "no download site can be reached"
    say "        Check that Wi-Fi is connected and that a browser can open https://github.com ."
    say "        University or hotel Wi-Fi may first need a login page in the browser. A VPN or proxy app can also block traffic."
    return 1
  fi
  [ "$bad" = 0 ] && { ok "Internet access" "all download sites reachable"; return 0; }
  case "$BLOCKED" in *" github.com "*)
    if site_ok "https://registry.npmmirror.com"; then
      export UV_PYTHON_INSTALL_MIRROR="https://registry.npmmirror.com/-/binary/python-build-standalone"
      say "        Python will be downloaded from a mirror site instead of GitHub."
    fi
    if site_ok "https://mirrors.tuna.tsinghua.edu.cn/"; then
      export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
      export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
      export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
      export HOMEBREW_INSTALL_FROM_API=1
      say "        Homebrew will use the Tsinghua mirror."
    fi ;;
  esac
  case "$BLOCKED" in *" pypi.org "*)
    for m in https://mirrors.aliyun.com/pypi/simple https://pypi.tuna.tsinghua.edu.cn/simple; do
      if site_ok "$m/"; then export UV_DEFAULT_INDEX="$m"; say "        Python packages will come from the mirror $m"; break; fi
    done ;;
  esac
  case "$BLOCKED" in *" cloud.r-project.org "*)
    for m in https://cran.wu.ac.at https://mirrors.tuna.tsinghua.edu.cn/CRAN https://cran.ms.unimelb.edu.au; do
      if site_ok "$m/"; then CRAN="$m"; say "        R packages will come from the mirror $m"; break; fi
    done ;;
  esac
  say "        If something below fails, connect to a different network (e.g. a phone hotspot) or turn on your VPN, and run this again."
  return 0
}

# ---------- 1. pre-checks ----------------------------------------------------
precheck() {
  step "1/9  Checking this computer"
  ok "System" "$PLATFORM $(sw_vers -productVersion 2>/dev/null || uname -r), $ARCH"
  if [ "$PLATFORM" = mac ]; then
    local major; major="$(sw_vers -productVersion | cut -d. -f1)"
    if [ "$major" -lt 12 ]; then fail "macOS version" "macOS 12 or newer is needed; you have $(sw_vers -productVersion)"; return 1; fi
  fi
  local free_gb; free_gb="$(df -Pk "$HOME" | awk 'NR==2 {print int($4/1048576)}')"
  # The course tools need about 4 GB; 8 GB leaves room for course work. A GitHub Codespace shows only ~7 GB free
  # while it is still being built (20 GB a few minutes later; 2026-11-09), so there 4 GB is enough.
  local need=8; [ -n "${CODESPACES:-}" ] && need=4
  if [ "${free_gb:-0}" -lt "$need" ]; then fail "Free disk space" "${free_gb} GB free, $need GB needed"; return 1; else ok "Free disk space" "${free_gb} GB"; fi
  setup_proxy
  setup_network || return 1
  if [ -n "$SUDO" ] && [ "$DRY_RUN" = 0 ]; then
    say "  Some steps need your computer password (the one you use to log in). Typing shows no characters."
    sudo -v || { fail "Administrator password" "needed to install R and other tools"; return 1; }
    ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  fi
}

# ---------- 2. package manager ----------------------------------------------
pkg_manager() {
  step "2/9  Package manager"
  if [ "$PLATFORM" = mac ]; then
    if ! have brew; then
      for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
    fi
    if have brew; then
      if [ -w "$(brew --prefix)" ]; then ok "Homebrew" "$(brew --version | head -1)"
      else warn "Homebrew" "belongs to another account on this Mac: tools it already has are used, missing ones may fail"; fi
      return 0
    fi
    say "  Installing Homebrew (this also installs Apple's command line tools; 5-15 minutes)..."
    if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install Homebrew"; return 0; fi
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)" && add_path "$(dirname "$p")"; done
    have brew && ok "Homebrew" "installed" || { fail "Homebrew" "installation failed, see $LOG_FILE"; return 1; }
  else
    retry $SUDO apt-get update -y && ok "apt" "package lists updated" || { fail "apt" "apt-get update failed"; return 1; }
  fi
}

# ---------- 3. core tools ----------------------------------------------------
install_tools() {
  step "3/9  Core tools: Git, Node.js, uv (Python), R, Quarto, RStudio"
  say "  Rule: this setup never upgrades or removes software that is already on this computer."
  if [ "$PLATFORM" = mac ]; then
    # tools another account installed for the whole Mac: make them usable from this account
    local d; for d in /Library/Frameworks/R.framework/Resources/bin /Applications/quarto/bin /opt/homebrew/bin /usr/local/bin; do
      [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) { [ -x "$d/Rscript" ] || [ -x "$d/quarto" ] || [ -x "$d/git" ]; } && add_path "$d" ;; esac
    done
    local f; for f in git node uv; do
      if have "$f"; then ok "$f" "already installed"; elif retry brew install "$f"; then ok "$f" "installed"
      elif [ "$f" = uv ] && uv_from_pypi; then ok "uv" "installed (direct download)"; else fail "$f" "brew install $f failed"; fi
    done
    # R older than 4.5: the course packages no longer come ready-built for it, so all of them fail (class 2026-11-09:
    # a MacBook with R 4.0.0 from 2020). The R installer keeps the old version in R.framework/Versions; the new one
    # becomes the default. This is the one exception to "never upgrade": nothing is removed.
    local rv=""; have R && rv="$(R --version 2>/dev/null | head -1 | sed -n 's/^R version \([0-9]*\.[0-9]*\).*/\1/p')"
    if [ -n "$rv" ] && [ "$(printf '%s\n4.5\n' "$rv" | sort -t. -k1,1n -k2,2n | head -1)" = 4.5 ]; then ok "R" "already installed (R $rv)"
    else
      [ -n "$rv" ] && say "  Your R ($rv) is too old for the course packages. Installing the current R next to it (your old R stays; macOS may ask for your password)."
      local rcmd="install"; [ -n "$rv" ] && brew list --cask r >/dev/null 2>&1 && rcmd="upgrade"   # an old R that brew itself installed
      retry brew $rcmd --cask r && ok "R" "installed$([ -n "$rv" ] && echo " (current R; old R $rv kept)")" || fail "R" "brew install --cask r failed"
    fi
    have quarto  && ok "Quarto" "already installed"  || { retry brew install --cask quarto  && ok "Quarto" "installed"  || fail "Quarto" "brew install --cask quarto failed"; }
    if [ "$SKIP_GUI" = 0 ]; then
      if [ -d "/Applications/RStudio.app" ]; then ok "RStudio" "already installed"
      else retry brew install --cask rstudio && ok "RStudio" "installed" || fail "RStudio" "brew install --cask rstudio failed"; fi
    fi
  else
    # only what is missing (a course Codespace already brings current Node.js and R; never replace them)
    local want="curl ca-certificates unzip python3"
    have git || want="$want git"; have node || want="$want nodejs npm"; have R || want="$want r-base r-base-dev"
    retry $SUDO apt-get install -y --no-install-recommends $want \
      && ok "Git, Node.js, R" "ready (git $(git --version 2>/dev/null | cut -d' ' -f3), node $(node --version 2>/dev/null), R $(R --version 2>/dev/null | head -1 | cut -d' ' -f3))" \
      || fail "apt packages" "see $LOG_FILE"
    if have uv; then ok "uv" "already installed"
    elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install uv"
    else curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >> "$LOG_FILE" 2>&1; add_path "$HOME/.local/bin"
      if have uv; then ok "uv" "installed"; elif uv_from_pypi; then ok "uv" "installed (direct download)"; else fail "uv" "installer failed"; fi; fi
    if have quarto; then ok "Quarto" "already installed"
    elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install Quarto"
    else
      local qv="1.8.25" qa; [ "$ARCH_ID" = arm64 ] && qa=arm64 || qa=amd64
      retry curl -fsSL -o /tmp/quarto.deb "https://github.com/quarto-dev/quarto-cli/releases/download/v$qv/quarto-$qv-linux-$qa.deb" \
        && run $SUDO apt-get install -y /tmp/quarto.deb && ok "Quarto" "installed" || fail "Quarto" "download or install failed"
    fi
  fi
  add_path "$HOME/.local/bin"
}

# ---------- 4. OpenCode -------------------------------------------------------
install_opencode() {
  step "4/9  OpenCode $OPENCODE_VERSION (AI assistant)"
  local base="https://github.com/anomalyco/opencode/releases/download/v$OPENCODE_VERSION" bindir="$HOME/.local/bin" tmp
  tmp="$(mktemp -d)"
  if have opencode && [ "$(opencode --version 2>/dev/null)" = "$OPENCODE_VERSION" ]; then ok "OpenCode command line" "version $OPENCODE_VERSION already installed"
  else
    local asset
    if [ "$PLATFORM" = mac ]; then [ "$ARCH_ID" = arm64 ] && asset="opencode-darwin-arm64.zip" || asset="opencode-darwin-x64-baseline.zip"
    else [ "$ARCH_ID" = arm64 ] && asset="opencode-linux-arm64.tar.gz" || asset="opencode-linux-x64-baseline.tar.gz"; fi
    local got=0 pkg reg bin
    case "$BLOCKED" in *" github.com "*) ;; *)
      if retry curl -fsSL -o "$tmp/$asset" "$base/$asset"; then
        case "$asset" in *.zip) run unzip -o -q "$tmp/$asset" -d "$tmp/x" ;; *) run mkdir -p "$tmp/x"; run tar -xzf "$tmp/$asset" -C "$tmp/x" ;; esac
        got=1
      fi ;;
    esac
    if [ "$got" = 0 ] && [ "$DRY_RUN" = 0 ]; then
      # the same program, published as an npm package: npm's own site, then a mirror reachable from China
      pkg="opencode-$( [ "$PLATFORM" = mac ] && echo darwin || echo linux )-$( [ "$ARCH_ID" = arm64 ] && echo arm64 || echo x64-baseline )"
      for reg in https://registry.npmjs.org https://registry.npmmirror.com; do
        if curl -fsSL -m 300 -o "$tmp/oc.tgz" "$reg/$pkg/-/$pkg-$OPENCODE_VERSION.tgz" 2>>"$LOG_FILE"; then
          mkdir -p "$tmp/x" && tar -xzf "$tmp/oc.tgz" -C "$tmp/x" 2>>"$LOG_FILE"
          bin="$(find "$tmp/x" -type f -name opencode | head -1)"
          if [ -n "$bin" ]; then cp "$bin" "$tmp/x/opencode" 2>/dev/null; got=1; echo "OpenCode from $reg" >> "$LOG_FILE"; break; fi
        fi
      done
    fi
    if [ "$got" = 1 ] || [ "$DRY_RUN" = 1 ]; then
      run mkdir -p "$bindir"
      run cp "$tmp/x/opencode" "$bindir/opencode"; run chmod +x "$bindir/opencode"
      add_path "$bindir"
      [ "$DRY_RUN" = 1 ] || { [ "$(opencode --version 2>/dev/null)" = "$OPENCODE_VERSION" ] && ok "OpenCode command line" "installed $OPENCODE_VERSION" || fail "OpenCode command line" "installed but does not start"; }
    else fail "OpenCode command line" "download failed from GitHub and from npm; see $LOG_FILE"; fi
  fi
  if [ "$PLATFORM" = mac ] && [ "$SKIP_GUI" = 0 ]; then
    if [ -d "/Applications/OpenCode.app" ] || [ -d "$HOME/Applications/OpenCode.app" ]; then ok "OpenCode desktop app" "already installed"
    else
      local app="opencode-desktop-mac-$ARCH_ID.zip"
      case "$BLOCKED" in *" github.com "*) warn "OpenCode desktop app" "GitHub is blocked here, so only the command-line OpenCode is installed (type opencode in Terminal)"; rm -rf "$tmp"; return 0 ;; esac
      if retry curl -fsSL -o "$tmp/$app" "$base/$app"; then
        run ditto -x -k "$tmp/$app" "$tmp/app"
        local found; found="$(find "$tmp/app" -maxdepth 2 -name '*.app' | head -1)"
        if [ -n "$found" ] && run cp -R "$found" /Applications/; then ok "OpenCode desktop app" "in Applications"
        elif [ -n "$found" ] && run mkdir -p "$HOME/Applications" && run cp -R "$found" "$HOME/Applications/"; then ok "OpenCode desktop app" "in your personal Applications folder"
        else [ "$DRY_RUN" = 1 ] || fail "OpenCode desktop app" "could not unpack"; fi
      else fail "OpenCode desktop app" "download failed"; fi
    fi
  fi
  rm -rf "$tmp"
}

# ---------- 5. R packages ------------------------------------------------------
install_r_packages() {
  step "5/9  R packages for the course"
  have Rscript || { fail "R packages" "R is not installed"; return 1; }
  local repo="$CRAN"
  if [ "$PLATFORM" = linux ]; then repo="https://packagemanager.posit.co/cran/__linux__/$(. /etc/os-release; echo "$VERSION_CODENAME")/latest"; fi
  local lib; lib="$(Rscript -e 'cat(Sys.getenv("R_LIBS_USER"))' 2>/dev/null)"
  run mkdir -p "$lib"
  # On Linux, Posit's server sends ready-made (binary) packages only if R identifies itself this way
  local ua="options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version[['platform']], R.version[['arch']], R.version[['os']])));"
  run Rscript -e "$ua pk <- strsplit('$R_PACKAGES',' ')[[1]]; miss <- pk[!pk %in% rownames(installed.packages())]; if (length(miss)) install.packages(miss, lib='$lib', repos='$repo', Ncpus=2)"
  local missing; missing="$(Rscript -e "pk <- strsplit('$R_PACKAGES',' ')[[1]]; cat(pk[!pk %in% rownames(installed.packages())])" 2>/dev/null)"
  if [ "$DRY_RUN" = 1 ]; then :; elif [ -z "$missing" ]; then ok "R packages" "$(echo $R_PACKAGES | wc -w | tr -d ' ') packages ready"; else fail "R packages" "missing: $missing"; fi
}

fix_pandoc() { # R needs a working pandoc for reports; if the first one on PATH is broken, use Quarto's own
  [ "$DRY_RUN" = 1 ] && return 0
  have Rscript && have quarto || return 0
  local out; out="$(Rscript "$SCRIPT_DIR/lib/fix_pandoc.R" "$(dirname "$(command -v quarto)")" 2>&1)"
  echo "fix_pandoc: $out" >> "$LOG_FILE"
  case "$out" in FIXED*) ok "Pandoc for R" "a broken pandoc was in the way; R now uses Quarto's own copy" ;;
                 OK*) ok "Pandoc for R" "works" ;; *) fail "Pandoc for R" "$out" ;; esac
}

# ---------- 6. course folder + Python environment ----------------------------
setup_course_folder() {
  step "6/9  Course folder: $COURSE_DIR"
  [ -d "$KIT_DIR" ] || { fail "Course kit" "folder course-kit is missing next to this script"; return 1; }
  run mkdir -p "$COURSE_DIR"
  # copy kit files without overwriting the student's own work; course files that may be updated get a backup
  local f rel
  ( cd "$KIT_DIR" && find . -type f ) | while read -r rel; do
    rel="${rel#./}"; f="$COURSE_DIR/$rel"
    if [ ! -e "$f" ]; then run mkdir -p "$(dirname "$f")"; run cp "$KIT_DIR/$rel" "$f"
    else case "$rel" in AGENTS.md|pyproject.toml|check/*)
      cmp -s "$KIT_DIR/$rel" "$f" || { run cp "$f" "$f.bak"; run cp "$KIT_DIR/$rel" "$f"; } ;; esac
    fi
  done
  ok "Course folder" "$COURSE_DIR"
  have uv || { fail "Python environment" "uv is not installed"; return 1; }
  if retry uv sync --directory "$COURSE_DIR" --python 3.12; then ok "Python environment" "Python 3.12 + course packages"
  else fail "Python environment" "uv sync failed, see $LOG_FILE"; fi
  write_opencode_config
}

write_opencode_config() {
  # Project config in the course folder: default free model, optional providers, MCP tools OFF.
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] write $COURSE_DIR/opencode.json"; return 0; fi
  py config >> "$LOG_FILE" 2>&1 && ok "OpenCode settings" "free model as default, 6 MCP tools (off)"     || fail "OpenCode settings" "could not write opencode.json, see $LOG_FILE"
}

py() { # run the shared cross-platform helper with uv's Python
  uv run --no-project --python 3.12 --quiet python "$SCRIPT_DIR/lib/course_setup.py" "$@" --course "$COURSE_DIR"
}

# ---------- 7/8. optional keys and the real-task check ------------------------
key_wizard() { step "Optional: free AI keys"; py keys; }

run_check() {
  step "8/9  Real-task check (uses every installed tool)"
  have uv || { fail "uv" "not installed, cannot run the check"; return 1; }
  local extra=""; [ "$SKIP_AI" = 1 ] && extra="--skip-ai"
  if py check $extra --log "$LOG_FILE"; then CHECK_OK=1; else CHECK_OK=0; FAILED=$((FAILED+1)); fi
}

# ---------- AI setup helper ------------------------------------------------------
start_doctor() { # when something failed, OpenCode itself (free model) reads the log and guides the student
  step "AI setup helper"
  have opencode || { say "  The AI helper needs OpenCode, which is not installed yet. Run the setup again, or show the teacher the log."; return 0; }
  local help="$HOME/MetaScience-help" src="$LOG_FILE" prev model
  mkdir -p "$help"; cp "$SCRIPT_DIR/doctor/AGENTS.md" "$help/AGENTS.md"
  if [ "$MODE" = fix ]; then   # diagnose the newest earlier setup log
    prev="$(ls -t "${TMPDIR:-/tmp}"/metascience-setup-*.log 2>/dev/null | grep -v "$LOG_FILE" | head -1)"; [ -n "$prev" ] && src="$prev"
  fi
  cp "$src" "$help/setup-log.txt"
  [ -f "$COURSE_DIR/setup-report.txt" ] && cp "$COURSE_DIR/setup-report.txt" "$help/setup-report.txt"
  cat > "$help/SETUP-INFO.txt" <<EOF
Computer: $PLATFORM $(sw_vers -productVersion 2>/dev/null || uname -r), $ARCH, user account $(id -un)
Setup scripts folder: $SCRIPT_DIR
Course folder: $COURSE_DIR
Log being diagnosed: $src

Re-run the whole setup (safe; skips what works; can take up to 30 minutes, use a long timeout):
  bash "$SCRIPT_DIR/setup-mac.sh" --yes
Re-run only the final check (up to 10 minutes):
  bash "$SCRIPT_DIR/setup-mac.sh" --check --yes
Commands that need the computer password (sudo) cannot be typed into the AI: ask the student to run those in Terminal.
EOF
  model="$(opencode models opencode 2>/dev/null | grep -E '^opencode/(glm-5.3-flash-free|deepseek-v4.1-flash-free)$' | head -1)"
  [ -z "$model" ] && model="$(opencode models opencode 2>/dev/null | grep -E '^opencode/.*-free$' | grep -vE 'inkling|crouton' | head -1)"
  printf '{ "$schema": "https://opencode.ai/config.json", "share": "disabled", "autoupdate": false, "permission": { "edit": "allow", "webfetch": "allow", "external_directory": "allow", "bash": { "*": "allow", "rm *": "deny", "*rm -rf*": "deny", "sudo *": "deny", "chmod *": "deny", "chown *": "deny", "dd *": "deny", "mkfs*": "deny", "diskutil *": "deny", "Remove-Item*": "deny", "del *": "deny", "rd *": "deny", "rmdir *": "deny", "format *": "deny", "reg *": "deny", "Set-ExecutionPolicy*": "deny" } }%s }\n' \
    "${model:+, \"model\": \"$model\"}" > "$help/opencode.json"
  say ""
  say "  The AI helper starts now. It has read nothing on your computer except the setup log."
  say "  It runs its fix commands by itself (it is not allowed to delete files or use admin rights) and explains each one."
  say "  To stop the helper: type /exit and press Enter (or press Ctrl+C twice)."
  [ "$ASSUME_YES" = 1 ] || { printf '  Press Enter to start '; read -r _ || true; }
  opencode "$help" --prompt "Please read AGENTS.md, SETUP-INFO.txt, setup-report.txt and setup-log.txt in this folder. Then explain in simple words what went wrong in my course setup, and help me fix it step by step." </dev/tty
  say "Helper notes (if any) are in $help"
}

summary() {
  step "9/9  Summary"
  if [ "$DRY_RUN" = 1 ]; then say "${Y}Dry run finished: the lines above show what a real run would do.${N}"
  elif [ "$FAILED" = 0 ]; then say "${G}${B}All done. Everything works.${N}"
  else say "${R}${B}Something needs attention (see the FAIL lines above).${N} Run this script again first; it repairs most problems."
       say "If it still fails, show the teacher: $COURSE_DIR/setup-report.txt"; fi
  say "Full log: $LOG_FILE"
  say "Next: open OpenCode, choose the folder $COURSE_DIR, and follow the guide."
}

install_pack() { # installed copy of the pack + a daily update check for this account (no admin)
  step "7/9  Updates for this pack"
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] copy the pack to $PACK_DIR and add the daily update check"; return 0; fi
  if [ "$(cd "$SCRIPT_DIR" && pwd -P)" != "$(cd "$PACK_DIR" 2>/dev/null && pwd -P)" ]; then
    mkdir -p "$PACK_DIR" || { warn "Pack copy" "could not create $PACK_DIR; updates will not work"; return 0; }
    local i; for i in $PACK_ITEMS; do [ -e "$SCRIPT_DIR/$i" ] && cp -R "$SCRIPT_DIR/$i" "$PACK_DIR/"; done
    chmod +x "$PACK_DIR/setup-mac.sh" "$PACK_DIR/update/update.sh" 2>/dev/null
    ok "Pack copy" "$PACK_DIR"
  fi
  local upd="$PACK_DIR/update/update.sh"
  [ -f "$upd" ] || { warn "Automatic updates" "this copy of the pack has no updater"; return 0; }
  local plist="$HOME/Library/LaunchAgents/org.freeaisetup.update.plist"
  if [ "$NO_AUTO_UPDATE" = 1 ]; then
    if [ "$PLATFORM" = mac ]; then launchctl unload "$plist" >/dev/null 2>&1; rm -f "$plist"
    else crontab -l 2>/dev/null | grep -v 'freeaisetup-update' | crontab - 2>/dev/null; fi
    ok "Automatic updates" "off (update by hand: bash setup-mac.sh --update)"; return 0
  fi
  if [ "$ASSUME_YES" = 0 ] && [ -t 0 ] && [ ! -f "$plist" ]; then
    printf '\n  Keep this course pack up to date automatically (a short daily check)? Recommended. [Y/n] '; read -r a || a=""
    case "$a" in n|N|no) ok "Automatic updates" "off (update by hand: bash setup-mac.sh --update)"; return 0 ;; esac
  fi
  if [ "$PLATFORM" = mac ]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>org.freeaisetup.update</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$upd</string><string>--auto</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>30</integer></dict>
  <key>StandardOutPath</key><string>/dev/null</string><key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
PLIST
    launchctl unload "$plist" >/dev/null 2>&1; launchctl load "$plist" >/dev/null 2>&1 \
      && ok "Automatic updates" "on: a short check once a day (turn off: bash setup-mac.sh --no-auto-update)" \
      || warn "Automatic updates" "could not add the daily check; update by hand: bash setup-mac.sh --update"
  elif have crontab; then
    ( crontab -l 2>/dev/null | grep -v 'freeaisetup-update'; echo "30 12 * * * bash '$upd' --auto # freeaisetup-update" ) | crontab - \
      && ok "Automatic updates" "on: a short check once a day (turn off: bash setup-mac.sh --no-auto-update)" \
      || warn "Automatic updates" "could not add the daily check; update by hand: bash setup-mac.sh --update"
  else
    warn "Automatic updates" "no scheduler found; update by hand: bash setup-mac.sh --update"
  fi
}

# ---------- main ---------------------------------------------------------------
say "${B}MetaScience course setup $SETUP_VERSION${N}  ($PLATFORM, $ARCH)  log: $LOG_FILE"
[ "$DRY_RUN" = 1 ] && say "${Y}DRY RUN: nothing will be changed.${N}"
updater="$PACK_DIR/update/update.sh"; [ -f "$updater" ] || updater="$SCRIPT_DIR/update/update.sh"
case "$MODE" in
  update)   bash "$updater"; exit $? ;;
  rollback) bash "$updater" --rollback; exit $? ;;
  fix)   add_path "$HOME/.local/bin"; start_doctor; exit 0 ;;
  check) add_path "$HOME/.local/bin"; [ "$PLATFORM" = mac ] && for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
         run_check; summary ;;
  keys)  add_path "$HOME/.local/bin"; key_wizard; run_check; summary ;;
  full)  precheck || { summary; exit 1; }
         pkg_manager || { summary; exit 1; }
         install_tools; install_opencode; install_r_packages; fix_pandoc; setup_course_folder
         [ "$FROM_UPDATE" = 1 ] || install_pack
         if [ "$DRY_RUN" = 0 ] && [ "$FROM_UPDATE" = 0 ]; then
           if [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
             printf '\n  Add optional free AI keys now? You can also do it later with --keys. [y/N] '; read -r a || a=""
             case "$a" in y|Y|yes) key_wizard ;; esac
           fi
           run_check
         fi
         summary ;;
esac
upload_log() { # with the student's yes: send the log to the teacher's private log box (kept 180 days, write-only address)
  local plat="$PLATFORM" body id; [ -n "${CODESPACES:-}" ] && plat=codespace
  have curl || return 0
  body="$( { echo "== setup-report.txt =="; cat "$COURSE_DIR/setup-report.txt" 2>/dev/null; echo; echo "== setup log =="; cat "$LOG_FILE"; }           | sed -e "s#$HOME#~#g" )"
  local w; for w in "$(id -un)" "$(hostname -s 2>/dev/null)"; do   # short names would hit ordinary words: only 4+ letters
    [ "${#w}" -ge 4 ] && case "$w" in *[!A-Za-z0-9._-]*) ;; *) body="$(printf '%s' "$body" | sed "s#$w#<name>#g")" ;; esac
  done
  id="$(printf '%s' "$body" | curl -fsS --max-time 60 -X POST -H 'x-freeaisetup: 1' --data-binary @-         "https://freeaisetup-logs.giladfel.workers.dev/upload?platform=$plat&version=$SETUP_VERSION&result=failed" 2>/dev/null | tr -d '
 ')"
  if [ -n "$id" ]; then say "  ${G}Sent.${N} Your code is ${B}$id${N}. Tell your teacher this code."
  else say "  Could not send it (no internet?). Show your teacher this file instead: $COURSE_DIR/setup-report.txt"; fi
}
if [ "$FAILED" != 0 ] && [ "$DRY_RUN" = 0 ] && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
  printf '
  Send this setup report to your teacher, so they can see what went wrong?
  It contains no passwords and no course work; your user name is removed. [Y/n] '
  read -r a || a="n"; case "$a" in n|N|no) ;; *) upload_log ;; esac
fi
if [ "$FAILED" != 0 ] && [ "$DRY_RUN" = 0 ] && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
  printf '
  Some steps failed. Start the AI setup helper? It reads the setup log and fixes what it can, explaining each step. [Y/n] '
  read -r a || a="n"; case "$a" in n|N|no) ;; *) start_doctor ;; esac
fi
[ "$FAILED" = 0 ]
