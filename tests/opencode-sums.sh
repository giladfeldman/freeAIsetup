#!/usr/bin/env bash
# The Mac/Linux setup uses an OpenCode download only when it has the pinned checksum (d-8e46a7). Runs anywhere with
# bash and openssl, offline: the check is tested on small stand-in files; the real downloads are checked by the full
# Linux install (tests/linux-full.sh), which must pass the same check.
#   bash tests/opencode-sums.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
LOG_FILE="$T/log"; DRY_RUN=0; : > "$LOG_FILE"
have() { command -v "$1" >/dev/null 2>&1; }
eval "$(sed -n '/^OPENCODE_VERSION=/p' "$ROOT/setup-mac.sh")"
eval "$(sed -n '/^oc_sum() {/,/^}/p; /^oc_ok() {/,/^}/p; /^sha256_of() {/p' "$ROOT/setup-mac.sh")"
unset MS_TEST_OC_UNCHECKED

# 1. a pin for every file the setup can download for the current version (CLI per Mac/Linux processor, desktop app, npm)
for a in opencode-darwin-arm64.zip opencode-darwin-x64-baseline.zip opencode-linux-arm64.tar.gz opencode-linux-x64-baseline.tar.gz \
         opencode-desktop-mac-arm64.zip opencode-desktop-mac-x64.zip opencode-darwin-arm64.tgz opencode-darwin-x64-baseline.tgz \
         opencode-linux-arm64.tgz opencode-linux-x64-baseline.tgz; do
  case "$a" in *.tgz) re='^sha512-[A-Za-z0-9+/]{86}==$' ;; *) re='^[0-9a-f]{64}$' ;; esac
  check "OpenCode $OPENCODE_VERSION: a checksum for $a" '[[ "$(oc_sum "$a")" =~ $re ]]'
done
# 2. the check itself: the right file is used, a changed one refused and deleted, an unknown one refused
printf 'stand-in\n' > "$T/f"; good256="$(sha256_of "$T/f")"; good512="sha512-$(openssl dgst -sha512 -binary "$T/f" | openssl base64 -A)"
oc_sum() { case "$1" in a.zip) echo "$good256" ;; a.tgz) echo "$good512" ;; esac; }
check "the file with the pinned SHA-256 is used" 'oc_ok "$T/f" a.zip'
check "the file with the pinned sha512 (npm) is used" 'oc_ok "$T/f" a.tgz'
printf 'changed\n' > "$T/g"; check "a changed file is refused and deleted (SHA-256)" '! oc_ok "$T/g" a.zip && [ ! -e "$T/g" ] && grep -q "checksum of a.zip is .*refused" "$LOG_FILE"'
printf 'changed\n' > "$T/g"; check "a changed file is refused and deleted (npm sha512)" '! oc_ok "$T/g" a.tgz && [ ! -e "$T/g" ]'
check "a file with no pinned checksum (a new version) is refused" '! oc_ok "$T/f" b.zip && grep -q "no checksum for b.zip" "$LOG_FILE"'
echo "RESULT pass=$pass fail=$fail"
exit $fail
