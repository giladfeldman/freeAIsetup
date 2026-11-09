#!/bin/bash
# Exercises the macOS branch of setup-mac.sh on Linux by replacing macOS-only commands with
# small fakes that record how they were called. Proves the Mac control flow (Homebrew, casks,
# desktop app unpacking, PATH edits) without a Mac. It does NOT prove the real Mac installers work.
set -u
STUB=/tmp/stubs; mkdir -p "$STUB"; CALLS=/tmp/calls.log; : > "$CALLS"
mk() { printf '#!/bin/bash\necho "%s $*" >> %s\n%s\n' "$1" "$CALLS" "${2:-exit 0}" > "$STUB/$1"; chmod +x "$STUB/$1"; }
mk uname 'case "$1" in -s) echo Darwin;; -m) echo arm64;; *) echo Darwin;; esac'
mk sw_vers 'echo 15.1'
mk sudo 'if [ "$1" = -v ] || [ "$1" = -n ]; then exit 0; fi; "$@"'
mk brew 'if [ "$1" = --version ]; then echo "Homebrew 5.0.0"; exit 0; fi
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
grep -q 'MetaScience setup' "$HOME/.zprofile" && { echo "PASS PATH added to .zprofile"; pass=$((pass+1)); } || { echo "MISS PATH added to .zprofile"; failn=$((failn+1)); }
echo "RESULT pass=$pass miss=$failn"; [ $failn = 0 ]
