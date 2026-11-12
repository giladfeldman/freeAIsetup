#!/usr/bin/env bash
# Tests the free-AI switch (course-kit/.opencode/plugins/free-ai-switch.js) against a real OpenCode server and fake
# AI providers (mock_provider.py). No real AI service is called and the user's own OpenCode data is not touched.
#   bash tests/free-ai-switch/run.sh [path-to-opencode]
# Cases:
#   1. free models refuse -> the message is answered by the backup, and the chat shows the automatic note
#   2. while the refusal holds, a NEW message goes straight to the backup (no request to the free models)
#   3. no backup connected -> the add-on stops the endless retrying and records why (control: nothing switched)
#   4. the backup is out of free requests -> the next backup in the list answers
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
OC="${1:-opencode}"
PY="$(command -v python3 || command -v python)"
PORT=18555; OCPORT=18556
T="$(mktemp -d)"; trap 'kill $MOCK $SRV 2>/dev/null; wait 2>/dev/null; sleep 1; rm -rf "$T" 2>/dev/null' EXIT
export XDG_DATA_HOME="$T/xdg/data" XDG_CONFIG_HOME="$T/xdg/config" XDG_STATE_HOME="$T/xdg/state" XDG_CACHE_HOME="$T/xdg/cache"
export MS_FREE_AI_FALLBACK="$T/fallback.json" MS_FREE_AI_STATE="$T/state.json" OPENCODE_DISABLE_AUTOUPDATE=1
FAIL=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; FAIL=1; }

"$PY" "$HERE/mock_provider.py" $PORT "$T/requests.log" & MOCK=$!
mkdir -p "$T/course/.opencode/plugins"
[ "${MS_TEST_NO_PLUGIN:-}" = 1 ] || cp "$ROOT/course-kit/.opencode/plugins/free-ai-switch.js" "$T/course/.opencode/plugins/"   # =1: control run, must fail
cat > "$T/course/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "opencode/glm-5.3-flash-free",
  "small_model": "opencode/glm-5.3-flash-free",
  "provider": {
    "opencode": { "options": { "baseURL": "http://127.0.0.1:$PORT/zen/v1", "apiKey": "public" } },
    "backup": { "npm": "@ai-sdk/openai-compatible", "name": "Backup",
      "options": { "baseURL": "http://127.0.0.1:$PORT/backup/v1", "apiKey": "x" },
      "models": { "backup-free": { "name": "Backup Free" } } },
    "tired": { "npm": "@ai-sdk/openai-compatible", "name": "Tired",
      "options": { "baseURL": "http://127.0.0.1:$PORT/tired/v1", "apiKey": "x" },
      "models": { "tired-free": { "name": "Tired Free" } } }
  }
}
EOF
SRV=""
start() { # a fresh server (and fresh add-on state) on a new port for each case
  [ -n "$SRV" ] && { kill $SRV 2>/dev/null; wait $SRV 2>/dev/null; }
  OCPORT=$((OCPORT + 1)); API="http://127.0.0.1:$OCPORT"
  rm -f "$MS_FREE_AI_STATE"; : > "$T/requests.log"
  cd "$T/course"; "$OC" serve --port $OCPORT --hostname 127.0.0.1 >> "$T/serve.log" 2>&1 & SRV=$!; cd - >/dev/null
  for _ in $(seq 60); do curl -s -m 2 "$API/session" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "server did not start"; return 1
}

ask() { # session-id text -> waits until the session is idle with an answer or 60 s pass
  curl -s -m 10 -X POST "$API/session/$1/prompt_async" -H 'Content-Type: application/json' \
    -d "{\"model\":{\"providerID\":\"opencode\",\"modelID\":\"glm-5.3-flash-free\"},\"parts\":[{\"type\":\"text\",\"text\":\"$2\"}]}" >/dev/null
  for _ in $(seq 60); do sleep 1; curl -s -m 5 "$API/session/$1/message" > "$T/msgs.json"
    grep -q BACKUP-ANSWER "$T/msgs.json" && [ "$(grep -o BACKUP-ANSWER "$T/msgs.json" | wc -l)" -ge "${3:-1}" ] && return 0; done
  return 1
}
newsession() { curl -s -m 10 -X POST "$API/session" -H 'Content-Type: application/json' -d '{}' | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["id"])'; }

# --- case 3 first (control): no backup listed
echo '[]' > "$MS_FREE_AI_FALLBACK"
start
S="$(newsession)"
ask "$S" "hello" >/dev/null; sleep 3
if grep -q "no free backup" "$MS_FREE_AI_STATE" 2>/dev/null && ! grep -q BACKUP-ANSWER "$T/msgs.json"; then
  pass "3 no backup: retrying stopped, state says no backup connected"
else fail "3 no backup: state=$(cat "$MS_FREE_AI_STATE" 2>/dev/null)"; fi
before=$(grep -c "/zen/" "$T/requests.log"); sleep 25; after=$(grep -c '/zen/' "$T/requests.log")
[ "$after" = "$before" ] && pass "3 no backup: no more requests to the free models after the stop" || fail "3 still retrying ($before -> $after)"

# --- case 1: refusal -> backup answers, note visible
printf '[{"providerID":"backup","modelID":"backup-free","name":"Backup Free","free":true}]' > "$MS_FREE_AI_FALLBACK"
start
S="$(newsession)"
if ask "$S" "hello"; then pass "1 refusal: the backup answered"; else fail "1 refusal: no backup answer"; fi
grep -q "Automatic note from the course setup" "$T/msgs.json" && pass "1 the chat shows the automatic note" || fail "1 no note in chat"
grep -q '/zen/' "$T/requests.log" && pass "1 control: the free models were really tried first" || fail "1 free models never tried"

# --- case 2: next message goes straight to the backup
sleep 4   # let the first chat's own late requests (title, aborted retry) finish before counting
zen_before=$(grep -c '/zen/' "$T/requests.log")
if ask "$S" "second" 2; then pass "2 new message answered by the backup"; else fail "2 no answer to second message"; fi
zen_after=$(grep -c '/zen/' "$T/requests.log")
[ "$zen_after" = "$zen_before" ] && pass "2 no request went to the used-up free models" || fail "2 free models asked again ($zen_before -> $zen_after)"

# --- case 4: first backup out of requests -> next backup
printf '[{"providerID":"tired","modelID":"tired-free","name":"Tired Free","free":true},{"providerID":"backup","modelID":"backup-free","name":"Backup Free","free":true}]' > "$MS_FREE_AI_FALLBACK"
start
S="$(newsession)"
if ask "$S" "hello"; then pass "4 the second backup answered"; else fail "4 no answer"; fi
grep -q '/tired/' "$T/requests.log" && pass "4 control: the first backup was really tried" || fail "4 first backup never tried"

# a paid-looking entry is never used: an OpenRouter model without :free must be ignored by the add-on
grep -q 'endsWith(":free")' "$ROOT/course-kit/.opencode/plugins/free-ai-switch.js" && pass "guard: OpenRouter entries must end in :free" || fail "guard missing"

[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "--- state"; cat "$MS_FREE_AI_STATE" 2>/dev/null; echo "--- requests"; cat "$T/requests.log"; echo "--- serve log tail"; tail -30 "$T/serve.log"; }
exit $FAIL
