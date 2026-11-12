#!/bin/bash
# =============================================================================
#  freeAIsetup one-line installer for macOS (and Linux)
#
#  Students paste ONE line into Terminal (Cmd+Space, type "Terminal", Enter):
#
#    curl -fsSL https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/install.sh | bash
#
#  If GitHub is blocked, the same file comes from jsDelivr (a free public mirror of GitHub):
#
#    curl -fsSL https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/install.sh | bash
#
#  Why a pasted line instead of the zip: macOS Gatekeeper blocks scripts a browser downloaded
#  ("cannot be opened because it is from an unidentified developer"). Files curl downloads are not
#  marked that way, and nobody has to find the right file to double-click.
#
#  What it does: downloads the signed list of the current release (manifest), checks its signature
#  against the public key below, downloads every file in that list and checks each file's SHA-256,
#  then starts the normal setup (setup-mac.sh). A file that fails a check stops the install.
#  A stop here (no download, a failed check) offers to send a short report to the teacher's log box, like the
#  setup itself does.
#  If the line was pasted without its ending "| bash", Terminal only shows this file: copy the WHOLE line again.
#  Testing: MS_UPDATE_SOURCES (same format as update/update.sh), MS_SETUP_ARGS, MS_INSTALL_DIR,
#  MS_LOG_URL and MS_LOG_ENV (log box address and "local" marker, as in setup-mac.sh).
# =============================================================================
# Everything is inside main(), called on the last line, so a half-downloaded script runs nothing.
main() {
  set -u
  local PUBKEY='-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA6GBNEcoCRllHdfOkRQwk
9Z82PoqIo5MyTvsPHBro9g2Mrm/nyCc0mllmRKljYcX/o67z4yYsKpYycQsuZczg
CsIxHDe/ks4CQp1UwXAihkarJfsX3oI77Kj7Cp+R9tBmZw9OTxGrclmtMVTGVeGL
MPRU69NthpxlIznQoYPRu1DikktWAr+kmhbQMlV4zY4OMRjzj4suuODZTkdrETky
j2MTH3y/Xi0VRtu2JJ3O6nPfNg8VU3IUJPXh3102ZR7F77hcUxMyhR1meVb7XRew
iZ3TxHJ2G++qnS4rdZohxs4BSYrh5Q5c6geNzNZh0FNWEoeOdVqg5qInGgBIIjC6
vvO4oM3wDl33lsD59GKvP2VZvv2hWTx6uvbmBoRzIR6D1ynvk4J4FQW8Cl3769Kb
CV0KHKp94sa+RS3R8jjDk7QL9Wseo0CQOXsiK7IYitawCcpffLtzdeo5fvHiGZHl
fYLUKs+KlwabPzetzAsEq4vOZazV0eyeYWRWuNSATmUNAgMBAAE=
-----END PUBLIC KEY-----'
  local DEFAULT='https://raw.githubusercontent.com/giladfeldman/freeAIsetup/main/release/manifest.json|https://raw.githubusercontent.com/giladfeldman/freeAIsetup/v{V}/{P};https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@main/release/manifest.json|https://cdn.jsdelivr.net/gh/giladfeldman/freeAIsetup@v{V}/{P}'
  local SOURCES="${MS_UPDATE_SOURCES:-$DEFAULT}"
  local WORK; WORK="$(mktemp -d)"
  get() { local u="$1"; case "$u" in http*) case "$u" in *\?*) u="$u&t=$(date +%s)" ;; *) u="$u?t=$(date +%s)" ;; esac ;; esac
          curl -fsSL -m 120 --retry 3 -A "freeAIsetup-installer" -o "$2" "$u"; }
  sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
  printf '%s\n' "$PUBKEY" > "$WORK/pub.pem"
  # Everything the installer saw, for the report a student may send when it stops (a stop here used to reach nobody).
  local NOTES="$WORK/notes.txt" VER="installer"; : > "$NOTES"
  stop_report() { # $1 = step, $2 = why. Asks on the keyboard (this script itself arrives through a pipe).
    local a="" plat body id box="${MS_LOG_URL:-https://freeaisetup-logs.giladfel.workers.dev}" w
    box="${box%/}"; plat=mac; [ "$(uname -s)" = Darwin ] || plat=linux; [ -n "${CODESPACES:-}" ] && plat=codespace
    if (exec < /dev/tty) 2>/dev/null; then
      printf '  Send a short report to your teacher, so they can see what went wrong?\n  It contains no passwords; your user name is removed. [Y/n] '
      read -r a < /dev/tty || a=""
    fi
    case "$a" in n|N|no) return 0 ;; esac
    body="$(printf '== installer (install.sh) ==\nFAIL  %s  %s\n\n%s %s %s, bash %s\n\n' "$1" "$2" "$(uname -s)" "$(sw_vers -productVersion 2>/dev/null || uname -r)" "$(uname -m)" "$BASH_VERSION"; cat "$NOTES")"
    body="$(printf '%s' "$body" | sed -e "s#$HOME#~#g")"
    for w in "$(id -un)" "$(hostname -s 2>/dev/null)"; do
      [ "${#w}" -ge 4 ] && case "$w" in *[!A-Za-z0-9._-]*) ;; *) body="$(printf '%s' "$body" | sed "s#$w#<name>#g")" ;; esac
    done
    if [ -n "${MS_LOG_ENV:-}" ]; then
      id="$(printf '%s' "$body" | curl -fsS --max-time 60 -X POST -H 'x-freeaisetup: 1' -H "x-freeaisetup-env: $MS_LOG_ENV" --data-binary @- "$box/upload?platform=$plat&version=$VER&result=failed" 2>/dev/null | tr -d '\r\n ')"
    else
      id="$(printf '%s' "$body" | curl -fsS --max-time 60 -X POST -H 'x-freeaisetup: 1' --data-binary @- "$box/upload?platform=$plat&version=$VER&result=failed" 2>/dev/null | tr -d '\r\n ')"
    fi
    if [ -n "$id" ]; then echo "  Sent. Your code is $id. Tell your teacher this code."
    else echo "  Could not send it (no internet?). Take a photo of this window for your teacher instead."; fi
  }

  echo ""
  echo "  MetaScience course setup: downloading the setup files..."
  local MANIFEST="" FILEURL="" s murl furl
  local IFS_OLD="$IFS"; IFS=';'; local SRC; read -r -a SRC <<< "$SOURCES"; IFS="$IFS_OLD"
  for s in "${SRC[@]}"; do
    murl="${s%%|*}"; furl="${s#*|}"
    if ! get "$murl" "$WORK/manifest.json" || ! get "${murl%manifest.json}manifest.sig" "$WORK/manifest.sig"; then
      echo "could not read $murl" >> "$NOTES"; echo "  Could not reach ${murl%%/release/*} ; trying another source."; continue
    fi
    openssl base64 -d -A -in "$WORK/manifest.sig" -out "$WORK/sig.bin" 2>/dev/null
    if ! openssl dgst -sha256 -verify "$WORK/pub.pem" -signature "$WORK/sig.bin" "$WORK/manifest.json" >/dev/null 2>&1; then
      echo "signature check failed: $murl (openssl: $(command -v openssl || echo missing))" >> "$NOTES"
      echo "  The files at $murl failed the signature check; trying another source."; continue
    fi
    MANIFEST="$WORK/manifest.json"; FILEURL="$furl"; break
  done
  if [ -z "$MANIFEST" ]; then
    echo ""
    echo "  The setup files could not be downloaded. Check the internet connection and paste the line again."
    echo "  If it still fails, show this window to the teacher."
    stop_report "Installer download" "no source gave a signed file list"
    return 1
  fi

  VER="$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' "$MANIFEST" | head -1)"
  sed -n '/"files": {/,/}/p' "$MANIFEST" | sed -n 's/^ *"\([^"]*\)": *"\([0-9a-f]\{64\}\)",\{0,1\}$/\1 \2/p' > "$WORK/files.txt"
  [ -s "$WORK/files.txt" ] || { echo "  The file list is empty; show this window to the teacher."; stop_report "Installer files" "the file list is empty"; return 1; }
  local DIR="${MS_INSTALL_DIR:-$HOME/.metascience-installer}/$VER"
  rm -rf "$DIR"; mkdir -p "$DIR"
  local rel want url
  while read -r rel want; do
    case "$rel" in /*|*..*|*:*) echo "  Unsafe path in the file list: $rel. Show this window to the teacher."; stop_report "Installer files" "unsafe path in the file list: $rel"; return 1 ;; esac
    url="${FILEURL//\{V\}/$VER}"; url="${url//\{P\}/$rel}"
    mkdir -p "$(dirname "$DIR/$rel")"
    if ! get "$url" "$DIR/$rel" || [ "$(sha "$DIR/$rel")" != "$want" ]; then
      echo "  Download stopped at $rel. Paste the line again; if it fails twice, show this window to the teacher."
      stop_report "Installer files" "download or checksum failed at $rel"; return 1
    fi
  done < "$WORK/files.txt"
  rm -rf "$WORK"
  chmod +x "$DIR/setup-mac.sh" "$DIR/update/update.sh" 2>/dev/null
  echo "  Version $VER downloaded and checked. Starting the setup..."
  echo ""
  # The setup asks questions (and the Mac password): read them from the keyboard, not from this pipe.
  # shellcheck disable=SC2086
  if (exec < /dev/tty) 2>/dev/null; then bash "$DIR/setup-mac.sh" ${MS_SETUP_ARGS:-} < /dev/tty
  else bash "$DIR/setup-mac.sh" ${MS_SETUP_ARGS:-}; fi
}
main "$@"
# SEEING THIS TEXT IN YOUR TERMINAL? Then the line was pasted without its ending  | bash
# Nothing was installed. Copy the WHOLE line from the guide again, including  | bash  at the end, and press Enter.
