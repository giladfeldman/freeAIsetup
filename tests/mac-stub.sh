#!/bin/bash
# Exercises the macOS branch of setup-mac.sh on Linux by replacing macOS-only commands with
# small fakes that record how they were called. Proves the Mac control flow (Homebrew, casks,
# desktop app unpacking, PATH edits) without a Mac. It does NOT prove the real Mac installers work.
set -u
export MS_LOG_ENV=local   # test runs never count as real installs or send real alerts
STUB=/tmp/stubs; mkdir -p "$STUB"; CALLS=/tmp/calls.log; : > "$CALLS"
mk() { printf '#!/bin/bash\necho "%s $*" >> %s\n%s\n' "$1" "$CALLS" "${2:-exit 0}" > "$STUB/$1"; chmod +x "$STUB/$1"; }
mk uname 'case "$1" in -s) echo Darwin;; -m) echo arm64;; *) echo Darwin;; esac'
mk sw_vers 'echo 15.1'
mk sudo 'if [ "$1" = -v ] || [ "$1" = -n ]; then exit 0; fi; "$@"'
mk brew 'if [ "$1" = --version ]; then echo "Homebrew 5.0.0"; exit 0; fi
if [ "$1" = list ]; then exit 1; fi   # nothing installed yet (the setup asks before it records a brew install as its own)
case "$*" in "install --cask r") printf "#!/bin/bash\necho R\n" > '"$STUB"'/Rscript; chmod +x '"$STUB"'/Rscript;;
 "install --cask quarto") printf "#!/bin/bash\necho quarto\n" > '"$STUB"'/quarto; chmod +x '"$STUB"'/quarto;;
 "install uv") printf "#!/bin/bash\nexit 0\n" > '"$STUB"'/uv; chmod +x '"$STUB"'/uv;; esac; exit 0'
mk ditto 'mkdir -p "$4/OpenCode.app"'
mk open 'exit 0'
mk curl 'case " $* " in *" -w "*) echo 200; exit 0;; esac; for a in "$@"; do case "$prev" in -o) out="$a";; esac; prev="$a"; done; [ -n "${out:-}" ] && { case "$out" in *.zip) (cd /tmp && rm -rf zz && mkdir zz && printf "#!/bin/bash\necho 1.19.5\n" > zz/opencode && chmod +x zz/opencode && python3 -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1],\"w\");z.write(\"zz/opencode\",\"opencode\")" "$out");; *) : > "$out";; esac; }; exit 0'
mk unzip 'python3 -c "import zipfile,sys,os;z=zipfile.ZipFile(sys.argv[1]);z.extractall(sys.argv[2]);[os.chmod(os.path.join(sys.argv[2],n),0o755) for n in z.namelist()]" "$3" "$5"'
mk df 'echo "Filesystem 1024-blocks Used Available"; echo "disk 1 1 52428800"'
export PATH="$STUB:$PATH" HOME=/tmp/fakehome; mkdir -p "$HOME"
# make /Applications writable for the fake install
/usr/bin/sudo mkdir -p /Applications && /usr/bin/sudo chmod 777 /Applications
cp -r /src /tmp/student-setup && cd /tmp/student-setup
bash setup-mac.sh --yes --skip-ai > /tmp/run.log 2>&1; rc=$?
echo "exit=$rc"; echo "--- calls ---"; cat "$CALLS" | grep -v '^uname\|^sw_vers\|^df' | head -40
echo "--- checks ---"
pass=0; failn=0
t() { if grep -q "$2" "$CALLS"; then echo "PASS $1"; pass=$((pass+1)); else echo "MISS $1"; failn=$((failn+1)); fi; }
n() { if grep -q "$2" "$CALLS"; then echo "MISS $1"; failn=$((failn+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }
t "Homebrew asked for git"      "^brew install git"
t "Homebrew asked for node"     "^brew install node"
t "Homebrew asked for uv"       "^brew install uv"
t "R installed as cask"         "^brew install --cask r$"
t "Quarto installed as cask"    "^brew install --cask quarto"
t "RStudio installed as cask"   "^brew install --cask rstudio"
t "arm64 CLI downloaded"        "opencode-darwin-arm64.zip"
t "arm64 desktop app downloaded" "opencode-desktop-mac-arm64.zip"
t "desktop app unpacked"        "^ditto -x -k"
if [ -d /Applications/OpenCode.app ] || [ -d "$HOME/Applications/OpenCode.app" ]; then echo "PASS app copied"; pass=$((pass+1)); else echo "MISS app copied"; failn=$((failn+1)); fi
REC="$(ls "$HOME"/Library/Application\ Support/MetaScience/installed.tsv 2>/dev/null | head -1)"
for k in "core	brew	git" "r	cask	r" "quarto	cask	quarto" "rstudio	cask	rstudio"; do
  if [ -n "$REC" ] && grep -qxF "$k" "$REC"; then echo "PASS recorded: $k"; pass=$((pass+1)); else echo "MISS recorded: $k"; failn=$((failn+1)); fi
done
grep -q 'MetaScience setup' "$HOME/.zprofile" && { echo "PASS PATH added to .zprofile"; pass=$((pass+1)); } || { echo "MISS PATH added to .zprofile"; failn=$((failn+1)); }
# An old R (from Homebrew, then from elsewhere): the current R comes from CRAN next to it. The R installer deletes
# every R it has an install receipt for, so the old R's receipt must be forgotten BEFORE the installer runs, and
# Homebrew must never upgrade or install R over it (d-8f5f6e).
printf '#!/bin/bash\necho "R version 4.3.1 (2023-06-16)"\n' > "$STUB/R"; chmod +x "$STUB/R"
mk pkgutil 'if [ "$1" = --pkgs ]; then printf "com.apple.pkg.CLTools_Executables\norg.R-project.arm64.R.fw.pkg\norg.R-project.arm64.R.GUI.pkg\n"; fi; exit 0'
mk installer 'exit 0'
mk curl 'case " $* " in *" -w "*) echo 200; exit 0;; esac; out=""; prev=""; url=""; for a in "$@"; do case "$prev" in -o) out="$a";; esac; case "$a" in http*) url="$a";; esac; prev="$a"; done
case "$url" in */sonoma-arm64/base/) echo "<a href=\"R-4.6.1-arm64.pkg\">x</a> <a href=\"R-4.6.2-arm64.pkg\">x</a>"; exit 0;; esac
[ -n "$out" ] && : > "$out"; exit 0'
for who in brew other; do
  if [ "$who" = brew ]; then bl='if [ "$*" = "list --cask r" ]; then exit 0; fi'; else bl=''; fi
  mk brew 'if [ "$1" = --version ]; then echo "Homebrew 5.0.0"; exit 0; fi
'"$bl"'
if [ "$1" = list ]; then exit 1; fi; exit 0'
  : > "$CALLS"; bash setup-mac.sh --yes --skip-ai --components=r > /tmp/run2.log 2>&1
  n "old R ($who): Homebrew never upgrades R"      "^brew upgrade"
  n "old R ($who): Homebrew never installs R"      "^brew install --cask r$"
  t "old R ($who): current CRAN R for Apple chips" "^installer -pkg .*sonoma-arm64.*\|^installer -pkg .*R-4.6.2-arm64.pkg -target /"
  fl="$(grep -n '^pkgutil --forget org.R-project.arm64.R.fw.pkg$' "$CALLS" | head -1 | cut -d: -f1)"
  il="$(grep -n '^installer -pkg .*R-4.6.2-arm64.pkg' "$CALLS" | head -1 | cut -d: -f1)"
  if [ -n "$fl" ] && [ -n "$il" ] && [ "$fl" -lt "$il" ]; then echo "PASS old R ($who): receipt forgotten before the installer"; pass=$((pass+1)); else echo "MISS old R ($who): receipt forgotten before the installer"; failn=$((failn+1)); fi
  n "old R ($who): the R app receipt is kept"      "^pkgutil --forget org.R-project.arm64.R.GUI.pkg"
  if grep -q "old R 4.3 kept" /tmp/run2.log; then echo "PASS old R ($who): message says the old R stays"; pass=$((pass+1)); else echo "MISS old R ($who): message says the old R stays"; failn=$((failn+1)); fi
done
# Quarto without GitHub (d-e4a52e): Homebrew's Quarto comes from GitHub; when it fails, the Quarto inside RStudio is
# used (PATH entry only, recorded as such); with no Quarto inside RStudio the failure is still reported.
rm -f "$STUB/quarto"
mk brew 'if [ "$1" = --version ]; then echo "Homebrew 5.0.0"; exit 0; fi
if [ "$1" = list ]; then exit 1; fi
case "$*" in "install --cask quarto") exit 1;; esac; exit 0'
Q=/Applications/RStudio.app/Contents/Resources/app/quarto/bin
for has in yes no; do
  rm -rf /Applications/RStudio.app "$HOME"; mkdir -p /Applications/RStudio.app/Contents/Resources/app/bin "$HOME"
  [ $has = yes ] && { mkdir -p "$Q"; printf '#!/bin/bash\necho 1.8.25\n' > "$Q/quarto"; chmod +x "$Q/quarto"; }
  : > "$CALLS"; bash setup-mac.sh --yes --skip-ai --components=quarto,rstudio > /tmp/run3.log 2>&1
  REC="$HOME/Library/Application Support/MetaScience/installed.tsv"
  if [ $has = yes ]; then
    grep -q "OK.*Quarto.*the Quarto inside RStudio" /tmp/run3.log && { echo "PASS no GitHub: the Quarto inside RStudio is used"; pass=$((pass+1)); } || { echo "MISS no GitHub: the Quarto inside RStudio is used"; failn=$((failn+1)); }
    grep -q "FAIL.*Quarto" /tmp/run3.log && { echo "MISS no GitHub: no Quarto failure reported"; failn=$((failn+1)); } || { echo "PASS no GitHub: no Quarto failure reported"; pass=$((pass+1)); }
    grep -qF "$Q" "$HOME/.zprofile" 2>/dev/null && { echo "PASS no GitHub: RStudio's Quarto on PATH"; pass=$((pass+1)); } || { echo "MISS no GitHub: RStudio's Quarto on PATH"; failn=$((failn+1)); }
    grep -qxF "core	path	$Q" "$REC" 2>/dev/null && ! grep -q "RStudio.app/Contents" <(grep -v "	path	" "$REC") && { echo "PASS no GitHub: only the PATH entry recorded"; pass=$((pass+1)); } || { echo "MISS no GitHub: only the PATH entry recorded"; failn=$((failn+1)); }
  else
    grep -q "FAIL.*Quarto.*no Quarto inside RStudio" /tmp/run3.log && { echo "PASS no GitHub, no Quarto in RStudio: failure reported"; pass=$((pass+1)); } || { echo "MISS no GitHub, no Quarto in RStudio: failure reported"; failn=$((failn+1)); }
  fi
done
echo "RESULT pass=$pass miss=$failn"; [ $failn = 0 ]
