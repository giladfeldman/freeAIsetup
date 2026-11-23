#!/bin/bash
# Every way a Mac/Linux setup can stop must offer the report to the teacher's log box, and every run must send one
# anonymous result (POST /result) with nothing personal in it. Runs in the Docker test image (tests/run-tests.ps1 -Only exits) and installs nothing:
# each case stops before any install (test hooks MS_TEST_FAIL_AT / MS_TEST_CRASH), the installer cases stop at their
# download checks, and the log box is a local fake (tests/fake_logbox.py). `script` gives the setup a keyboard
# (a terminal), because the offer is only made to a person at a keyboard.
set -u
export MS_LOG_ENV=local
{ mkdir -p /tmp/ss && tar -C /src --exclude=./.claude/worktrees --exclude=./logs-worker/node_modules -cf - . | tar -C /tmp/ss -xf -; } && cd /tmp/ss
REC=/tmp/record.jsonl; : > "$REC"; PORT=28765
python3 tests/fake_logbox.py "$PORT" "$REC" & BOX=$!
# wait until the box answers (a fixed 2 s was sometimes too short: the first case then found no box, 2026-11-16)
for _ in $(seq 60); do python3 -c "import socket,sys;socket.create_connection(('127.0.0.1',int(sys.argv[1])),1)" "$PORT" 2>/dev/null && break; sleep 0.5; done
export MS_LOG_URL="http://127.0.0.1:$PORT" METASCIENCE_DIR=/tmp/MetaScience
export MS_TEST_NO_JOBS=1   # (the setup's own guard for this computer's scheduler; Docker has none anyway)
export MS_STATE_DIR=/tmp/ms-state; mkdir -p "$MS_STATE_DIR"; echo all > "$MS_STATE_DIR/parts.txt"; echo "web codex claude" > "$MS_STATE_DIR/asked.txt"   # no parts or extras questions
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
results() { grep -c '"path": "/result"' "$REC"; }
last_result() { python3 -c "import json;r=[json.loads(l) for l in open('$REC') if l.strip()];u=[x for x in r if x['path']=='/result'];print(u[-1]['body'] if u else '{}')"; }
# $1 = python expression over the parsed result r; prints yes/no
result_is() { last_result | python3 -c "import json,sys;r=json.load(sys.stdin);print('yes' if ($1) else 'no')" 2>/dev/null; }
private_free() { local b u; b="$(last_result)"; u="$(id -un)"; ! printf "%s" "$b" | grep -q "$HOME/" && { [ "${#u}" -lt 4 ] || ! printf "%s" "$b" | grep -qF "$u"; }; }
named_file_exists() { # the file the summary tells the student to show the teacher must exist
  local f; f="$(sed -n 's/.*show the teacher: \([^ ]*\).*/\1/p' /tmp/out.txt | tr -d '\r' | tail -1)"; [ -n "$f" ] && [ -f "$f" ]
}

for c in "precheck|MS_TEST_FAIL_AT=precheck|Test stop|precheck" "crash before any step|MS_TEST_CRASH=main|Setup stopped|crash" \
         "crash in step 3|MS_TEST_CRASH=tools|Setup stopped|crash" "bash error in step 3|MS_TEST_CRASH=unbound|Setup stopped|crash"; do
  name="${c%%|*}"; rest="${c#*|}"; var="${rest%%|*}"; rest="${rest#*|}"; step="${rest%%|*}"; stage="${rest#*|}"
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
  check "$name: one anonymous result sent" '[ "$(results)" = 1 ]'
  check "$name: result says failed, linux, stage $stage" '[ "$(result_is "r[\"v\"]==1 and r[\"outcome\"]==\"failed\" and r[\"platform\"]==\"linux\" and r[\"stage\"]==\"$stage\"")" = yes ]'
  check "$name: result names the failed step" '[ "$(result_is "any(i[0]==\"FAIL\" and i[1]==\"$step\" for i in r[\"issues\"])")" = yes ]'
  check "$name: result has no home folder or user name" private_free
done
# Nothing of the setup runs on after it (Sol review 2026-11-24: the password keep-alive slept on for up to 50 s). Run
# outside a terminal session: closing the test's terminal takes its children along and hides a leftover; a student's
# Terminal stays open. The grep proves the password step (and so the keep-alive) ran at all.
env MS_TEST_CRASH=tools bash setup-mac.sh --yes </dev/null >/tmp/out-keeper.txt 2>&1; sleep 1
check "after the setup ends: its password keep-alive is gone" 'command -v pgrep >/dev/null && grep -q "computer password" /tmp/out-keeper.txt && ! pgrep -f "^sleep 50$" >/dev/null'   # no pgrep = FAIL
pkill -f "^sleep 50$" 2>/dev/null; : > "$REC"
: > "$REC"; rc="$(run_tty 'n n' "env MS_TEST_FAIL_AT=precheck bash setup-mac.sh")"
check "student says no: no report sent, one anonymous result" '[ "$(uploads)" = 0 ] && [ "$(results)" = 1 ]'
: > "$REC"; rc="$(run_tty - "env MS_TEST_FAIL_AT=precheck bash setup-mac.sh --yes")"
check "--yes: no report, one result, exit not 0" '[ "$(uploads)" = 0 ] && [ "$(results)" = 1 ] && [ "$rc" != 0 ]'
: > "$REC"; rc="$(run_tty - "env MS_NO_COUNT=1 MS_TEST_FAIL_AT=precheck bash setup-mac.sh --yes")"
check "MS_NO_COUNT=1: no result sent" '[ "$(results)" = 0 ]'
check "no run sent the old /count" '! grep -q "\"path\": \"/count" "$REC"'
: > "$REC"; rc="$(run_tty 'y n' "timeout -s INT 3 bash setup-mac.sh")"   # Ctrl+C while step 1 checks the network
check "Ctrl+C: stops without asking, nothing sent, no result either ($rc)" '[ "$(uploads)" = 0 ] && [ "$(results)" = 0 ] && grep -q "Setup stopped (Ctrl+C)" /tmp/out.txt'

# the result message itself (send_result), as at the end of a run: one FAIL row with the home folder in it, one
# WARN row from the check's file (tab-separated, lib/course_setup.py), sent once for two calls
: > "$REC"
( SETUP_VERSION=9.9.9; PLATFORM=linux; ARCH_ID=x86_64; LOG_FILE=/tmp/res.log; DRY_RUN=0; FAILED=1; RUN_MODE=first
  PARTS="r python"; RUN_START=$(( $(date +%s) - 720 )); LOG_BOX="$MS_LOG_URL"; have() { command -v "$1" >/dev/null 2>&1; }
  RESULTS="OK|Git|fine
FAIL|R step|not found in $HOME/R \"quoted\" via http://bob:s3cretpw@proxy.example:8080 jane.doe@uni.example /Users/Other Person/x
"
  printf 'WARN\tVS Code\tnot on PATH in %s\n' "$HOME" > /tmp/res.check.tsv
  eval "$(sed -n '/^log_box_post() {/,/^}/p; /^log_platform() {/p; /^json_s() {/p; /^scrub() {/,/^}/p; /^send_result() {/,/^}/p' setup-mac.sh)"
  send_result done; send_result done )
check "result: sent once for two calls" '[ "$(results)" = 1 ]'
check "result: fields" '[ "$(result_is "r[\"version\"]==\"9.9.9\" and r[\"outcome\"]==\"failed\" and r[\"stage\"]==\"done\" and r[\"mode\"]==\"first\" and r[\"parts\"]==\"r,python\" and r[\"minutes\"]==12 and r[\"arch\"]==\"x86_64\" and r[\"os\"]!=\"\"")" = yes ]'
check "result: issues [status, step, reason, source], quotes kept, check row marked" '[ "$(result_is "len(r[\"issues\"])==2 and r[\"issues\"][0][:2]==[\"FAIL\",\"R step\"] and \"\\\"quoted\\\"\" in r[\"issues\"][0][2] and r[\"issues\"][0][3]==\"setup\" and r[\"issues\"][1]==[\"WARN\",\"VS Code\",r[\"issues\"][1][2],\"check\"]")" = yes ]'
check "result: no home folder or user name" private_free
# Sol review 2026-11-24: a proxy's password, an e-mail address and another account's folder were sent as written
check "result: no proxy password, e-mail address or other account's folder" '[ "$(result_is "not any(b in r[\"issues\"][0][2] for b in (\"s3cretpw\",\"bob\",\"jane\",\"Other\",\"Person\")) and \"<login>@proxy\" in r[\"issues\"][0][2] and \"<e-mail> /Users/<name>/x\" in r[\"issues\"][0][2]")" = yes ]'
check "result: the check's file is removed after reading" '[ ! -f /tmp/res.check.tsv ]'
# Sol review 2026-11-24: with the result switched off, the check's rows file was left behind
: > "$REC"; printf 'WARN\tVS Code\tx\n' > /tmp/res.check.tsv
( LOG_FILE=/tmp/res.log; DRY_RUN=0; MS_NO_COUNT=1; LOG_BOX="$MS_LOG_URL"
  eval "$(sed -n '/^send_result() {/,/^}/p' setup-mac.sh)"; send_result done )
check "result off (MS_NO_COUNT): nothing sent, the check's rows file removed" '[ "$(results)" = 0 ] && [ ! -f /tmp/res.check.tsv ]'

# install.sh: a stop at the download checks offers the report too
command -v openssl >/dev/null || { sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y -qq openssl >/dev/null 2>&1; }
: > "$REC"
run_tty y "env MS_UPDATE_SOURCES='http://127.0.0.1:1/release/manifest.json|http://127.0.0.1:1/{P}' MS_INSTALL_DIR=/tmp/inst bash install.sh" >/dev/null
check "installer: no source reachable: report uploaded" '[ "$(uploads)" = 1 ] && last_upload | grep -q "Installer download"'
check "installer: version 'installer' in the address" 'last_upload | grep -q "version=installer"'
check "installer: one anonymous result, stage installer, the step named" '[ "$(results)" = 1 ] && [ "$(result_is "r[\"stage\"]==\"installer\" and r[\"outcome\"]==\"failed\" and r[\"issues\"][0][1]==\"Installer download\"")" = yes ]'
# the installer's own result removes the same things as the setup's (Sol review 2026-11-24); setsid: no terminal, so
# stop_report sends the result and asks nothing
: > "$REC"
( export MS_LOG_URL; WORK=/tmp; VER=installer; eval "$(sed -n '/^  stop_report() {/,/^  }$/p' install.sh)"
  setsid -w bash -c "$(declare -f stop_report); stop_report 'Installer files' 'x in $HOME/a on $(id -un) via http://bob:s3cretpw@proxy.example:8080 jane.doe@uni.example /home/other person/x'" </dev/null >/dev/null 2>&1 )
check "installer result (in-process): no names, no proxy password, e-mail address or other account's folder" '[ "$(results)" = 1 ] && private_free && [ "$(result_is "not any(b in r[\"issues\"][0][2] for b in (\"s3cretpw\",\"bob\",\"jane\",\"other\",\"person\")) and \"<e-mail> /home/<name>/x\" in r[\"issues\"][0][2]")" = yes ]'
: > "$REC"
run_tty y "env MS_UPDATE_SOURCES='http://127.0.0.1:$PORT/m/manifest.json|http://127.0.0.1:$PORT/bad/{P}' MS_INSTALL_DIR=/tmp/inst bash install.sh" >/dev/null
check "installer: a file fails its checksum: report uploaded" '[ "$(uploads)" = 1 ] && last_upload | grep -q "Installer files"'
check "installer: release version in the address" 'last_upload | grep -q "version=2026\."'

kill "$BOX" 2>/dev/null
echo "RESULT pass=$pass fail=$failn"; [ "$failn" = 0 ]
