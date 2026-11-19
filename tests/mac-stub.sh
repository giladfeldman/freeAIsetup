#!/bin/bash
# Exercises the macOS branch of setup-mac.sh on Linux by replacing macOS-only commands with
# small fakes that record how they were called. Proves the Mac control flow (Homebrew, casks,
# desktop app unpacking, PATH edits) without a Mac. It does NOT prove the real Mac installers work.
set -u
export MS_LOG_ENV=local   # test runs never count as real installs or send real alerts
STUB=/tmp/stubs; mkdir -p "$STUB"; CALLS=/tmp/calls.log; : > "$CALLS"
mk() { printf '#!/bin/bash\necho "%s $*" >> %s\n%s\n' "$1" "$CALLS" "${2:-exit 0}" > "$STUB/$1"; chmod +x "$STUB/$1"; }
# a stand-in for VS Code's code command: keeps a list of add-ons with versions, as the real add-on store gave them on
# 2026-11-16 (the Python add-on brings two more, the R add-on one); FAKE_CODE_OLD = a VS Code too old for the newest
cat > /tmp/code-fake <<'CODE'
#!/bin/bash
echo "code $*" >> /tmp/calls.log
L=/tmp/codelist; touch "$L"
case " $* " in *" --help "*) printf 'Visual Studio Code 1.139.1\n\nUsage: code [options][paths...]\n'; exit 0 ;; esac
case " $* " in *" --version "*) printf '1.139.1\nabc\narm64\n'; exit 0 ;; esac
case " $* " in *" --list-extensions "*) case " $* " in *" --show-versions "*) cat "$L" ;; *) cut -d@ -f1 "$L" ;; esac; exit 0 ;; esac
force=0; for a in "$@"; do [ "$a" = --force ] && force=1; done
prev=""; for a in "$@"; do
  if [ "$prev" = --install-extension ]; then
    if grep -q "^$a@" "$L" && [ "$force" = 0 ]; then echo "Extension '$a' is already installed."
    else
      case "$a" in ms-python.python) v=2026.10.0; [ -n "${FAKE_CODE_OLD:-}" ] && v=2025.2.0 ;; reditorsupport.r) v=3.4.0; [ -n "${FAKE_CODE_OLD:-}" ] && v=2.8.8 ;; *) v=1.0.0 ;; esac
      grep -v "^$a@" "$L" > "$L.t"; mv "$L.t" "$L"; echo "$a@$v" >> "$L"
      case "$a" in ms-python.python) w="ms-python.vscode-pylance@2026.4.1 ms-python.debugpy@2026.6.0" ;; reditorsupport.r) w="reditorsupport.r-syntax@0.1.5" ;; *) w="" ;; esac
      for c in $w; do grep -q "^${c%@*}@" "$L" || echo "$c" >> "$L"; done
    fi
  fi; prev="$a"; done; exit 0
CODE
chmod +x /tmp/code-fake; rm -f /tmp/codelist
mk uname 'case "$1" in -s) echo Darwin;; -m) echo arm64;; *) echo Darwin;; esac'
mk sw_vers 'echo 15.1'
mk sudo 'if [ "$1" = -v ] || [ "$1" = -n ]; then exit 0; fi; "$@"'
mk brew 'if [ "$1" = --version ]; then echo "Homebrew 5.0.0"; exit 0; fi
if [ "$1" = list ]; then exit 1; fi   # nothing installed yet (the setup asks before it records a brew install as its own)
case "$*" in "install --cask r") printf "#!/bin/bash\necho Rscript \"\$*\" >> /tmp/calls.log\necho R\n" > '"$STUB"'/Rscript; chmod +x '"$STUB"'/Rscript;;
 "install --cask quarto") printf "#!/bin/bash\necho quarto\n" > '"$STUB"'/quarto; chmod +x '"$STUB"'/quarto;;
 "install uv") printf "#!/bin/bash\nexit 0\n" > '"$STUB"'/uv; chmod +x '"$STUB"'/uv;;
 "install --cask visual-studio-code") cp /tmp/code-fake '"$STUB"'/code;; esac; exit 0'
mk ditto 'mkdir -p "$4/OpenCode.app"'
mk open 'exit 0'
mk curl 'case " $* " in *" -w "*) echo 200; exit 0;; esac; for a in "$@"; do case "$prev" in -o) out="$a";; esac; prev="$a"; done; [ -n "${out:-}" ] && { case "$out" in *.zip) (cd /tmp && rm -rf zz && mkdir zz && printf "#!/bin/bash\necho 1.19.5\n" > zz/opencode && chmod +x zz/opencode && python3 -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1],\"w\");z.write(\"zz/opencode\",\"opencode\")" "$out");; *) : > "$out";; esac; }; exit 0'
mk unzip 'python3 -c "import zipfile,sys,os;z=zipfile.ZipFile(sys.argv[1]);z.extractall(sys.argv[2]);[os.chmod(os.path.join(sys.argv[2],n),0o755) for n in z.namelist()]" "$3" "$5"'
mk df 'echo "Filesystem 1024-blocks Used Available"; echo "disk 1 1 52428800"'
export PATH="$STUB:$PATH" HOME=/tmp/fakehome; mkdir -p "$HOME"
export MS_TEST_OC_UNCHECKED=1   # the stand-in downloads cannot match the pinned OpenCode checksums (tests/opencode-sums.sh tests the check)
# make /Applications writable for the fake install
/usr/bin/sudo mkdir -p /Applications && /usr/bin/sudo chmod 777 /Applications
{ mkdir -p /tmp/student-setup && tar -C /src --exclude=./.claude/worktrees --exclude=./logs-worker/node_modules -cf - . | tar -C /tmp/student-setup -xf -; } && cd /tmp/student-setup
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
t "VS Code installed as cask"   "^brew install --cask visual-studio-code$"
t "OpenCode add-on added"       "^code --install-extension sst-dev.opencode$"
t "Python add-on added"         "^code --install-extension ms-python.python$"
t "R add-on added (R chosen)"   "^code --install-extension reditorsupport.r$"
n "add-ons never forced (nothing there to update)" "^code .*--force"
t "R packages include languageserver (VS Code chosen)" "^Rscript .*languageserver"
t "arm64 desktop app downloaded" "opencode-desktop-mac-arm64.zip"
t "desktop app unpacked"        "^ditto -x -k"
if [ -d /Applications/OpenCode.app ] || [ -d "$HOME/Applications/OpenCode.app" ]; then echo "PASS app copied"; pass=$((pass+1)); else echo "MISS app copied"; failn=$((failn+1)); fi
REC="$(ls "$HOME"/Library/Application\ Support/MetaScience/installed.tsv 2>/dev/null | head -1)"
for k in "core	brew	git" "r	cask	r" "quarto	cask	quarto" "rstudio	cask	rstudio" "vscode	cask	visual-studio-code" "vscode	vsext	sst-dev.opencode" "vscode	vsext	ms-python.python" "vscode	vsext	ms-python.vscode-pylance" "vscode	vsext	reditorsupport.r" "vscode	vsext	reditorsupport.r-syntax" "vscode	dir	$HOME/.vscode"; do
  if [ -n "$REC" ] && grep -qxF "$k" "$REC"; then echo "PASS recorded: $k"; pass=$((pass+1)); else echo "MISS recorded: $k"; failn=$((failn+1)); fi
done
grep -q 'MetaScience setup' "$HOME/.zprofile" && { echo "PASS PATH added to .zprofile"; pass=$((pass+1)); } || { echo "MISS PATH added to .zprofile"; failn=$((failn+1)); }
grep -q "In VS Code: File > Open Folder" /tmp/run.log && { echo "PASS summary says how to open OpenCode in VS Code"; pass=$((pass+1)); } || { echo "MISS summary says how to open OpenCode in VS Code"; failn=$((failn+1)); }
# A VS Code that was here before: kept as it is (never installed or upgraded through Homebrew); its current OpenCode
# add-on is left alone, its old Python add-on (the student's own) is updated and stays the student's; no R add-on
# without the R part
printf '%s\n' sst-dev.opencode@1.0.0 someone.mine@1.0.0 ms-python.python@2025.2.0 ms-python.vscode-pylance@2026.4.1 ms-python.debugpy@2026.6.0 > /tmp/codelist; cp /tmp/code-fake "$STUB/code"
rm -rf "$HOME"; mkdir -p "$HOME"; : > "$CALLS"; bash setup-mac.sh --yes --skip-ai --components=vscode > /tmp/run4.log 2>&1
REC="$HOME/Library/Application Support/MetaScience/installed.tsv"
n "VS Code here before: Homebrew never asked for it" "^brew \(install\|upgrade\|reinstall\) .*visual-studio-code"
n "VS Code here before: the current OpenCode add-on is not installed again" "^code --install-extension sst-dev.opencode"
t "VS Code here before: the student's old Python add-on is updated" "^code --install-extension ms-python.python --force$"
n "VS Code here before: no R add-on without the R part" "reditorsupport"
if ! grep -q "^vscode	" "$REC" 2>/dev/null && grep -q "updated: Python" /tmp/run4.log; then echo "PASS VS Code here before: nothing recorded (the updated add-on stays the student's), says updated"; pass=$((pass+1)); else echo "MISS VS Code here before: nothing recorded (the updated add-on stays the student's), says updated"; failn=$((failn+1)); fi
# A VS Code too old for the tested add-ons: the store gives older ones; a warning that says to update VS Code, no failure
: > /tmp/codelist; rm -rf "$HOME"; mkdir -p "$HOME"; : > "$CALLS"; FAKE_CODE_OLD=1 bash setup-mac.sh --yes --skip-ai --components=r,vscode > /tmp/run5.log 2>&1
if grep -q "WARN.*VS Code add-ons.*reditorsupport.r 2.8.8 (tested: 3.4.0).*Check for Updates" /tmp/run5.log && ! grep -q "FAIL.*VS Code add-ons" /tmp/run5.log; then echo "PASS VS Code too old: a warning naming the old add-on, no failure"; pass=$((pass+1)); else echo "MISS VS Code too old: a warning naming the old add-on, no failure"; failn=$((failn+1)); fi
# A "code" on PATH that is not VS Code's (no version from --version): the code command inside the VS Code app is used
printf '#!/bin/bash\necho "not vs code $*" >> /tmp/calls.log\necho not vs code\n' > "$STUB/code"; chmod +x "$STUB/code"
A="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"; mkdir -p "$A"; cp /tmp/code-fake "$A/code"
: > /tmp/codelist; rm -rf "$HOME"; mkdir -p "$HOME"; : > "$CALLS"; bash setup-mac.sh --yes --skip-ai --components=vscode > /tmp/run6.log 2>&1
if grep -q "OK.*VS Code add-ons.*OpenCode, Python ready" /tmp/run6.log && grep -q "^code --install-extension sst-dev.opencode$" "$CALLS"; then echo "PASS a code command that is not VS Code's: the one inside the app is used"; pass=$((pass+1)); else echo "MISS a code command that is not VS Code's: the one inside the app is used"; failn=$((failn+1)); fi
# Another editor's code command (an editor built from VS Code): it answers --version with a version, but its --help
# names that editor, so the one inside the VS Code app is used (d-a09ebb)
printf '#!/bin/bash\necho "other editor $*" >> /tmp/calls.log\ncase " $* " in *" --help "*) echo "Cursor 1.2.3";; *" --version "*) printf "1.2.3\\nabc\\narm64\\n";; *) echo other;; esac\n' > "$STUB/code"; chmod +x "$STUB/code"
: > /tmp/codelist; rm -rf "$HOME"; mkdir -p "$HOME"; : > "$CALLS"; bash setup-mac.sh --yes --skip-ai --components=vscode > /tmp/run6b.log 2>&1
if grep -q "OK.*VS Code add-ons.*OpenCode, Python ready" /tmp/run6b.log && grep -q "^code --install-extension sst-dev.opencode$" "$CALLS" && ! grep -q "^other editor --install-extension" "$CALLS"; then echo "PASS another editor's code command: the one inside the VS Code app is used"; pass=$((pass+1)); else echo "MISS another editor's code command: the one inside the VS Code app is used"; failn=$((failn+1)); fi
rm -rf "/Applications/Visual Studio Code.app"
# Another editor's code command and NO VS Code (production 2026-11-19, report XK938T: Cursor's /usr/local/bin/code):
# VS Code is not "already installed", the cask brings it (its app; the other editor's code stays first on PATH), its
# add-ons go into VS Code, and the check reads VS Code's own list, never the other editor's.
: > /tmp/codelist; rm -rf "$HOME"; mkdir -p "$HOME"; : > "$CALLS"; mv "$STUB/brew" "$STUB/brew.real"
printf '#!/bin/bash\nif [ "$*" = "install --cask visual-studio-code" ]; then echo "brew $*" >> %s; mkdir -p "%s"; cp /tmp/code-fake "%s/code"; exit 0; fi\nexec %s "$@"\n' "$CALLS" "$A" "$A" "$STUB/brew.real" > "$STUB/brew"; chmod +x "$STUB/brew"
bash setup-mac.sh --yes --skip-ai --components=vscode > /tmp/run6c.log 2>&1
mv "$STUB/brew.real" "$STUB/brew"
if grep -q "^brew install --cask visual-studio-code$" "$CALLS" && ! grep -q "VS Code.*already installed" /tmp/run6c.log; then echo "PASS only another editor's code command: VS Code is installed, not taken as already there"; pass=$((pass+1)); else echo "MISS only another editor's code command: VS Code is installed, not taken as already there"; failn=$((failn+1)); fi
if grep -q "OK.*VS Code add-ons.*OpenCode, Python ready" /tmp/run6c.log && ! grep -q "^other editor --install-extension" "$CALLS"; then echo "PASS only another editor's code command: the add-ons go into the new VS Code"; pass=$((pass+1)); else echo "MISS only another editor's code command: the add-ons go into the new VS Code"; failn=$((failn+1)); fi
# the check itself (uv is a stand-in here, so the setup's own check did not run): python3 runs it as uv would
python3 lib/course_setup.py check --course "$HOME/MetaScience" --skip-ai --parts vscode --log /tmp/check6c.log > /tmp/run6c-check.log 2>&1
if grep -Eq "^ *OK +VS Code +1\.139\.1" /tmp/run6c-check.log && grep -Eq "^ *OK +VS Code add-ons" /tmp/run6c-check.log && ! grep -Eq "^ *(OK|WARN) +VS Code +1\.2\.3" /tmp/run6c-check.log; then echo "PASS only another editor's code command: the check reads VS Code, not the other editor"; pass=$((pass+1)); else echo "MISS only another editor's code command: the check reads VS Code, not the other editor"; failn=$((failn+1)); fi
# Another editor's code command and no VS Code at all, check only: VS Code is reported missing, never as that editor
rm -rf "/Applications/Visual Studio Code.app"
python3 lib/course_setup.py check --course "$HOME/MetaScience" --skip-ai --parts vscode --log /tmp/check6d.log > /tmp/run6d.log 2>&1
if grep -Eq "^ *FAIL +VS Code +.*another editor" /tmp/run6d.log && ! grep -Eq "^ *OK +VS Code" /tmp/run6d.log; then echo "PASS check, no VS Code, another editor's code: VS Code reported missing, not that editor"; pass=$((pass+1)); else echo "MISS check, no VS Code, another editor's code: VS Code reported missing, not that editor"; failn=$((failn+1)); fi
rm -rf "/Applications/Visual Studio Code.app"
rm -f "$STUB/code"
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
    grep -qxF "core	path	$Q" "$REC" 2>/dev/null && ! grep -q "RStudio.app/Contents" <(grep -Ev "	(path|pathdir)	" "$REC") && { echo "PASS no GitHub: only the PATH entry recorded"; pass=$((pass+1)); } || { echo "MISS no GitHub: only the PATH entry recorded"; failn=$((failn+1)); }
  else
    grep -q "FAIL.*Quarto.*no Quarto inside RStudio" /tmp/run3.log && { echo "PASS no GitHub, no Quarto in RStudio: failure reported"; pass=$((pass+1)); } || { echo "MISS no GitHub, no Quarto in RStudio: failure reported"; failn=$((failn+1)); }
  fi
done
echo "RESULT pass=$pass miss=$failn"; [ $failn = 0 ]
