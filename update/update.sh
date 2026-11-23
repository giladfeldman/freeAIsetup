#!/usr/bin/env bash
# =============================================================================
#  freeAIsetup pack updater (Mac and Linux)
#  Checks the published release, verifies its signature, downloads only the files that changed,
#  keeps the previous version for rollback, then re-runs the setup so new tools get installed.
#  It runs only when the student starts it (bash setup-mac.sh --update), or as a Codespace starts: nothing is scheduled.
#    update.sh            check and update now
#    update.sh --auto     quiet run as a Codespace starts (.devcontainer/start.sh); on a computer (the daily check of
#                         setups before 2026-11-24) it removes that check and stops
#    update.sh --rollback go back to the previous version
#    update.sh --check-only
# =============================================================================
set -u
AUTO=0; ROLLBACK=0; CHECK_ONLY=0
for a in "$@"; do case "$a" in --auto) AUTO=1 ;; --rollback) ROLLBACK=1 ;; --check-only) CHECK_ONLY=1 ;; esac; done
HERE="$(cd "$(dirname "$0")" && pwd)"
PACK="$(dirname "$HERE")"
BASE="$(dirname "$PACK")"
PREV="$BASE/pack-previous"
STATE="$BASE/update-log.txt"
COURSE_DIR="${METASCIENCE_DIR:-$HOME/MetaScience}"
DEFAULT_SOURCES='https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/release/manifest.json|https://raw.githubusercontent.com/giladfeldman/freeAIsetup/v{V}/{P};https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/release/manifest.json|https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@v{V}/{P}'
SOURCES="${MS_UPDATE_SOURCES:-$DEFAULT_SOURCES}"   # (a literal default here would end at the first "}" of {V})

note() { local l; l="$(date '+%Y-%m-%d %H:%M')  $*"; echo "$l" >> "$STATE" 2>/dev/null; [ "$AUTO" = 1 ] || echo "  $*"; }
get() { # url dest
  local u="$1"; case "$u" in http*) case "$u" in *\?*) u="$u&t=$(date +%s)" ;; *) u="$u?t=$(date +%s)" ;; esac ;; esac
  curl -fsSL -m 60 -A "freeAIsetup-updater" -o "$2" "$u"
}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
vercmp_gt() { # true if $1 > $2 (dotted numbers)
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)" = "$1" ]
}
sync_dir() { # copy $1 over $2, removing files that $1 does not have
  mkdir -p "$2"
  (cd "$2" && find . -type f) | while IFS= read -r f; do [ -e "$1/$f" ] || rm -f "$2/$f"; done
  (cd "$1" && tar -cf - .) | (cd "$2" && tar -xf -)
}

if [ "$AUTO" = 1 ] && [ -z "${CODESPACES:-}" ]; then
  # Started by the old daily check: remove it and stop. Nothing is downloaded or installed in the background (owner
  # directive 2026-11-24). On a Mac the job is unloaded last, because unloading it stops this script.
  [ -n "${MS_TEST_NO_JOBS:-}" ] && { note "test mode: the old daily update check was not touched"; exit 0; }   # tests: never this computer's jobs
  if [ "$(uname -s)" = Darwin ]; then
    rm -f "$HOME/Library/LaunchAgents/org.freeaisetup.update.plist"
    note "the old daily update check was removed; updates now run only by hand: bash setup-mac.sh --update"
    launchctl remove org.freeaisetup.update >/dev/null 2>&1
  else
    if cur="$(crontab -l 2>/dev/null)"; then printf '%s\n' "$cur" | grep -v 'freeaisetup-update' | crontab - 2>/dev/null; fi
    note "the old daily update check was removed; updates now run only by hand: bash setup-mac.sh --update"
  fi
  exit 0
fi
run_setup() { # the student's own run (or a Codespace's start-up), so the setup does its whole job
  [ -n "${MS_UPDATE_NO_SETUP:-}" ] && { note "test mode: setup re-run skipped"; return 0; }
  local rc
  if [ "$AUTO" = 1 ]; then MS_UPDATE_BY_HAND=1 bash "$PACK/setup-mac.sh" --yes --from-update >> "$STATE" 2>&1; rc=$?
  else MS_UPDATE_BY_HAND=1 bash "$PACK/setup-mac.sh" --yes --from-update; rc=$?; fi
  note "setup after update finished (exit $rc)"
}
applied_behind() { # an update an older updater copied in unseen, whose setup did nothing yet (setup-mac.sh)
  local a; a="$(head -1 "$BASE/applied-version.txt" 2>/dev/null | tr -d '\r ')"
  [ -f "$BASE/installed.tsv" ] && { [ -z "$a" ] || vercmp_gt "$CURRENT" "$a"; }
}

if [ "$ROLLBACK" = 1 ]; then
  [ -f "$PREV/VERSION" ] || { echo "No previous version is stored."; exit 1; }
  sync_dir "$PREV" "$PACK"; note "rolled back to $(head -1 "$PACK/VERSION")"; exit 0
fi

CURRENT="$(head -1 "$PACK/VERSION" 2>/dev/null | tr -d '\r ')"; CURRENT="${CURRENT:-0}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
MANIFEST=""; FILEURL=""
IFS=';' read -r -a SRC <<< "$SOURCES"
for s in "${SRC[@]}"; do
  murl="${s%%|*}"; furl="${s#*|}"
  if ! get "$murl" "$WORK/manifest.json" || ! get "${murl%manifest.json}manifest.sig" "$WORK/manifest.sig"; then
    note "could not reach ${murl%%/release/*}"; continue
  fi
  openssl base64 -d -A -in "$WORK/manifest.sig" -out "$WORK/sig.bin" 2>/dev/null
  if ! openssl dgst -sha256 -verify "$HERE/pubkey.pem" -signature "$WORK/sig.bin" "$WORK/manifest.json" >/dev/null 2>&1; then
    note "REFUSED: the update from $murl has an invalid signature"; continue
  fi
  MANIFEST="$WORK/manifest.json"; FILEURL="$furl"; break
done
[ -n "$MANIFEST" ] || { note "no update source reachable; nothing changed"; exit 0; }

# the manifest is signed JSON; read it with Python if present, else with a strict line parser
LATEST="$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' "$MANIFEST" | head -1)"
NOTES="$(sed -n 's/^ *"notes": *"\(.*\)",$/\1/p' "$MANIFEST" | head -1)"
if ! vercmp_gt "$LATEST" "$CURRENT"; then
  if [ "$CHECK_ONLY" = 0 ] && applied_behind; then note "pack $CURRENT is here but its tools were not brought up to date yet; running the setup now"; run_setup; exit 0; fi
  note "up to date ($CURRENT)"; exit 0
fi
[ "$CHECK_ONLY" = 1 ] && { note "update available: $CURRENT -> $LATEST"; exit 0; }
if [ "$AUTO" = 1 ] && pgrep -if "opencode|rstudio" >/dev/null 2>&1; then note "update $LATEST waits: OpenCode or RStudio is open"; exit 0; fi

# files block: lines like   "path": "sha256",
sed -n '/"files": {/,/}/p' "$MANIFEST" | sed -n 's/^ *"\([^"]*\)": *"\([0-9a-f]\{64\}\)",\{0,1\}$/\1 \2/p' > "$WORK/files.txt"
[ -s "$WORK/files.txt" ] || { note "update $LATEST NOT applied: empty file list"; exit 1; }
STAGE="$WORK/stage"; mkdir -p "$STAGE"; (cd "$PACK" && tar -cf - .) | (cd "$STAGE" && tar -xf -)
CHANGED=0
while read -r rel want; do
  case "$rel" in /*|*..*|*:*) note "update $LATEST NOT applied: unsafe path $rel"; exit 1 ;; esac
  dest="$STAGE/$rel"
  if [ -f "$dest" ] && [ "$(sha "$dest")" = "$want" ]; then continue; fi
  url="${FILEURL//\{V\}/$LATEST}"; url="${url//\{P\}/$rel}"
  mkdir -p "$(dirname "$dest")"
  if ! get "$url" "$WORK/dl" || [ "$(sha "$WORK/dl")" != "$want" ]; then note "update $LATEST NOT applied: checksum mismatch or download failed for $rel"; exit 1; fi
  mv "$WORK/dl" "$dest"; CHANGED=$((CHANGED+1))
done < "$WORK/files.txt"
(cd "$STAGE" && find . -type f | sed 's#^\./##') | while IFS= read -r f; do awk -v f="$f" '$1 == f { found = 1 } END { exit !found }' "$WORK/files.txt" || rm -f "$STAGE/$f"; done
chmod +x "$STAGE/setup-mac.sh" "$STAGE/update/update.sh" 2>/dev/null
rm -rf "$PREV"; sync_dir "$PACK" "$PREV"
sync_dir "$STAGE" "$PACK"
note "updated $CURRENT -> $LATEST ($CHANGED files)"
[ -n "${MS_UPDATE_NO_SETUP:-}" ] && { note "test mode: setup re-run skipped"; exit 0; }
run_setup
mkdir -p "$COURSE_DIR" && echo "$(date '+%Y-%m-%d')  updated the course pack to $LATEST. Notes: $NOTES" >> "$COURSE_DIR/UPDATES.txt"
exit 0
