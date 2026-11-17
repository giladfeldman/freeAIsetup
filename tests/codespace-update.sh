#!/usr/bin/env bash
# A Codespace made before a release gets the release's start-page and start.sh fixes at its next start (d-c09bc7).
# A local stand-in for GitHub (a bare git repository) and a Codespace copy cloned from it; programs the start script
# would launch are stand-ins, so nothing is started and no network is used.
#   bash tests/codespace-update.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
mkdir -p "$T/stubs" "$T/home" "$T/course"
for s in setsid sleep; do printf '#!/bin/bash\nexit 0\n' > "$T/stubs/$s"; done
printf '#!/bin/bash\nexit 0\n' > "$T/stubs/pgrep"                        # "already running": nothing is started
printf '#!/bin/bash\necho 000\n' > "$T/stubs/curl"
chmod +x "$T/stubs/"*
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

g init --bare "$T/origin.git"
g clone "$T/origin.git" "$T/seed"; mkdir -p "$T/seed/.devcontainer"; cp "$ROOT/.devcontainer/start.sh" "$T/seed/.devcontainer/"
echo "readme" > "$T/seed/README.md"; g -C "$T/seed" add -A; g -C "$T/seed" commit -m one; g -C "$T/seed" push origin HEAD:main
g clone "$T/origin.git" "$T/cs"                                          # the Codespace, made on release day
old="$(git -C "$T/cs" rev-parse HEAD)"
# the next release changes start.sh
sed -i 's|^HERE="$(cd "$(dirname "$0")" \&\& pwd)"$|&\necho NEW-START-MARKER|' "$T/seed/.devcontainer/start.sh"
grep -q NEW-START-MARKER "$T/seed/.devcontainer/start.sh" || { echo "FAIL test setup: marker not added"; exit 1; }
g -C "$T/seed" commit -am two; g -C "$T/seed" push origin HEAD:main
new="$(git -C "$T/seed" rev-parse HEAD)"

run() { : > "$T/log"; env -u MS_START_UPDATED PATH="$T/stubs:$PATH" HOME="$T/home" METASCIENCE_DIR="$T/course" XDG_DATA_HOME="$T/home/data" \
          MS_START_LOG="$T/log" bash "$T/cs/.devcontainer/start.sh"; }

# 1. a newer release: the copy is updated and the new start.sh runs, once
run
check "newer release: the Codespace copy is brought up to date" '[ "$(git -C "$T/cs" rev-parse HEAD)" = "$new" ]'
check "newer release: the log says so" 'grep -q "copy of the setup updated ($old -> $new)" "$T/log"'
check "newer release: the new start.sh ran, once" '[ "$(grep -c NEW-START-MARKER "$T/log")" = 1 ] && [ "$(grep -c "^== start.sh" "$T/log")" = 2 ]'
check "newer release: the start continues to the end" 'grep -q "^port 4000" "$T/log"'

# 2. already current: no second run
run
check "already current: start.sh runs once and says the copy is current" '[ "$(grep -c "^== start.sh" "$T/log")" = 1 ] && grep -q "copy of the setup is current" "$T/log"'

# 3. a file in the copy was changed here: nothing is pulled, the change stays
g -C "$T/cs" reset --hard "$old"; echo "my change" >> "$T/cs/README.md"
run
check "changed here: not updated, the change kept" '[ "$(git -C "$T/cs" rev-parse HEAD)" = "$old" ] && grep -q "my change" "$T/cs/README.md" && grep -q "was not updated" "$T/log"'
check "changed here: the start continues to the end" 'grep -q "^port 4000" "$T/log"'

# 4. GitHub cannot be reached: the old copy runs as before
g -C "$T/cs" checkout -- README.md; mv "$T/origin.git" "$T/gone.git"
run
check "offline: the old copy stays and the start continues" '[ "$(git -C "$T/cs" rev-parse HEAD)" = "$old" ] && ! grep -q NEW-START-MARKER "$T/log" && grep -q "^port 4000" "$T/log"'

echo "RESULT pass=$pass fail=$fail"
exit $fail
