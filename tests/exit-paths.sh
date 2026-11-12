#!/bin/bash
# Every way a Mac/Linux setup can stop must offer the report to the teacher's log box, and a success must send the
# anonymous count once. Runs in the Docker test image (tests/run-tests.ps1 -Only exits) and installs nothing:
# each case stops before any install (test hooks MS_TEST_FAIL_AT / MS_TEST_CRASH), the installer cases stop at their
# download checks, and the log box is a local fake (tests/fake_logbox.py). `script` gives the setup a keyboard
# (a terminal), because the offer is only made to a person at a keyboard.
set -u
export MS_LOG_ENV=local
cp -r /src /tmp/ss && cd /tmp/ss
REC=/tmp/record.jsonl; : > "$REC"; PORT=28765
python3 tests/fake_logbox.py "$PORT" "$REC" & BOX=$!
sleep 2
export MS_LOG_URL="http://127.0.0.1:$PORT" METASCIENCE_DIR=/tmp/MetaScience
export MS_STATE_DIR=/tmp/ms-state; mkdir -p "$MS_STATE_DIR"; echo all > "$MS_STATE_DIR/parts.txt"   # no parts question
pass=0; failn=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; failn=$((failn+1)); fi; }
uploads() { grep -c '"path": "/upload' "$REC"; }
last_upload() { python3 -c "import json,sys;r=[json.loads(l) for l in open('$REC') if l.strip()];u=[x for x in r if x['path'].startswith('/upload')];print(json.dumps(u[-1]) if u else '{}')"; }
feed() { # types each answer only when its question ([Y/n] or [y/N]) is on screen: earlier steps (apt) read the keyboard too
  local i=0 a; for a in "$@"; do i=$((i+1))
    while [ "$(grep -o '\[[Yy]/[Nn]\]' /tmp/out.txt 2>/dev/null | wc -l)" -lt "$i" ]; do [ -f /tmp/rc.done ] && return; sleep 1; done
    printf '%s\n' "$a"; done
  while [ ! -f /tmp/rc.done ]; do sleep 1; done
}
run_tty() { # $1 = answers (space-separated, "-" for none), rest = command; returns the command's exit code
  local ans="$1"; shift; rm -f /tmp/rc /tmp/rc.done; : > /tmp/out.txt
  [ "$ans" = - ] && ans=""
  # shellcheck disable=SC2086
  feed $ans | script -qec "$*; echo \"RC=\$?\" > /tmp/rc; touch /tmp/rc.done" /dev/null > /tmp/out.txt 2>&1
  sed -n 's/^RC=//p' /tmp/rc
}
named_file_exists() { # the file the summary tells the student to show the teacher must exist
  local f; f="$(sed -n 's/.*show the teacher: \([^ ]*\).*/\1/p' /tmp/out.txt | tr -d '\r' | tail -1)"; [ -n "$f" ] && [ -f "$f" ]
}

for c in "precheck|MS_TEST_FAIL_AT=precheck|Test stop" "crash before any step|MS_TEST_CRASH=main|Setup stopped" \
         "crash in step 3|MS_TEST_CRASH=tools|Setup stopped" "bash error in step 3|MS_TEST_CRASH=unbound|Setup stopped"; do
  name="${c%%|*}"; rest="${c#*|}"; var="${rest%%|*}"; step="${rest#*|}"
  : > "$REC"
  rc="$(run_tty 'y n' "env $var bash setup-mac.sh")"
  check "$name: exit code is not 0 ($rc)" '[ "$rc" != 0 ]'
  check "$name: report uploaded" '[ "$(uploads)" = 1 ]'
  u="$(last_upload)"
  check "$name: report has the FAIL line" 'printf "%s" "$u" | grep -q "FAIL.*$step"'
  check "$name: local marker and header" 'printf "%s" "$u" | grep -q "\"env\": \"local\"" && printf "%s" "$u" | grep -q "\"x-freeaisetup\": \"1\""'
  check "$name: home folder removed" '! printf "%s" "$u" | grep -q "$HOME/"'
  check "$name: student told the code" 'grep -q "Your code is.*TESTID" /tmp/out.txt'
  check "$name: the file named in the summary exists" named_file_exists
done
: > "$REC"; rc="$(run_tty 'n n' "env MS_TEST_FAIL_AT=precheck bash setup-mac.sh")"
check "student says no: nothing sent" '[ "$(uploads)" = 0 ]'
: > "$REC"; rc="$(run_tty - "env MS_TEST_FAIL_AT=precheck bash setup-mac.sh --yes")"
check "--yes: nothing sent, exit not 0" '[ "$(uploads)" = 0 ] && [ "$rc" != 0 ]'
: > "$REC"; rc="$(run_tty 'y n' "timeout -s INT 3 bash setup-mac.sh")"   # Ctrl+C while step 1 checks the network
check "Ctrl+C: stops without asking, nothing sent ($rc)" '[ "$(uploads)" = 0 ] && grep -q "Setup stopped (Ctrl+C)" /tmp/out.txt'

# success count: the function itself, sent once for two successful runs
: > "$REC"
( STATE_DIR=/tmp/countpack; SETUP_VERSION=9.9.9; PLATFORM=linux; LOG_FILE=/tmp/count.log; have() { command -v "$1" >/dev/null 2>&1; }
  LOG_BOX="$MS_LOG_URL"
  eval "$(sed -n '/^log_box_post() {/,/^}/p; /^log_platform() {/p; /^count_success() {/,/^}/p' setup-mac.sh)"
  count_success; count_success )
check "success count: sent once" '[ "$(grep -c "\"path\": \"/count" "$REC")" = 1 ]'
check "success count: only platform and version" 'grep -q "\"path\": \"/count?platform=linux&version=9.9.9\"" "$REC"'
check "success count: empty body" 'grep -q "\"body\": \"\"" "$REC"'

# install.sh: a stop at the download checks offers the report too
command -v openssl >/dev/null || { sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y -qq openssl >/dev/null 2>&1; }
: > "$REC"
run_tty y "env MS_UPDATE_SOURCES='http://127.0.0.1:1/release/manifest.json|http://127.0.0.1:1/{P}' MS_INSTALL_DIR=/tmp/inst bash install.sh" >/dev/null
check "installer: no source reachable: report uploaded" '[ "$(uploads)" = 1 ] && last_upload | grep -q "Installer download"'
check "installer: version 'installer' in the address" 'last_upload | grep -q "version=installer"'
: > "$REC"
run_tty y "env MS_UPDATE_SOURCES='http://127.0.0.1:$PORT/m/manifest.json|http://127.0.0.1:$PORT/bad/{P}' MS_INSTALL_DIR=/tmp/inst bash install.sh" >/dev/null
check "installer: a file fails its checksum: report uploaded" '[ "$(uploads)" = 1 ] && last_upload | grep -q "Installer files"'
check "installer: release version in the address" 'last_upload | grep -q "version=2026\."'

kill "$BOX" 2>/dev/null
echo "RESULT pass=$pass fail=$failn"; [ "$failn" = 0 ]
