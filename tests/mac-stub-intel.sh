#!/bin/bash
# Exercises the Intel-Mac branch of setup-mac.sh (no Homebrew: each tool from its maker) on Linux with small
# fakes that record how they were called. Proves the control flow, not that the real installers work.
set -u
STUB=/tmp/stubs; mkdir -p "$STUB"; CALLS=/tmp/calls.log; : > "$CALLS"
mk() { printf '#!/bin/bash\necho "%s $*" >> %s\n%s\n' "$1" "$CALLS" "${2:-exit 0}" > "$STUB/$1"; chmod +x "$STUB/$1"; }
# a real Node tarball with a fake node inside, and its checksum, as nodejs.org would serve them
NT=/tmp/nodetar; mkdir -p "$NT/node-v22.9.9-darwin-x64/bin"
printf '#!/bin/bash\necho v22.9.9\n' > "$NT/node-v22.9.9-darwin-x64/bin/node"; chmod +x "$NT/node-v22.9.9-darwin-x64/bin/node"
tar -czf "$NT/node-v22.9.9-darwin-x64.tar.gz" -C "$NT" node-v22.9.9-darwin-x64
NSUM="$(sha256sum "$NT/node-v22.9.9-darwin-x64.tar.gz" | cut -d' ' -f1)"
mk uname 'case "$1" in -s) echo Darwin;; -m) echo x86_64;; *) echo Darwin;; esac'
mk sw_vers 'echo 15.8.2'
mk sudo 'if [ "$1" = -v ] || [ "$1" = -n ]; then exit 0; fi; "$@"'
mk brew 'exit 1'
mk xcode-select '[ -f /tmp/clt-installed ] && { echo /Library/Developer/CommandLineTools; exit 0; }; exit 2'
mk softwareupdate 'case "$1" in -l) echo "   * Label: Command Line Tools for Xcode-16.4";; -i) touch /tmp/clt-installed;; esac; exit 0'
mk installer 'case "$2" in *R-*) printf "#!/bin/bash\necho \"R version 4.6.2 (2026-10-31)\"\n" > '"$STUB"'/R; cp '"$STUB"'/R '"$STUB"'/Rscript; chmod +x '"$STUB"'/R '"$STUB"'/Rscript;; *quarto*) printf "#!/bin/bash\necho 1.8.25\n" > '"$STUB"'/quarto; chmod +x '"$STUB"'/quarto;; esac; exit 0'
mk hdiutil 'if [ "$1" = attach ]; then mkdir -p "$5/RStudio.app"; fi; exit 0'
mk ditto 'mkdir -p "${@: -1}"'
mk shasum 'sha256sum "$3"'
mk open 'exit 0'
mk curl 'case " $* " in *" -w "*) echo 200; exit 0;; esac; url=""; out=""; prev=""; for a in "$@"; do case "$prev" in -o) out="$a";; esac; case "$a" in http*) url="$a";; esac; prev="$a"; done
case "$url" in
  *SHASUMS256.txt) echo "'"$NSUM"'  node-v22.9.9-darwin-x64.tar.gz"; exit 0;;
  */big-sur-x86_64/base/) echo "<a href=\"R-4.5.3-x86_64.pkg\">x</a> <a href=\"R-4.6.2-x86_64.pkg\">x</a> <a href=\"R-4.6.10-x86_64.pkg\">x</a>"; exit 0;;
  *astral.sh/uv/install.sh) printf "mkdir -p \$HOME/.local/bin; printf \"#!/bin/bash\\nexit 0\\n\" > \$HOME/.local/bin/uv; chmod +x \$HOME/.local/bin/uv\n"; exit 0;;
esac
[ -n "$out" ] || exit 0
case "$out" in
  *node-v22*) cp '"$NT"'/node-v22.9.9-darwin-x64.tar.gz "$out";;
  *.zip) (cd /tmp && rm -rf zz && mkdir zz && printf "#!/bin/bash\necho 1.19.5\n" > zz/opencode && chmod +x zz/opencode && python3 -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1],\"w\");z.write(\"zz/opencode\",\"opencode\")" "$out");;
  *) : > "$out";;
esac; exit 0'
mk unzip 'python3 -c "import zipfile,sys,os;z=zipfile.ZipFile(sys.argv[1]);z.extractall(sys.argv[2]);[os.chmod(os.path.join(sys.argv[2],n),0o755) for n in z.namelist()]" "$3" "$5"'
mk df 'echo "Filesystem 1024-blocks Used Available"; echo "disk 1 1 52428800"'
for b in git node npm R Rscript quarto uv; do while p="$(command -v $b)"; do /usr/bin/sudo rm -f "$p" || break; done; done
export PATH="$STUB:$PATH" HOME=/tmp/fakehome; mkdir -p "$HOME"
/usr/bin/sudo mkdir -p /Applications && /usr/bin/sudo chmod 777 /Applications
cp -r /src /tmp/student-setup && cd /tmp/student-setup
bash setup-mac.sh --yes --skip-ai > /tmp/run.log 2>&1; rc=$?
echo "exit=$rc"; echo "--- log tail ---"; tail -15 /tmp/run.log; echo "--- calls ---"; grep -v '^uname\|^sw_vers\|^df' "$CALLS" | head -40
echo "--- step 2-3 output ---"; sed -n '/2\/9/,/4\/9/p' /tmp/run.log
pass=0; failn=0
t() { if grep -q "$2" "$CALLS"; then echo "PASS $1"; pass=$((pass+1)); else echo "MISS $1"; failn=$((failn+1)); fi; }
n() { if grep -q "$2" "$CALLS"; then echo "MISS $1"; failn=$((failn+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }
o() { if grep -q "$2" /tmp/run.log; then echo "PASS $1"; pass=$((pass+1)); else echo "MISS $1"; failn=$((failn+1)); fi; }
n "Homebrew never asked to install"  "^brew install"
t "Apple tools via softwareupdate"   "^softwareupdate -i Command Line Tools for Xcode-16.4"
t "newest CRAN Intel R chosen"       "^installer -pkg .*R-4.6.10-x86_64.pkg -target /"
t "Quarto package installed"         "^installer -pkg .*quarto-1.8.25-macos.pkg"
t "RStudio disk image opened"        "^hdiutil attach"
t "RStudio copied to Applications"   "^ditto .*RStudio.app /Applications/RStudio.app"
t "Intel CLI downloaded"             "opencode-darwin-x64-baseline.zip"
o "Node unpacked and on PATH"        "OK    node  (installed (v22.9.9))"
o "Homebrew skipped with reason"     "not used on Intel Macs"
grep -q '.local/share/node/bin' "$HOME/.zprofile" && { echo "PASS node PATH in .zprofile"; pass=$((pass+1)); } || { echo "MISS node PATH in .zprofile"; failn=$((failn+1)); }
echo "RESULT pass=$pass miss=$failn"; [ $failn = 0 ]
