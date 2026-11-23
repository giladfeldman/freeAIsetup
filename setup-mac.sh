#!/bin/bash
# =============================================================================
#  Meta-science course: one-step setup for macOS (and Linux, used for testing)
#  Installs: OpenCode (desktop + command line), Git, Node.js, uv + Python,
#            R + course packages, RStudio, Quarto, VS Code (+ OpenCode, Python add-ons); creates ~/MetaScience;
#            optionally the website tools (GitHub CLI, Vercel, Neon, Railway), Codex and Claude Code;
#            runs a real end-to-end check that uses every installed tool.
#  Safe to run again: it skips what is already installed and repairs the rest.
#
#  Usage:  bash setup-mac.sh            full setup (asks for your Mac password once)
#          bash setup-mac.sh --check    only run the check (doctor)
#          bash setup-mac.sh --keys     add optional free AI keys (OpenRouter, Groq, ...)
#          bash setup-mac.sh --fix      start the AI setup helper on the last setup log
#          bash setup-mac.sh --dry-run  show what would be done, change nothing
#          bash setup-mac.sh --choose   ask again which parts to install
#          bash setup-mac.sh --components=r,rstudio,quarto,python,node,vscode,web,codex,claude   (or all / none) the parts, without asking
#          bash setup-mac.sh --uninstall   remove some or all of what this setup installed
#                                          (with --yes --remove-course: the course folder too)
#          bash setup-mac.sh --help
#  Written for bash 3.2 (the macOS default): no associative arrays, no ${x,,}.
# =============================================================================
set -u

OPENCODE_VERSION="1.19.5"
# The checksum of each OpenCode $OPENCODE_VERSION download, so a changed file is never used (d-8e46a7). GitHub's own
# SHA-256 of each release file (read with the GitHub API 2026-11-17; linux-x64 and darwin-arm64 also downloaded and
# hashed here, both equal) and npm's sha512 of each npm package (the second source). A new OPENCODE_VERSION needs new
# lines here: without them the download is refused, never used unchecked (tests/opencode-sums.sh checks every line).
oc_sum() {
  case "$OPENCODE_VERSION:$1" in
    1.19.5:opencode-darwin-arm64.zip)          echo c1c9e62521192192ef4c3ed1355ada2144055bddb61682217e997b03c55203c1 ;;
    1.19.5:opencode-darwin-x64-baseline.zip)   echo e1235374cb7e712cdc15e21ba915a029a5d22312b460606d0783754739706775 ;;
    1.19.5:opencode-linux-arm64.tar.gz)        echo fae5be262d693b7c5e562856cc473e59e741772936db0c0600ac0d5ed5bd088b ;;
    1.19.5:opencode-linux-x64-baseline.tar.gz) echo 17c200fd4b2289954cc01552559f9b6d03ec157b2ddfb5eb54144f491656333d ;;
    1.19.5:opencode-desktop-mac-arm64.zip)     echo cd9710eece3ab6ee6f39d19f2af837ae6ddbc23089715c021991e791fcf7bb97 ;;
    1.19.5:opencode-desktop-mac-x64.zip)       echo 5c0ed06b1d29bd780bffdad9ff2aca2816235b5cb1d0f381dd730f1245717b79 ;;
    1.19.5:opencode-darwin-arm64.tgz)          echo sha512-0MbSbKkmwVHtgP31GJyyECe6QVy4T7W4Wp7s2TsmXHTPPyf01ne3dWSX97X9dkNK28Lc6kt+zMPQUP/9GgDLZg== ;;
    1.19.5:opencode-darwin-x64-baseline.tgz)   echo sha512-rftvAoHBWPVkvwBLr3SQWRZvcIjyMTN0SlhMzlt+lgvoQBBGNEmZQ/7sS/Ux1oHsJV/++UDuLVso4n5L95YD5Q== ;;
    1.19.5:opencode-linux-arm64.tgz)           echo sha512-u2HFRI6v1nNMVKiV34An8XrGBxJeZ+RCg2tYu3SqlGODKqKsr5RoEbaX1tnsfGb+rETh9AJVX9kS8dSZXPufsA== ;;
    1.19.5:opencode-linux-x64-baseline.tgz)    echo sha512-9kA+st3XXtCXMPx5f3Ld1u19uoHTO2u2Btt8a2cqhJ4GIqVbD1mXLevj3LHFEmtuQoFGk+UstGnl38sCqXj5sQ== ;;
  esac
}
oc_ok() { # $1 = downloaded file, $2 = its name in oc_sum: 0 only when the file has the pinned checksum
  [ "$DRY_RUN" = 1 ] && return 0   # nothing was downloaded
  [ "${MS_TEST_OC_UNCHECKED:-}" = 1 ] && { echo "OpenCode checksum not checked (test stand-in files)" >> "$LOG_FILE"; return 0; }
  local want got; want="$(oc_sum "$2")"
  [ -n "$want" ] || { echo "no checksum for $2 of OpenCode $OPENCODE_VERSION: refused" >> "$LOG_FILE"; return 1; }
  case "$want" in sha512-*) got="sha512-$(openssl dgst -sha512 -binary "$1" 2>/dev/null | openssl base64 -A 2>/dev/null)" ;;
                  *) got="$(sha256_of "$1")" ;; esac
  [ "$got" = "$want" ] && return 0
  echo "checksum of $2 is $got, not $want: refused" >> "$LOG_FILE"; rm -f "$1"; return 1
}
COURSE_DIR="${METASCIENCE_DIR:-$HOME/MetaScience}"
KEY_DIR="$HOME/.config/metascience/keys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$SCRIPT_DIR/course-kit"
export UV_HTTP_TIMEOUT=300 UV_CONCURRENT_DOWNLOADS=4 UV_HTTP_RETRIES=5   # slow or crowded Wi-Fi: wait longer, fewer at once
SETUP_VERSION="$(head -1 "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '\r ')"; SETUP_VERSION="${SETUP_VERSION:-dev}"
if [ "$(uname -s)" = Darwin ]; then PACK_DIR="$HOME/Library/Application Support/MetaScience/pack"
else PACK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/metascience/pack"; fi   # installed copy of this pack (updated by hand: --update)
PACK_ITEMS="install-windows.cmd setup-windows.ps1 setup-mac.sh VERSION lib course-kit doctor guide update"
# What this setup remembers for this account: the chosen parts and a record of what it installed (tests: MS_STATE_DIR)
STATE_DIR="${MS_STATE_DIR:-$(dirname "$PACK_DIR")}"
LOG_FILE="${TMPDIR:-/tmp}/metascience-setup-$(date +%Y%m%d-%H%M%S).log"
RUN_START=$(( $(date +%s) - 2 ))   # a folder created after this was made by this run (PATH folders, d-c97c73)
R_PACKAGES="rmarkdown knitr readr dplyr tidyr ggplot2 metafor statcheck irr here mcptools"

DRY_RUN=0; MODE="full"; ASSUME_YES=0; SKIP_AI=0; SKIP_GUI=0; NO_AUTO_UPDATE=0; FROM_UPDATE=0; CHOOSE=0; COMPONENTS=""
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
    --no-auto-update) NO_AUTO_UPDATE=1 ;;   # accepted and ignored: there is no automatic update check any more (2026-11-24)
    --from-update) FROM_UPDATE=1; ASSUME_YES=1 ;;   # internal: run by the updater after new files arrived
    --choose)  CHOOSE=1 ;;
    --components=*|--parts=*) COMPONENTS="${arg#*=}" ;;   # --parts= is the uninstaller's word for the same
    --uninstall) MODE="uninstall" ;;
    --remove-course) REMOVE_COURSE=1 ;;   # with --uninstall --yes: also delete the course folder
    --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
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
skip()  { say "  SKIP  $1  (${2:-not chosen})"; }
# What this setup itself installed, one line each: part <TAB> kind <TAB> target. The uninstall (lib/uninstall-mac.sh)
# removes only what is listed here, so software that was on this computer before the setup is never touched.
record_install() {
  [ "$DRY_RUN" = 1 ] && return 0; [ -n "${3:-}" ] || return 0
  local line f; line="$(printf '%s\t%s\t%s' "$1" "$2" "$3")"; f="$STATE_DIR/installed.tsv"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  grep -qxF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
}
recorded_paths() { # the short modes (--check, --fix, --keys) may run in a shell that has not read the start-up files
  # since the setup added a folder to PATH (Docker test 2026-11-17: Node.js and the website tools "not found" by the
  # check right after an install): every folder the setup recorded is put on PATH for this run (nothing is written)
  local part kind target
  [ -f "$STATE_DIR/installed.tsv" ] || return 0
  while IFS=$'	' read -r part kind target; do
    [ "$kind" = path ] && [ -d "$target" ] && case ":$PATH:" in *":$target:"*) ;; *) PATH="$target:$PATH" ;; esac
  done < "$STATE_DIR/installed.tsv"; export PATH; return 0
}
brew_had() { brew list "$@" >/dev/null 2>&1; }   # Homebrew already has it (maybe not on PATH): a later brew install says "ok" and installs nothing, so it is not ours to record
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
# Intel Macs: Homebrew's installer refuses them since 2026 ("only supported on Apple Silicon processors"; emulator
# test 2026-11-09, macOS 15.8.2 x86_64). There every tool comes straight from its maker's own download instead.
NO_BREW=0; [ "$PLATFORM" = mac ] && [ "$ARCH_ID" = x64 ] && NO_BREW=1
QUARTO_VERSION="1.8.25"

add_path() { # add a directory to PATH now and in the shell start-up files (once); $2 = the part it belongs to
  case ":$PATH:" in *":$1:"*) ;; *) export PATH="$1:$PATH" ;; esac
  [ "$DRY_RUN" = 1 ] && return 0
  local f; for f in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    touch "$f"; grep -qF "$1" "$f" 2>/dev/null || { printf '\nexport PATH="%s:$PATH"  # added by MetaScience setup\n' "$1" >> "$f"; record_install "${2:-core}" path "$1"; }
  done
  # made by this run: the uninstall may remove it once empty (a folder the student already had is never removed).
  # Birth time: Linux stat -c %W (0 or "-" where the file system does not keep it: then not recorded); macOS stat -f %B.
  # Linux first, and only a successful answer counts: on Linux "stat -f" means file-system information, which prints
  # several lines even when it fails (Docker test 2026-11-17).
  local born; born="$(stat -c %W "$1" 2>/dev/null)" || born="$(stat -f %B "$1" 2>/dev/null)" || born=""
  case "$born" in ''|*[!0-9]*|0) ;; *) [ "$born" -ge "$RUN_START" ] && record_install "${2:-core}" pathdir "$1" ;; esac
  return 0
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
  local plat idx page url tmp want
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
    # the package site gives each file's SHA-256 in its link (#sha256=...): a file without it, or not matching it, is not used
    case "$url" in *"#sha256="*) want="${url##*#sha256=}"; want="${want%%&*}" ;; *) echo "uv wheel without a checksum: not used" >> "$LOG_FILE"; continue ;; esac
    tmp="$(mktemp -d)"
    if curl -fsSL -m 300 -o "$tmp/uv.zip" "${url%%#*}" && { [ "$(sha256_of "$tmp/uv.zip")" = "$want" ] || { echo "uv wheel checksum does not match: not used" >> "$LOG_FILE"; false; }; } && { unzip -q -o "$tmp/uv.zip" -d "$tmp" || python3 -m zipfile -e "$tmp/uv.zip" "$tmp"; } >> "$LOG_FILE" 2>&1; then
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
      github.com) need="OpenCode, Homebrew, Python; Quarto then comes from inside RStudio, if RStudio is installed" ;; opencode.ai) need="the free AI models" ;;
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
# ---------- parts the student chooses (owner request 2026-11-12) ---------------------
# The AI assistant (OpenCode), Git and uv (which runs the setup's own Python helper) are always installed.
ALL_PARTS="r rstudio quarto python node vscode web codex claude"
MENU_PARTS="r rstudio quarto python node vscode"   # the numbered list; Enter = all of these (that this computer is offered)
# Owner request 2026-11-16: these three are each explained and asked on their own, and only a typed yes or no counts
# (Enter alone does not). Recommended answers: web yes; codex and claude no (they need a ChatGPT or Claude plan).
ASK_PARTS="web codex claude"
DEFAULT_PARTS="r rstudio quarto python node vscode web"   # unattended runs (--yes, a new Codespace)
# The parts of a setup from before the student could choose (no parts.txt). An update never adds a part the student
# did not choose: VS Code and the three extras (added 2026-11-16) come only when they run the setup themselves.
LEGACY_PARTS="r rstudio quarto python node"
# Parts this computer can get: VS Code is offered on a Mac only (a course Codespace gets its add-ons from
# .devcontainer/devcontainer.json, and Linux laptops install their own editor); --no-gui leaves out the desktop programs.
offered_parts() { local p o=""; for p in $ALL_PARTS; do
  case "$p" in vscode) [ "$PLATFORM" = mac ] && [ "$SKIP_GUI" = 0 ] || continue ;; rstudio) [ "$SKIP_GUI" = 0 ] || continue ;; esac
  o="$o $p"; done; echo "${o# }"; }
only_offered() { # $PARTS without the parts this computer is not offered
  local p k="" o; o=" $(offered_parts) "; for p in $PARTS; do case "$o" in *" $p "*) k="$k $p" ;; esac; done; PARTS="${k# }"; }
# Pinned versions (checked 2026-11-16). npm installs each part into a folder of its own; the GitHub CLI is its official
# archive, SHA-256 checked. A tool already on this computer is used as it is (never upgraded).
WEB_PKGS="vercel@65.16.0:vercel neonctl@9.5.1:neonctl @railway/cli@5.74.1:railway"
CODEX_PKG="@openai/codex@0.169.0:codex"
CLAUDE_PKG="@anthropic-ai/claude-code@2.1.325:claude"
GH_VERSION="2.104.0"
PARTS="$DEFAULT_PARTS"
has_part() { case " $PARTS " in *" $1 "*) return 0 ;; esac; return 1; }
part_name() {
  case "$1" in r) echo "R and the course R packages" ;; rstudio) echo "RStudio (an editor for R; needs R)" ;;
    quarto) echo "Quarto (turns an analysis into a report)" ;; python) echo "Python course packages" ;;
    node) echo "Node.js (a few optional AI tools need it)" ;; vscode) echo "VS Code (code editor; OpenCode, Python and R add-ons)" ;;
    web) echo "Website tools (GitHub CLI, Vercel, Neon, Railway)" ;; codex) echo "Codex (OpenAI; for a ChatGPT plan)" ;;
    claude) echo "Claude Code (Anthropic; for a paid Claude plan)" ;; esac
}
r_current() { # R 4.5 or newer is here (an older R gets a current one next to it)
  local rv; have R || return 1; rv="$(R --version 2>/dev/null | head -1 | sed -n 's/^R version \([0-9]*\.[0-9]*\).*/\1/p')"
  [ -n "$rv" ] && [ "$(printf '%s\n4.5\n' "$rv" | sort -t. -k1,1n -k2,2n | head -1)" = 4.5 ]
}
# GB a part still needs here (0 = already on this computer). Sizes measured on one Windows 11 computer on 2026-11-12;
# not yet measured on a Mac, where they are assumed to be similar.
part_gb() {
  case "$1" in
    r) if r_current; then echo 0.2; else echo 0.4; fi ;;
    rstudio) if [ -d /Applications/RStudio.app ] || [ -d "$HOME/Applications/RStudio.app" ]; then echo 0; else echo 1.9; fi ;;
    quarto) if have quarto; then echo 0; else echo 0.5; fi ;;
    python) if [ -d "$COURSE_DIR/.venv" ]; then echo 0; else echo 0.5; fi ;;
    node) if have node; then echo 0; else echo 0.2; fi ;;
    # VS Code 0.8 GB + its add-ons 0.17 GB (measured on Windows 11, 2026-11-16); with VS Code here, its add-ons may be missing
    vscode) if vscode_here; then echo 0.2; else echo 1.0; fi ;;
    # npm installs measured on Windows 2026-11-16 (462, 492, 356 MB); not yet measured on a Mac
    web) if have gh && have vercel && have neonctl && have railway; then echo 0; else echo 0.5; fi ;;
    codex) if have codex; then echo 0; else echo 0.5; fi ;;
    claude) if have claude; then echo 0; else echo 0.4; fi ;;
  esac
}
estimate_gb() { # disk space this run will use: only the chosen parts that are not on this computer yet
  local gb=0 p
  have opencode || gb="$gb+0.6"
  have uv || gb="$gb+0.2"
  if [ "$PLATFORM" = mac ]; then
    # Apple's command line tools (they bring git) and Homebrew: rough sizes, not measured here
    xcode-select -p >/dev/null 2>&1 || gb="$gb+2.0"
    [ "$NO_BREW" = 1 ] || have brew || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ] || gb="$gb+0.5"
  else have git || gb="$gb+0.4"; fi
  for p in $PARTS; do gb="$gb+$(part_gb "$p")"; done
  awk "BEGIN { printf \"%.1f\", $gb }"
}
PARSED=""; BAD_PARTS=""
parse_parts() { # $1 = text -> PARSED (valid parts, in order) and BAD_PARTS (unknown words)
  local w want="" p; BAD_PARTS=""
  for w in $(printf '%s' "$1" | tr ',;' '  ' | tr 'A-Z' 'a-z'); do
    case "$w" in all) want="$want $ALL_PARTS" ;; none) ;; r|rstudio|quarto|python|node|vscode|web|codex|claude) want="$want $w" ;; *) BAD_PARTS="$BAD_PARTS $w" ;; esac
  done
  case " $want " in *" rstudio "*) case " $want " in *" r "*) ;; *) want="$want r" ;; esac ;; esac   # RStudio needs R
  case " $want " in *" web "*|*" codex "*|*" claude "*) want="$want node" ;; esac   # these come with npm, part of Node.js
  PARSED=""; for p in $ALL_PARTS; do case " $want " in *" $p "*) PARSED="$PARSED $p" ;; esac; done
  PARSED="${PARSED# }"; BAD_PARTS="${BAD_PARTS# }"
}
save_parts() { [ "$DRY_RUN" = 1 ] && return 0; mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "${PARTS:-none}" > "$STATE_DIR/parts.txt"; }
save_asked() { [ "$DRY_RUN" = 1 ] && return 0; mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$ASK_PARTS" > "$STATE_DIR/asked.txt"; }
ask_yes_no() { # $1 = question; only a typed yes or no counts, Enter alone asks again (owner request 2026-11-16)
  local a try
  for try in 1 2 3; do
    printf '%s Type yes or no: ' "$1"; read -r a || a=""; a="$(printf '%s' "$a" | tr 'A-Z' 'a-z' | tr -d ' ')"
    case "$a" in y|yes) return 0 ;; n|no) return 1 ;; esac
    say "  Please type yes or no (pressing Enter alone does not choose)."
  done
  say "  No answer, so it is not installed. To choose again later: bash setup-mac.sh --choose"; return 1
}
EXTRA=""
ask_extras() { # the three optional extras, each explained and answered with a typed yes or no -> EXTRA
  EXTRA=""
  say ""; say "--- Optional: publishing your tools as websites  (recommended: yes; about 0.5 GB) ---"
  say "  Installs four free command-line tools that the AI assistant can use for you:"
  say "    GitHub CLI (gh) - keeps your code on GitHub     Vercel - puts your tool online as a website"
  say "    Neon - a database for it                        Railway - a small server, if your tool needs one"
  say "  Each needs its own free account, which you create only when you want to publish something."
  say "  Their free plans need no payment card: never enter a card on any of these sites."
  ask_yes_no "  Install the website tools?" && EXTRA="$EXTRA web"
  say ""; say "--- Optional: Codex, the AI assistant from OpenAI  (recommended: no, unless you have ChatGPT; about 0.5 GB) ---"
  say "  Codex signs in with your ChatGPT account and uses that plan's AI, which is stronger than the free models."
  say "  It is meant for a paid ChatGPT plan (Plus or higher). If you have one, you can ALSO use it inside OpenCode"
  say "  without Codex: in OpenCode type /connect, choose OpenAI, then \"ChatGPT Plus/Pro\"."
  say "  The course itself needs only the free AI. Without a ChatGPT plan, answer no."
  ask_yes_no "  Install Codex?" && EXTRA="$EXTRA codex"
  say ""; say "--- Optional: Claude Code, the AI assistant from Anthropic  (recommended: no, unless you pay for Claude; about 0.4 GB) ---"
  say "  Claude Code signs in with a paid Claude plan (Pro, Max or Ultra); it does not work with the free Claude plan."
  say "  It is the way Anthropic allows a Claude plan to be used for this kind of work: a Claude plan cannot be"
  say "  connected to OpenCode. The course itself needs only the free AI. Without a paid Claude plan, answer no."
  ask_yes_no "  Install Claude Code?" && EXTRA="$EXTRA claude"
  return 0
}
without() { # $1 minus the words in $2
  local w out=""; for w in $1; do case " $2 " in *" $w "*) ;; *) out="$out $w" ;; esac; done; printf '%s' "${out# }"
}
load_parts() { # the parts chosen last time; everything when nothing was chosen (older setups installed all)
  if [ -f "$STATE_DIR/parts.txt" ]; then parse_parts "$(cat "$STATE_DIR/parts.txt")"; PARTS="$PARSED"; else PARTS="$LEGACY_PARTS"; fi
  # Until the student has answered the extras questions, a saved list never brings Codex or Claude Code (their answer
  # must be a typed yes): "all" saved by an older setup meant the parts of that time. The website tools (default yes)
  # stay when an unattended run saved them.
  if [ ! -f "$STATE_DIR/asked.txt" ]; then PARTS="$(without "$PARTS" "codex claude")"; fi
  only_offered; return 0
}
choose_parts() {
  local offer; offer="$(offered_parts)"
  if [ -n "$COMPONENTS" ]; then
    parse_parts "$COMPONENTS"
    [ -n "$BAD_PARTS" ] && { say "Unknown part: $BAD_PARTS. Use any of: r, rstudio, quarto, python, node, vscode, web, codex, claude, or all, or none."; FINISHED=1; exit 2; }
    PARTS="$PARSED"; save_parts; save_asked
  elif [ -f "$STATE_DIR/parts.txt" ] && [ "$CHOOSE" = 0 ]; then
    load_parts
    # chosen with a setup from before 2026-11-16: the three newer extras are asked once (never by an update)
    if [ ! -f "$STATE_DIR/asked.txt" ] && [ "$ASSUME_YES" = 0 ] && [ "$FROM_UPDATE" = 0 ] && [ "$DRY_RUN" = 0 ] && [ -t 0 ]; then
      say ""; say "This version of the setup offers three more optional parts."
      ask_extras; parse_parts "$(without "$PARTS" "$ASK_PARTS") $EXTRA"; PARTS="$PARSED"; only_offered; save_parts; save_asked   # the answers decide these three
    fi
  elif [ "$FROM_UPDATE" = 1 ]; then PARTS="$LEGACY_PARTS"   # an update never adds a part (see LEGACY_PARTS)
  elif [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then PARTS="$DEFAULT_PARTS"; only_offered; save_parts   # saved, so a later check and update know them
  else
    say ""; say "What should the setup install? The AI assistant (OpenCode), Git and uv (for Python) are always installed."
    local i=0 p g a n try picked menu="" cnt
    for p in $offer; do case " $MENU_PARTS " in *" $p "*) menu="$menu $p" ;; esac; done
    menu="${menu# }"; cnt="$(echo $menu | wc -w | tr -d ' ')"; picked="$menu"
    for p in $menu; do i=$((i+1)); g="$(part_gb "$p")"
      if [ "$g" = 0 ]; then g="already on this computer"; else g="about $g GB"; fi
      say "$(printf '  %d. %-44s %s' "$i" "$(part_name "$p")" "$g")"
    done
    for try in 1 2 3; do
      printf 'Press Enter to install all of them (recommended), or type the numbers you want, for example 1 3 (0 = none): '
      read -r a || a=""; a="$(printf '%s' "$a" | tr ',;' '  ')"
      if [ -z "${a// /}" ]; then picked="$menu"; break; fi
      picked=""; for n in $a; do case "$n" in *[!0-9]*) picked=bad; break ;; esac; [ "$n" -le "$cnt" ] || { picked=bad; break; }; done
      [ "$picked" = bad ] && { picked="$menu"; say "  Please type only numbers from the list (0 to $cnt)."; continue; }
      for n in $a; do [ "$n" = 0 ] || picked="$picked $(echo $menu | cut -d' ' -f"$n")"; done
      case " $picked " in *" rstudio "*) case " $picked " in *" r "*) ;; *) say "  RStudio needs R, so R is installed too." ;; esac ;; esac
      break
    done
    ask_extras
    if [ -n "$EXTRA" ]; then case " $picked " in *" node "*) ;; *) say "  Node.js is installed too: the tools you chose need it." ;; esac; fi
    parse_parts "$picked $EXTRA"; PARTS="$PARSED"
    save_parts; save_asked
  fi
  only_offered
  local names="" p; for p in $PARTS; do names="$names, $(part_name "$p")"; done
  say "  Installing: the AI assistant$names  (to change this: bash setup-mac.sh --choose)"
}

precheck() {
  step "1/9  Checking this computer"
  # test hook: a stop in step 1 must still reach the offer to send the report (tests/exit-paths.sh)
  [ "${MS_TEST_FAIL_AT:-}" = precheck ] && { fail "Test stop" "MS_TEST_FAIL_AT=precheck"; return 1; }
  ok "System" "$PLATFORM $(sw_vers -productVersion 2>/dev/null || uname -r), $ARCH"
  if [ "$PLATFORM" = mac ]; then
    local major; major="$(sw_vers -productVersion | cut -d. -f1)"
    if [ "$major" -lt 12 ]; then fail "macOS version" "macOS 12 or newer is needed; you have $(sw_vers -productVersion)"; return 1; fi
  fi
  local free_gb need_gb min; free_gb="$(df -Pk "$HOME" | awk 'NR==2 {print int($4/1048576)}')"
  # The chosen parts that are not here yet, plus 2 GB for the downloads while installing; 3 GB more leaves room for
  # course work (before 2026-11-12 a flat 8 GB). A GitHub Codespace shows only ~7 GB free while it is still being
  # built (20 GB a few minutes later; 2026-11-09), so there 4 GB is enough.
  need_gb="$(estimate_gb)"; min="$(awk "BEGIN { m = $need_gb + 2; printf \"%d\", (m == int(m)) ? m : int(m) + 1 }")"
  [ -n "${CODESPACES:-}" ] && min=4
  if [ "${free_gb:-0}" -lt "$min" ]; then
    fail "Free disk space" "${free_gb} GB free; this setup needs about $need_gb GB, plus 2 GB while it installs. Free up space (or install fewer parts: bash setup-mac.sh --choose), then run it again"; return 1
  elif [ -z "${CODESPACES:-}" ] && [ "${free_gb:-0}" -lt $((min + 3)) ]; then warn "Free disk space" "${free_gb} GB free; the setup will use about $need_gb GB, which leaves little room for your course work"
  elif [ "$need_gb" = 0.0 ]; then ok "Free disk space" "${free_gb} GB free; what you chose is already on this computer"
  else ok "Free disk space" "${free_gb} GB free; this setup will use about $need_gb GB"; fi
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
  if [ "$NO_BREW" = 1 ]; then ok "Homebrew" "not used on Intel Macs: each tool is downloaded from its maker"; return 0; fi
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
    have brew && { record_install core homebrew "$(brew --prefix)"; ok "Homebrew" "installed"; } || { fail "Homebrew" "installation failed, see $LOG_FILE"; return 1; }
  else
    retry $SUDO apt-get update -y && ok "apt" "package lists updated" || { fail "apt" "apt-get update failed"; return 1; }
  fi
}

# ---------- 3. core tools ----------------------------------------------------
gatekeeper_note() { # $1 = a downloaded app or installer package, $2 = execute (app) | install (package)
  # macOS's own check of who made a download (Gatekeeper, what a double-click runs) is skipped by a command-line
  # install. The setup asks for its verdict and RECORDS it in the log; it does not yet refuse a download on it, until a
  # real Mac run confirms each real download passes (d-4e90ed; Windows refuses an unsigned download already).
  local out rc; out="$(spctl --assess --type "$2" -v "$1" 2>&1)"; rc=$?
  echo "Gatekeeper check ($2, not enforced yet) of $1: exit $rc: $out" | tr '\n' ' ' >> "$LOG_FILE"; echo >> "$LOG_FILE"
  return 0
}
mac_pkg() { # $1 = official installer package address: download it and install it for this Mac (needs the password)
  local d f rc; d="$(mktemp -d)"; f="$d/$(basename "$1")"
  retry curl -fL -m 900 -A "MetaScience-setup" -o "$f" "$1" && gatekeeper_note "$f" install && run $SUDO installer -pkg "$f" -target /
  rc=$?; rm -rf "$d"; return $rc
}
cran_r() { # $1 = the old R version, if any. Installs the newest R from CRAN for this Mac's chip, keeping an old R.
  # The R installer deletes every R it holds an install receipt for ("R Installation and Administration", section
  # "Multiple versions"), so the old R's receipt is forgotten first: its files stay in R.framework/Versions/<x.y>.
  # The new R becomes the one R, RStudio and the terminal start; the old one can still be chosen (e.g. with RSwitch).
  [ "$DRY_RUN" = 1 ] && { say "  [dry-run] install the current R from CRAN"; CRAN_R="current (dry-run)"; return 0; }
  local dir arch nv p
  if [ "$(uname -m)" = arm64 ]; then arch=arm64; dir=big-sur-arm64
    [ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" -ge 14 ] 2>/dev/null && dir=sonoma-arm64   # R 4.6+ for Apple chips needs macOS 14
  else arch=x86_64; dir=big-sur-x86_64; fi
  local rb="$CRAN/bin/macosx/$dir/base"
  nv="$(curl -fsSL -m 60 "$rb/" 2>>"$LOG_FILE" | grep -oE "R-[0-9]+\.[0-9]+\.[0-9]+-$arch\.pkg" | sed "s/^R-//; s/-$arch\.pkg\$//" | sort -u -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [ -n "$nv" ] || return 1
  if [ -n "$1" ]; then
    for p in $(pkgutil --pkgs 2>/dev/null | grep -E '^org\.[Rr]-project\.([A-Za-z0-9_]+\.)?R\.fw\.pkg$'); do run $SUDO pkgutil --forget "$p" || return 1; done
  fi
  mac_pkg "$rb/R-$nv-$arch.pkg" || return 1
  add_path /Library/Frameworks/R.framework/Resources/bin
  CRAN_R="$nv"
}
node_direct() { # $1 = temp folder. Node.js: the official current 22.x build, unpacked into your own folder (no password)
  # Used on Intel Macs, and on Linux, where the system's own Node.js (18 on Ubuntu 24.04) is too old for the website
  # tools, Codex and Claude Code (2026-11-16).
  local t="$1" pat
  case "$PLATFORM-$ARCH_ID" in mac-*) pat="darwin-$ARCH_ID" ;; linux-x64) pat="linux-x64" ;; linux-arm64) pat="linux-arm64" ;; esac
  if ! has_part node; then skip "node"
  elif have node; then ok "node" "already installed"
  elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install Node.js"
  else
    local nb="https://nodejs.org/dist/latest-v22.x" sums nf
    sums="$(curl -fsSL -m 60 "$nb/SHASUMS256.txt" 2>>"$LOG_FILE")"
    nf="$(printf '%s\n' "$sums" | awk -v p="$pat" '$2 ~ ("-" p "\\.tar\\.gz$") {print $2; exit}')"
    if [ -n "$nf" ] && retry curl -fL -m 900 -o "$t/$nf" "$nb/$nf" \
       && [ "$(sha256_of "$t/$nf")" = "$(printf '%s\n' "$sums" | awk -v f="$nf" '$2 == f {print $1}')" ]; then
      mkdir -p "$HOME/.local/share" && tar -xzf "$t/$nf" -C "$HOME/.local/share" \
        && ln -sfn "$HOME/.local/share/${nf%.tar.gz}" "$HOME/.local/share/node" && add_path "$HOME/.local/share/node/bin" node
      have node && { record_install node dir "$HOME/.local/share/${nf%.tar.gz}"; record_install node file "$HOME/.local/share/node"; ok "node" "installed ($(node --version))"; } || fail "node" "could not unpack $nf"
    else fail "node" "download from nodejs.org failed or did not match its checksum"; fi
  fi
}
install_tools_direct() { # Intel Macs (no Homebrew): the same tools, from the makers' own download pages
  local t; t="$(mktemp -d)"
  # Git comes with Apple's command line tools. /usr/bin/git exists without them (it only opens Apple's install
  # window), so check for the tools themselves; softwareupdate installs them without that window.
  if xcode-select -p >/dev/null 2>&1 || { have git && [ "$(command -v git)" != /usr/bin/git ]; }; then ok "git" "already installed"
  elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install Apple command line tools (git)"
  else
    say "  Installing Apple's command line tools (they include git; 10-40 minutes, the screen may look still)..."
    local flag=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
    touch "$flag"
    label="$(softwareupdate -l 2>>"$LOG_FILE" | sed -n 's/^[[:space:]]*\* Label: \(Command Line Tools.*\)$/\1/p' | tail -1)"
    if [ -n "$label" ] && run $SUDO softwareupdate -i "$label" && xcode-select -p >/dev/null 2>&1; then record_install core clt "$(xcode-select -p)"; ok "git" "installed (Apple command line tools)"
    else fail "git" "Apple command line tools did not install: run  xcode-select --install  then run the setup again"; fi
    rm -f "$flag"
  fi
  node_direct "$t"
  if have uv; then ok "uv" "already installed"
  elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install uv"
  else curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >> "$LOG_FILE" 2>&1; add_path "$HOME/.local/bin"
    if have uv; then record_uv; ok "uv" "installed"; elif uv_from_pypi; then record_uv; ok "uv" "installed (direct download)"; else fail "uv" "installer failed"; fi; fi
  # R: the newest Intel build on CRAN (same "older than 4.5" rule as with Homebrew; the old R stays)
  local rv=""; have R && rv="$(R --version 2>/dev/null | head -1 | sed -n 's/^R version \([0-9]*\.[0-9]*\).*/\1/p')"
  if ! has_part r; then skip "R"
  elif [ -n "$rv" ] && [ "$(printf '%s\n4.5\n' "$rv" | sort -t. -k1,1n -k2,2n | head -1)" = 4.5 ]; then ok "R" "already installed (R $rv)"
  elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install R"
  else
    [ -n "$rv" ] && say "  Your R ($rv) is too old for the course packages. Installing the current R next to it (your old R stays)."
    if cran_r "$rv"; then
      # an old R shares R.framework with the new one: only an R the setup brought alone may be removed later
      [ -z "$rv" ] && { record_install r pkgdir /Library/Frameworks/R.framework; record_install r pkgdir /Applications/R.app; }
      ok "R" "installed (R $CRAN_R$([ -n "$rv" ] && echo "; old R $rv kept"))"
    else fail "R" "download or install of R from CRAN failed"; fi
  fi
  if ! has_part quarto; then skip "Quarto"
  elif have quarto; then ok "Quarto" "already installed"
  elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install Quarto"
  elif mac_pkg "https://github.com/quarto-dev/quarto-cli/releases/download/v$QUARTO_VERSION/quarto-$QUARTO_VERSION-macos.pkg"; then
    record_install quarto pkgdir /Applications/quarto; add_path /Applications/quarto/bin; ok "Quarto" "installed"
  else quarto_later "download or install failed"; fi
  if [ "$SKIP_GUI" = 0 ] && ! has_part rstudio; then skip "RStudio"
  elif [ "$SKIP_GUI" = 0 ]; then
    if [ -d "/Applications/RStudio.app" ] || [ -d "$HOME/Applications/RStudio.app" ]; then ok "RStudio" "already installed"
    elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install RStudio"
    elif retry curl -fL -m 900 -o "$t/RStudio.dmg" "https://rstudio.org/download/latest/stable/desktop/mac/RStudio-latest.dmg" \
         && run hdiutil attach -nobrowse -readonly -mountpoint "$t/mnt" "$t/RStudio.dmg"; then
      gatekeeper_note "$t/mnt/RStudio.app" execute
      run $SUDO ditto "$t/mnt/RStudio.app" /Applications/RStudio.app
      run hdiutil detach "$t/mnt" -quiet
      [ -d /Applications/RStudio.app ] && { record_install rstudio pkgdir /Applications/RStudio.app; ok "RStudio" "installed"; } || fail "RStudio" "could not copy RStudio into Applications"
    else fail "RStudio" "download from Posit failed"; fi
  fi
  rm -rf "$t"
}
# Quarto without GitHub (d-e4a52e): Quarto's own downloads (and Homebrew's) come from GitHub, which some networks
# block (common in mainland China). RStudio, from Posit's own server, carries a whole Quarto inside it; when the
# Quarto install fails, the setup uses that one after the RStudio step (only a PATH entry is recorded: RStudio's
# files stay RStudio's).
quarto_later() { QUARTO_LATER="$1"; say "  Quarto: $1; the Quarto inside RStudio is tried after the RStudio step"; }
quarto_in_rstudio() { # the folder holding the quarto inside an installed RStudio, if any
  local a f; for a in /Applications/RStudio.app "$HOME/Applications/RStudio.app"; do
    [ -d "$a/Contents" ] || continue
    f="$(find "$a/Contents" -type f -path '*/quarto/bin/quarto' 2>/dev/null | head -1)"
    [ -n "$f" ] && [ -x "$f" ] && { dirname "$f"; return 0; }
  done; return 1; }
quarto_after_rstudio() {
  [ -n "${QUARTO_LATER:-}" ] || return 0
  local q; q="$(quarto_in_rstudio)"
  if [ -n "$q" ]; then add_path "$q"; ok "Quarto" "the Quarto inside RStudio"
  else fail "Quarto" "$QUARTO_LATER (and no Quarto inside RStudio)"; fi
  QUARTO_LATER=""; }
record_uv() { # uv installed by this setup: its files, and the Python and downloads it keeps, may go with the uninstall
  local f; for f in uv uvx; do [ -e "$HOME/.local/bin/$f" ] && record_install core file "$HOME/.local/bin/$f"; done
  record_install core uvdata "Python and downloads kept by uv"
}
# ---------- VS Code and its add-ons (owner request 2026-11-16; a Mac only) -------------------------------------------
# The add-ons the course uses. sst-dev.opencode is OpenCode's own (github.com/anomalyco/opencode, sdks/vscode): it opens
# a terminal in VS Code and starts the OpenCode this setup installed, with the same free models and settings
# (its button at the top right of an open file, or Cmd+Esc). ms-python.python is Microsoft's, and brings Pylance, the Python debugger and Python Environments with it.
# reditorsupport.r (the R add-on, brings R Syntax) only with the R part: it needs R, and the languageserver R package,
# which the R package step then adds (without it the add-on keeps asking to install it).
# Each add-on's version is the one this release was tested with: an older one is updated (owner, 2026-11-16: "only
# installs/updates them if not installed/outdated"). VS Code itself is never upgraded.
CODE_EXTENSIONS="sst-dev.opencode ms-python.python reditorsupport.r"
code_min() { case "$1" in sst-dev.opencode) echo 1.0.0 ;; ms-python.python) echo 2026.10.0 ;; reditorsupport.r) echo 3.4.0 ;; esac; }
code_label() { case "$1" in sst-dev.opencode) echo OpenCode ;; ms-python.python) echo Python ;; reditorsupport.r) echo R ;; *) echo "$1" ;; esac; }
code_wanted() { local e; for e in $CODE_EXTENSIONS; do { [ "$e" != reditorsupport.r ] || has_part r; } && printf '%s ' "$e"; done; return 0; }
CODE_ISO=()   # tests: MS_TEST_CODE_DIR gives VS Code a scratch add-on and settings folder, so a test never touches a real one
[ -n "${MS_TEST_CODE_DIR:-}" ] && CODE_ISO=(--extensions-dir "$MS_TEST_CODE_DIR/ext" --user-data-dir "$MS_TEST_CODE_DIR/data")
code_app() { local a; for a in "/Applications/Visual Studio Code.app" "$HOME/Applications/Visual Studio Code.app"; do
  [ -d "$a" ] && { echo "$a"; return 0; }; done; return 1; }
code_cli() { # VS Code's code command: on PATH, or inside the app. A "code" on PATH can be another editor's copy or a
  # script, so each candidate's --help must start with VS Code's own name ("Visual Studio Code 1.139.1", from its
  # product.json nameLong); an editor built from VS Code prints its own name there (d-a09ebb).
  local c v; for c in "$(command -v code 2>/dev/null)" "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
                      "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    v="$("$c" --help 2>/dev/null | head -1)"
    case "$v" in "Visual Studio Code "[0-9]*.[0-9]*|"Visual Studio Code - Insiders "[0-9]*.[0-9]*) echo "$c"; return 0 ;; esac
    echo "not VS Code's code command (its --help starts '$v', not 'Visual Studio Code'): $c" >> "$LOG_FILE"
  done; return 1; }
vscode_here() { # VS Code itself is on this Mac: its app, or a code command that is VS Code's. Another editor built from
  # VS Code (Cursor and others) can own the "code" command on PATH; it is not VS Code (production 2026-11-19).
  code_app >/dev/null || code_cli >/dev/null; }
code_exts() { # the add-ons VS Code has, one "id@version" per line, lower case; fails when VS Code did not answer
  local out; out="$("$1" ${CODE_ISO[@]+"${CODE_ISO[@]}"} --list-extensions --show-versions 2>/dev/null)" || { echo "code --list-extensions failed" >> "$LOG_FILE"; return 1; }
  printf '%s\n' "$out" | tr 'A-Z' 'a-z' | tr -d '\r' | grep -E '^[a-z0-9-]+\.[a-z0-9-]+@[^ ]+$'; return 0; }
ver_of() { printf '%s\n' "$2" | awk -F@ -v id="$1" '$1 == id { print $2; exit }'; }   # ver_of <id> <list>
older_than() { # true only when both read as versions and $1 is lower; unreadable = leave it
  awk -v a="$1" -v b="$2" 'BEGIN { sub(/[-+].*$/, "", a); if (a !~ /^[0-9]+(\.[0-9]+)*$/ || b !~ /^[0-9]+(\.[0-9]+)*$/) exit 1
    na = split(a, x, "."); nb = split(b, y, "."); n = (na > nb ? na : nb)
    for (i = 1; i <= n; i++) { p = (i <= na ? x[i] + 0 : 0); q = (i <= nb ? y[i] + 0 : 0); if (p < q) exit 0; if (p > q) exit 1 }
    exit 1 }'; }
recorded_exts() { awk -F'\t' '$1 == "vscode" && $2 == "vsext" { print tolower($3) }' "$STATE_DIR/installed.tsv" 2>/dev/null; return 0; }
install_vscode() {
  if ! has_part vscode; then [ "$PLATFORM" = mac ] && [ "$SKIP_GUI" = 0 ] && skip "VS Code"; return 0; fi
  # VS Code keeps its add-ons and settings in these folders; when the setup brings the first VS Code, they are its too
  local data="" d fresh=0 t
  for d in "$HOME/.vscode" "$HOME/Library/Application Support/Code"; do [ -e "$d" ] || data="$data$d"$'\n'; done
  if vscode_here; then ok "VS Code" "already installed"
  elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install VS Code"
  elif [ "$NO_BREW" = 0 ]; then
    local vhad=0; brew_had --cask visual-studio-code && vhad=1
    if retry brew install --cask visual-studio-code; then [ "$vhad" = 0 ] && { record_install vscode cask visual-studio-code; fresh=1; }; ok "VS Code" "installed"
    else fail "VS Code" "brew install --cask visual-studio-code failed"; return 0; fi
  else # Intel Macs: Microsoft's own download (about 400 MB)
    t="$(mktemp -d)"; say "  Downloading VS Code from Microsoft (about 400 MB; on slow Wi-Fi 10 minutes or more)..."
    if retry curl -fL -m 1800 -o "$t/vscode.zip" "https://update.code.visualstudio.com/latest/darwin/stable" \
       && run ditto -x -k "$t/vscode.zip" "$t/x" && [ -d "$t/x/Visual Studio Code.app" ] \
       && gatekeeper_note "$t/x/Visual Studio Code.app" execute \
       && run $SUDO ditto "$t/x/Visual Studio Code.app" "/Applications/Visual Studio Code.app" && [ -d "/Applications/Visual Studio Code.app" ]; then
      record_install vscode pkgdir "/Applications/Visual Studio Code.app"; fresh=1; ok "VS Code" "installed (direct download from Microsoft)"
    else fail "VS Code" "download from Microsoft or unpacking failed; see $LOG_FILE"; rm -rf "$t"; return 0; fi
    rm -rf "$t"
  fi
  [ "$fresh" = 1 ] && printf '%s' "$data" | while IFS= read -r d; do [ -n "$d" ] && record_install vscode dir "$d"; done
  # the code command: Homebrew links it; the direct download keeps it inside the app. Another editor's "code" already on
  # PATH (Cursor and others) is left first on purpose: the student's terminal keeps opening the editor they chose, and the
  # setup and check reach VS Code through the app itself (code_cli, course_setup.py vscode_cli)
  local app; have code || { app="$(code_app)" && [ -x "$app/Contents/Resources/app/bin/code" ] && add_path "$app/Contents/Resources/app/bin"; }
  install_code_extensions
}
install_code_extensions() {
  # Checks each add-on the course uses: a missing one is added, one older than the version this release was tested
  # with is updated (--force fetches the newest that this VS Code can run), one that is fine is left alone. Only the
  # add-ons this setup added are recorded (with the ones they brought), so the uninstall removes those and never the
  # student's own, even one the setup updated.
  local want names="" e v code have now ours k added="" updated="" missing="" old="" what=""
  want="$(code_wanted)"; for e in $want; do names="${names:+$names, }$(code_label "$e")"; done
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] add the VS Code add-ons that are missing or too old: $want"; return 0; fi
  code="$(code_cli)" || { fail "VS Code add-ons" "VS Code's code command was not found or did not answer; see $LOG_FILE"; return 0; }
  have="$(code_exts "$code")" || { fail "VS Code add-ons" "VS Code could not list its add-ons; see $LOG_FILE"; return 0; }
  ours=" $(recorded_exts | tr '\n' ' ') "
  for e in $want; do
    v="$(ver_of "$e" "$have")"
    if [ -n "$v" ] && ! older_than "$v" "$(code_min "$e")"; then continue; fi
    if [ -n "$v" ]; then retry "$code" ${CODE_ISO[@]+"${CODE_ISO[@]}"} --install-extension "$e" --force
    else retry "$code" ${CODE_ISO[@]+"${CODE_ISO[@]}"} --install-extension "$e"; fi
    now="$(code_exts "$code")" || now=""
    [ -n "$(ver_of "$e" "$now")" ] || continue   # reported below
    if [ -n "$v" ]; then echo "VS Code add-on $e updated from $v to $(ver_of "$e" "$now")" >> "$LOG_FILE"; updated="${updated:+$updated, }$(code_label "$e")"
    else added="${added:+$added, }$(code_label "$e")"; fi
    # what this step brought (a missing add-on's companions, or new ones an update of an add-on this setup added
    # brings) is recorded; companions an update of the student's own add-on brings belong with that add-on
    if [ -z "$v" ] || case "$ours" in *" $e "*) true ;; *) false ;; esac; then
      for k in $(printf '%s\n' "$now" | cut -d@ -f1); do
        [ -n "$(ver_of "$k" "$have")" ] && continue
        case "$ours" in *" $k "*) ;; *) record_install vscode vsext "$k"; ours="$ours$k " ;; esac
      done
    fi
    have="$now"
  done
  for e in $want; do
    v="$(ver_of "$e" "$have")"
    if [ -z "$v" ]; then missing="$missing $e"; elif older_than "$v" "$(code_min "$e")"; then old="${old:+$old, }$e $v (tested: $(code_min "$e"))"; fi
  done
  [ -n "$missing" ] && fail "VS Code add-ons" "could not add${missing} (the add-on store may be blocked on this network); see $LOG_FILE"
  [ -n "$old" ] && warn "VS Code add-ons" "$old - this VS Code is too old for the newer one: in VS Code, Code > Check for Updates, then run the setup again"
  if [ -z "$missing" ] && [ -z "$old" ]; then
    [ -n "$added" ] && what="added: $added"; [ -n "$updated" ] && what="${what:+$what; }updated: $updated"
    if [ -n "$what" ]; then ok "VS Code add-ons" "$names ready ($what)"; else ok "VS Code add-ons" "$names already there and up to date"; fi
  fi
  return 0
}
install_tools() {
  step "3/9  Core tools: Git, Node.js, uv (Python), R, Quarto, RStudio, VS Code"
  [ "${MS_TEST_CRASH:-}" = tools ] && { echo "test crash in step 3 (MS_TEST_CRASH)" >> "$LOG_FILE"; exit 3; }   # test hook: a crash mid-run
  [ "${MS_TEST_CRASH:-}" = unbound ] && echo "$MS_TEST_UNSET_VARIABLE"   # test hook: a bash error (set -u) mid-run
  say "  Rule: this setup never upgrades or removes software that is already on this computer"
  say "  (one exception: a VS Code add-on the course uses that is older than the course needs is updated)."
  if [ "$PLATFORM" = mac ]; then
    # tools another account installed for the whole Mac: make them usable from this account
    local d; for d in /Library/Frameworks/R.framework/Resources/bin /Applications/quarto/bin /opt/homebrew/bin /usr/local/bin; do
      [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) { [ -x "$d/Rscript" ] || [ -x "$d/quarto" ] || [ -x "$d/git" ]; } && add_path "$d" ;; esac
    done
    if [ "$NO_BREW" = 1 ]; then install_tools_direct; quarto_after_rstudio; add_path "$HOME/.local/bin"; install_vscode; return 0; fi
    local f fp; for f in git node uv; do
      fp=core; [ "$f" = node ] && fp=node
      if [ "$f" = node ] && ! has_part node; then skip "node"
      elif have "$f"; then ok "$f" "already installed"; elif had=0; brew_had --formula "$f" && had=1; retry brew install "$f"; then [ "$had" = 0 ] && { record_install "$fp" brew "$f"; [ "$f" = uv ] && record_uv; }; ok "$f" "installed"
      elif [ "$f" = uv ] && uv_from_pypi; then record_uv; ok "uv" "installed (direct download)"; else fail "$f" "brew install $f failed"; fi
    done
    # R older than 4.5: the course packages no longer come ready-built for it, so all of them fail (class 2026-11-09:
    # a MacBook with R 4.0.0 from 2020). Next to an old R the current R comes from CRAN directly (cran_r keeps the old
    # one), never through Homebrew: its upgrade replaces an R it installed, and its install runs the same R installer,
    # which deletes an old R it has a receipt for (d-8f5f6e).
    local rv=""; have R && rv="$(R --version 2>/dev/null | head -1 | sed -n 's/^R version \([0-9]*\.[0-9]*\).*/\1/p')"
    if ! has_part r; then skip "R"
    elif [ -n "$rv" ] && [ "$(printf '%s\n4.5\n' "$rv" | sort -t. -k1,1n -k2,2n | head -1)" = 4.5 ]; then ok "R" "already installed (R $rv)"
    else
      if [ -n "$rv" ]; then
        say "  Your R ($rv) is too old for the course packages. Installing the current R next to it (your old R stays; macOS may ask for your password)."
        if cran_r "$rv"; then ok "R" "installed (R $CRAN_R; old R $rv kept)"; else fail "R" "download or install of R from CRAN failed"; fi
      else
        local rhad=0; brew_had --cask r && rhad=1
        retry brew install --cask r && { [ "$rhad" = 0 ] && record_install r cask r; ok "R" "installed"; } || fail "R" "brew install --cask r failed"
      fi
    fi
    if ! has_part quarto; then skip "Quarto"
    elif have quarto; then ok "Quarto" "already installed"
    else local qhad=0; brew_had --cask quarto && qhad=1
      retry brew install --cask quarto && { [ "$qhad" = 0 ] && record_install quarto cask quarto; ok "Quarto" "installed"; } || quarto_later "brew install --cask quarto failed"; fi
    if [ "$SKIP_GUI" = 0 ]; then
      if ! has_part rstudio; then skip "RStudio"
      elif [ -d "/Applications/RStudio.app" ]; then ok "RStudio" "already installed"
      else local shad=0; brew_had --cask rstudio && shad=1
        retry brew install --cask rstudio && { [ "$shad" = 0 ] && record_install rstudio cask rstudio; ok "RStudio" "installed"; } || fail "RStudio" "brew install --cask rstudio failed"; fi
    fi
    quarto_after_rstudio
    install_vscode
  else
    # only what is missing (a course Codespace already brings current Node.js and R; never replace them)
    local want="curl ca-certificates unzip python3" added="" a
    have git || added="$added git"
    has_part r && ! have R && added="$added r-base r-base-dev"
    want="$want$added"
    retry $SUDO apt-get install -y --no-install-recommends $want \
      && { for a in $added; do case "$a" in git) record_install core apt git ;; *) record_install r apt "$a" ;; esac; done; true; } \
      && ok "Git, R" "ready (git $(git --version 2>/dev/null | cut -d' ' -f3), R $(R --version 2>/dev/null | head -1 | cut -d' ' -f3))" \
      || fail "apt packages" "see $LOG_FILE"
    # Node.js from nodejs.org, not apt: Ubuntu's own is 18, too old for the website tools, Codex and Claude Code
    local nt; nt="$(mktemp -d)"; node_direct "$nt"; rm -rf "$nt"
    if have uv; then ok "uv" "already installed"
    elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install uv"
    else curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh >> "$LOG_FILE" 2>&1; add_path "$HOME/.local/bin"
      if have uv; then record_uv; ok "uv" "installed"; elif uv_from_pypi; then record_uv; ok "uv" "installed (direct download)"; else fail "uv" "installer failed"; fi; fi
    if ! has_part quarto; then skip "Quarto"
    elif have quarto; then ok "Quarto" "already installed"
    elif [ "$DRY_RUN" = 1 ]; then say "  [dry-run] install Quarto"
    else
      local qv="$QUARTO_VERSION" qa; [ "$ARCH_ID" = arm64 ] && qa=arm64 || qa=amd64
      retry curl -fsSL -o /tmp/quarto.deb "https://github.com/quarto-dev/quarto-cli/releases/download/v$qv/quarto-$qv-linux-$qa.deb" \
        && run $SUDO apt-get install -y /tmp/quarto.deb && { record_install quarto apt quarto; ok "Quarto" "installed"; } || fail "Quarto" "download or install failed"
    fi
  fi
  add_path "$HOME/.local/bin"
}

# ---------- 4. OpenCode -------------------------------------------------------
install_opencode() {
  step "4/9  OpenCode $OPENCODE_VERSION (AI assistant)"
  local base="https://github.com/anomalyco/opencode/releases/download/v$OPENCODE_VERSION" bindir="$HOME/.local/bin" tmp
  tmp="$(mktemp -d)"
  if ! have opencode && [ ! -e "$bindir/opencode" ] && [ "$DRY_RUN" = 0 ]; then
    # a first OpenCode on this account: the uninstall may remove it and the settings and chats it keeps
    record_install core file "$bindir/opencode"
    local d; for d in .local/share/opencode .config/opencode .cache/opencode .local/state/opencode; do
      [ -e "$HOME/$d" ] || record_install core dir "$HOME/$d"; done
  fi
  if have opencode && [ "$(opencode --version 2>/dev/null)" = "$OPENCODE_VERSION" ]; then ok "OpenCode command line" "version $OPENCODE_VERSION already installed"
  else
    local asset
    if [ "$PLATFORM" = mac ]; then [ "$ARCH_ID" = arm64 ] && asset="opencode-darwin-arm64.zip" || asset="opencode-darwin-x64-baseline.zip"
    else [ "$ARCH_ID" = arm64 ] && asset="opencode-linux-arm64.tar.gz" || asset="opencode-linux-x64-baseline.tar.gz"; fi
    local got=0 pkg reg bin
    case "$BLOCKED" in *" github.com "*) ;; *)
      if retry curl -fsSL -o "$tmp/$asset" "$base/$asset" && oc_ok "$tmp/$asset" "$asset"; then
        case "$asset" in *.zip) run unzip -o -q "$tmp/$asset" -d "$tmp/x" ;; *) run mkdir -p "$tmp/x"; run tar -xzf "$tmp/$asset" -C "$tmp/x" ;; esac
        got=1
      fi ;;
    esac
    if [ "$got" = 0 ] && [ "$DRY_RUN" = 0 ]; then
      # the same program, published as an npm package: npm's own site, then a mirror reachable from China
      pkg="opencode-$( [ "$PLATFORM" = mac ] && echo darwin || echo linux )-$( [ "$ARCH_ID" = arm64 ] && echo arm64 || echo x64-baseline )"
      for reg in https://registry.npmjs.org https://registry.npmmirror.com; do
        if curl -fsSL -m 300 -o "$tmp/oc.tgz" "$reg/$pkg/-/$pkg-$OPENCODE_VERSION.tgz" 2>>"$LOG_FILE" && oc_ok "$tmp/oc.tgz" "$pkg.tgz"; then
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
    else fail "OpenCode command line" "download failed (or its checksum did not match) from GitHub and from npm; see $LOG_FILE"; fi
  fi
  if [ "$PLATFORM" = mac ] && [ "$SKIP_GUI" = 0 ]; then
    if [ -d "/Applications/OpenCode.app" ] || [ -d "$HOME/Applications/OpenCode.app" ]; then ok "OpenCode desktop app" "already installed"
    else
      local app="opencode-desktop-mac-$ARCH_ID.zip"
      case "$BLOCKED" in *" github.com "*) warn "OpenCode desktop app" "GitHub is blocked here, so only the command-line OpenCode is installed (type opencode in Terminal)"; rm -rf "$tmp"; return 0 ;; esac
      if retry curl -fsSL -o "$tmp/$app" "$base/$app" && oc_ok "$tmp/$app" "$app"; then
        run ditto -x -k "$tmp/$app" "$tmp/app"
        local found; found="$(find "$tmp/app" -maxdepth 2 -name '*.app' | head -1)"
        if [ -n "$found" ] && run cp -R "$found" /Applications/; then record_install core dir "/Applications/$(basename "$found")"; ok "OpenCode desktop app" "in Applications"
        elif [ -n "$found" ] && run mkdir -p "$HOME/Applications" && run cp -R "$found" "$HOME/Applications/"; then record_install core dir "$HOME/Applications/$(basename "$found")"; ok "OpenCode desktop app" "in your personal Applications folder"
        else [ "$DRY_RUN" = 1 ] || fail "OpenCode desktop app" "could not unpack"; fi
      else fail "OpenCode desktop app" "download failed or its checksum did not match; see $LOG_FILE"; fi
    fi
  fi
  rm -rf "$tmp"
}

# ---------- 4b. optional: website tools, Codex, Claude Code (owner request 2026-11-16) -----------------
# Everything goes into folders of this account (no password): npm installs each part into
# ~/.local/share/metascience-<part> (commands in its bin folder), so the uninstall can remove exactly that folder.
gh_sha256() {
  case "$1" in
    linux_amd64.tar.gz) echo 98cb101ad87dbbd3f6b2f2bfcbd43197ccd07643140121d8a9cfaa91eadbc24e ;;
    linux_arm64.tar.gz) echo cb34cefc6f4e77b90731374a2b737516bb8f3033c6ca46aa949e5344f68069e3 ;;
    macOS_amd64.zip)    echo a8c2a708dbae89dc7c05ba7b0beafc95bd8d09ab4a3505467b77d32ebf364dc6 ;;
    macOS_arm64.zip)    echo 23b12706219b9892e44236f988444a24adcf29284e16b35e03ba5b863fb6eb8e ;;
  esac
}
sha256_of() { if have shasum; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
node_at_least() { # $1 = minimum major.minor, e.g. 20.19: Node.js here is at least that version
  local v; have node || return 1; v="$(node --version 2>/dev/null | sed -n 's/^v\([0-9]*\.[0-9]*\).*/\1/p')"
  [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$v" "$1" | sort -t. -k1,1n -k2,2n | head -1)" = "$1" ]
}
install_gh() {
  if have gh; then ok "GitHub CLI" "already installed"; return 0; fi
  local prefix="$HOME/.local/share/metascience-web" os ext asset tmp
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] download GitHub CLI $GH_VERSION into $prefix/bin"; return 0; fi
  case "$BLOCKED" in *" github.com "*) warn "GitHub CLI" "GitHub is blocked on this network; run the setup again on another network to add it"; return 0 ;; esac
  if [ "$PLATFORM" = mac ]; then os=macOS; ext=zip; else os=linux; ext=tar.gz; fi
  asset="${os}_$( [ "$ARCH_ID" = arm64 ] && echo arm64 || echo amd64 ).$ext"
  tmp="$(mktemp -d)"
  if ! retry curl -fsSL -o "$tmp/gh.$ext" "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_$asset"; then
    fail "GitHub CLI" "download failed; see $LOG_FILE"; rm -rf "$tmp"; return 1; fi
  if [ "$(sha256_of "$tmp/gh.$ext")" != "$(gh_sha256 "$asset")" ]; then
    fail "GitHub CLI" "the download does not match its published checksum, so it was not installed"; rm -rf "$tmp"; return 1; fi
  mkdir -p "$tmp/x"
  if [ "$ext" = zip ]; then unzip -o -q "$tmp/gh.zip" -d "$tmp/x"; else tar -xzf "$tmp/gh.tar.gz" -C "$tmp/x"; fi
  local bin; bin="$(find "$tmp/x" -type f -path '*/bin/gh' | head -1)"
  [ -d "$prefix" ] || record_install web dir "$prefix"
  [ -e "$HOME/.config/gh" ] || record_install web dir "$HOME/.config/gh"   # its sign-in
  if [ -n "$bin" ] && mkdir -p "$prefix/bin" && cp "$bin" "$prefix/bin/gh" && chmod +x "$prefix/bin/gh"; then
    add_path "$prefix/bin" web; ok "GitHub CLI" "installed $GH_VERSION"
  else fail "GitHub CLI" "could not unpack it; see $LOG_FILE"; fi
  rm -rf "$tmp"
}
npm_tools() { # $1 = part, $2 = minimum Node.js (major.minor), $3 = name for messages, rest = package@version:command ...
  local part="$1" min="$2" label="$3" prefix="$HOME/.local/share/metascience-$1" todo="" item reg cache code=1
  shift 3
  for item in "$@"; do
    if have "${item##*:}"; then ok "${item##*:}" "already installed"; else todo="$todo $item"; fi
  done
  [ -n "$todo" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] npm install --global --prefix $prefix$(for item in $todo; do printf ' %s' "${item%:*}"; done)"; return 0; fi
  if ! node_at_least "$min"; then
    fail "$label" "$(have node && echo "Node.js $(node --version) is too old" || echo "Node.js is missing"); it needs Node.js $min or newer (this setup never upgrades software that is already here)"
    return 1
  fi
  [ -d "$prefix" ] || record_install "$part" dir "$prefix"
  cache="$(mktemp -d)"   # a throw-away download cache: no copy is left behind
  local pkg cmd
  for item in $todo; do   # one at a time: one tool that cannot be installed never takes the others with it
    pkg="${item%:*}"; cmd="${item##*:}"; code=1
    case "$pkg" in @railway/*) case "$BLOCKED" in *" github.com "*)   # its installer downloads from GitHub
      warn "$cmd" "its installer needs GitHub, which is blocked on this network; run the setup again on another network to add it"; continue ;; esac ;; esac
    # the mirror is for networks that block npm's site; it can lag behind (a missing version), so npm's site gets a second try
    for reg in https://registry.npmjs.org https://registry.npmmirror.com https://registry.npmjs.org; do
      echo "\$ npm install --global --prefix $prefix --registry $reg $pkg" >> "$LOG_FILE"
      npm install --global --prefix "$prefix" --cache "$cache" --registry "$reg" --no-fund --no-audit --loglevel=error "$pkg" >> "$LOG_FILE" 2>&1 && { code=0; break; }
    done
    [ "$code" = 0 ] && add_path "$prefix/bin" "$part"
    if [ "$code" = 0 ] && have "$cmd"; then ok "$cmd" "installed"
    elif [ "$code" = 0 ]; then fail "$cmd" "npm finished but '$cmd' was not found; see $LOG_FILE"
    else fail "$cmd" "npm could not install it; see $LOG_FILE"; fi
  done
  rm -rf "$cache"
}
install_extras() {
  step "4b/9  Optional: website tools, Codex, Claude Code"
  local p; for p in $ASK_PARTS; do has_part "$p" || skip "$(part_name "$p")"; done
  if has_part web; then
    # their sign-ins (paths read from each tool's own code, 2026-11-16), recorded only for a tool this setup installs
    # and only when the folder is not there yet, so a student's existing sign-in is never removed
    local d vd vc; if [ "$PLATFORM" = mac ]; then vd="$HOME/Library/Application Support/com.vercel.cli"; vc="$HOME/Library/Caches/com.vercel.cli"
    else vd="$HOME/.local/share/com.vercel.cli"; vc="$HOME/.cache/com.vercel.cli"; fi
    if ! have vercel; then for d in "$vd" "$vc"; do [ -e "$d" ] || record_install web dir "$d"; done; fi
    if ! have neonctl; then d="${XDG_CONFIG_HOME:-$HOME/.config}/neon"; [ -e "$d" ] || record_install web dir "$d"; fi
    if ! have railway; then [ -e "$HOME/.railway" ] || record_install web dir "$HOME/.railway"; fi
    install_gh
    # shellcheck disable=SC2086
    npm_tools web 20.19 "Website tools" $WEB_PKGS
  fi
  if has_part codex; then
    have codex || [ -e "$HOME/.codex" ] || record_install codex dir "$HOME/.codex"   # its sign-in and settings
    npm_tools codex 20.19 "Codex" "$CODEX_PKG"
  fi
  if has_part claude; then
    if ! have claude; then   # its sign-in and settings, when this is the first Claude Code on this account
      [ -e "$HOME/.claude" ] || record_install claude dir "$HOME/.claude"
      [ -e "$HOME/.claude.json" ] || record_install claude file "$HOME/.claude.json"
    fi
    npm_tools claude 22.0 "Claude Code" "$CLAUDE_PKG"
  fi
  has_part web && say "  Website tools: nothing to sign in to now. When you want to publish, follow Part 6 of the student guide."
  has_part codex && say "  Codex: type codex in a terminal, choose \"Sign in with ChatGPT\", and sign in in the browser."
  has_part claude && say "  Claude Code: type claude in a terminal and sign in with your Claude account in the browser."
  return 0
}

# ---------- 5. R packages ------------------------------------------------------
install_r_packages() {
  step "5/9  R packages for the course"
  has_part r || { skip "R packages"; return 0; }
  have Rscript || { fail "R packages" "R is not installed"; return 1; }
  # with VS Code, its R add-on needs the languageserver R package (else it keeps asking to install it)
  local pkgs="$R_PACKAGES"; has_part vscode && pkgs="$R_PACKAGES languageserver"
  local repo="$CRAN"
  if [ "$PLATFORM" = linux ]; then repo="https://packagemanager.posit.co/cran/__linux__/$(. /etc/os-release; echo "$VERSION_CODENAME")/latest"; fi
  local lib; lib="$(Rscript -e 'cat(Sys.getenv("R_LIBS_USER"))' 2>/dev/null)"
  run mkdir -p "$lib"
  local before pk; before=" $(Rscript -e "cat(rownames(installed.packages(lib.loc='$lib')))" 2>/dev/null) "
  # On Linux, Posit's server sends ready-made (binary) packages only if R identifies itself this way
  local ua="options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version[['platform']], R.version[['arch']], R.version[['os']])));"
  run Rscript -e "$ua pk <- strsplit('$pkgs',' ')[[1]]; miss <- pk[!vapply(pk, function(p) suppressWarnings(suppressMessages(requireNamespace(p, quietly=TRUE))), NA)]; if (length(miss)) install.packages(miss, lib='$lib', repos='$repo', Ncpus=2)"
  for pk in $(Rscript -e "cat(rownames(installed.packages(lib.loc='$lib')))" 2>/dev/null); do
    case "$before" in *" $pk "*) ;; *) record_install r rpkg "$pk" ;; esac
  done
  # a package counts as ready only when it loads (its folder can be there while a package it needs is missing)
  local missing; missing="$(Rscript -e "pk <- strsplit('$pkgs',' ')[[1]]; miss <- pk[!vapply(pk, function(p) suppressWarnings(suppressMessages(requireNamespace(p, quietly=TRUE))), NA)]; cat(miss)" 2>/dev/null)"
  if [ "$DRY_RUN" = 1 ]; then :; elif [ -z "$missing" ]; then ok "R packages" "$(echo $pkgs | wc -w | tr -d ' ') packages ready"; else fail "R packages" "missing or not loading: $missing"; fi
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
  [ -d "$COURSE_DIR" ] || record_install course dir "$COURSE_DIR"
  run mkdir -p "$COURSE_DIR"
  # copy kit files without overwriting the student's own work; course files that may be updated get a backup
  local f rel
  ( cd "$KIT_DIR" && find . -type f ) | while read -r rel; do
    rel="${rel#./}"; f="$COURSE_DIR/$rel"
    if [ ! -e "$f" ]; then run mkdir -p "$(dirname "$f")"; run cp "$KIT_DIR/$rel" "$f"
    else case "$rel" in AGENTS.md|pyproject.toml|check/*|.opencode/plugins/*)   # course files the pack keeps current
      cmp -s "$KIT_DIR/$rel" "$f" || { run cp "$f" "$f.bak"; run cp "$KIT_DIR/$rel" "$f"; } ;; esac
    fi
  done
  ok "Course folder" "$COURSE_DIR"
  have uv || { fail "Python environment" "uv is not installed"; return 1; }
  if ! has_part python; then skip "Python course packages"
  elif retry uv sync --directory "$COURSE_DIR" --python 3.12; then ok "Python environment" "Python 3.12 + course packages"
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
  local extra="" parts; [ "$SKIP_AI" = 1 ] && extra="--skip-ai"
  parts="$(printf '%s' "${PARTS:-none}" | tr ' ' ',')"
  if py check $extra --log "$LOG_FILE" --parts "$parts"; then CHECK_OK=1; else CHECK_OK=0; FAILED=$((FAILED+1)); fi
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

# The file to show the teacher: the report of the check (step 8), or the log when setup stopped before the check
report_file() { if [ -f "$COURSE_DIR/setup-report.txt" ]; then echo "$COURSE_DIR/setup-report.txt"; else echo "$LOG_FILE"; fi; }
summary() {
  step "9/9  Summary"
  if [ "$DRY_RUN" = 1 ]; then say "${Y}Dry run finished: the lines above show what a real run would do.${N}"
  elif [ "$FAILED" = 0 ]; then say "${G}${B}All done. Everything works.${N}"
  else say "${R}${B}Something needs attention (see the FAIL lines above).${N} Run this script again first; it repairs most problems."
       say "If it still fails, show the teacher: $(report_file)"; fi
  say "Full log: $LOG_FILE"
  say "Next: open OpenCode, choose the folder $COURSE_DIR, and follow the guide."
  has_part vscode && say "  In VS Code: File > Open Folder > $COURSE_DIR, open a file, then click the OpenCode button at its top right."
  return 0
}

remove_background_jobs() { # owner directive 2026-11-24: nothing of this setup runs on its own
  # Setups before 2026-11-24 added a daily update check: a LaunchAgent on a Mac (macOS lists it under Login Items /
  # "Background Items Added"), a crontab line on Linux. Every run of this setup (any mode) and every uninstall removes it.
  [ -n "${MS_TEST_NO_JOBS:-}" ] && { echo "background jobs: not touched (MS_TEST_NO_JOBS)" >> "$LOG_FILE"; return 0; }
  if [ "$PLATFORM" = mac ]; then
    local label=org.freeaisetup.update plist="$HOME/Library/LaunchAgents/org.freeaisetup.update.plist" loaded=0
    launchctl list "$label" >/dev/null 2>&1 && loaded=1
    [ -f "$plist" ] || [ "$loaded" = 1 ] || return 0
    if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] remove the old daily update check ($label)"; return 0; fi
    rm -f "$plist"
    # Started by that job (an old updater running this setup hidden): unloading it now would stop this very run. With
    # its file gone it does not come back after the next login, and the new update.sh removes it if it fires before.
    if [ "$loaded" = 1 ] && [ "$IN_OLD_JOB" = 0 ]; then launchctl remove "$label" >/dev/null 2>&1; fi
    if [ ! -f "$plist" ]; then ok "Old daily update check" "removed (nothing of this setup runs on its own any more)"
    else warn "Old daily update check" "could not remove $plist; delete that file by hand"; fi
  elif have crontab; then
    local cur
    cur="$(crontab -l 2>/dev/null)" || return 0          # no crontab (or it cannot be read): nothing to change
    printf '%s\n' "$cur" | grep -q 'freeaisetup-update' || return 0
    if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] remove the old daily update check (crontab line freeaisetup-update)"; return 0; fi
    printf '%s\n' "$cur" | grep -v 'freeaisetup-update' | crontab - 2>/dev/null
    if crontab -l 2>/dev/null | grep -q 'freeaisetup-update'; then warn "Old daily update check" "could not remove it; run crontab -e and delete the freeaisetup-update line"
    else ok "Old daily update check" "removed (nothing of this setup runs on its own any more)"; fi
  fi
  return 0
}

install_pack() { # installed copy of the pack, so the student can update it by hand later (nothing is scheduled)
  step "7/9  Updates for this pack"
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] copy the pack to $PACK_DIR"; return 0; fi
  if [ "$(cd "$SCRIPT_DIR" && pwd -P)" != "$(cd "$PACK_DIR" 2>/dev/null && pwd -P)" ]; then
    mkdir -p "$PACK_DIR" || { warn "Pack copy" "could not create $PACK_DIR; updates will not work"; return 0; }
    local i; for i in $PACK_ITEMS; do [ -e "$SCRIPT_DIR/$i" ] && cp -R "$SCRIPT_DIR/$i" "$PACK_DIR/"; done
    chmod +x "$PACK_DIR/setup-mac.sh" "$PACK_DIR/update/update.sh" 2>/dev/null
    record_install core pack "$PACK_DIR"; ok "Pack copy" "$PACK_DIR"
  fi
  [ -f "$PACK_DIR/update/update.sh" ] || { warn "Updates" "this copy of the pack has no updater"; return 0; }
  ok "Updates" "by hand only, nothing runs in the background: bash \"$PACK_DIR/setup-mac.sh\" --update"
}

# ---------- reporting to the teacher's log box ------------------------------------
# One address for both messages; tests point it at a local copy (MS_LOG_URL) and mark themselves (MS_LOG_ENV=local).
LOG_BOX="${MS_LOG_URL:-https://freeaisetup-logs.giladfel.workers.dev}"; LOG_BOX="${LOG_BOX%/}"
log_box_post() { # $1 = path?query; body on stdin
  if [ -n "${MS_LOG_ENV:-}" ]; then curl -fsS --max-time 60 -X POST -H 'x-freeaisetup: 1' -H "x-freeaisetup-env: $MS_LOG_ENV" --data-binary @- "$LOG_BOX/$1"
  else curl -fsS --max-time 60 -X POST -H 'x-freeaisetup: 1' --data-binary @- "$LOG_BOX/$1"; fi
}
log_platform() { if [ -n "${CODESPACES:-}" ]; then echo codespace; else echo "$PLATFORM"; fi; }
upload_log() { # with the student's yes: send the log to the teacher's private log box (kept 180 days, write-only address)
  local body id
  have curl || return 0
  body="$( { echo "== setup-report.txt =="; cat "$COURSE_DIR/setup-report.txt" 2>/dev/null; echo; echo "== setup log =="; cat "$LOG_FILE"; } | sed -e "s#$HOME#~#g" )"
  local w; for w in "$(id -un)" "$(hostname -s 2>/dev/null)"; do   # short names would hit ordinary words: only 4+ letters
    [ "${#w}" -ge 4 ] && case "$w" in *[!A-Za-z0-9._-]*) ;; *) body="$(printf '%s' "$body" | sed "s#$w#<name>#g")" ;; esac
  done
  id="$(printf '%s' "$body" | log_box_post "upload?platform=$(log_platform)&version=$SETUP_VERSION&result=failed" 2>/dev/null | tr -d '\r\n ')"
  if [ -n "$id" ]; then say "  ${G}Sent.${N} Your code is ${B}$id${N}. Tell your teacher this code."
  else say "  Could not send it (no internet?). Show your teacher this file instead: $(report_file)"; fi
}
json_s() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'; }   # a JSON string's inside
scrub() { # the same removal of names as the report upload (upload_log)
  local t="$1" w tl='~'; t="${t//"$HOME"/$tl}"
  for w in "$(id -un)" "$(hostname -s 2>/dev/null)"; do
    # quoted: the name is matched as plain text, so any name works, also one with letters like ü (upload_log's sed
    # skips those: d-0a67b9)
    [ "${#w}" -ge 4 ] && t="${t//"$w"/<name>}"
  done; printf '%s' "$t"
}
send_result() { # $1 = stage (done | precheck | install | crash | stopped)
  # Owner request 2026-11-23/24: one anonymous message at the end of every full setup run, success or not, for the
  # weekly digest: platform, OS version, processor type, pack version, the parts chosen, how long it took, and the
  # name and short reason of each step that failed or warned (user name, computer name and home folder removed). No
  # name, no e-mail, no files, no log, no ID that links two runs. MS_NO_COUNT=1 switches it off (README, Privacy).
  [ -n "${MS_NO_COUNT:-}" ] || [ "$DRY_RUN" = 1 ] || [ "${RESULT_SENT:-0}" = 1 ] && return 0
  RESULT_SENT=1; have curl || return 0
  local os outcome issues="" n=0 st it de where line ct
  if [ "$PLATFORM" = mac ]; then os="macOS $(sw_vers -productVersion 2>/dev/null)"
  else os="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")"; fi
  add_issue() { [ "$n" -lt 60 ] || return 0; issues="${issues:+$issues,}[\"$1\",\"$(json_s "$2")\",\"$(json_s "$(scrub "$3" | cut -c1-200)")\",\"$4\"]"; n=$((n+1)); }
  while IFS='|' read -r st it de; do case "$st" in FAIL|WARN) add_issue "$st" "$it" "$de" setup ;; esac; done <<EOF
$RESULTS
EOF
  ct="${LOG_FILE%.log}.check.tsv"   # the check's rows (lib/course_setup.py)
  if [ -f "$ct" ]; then
    while IFS=$'\t' read -r st it de; do case "$st" in FAIL|WARN) add_issue "$st" "$it" "$de" check ;; esac; done < "$ct"
    rm -f "$ct"
  fi
  if [ "$1" = stopped ]; then outcome=stopped; elif [ "$FAILED" = 0 ]; then outcome=ok; else outcome=failed; fi
  line="{\"v\":1,\"platform\":\"$(log_platform)\",\"version\":\"$(json_s "$SETUP_VERSION")\",\"os\":\"$(json_s "$os")\",\"arch\":\"$ARCH_ID\",\"outcome\":\"$outcome\",\"stage\":\"$1\",\"mode\":\"${RUN_MODE:-first}\",\"parts\":\"$(printf '%s' "${PARTS:-}" | tr ' ' ',')\",\"minutes\":$(( ($(date +%s) - RUN_START) / 60 )),\"issues\":[${issues}]}"
  if printf '%s' "$line" | log_box_post "result" >/dev/null 2>&1; then echo "result sent (anonymous): $line" >> "$LOG_FILE"
  else echo "result not sent" >> "$LOG_FILE"; fi
}
offer_help() { # every failing run ends here, however it stopped: a failed check, a stop in steps 1-2, or an unexpected error
  [ "$FAILED" != 0 ] && [ "$DRY_RUN" = 0 ] && [ "$ASSUME_YES" = 0 ] && [ -t 0 ] || return 0
  printf '\n  Send this setup report to your teacher, so they can see what went wrong?\n  It contains no passwords and no course work; your user name is removed. [Y/n] '
  read -r a || a="n"; case "$a" in n|N|no) ;; *) upload_log ;; esac
  printf '\n  Some steps failed. Start the AI setup helper? It reads the setup log and fixes what it can, explaining each step. [Y/n] '
  read -r a || a="n"; case "$a" in [nN]*) ;; *) start_doctor ;; esac
}
# An unexpected stop (a bash error, a command that kills the script) still ends with the offer: the EXIT trap runs
# whatever ends the script. Ctrl+C is the student's own choice and only says so.
FINISHED=0; INTERRUPTED=0
on_exit() {
  local rc=$?
  trap - EXIT
  [ "$FINISHED" = 1 ] && exit "$rc"
  if [ "$INTERRUPTED" = 1 ]; then exit "$rc"; fi
  if [ "$rc" != 0 ]; then fail "Setup stopped" "an unexpected error (exit code $rc); the log has the details"; summary
    [ "$MODE" = full ] && send_result crash; offer_help; fi
  exit "$rc"
}
trap on_exit EXIT
trap 'INTERRUPTED=1; echo; echo "  Setup stopped (Ctrl+C). Run it again any time."; exit 130' INT

# ---------- main ---------------------------------------------------------------
say "${B}MetaScience course setup $SETUP_VERSION${N}  ($PLATFORM, $ARCH)  log: $LOG_FILE"
[ "$DRY_RUN" = 1 ] && say "${Y}DRY RUN: nothing will be changed.${N}"
# An updater from before 2026-11-24, started by the old daily check, has just copied this version in and runs it
# unseen (--from-update without MS_UPDATE_BY_HAND, which the new updater and --update set). That last background run
# only removes the daily check; the tools come up to date the next time the student runs the setup or --update
# (applied-version.txt says this version is not applied yet). A Codespace's own start-up update is not such a run.
IN_OLD_JOB=0; [ "$FROM_UPDATE" = 1 ] && [ -z "${MS_UPDATE_BY_HAND:-}" ] && [ -z "${CODESPACES:-}" ] && IN_OLD_JOB=1
remove_background_jobs   # first, whatever this run was started for
if [ "$IN_OLD_JOB" = 1 ]; then
  FINISHED=1; say "Pack $SETUP_VERSION copied in by an older updater. Nothing more runs now; to finish the update, run: bash setup-mac.sh --update"; exit 0
fi
RUN_MODE=first; [ -f "$STATE_DIR/installed.tsv" ] && RUN_MODE=rerun; [ "$FROM_UPDATE" = 1 ] && RUN_MODE=update
updater="$PACK_DIR/update/update.sh"; [ -f "$updater" ] || updater="$SCRIPT_DIR/update/update.sh"
[ "${MS_TEST_CRASH:-}" = main ] && { echo "test crash (MS_TEST_CRASH)" >> "$LOG_FILE"; exit 3; }   # test hook: a crash still reaches the offer
case "$MODE" in
  update)   FINISHED=1; MS_UPDATE_BY_HAND=1 bash "$updater"; exit $? ;;   # the setup it starts is the student's own run
  rollback) FINISHED=1; MS_UPDATE_BY_HAND=1 bash "$updater" --rollback; exit $? ;;
  uninstall) FINISHED=1; un=(); [ -n "$COMPONENTS" ] && un+=("--parts=$COMPONENTS"); [ "$ASSUME_YES" = 1 ] && un+=(--yes)
             [ "$DRY_RUN" = 1 ] && un+=(--dry-run); [ "${REMOVE_COURSE:-0}" = 1 ] && un+=(--remove-course); bash "$SCRIPT_DIR/lib/uninstall-mac.sh" ${un[@]+"${un[@]}"}; exit $? ;;
  fix)   FINISHED=1; add_path "$HOME/.local/bin"; recorded_paths; start_doctor; exit 0 ;;
  check) add_path "$HOME/.local/bin"; recorded_paths; [ "$PLATFORM" = mac ] && for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
         load_parts; run_check; summary ;;
  keys)  add_path "$HOME/.local/bin"; recorded_paths; load_parts; key_wizard; run_check
         # a Codespace runs OpenCode as a web server that read its settings at start: restart it so it sees the new key
         if [ -n "${CODESPACES:-}" ] && [ -f "$SCRIPT_DIR/.devcontainer/start.sh" ]; then
           pkill -f "^opencode web" 2>/dev/null; sleep 1; bash "$SCRIPT_DIR/.devcontainer/start.sh"
           ok "OpenCode restarted" "reload the OpenCode tab to use the new key"
         fi
         summary ;;
  full)  # a stop in step 1 or 2 skips the installs but still ends with the summary and the offer to send the report
         choose_parts
         if precheck && pkg_manager; then
           install_tools; install_opencode; install_extras; install_r_packages; fix_pandoc; setup_course_folder
           [ "$FROM_UPDATE" = 1 ] || install_pack
           if [ "$DRY_RUN" = 0 ] && [ "$FROM_UPDATE" = 0 ]; then
             if [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
               printf '\n  Connect a free OpenRouter account as a backup for the AI (about 2 minutes, opens your browser)? You can also do it later with --keys. [y/N] '; read -r a || a=""
               case "$a" in y|Y|yes) key_wizard ;; esac
             fi
             run_check
           fi
           # the pack's tools match this version (update.sh reads it)
           [ "$DRY_RUN" = 0 ] && [ "$FAILED" = 0 ] && { mkdir -p "$STATE_DIR" && printf '%s\n' "$SETUP_VERSION" > "$STATE_DIR/applied-version.txt"; } 2>/dev/null
           RUN_STAGE=done
         else RUN_STAGE=precheck; fi
         summary; send_result "$RUN_STAGE" ;;
esac
offer_help
FINISHED=1
[ "$FAILED" = 0 ]
