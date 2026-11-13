#!/bin/bash
# =============================================================================
#  Meta-science course: remove some or all of what the setup installed (macOS, and Linux used for testing)
#  Removes ONLY what the setup itself recorded installing (installed.tsv, written by setup-mac.sh since 2026-11-12).
#  Software that was on this computer before the setup is not in that record and is never touched.
#  Your course folder is kept unless you type DELETE when asked (or pass --remove-course together with --yes).
#
#  Start it with:  bash setup-mac.sh --uninstall     (from the pack folder ~/Library/Application Support/MetaScience/pack)
#  or:             bash lib/uninstall-mac.sh [--components=rstudio,quarto|all] [--yes] [--dry-run]   (--parts= is the same)
#  Parts: rstudio, r, quarto, node, ai (the AI assistant, Git, uv, this pack and its daily update), all.
#  Written for bash 3.2 (the macOS default).
# =============================================================================
set -u
PARTS_ARG=""; YES=0; DRY_RUN=0; REMOVE_COURSE=0
for arg in "$@"; do
  case "$arg" in
    --parts=*|--components=*) PARTS_ARG="${arg#*=}" ;;
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --remove-course) REMOVE_COURSE=1 ;;
    --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
  esac
done
if [ "$(uname -s)" = Darwin ]; then PLATFORM=mac; PACK_DIR="$HOME/Library/Application Support/MetaScience/pack"
else PLATFORM=linux; PACK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/metascience/pack"; fi
STATE_DIR="${MS_STATE_DIR:-$(dirname "$PACK_DIR")}"
PACK_DIR="$STATE_DIR/pack"            # setup-mac.sh keeps the pack inside the state folder
RECORD="$STATE_DIR/installed.tsv"
LOG_FILE="${TMPDIR:-/tmp}/metascience-uninstall-$(date +%Y%m%d-%H%M%S).log"
FAKE="${MS_TEST_FAKE_UNINSTALL:-}"     # tests: other programs' uninstallers are only named, never run
SUDO=""; [ "$(id -u)" != 0 ] && SUDO="sudo"
TAB="$(printf '\t')"
GROUPS_ORDER="rstudio r quarto node core"
group_name() {
  case "$1" in rstudio) echo "RStudio" ;; r) echo "R and the course R packages" ;; quarto) echo "Quarto" ;; node) echo "Node.js" ;;
    core) echo "The AI assistant and the setup's own tools (OpenCode, Git, uv, this course pack and its daily update)" ;; esac
}
FAILED=0
say()  { printf '%s\n' "$*" | tee -a "$LOG_FILE"; }
ok()   { say "  OK    $1${2:+  ($2)}"; }
fail() { say "  FAIL  $1${2:+  ($2)}"; FAILED=$((FAILED+1)); }
run()  { # another program's own remover: logged; in a test only named
  echo "\$ $*" >> "$LOG_FILE"
  if [ -n "$FAKE" ]; then echo "would run: $*" >> "$LOG_FILE"; return 0; fi
  "$@" >> "$LOG_FILE" 2>&1
}
have() { command -v "$1" >/dev/null 2>&1; }

# ---- what the setup installed -------------------------------------------------------------------------------
ITEMS=""   # lines: part TAB kind TAB target (the record, plus the pack and its update check, which only the setup makes)
[ -f "$RECORD" ] && ITEMS="$(grep -v '^[[:space:]]*$' "$RECORD")"
add_item() { case "$ITEMS" in *"$TAB$1$TAB"*) ;; *) ITEMS="${ITEMS:+$ITEMS
}core$TAB$1$TAB$2" ;; esac; }
add_item pack "$PACK_DIR"
if [ "$PLATFORM" = mac ]; then add_item launchd "$HOME/Library/LaunchAgents/org.freeaisetup.update.plist"; else add_item cron freeaisetup-update; fi
items_of() { printf '%s\n' "$ITEMS" | awk -F'\t' -v p="$1" '$1 == p'; }
PRESENT=""; for g in $GROUPS_ORDER; do [ -n "$(items_of "$g")" ] && PRESENT="$PRESENT $g"; done; PRESENT="${PRESENT# }"
COURSE="$(items_of course | head -1 | cut -f3)"

say "MetaScience course setup: remove what the setup installed   (log: $LOG_FILE)"
[ "$DRY_RUN" = 1 ] && say "DRY RUN: nothing will be changed."
if [ ! -f "$RECORD" ]; then
  say "This computer has no record of the programs the setup installed (setups before November 2026 kept none)."
  say "So only the course pack and its daily update can be removed here. Other programs: drag them from"
  say "Applications to the Bin, or ask the teacher."
fi

# ---- choose -------------------------------------------------------------------------------------------------
CHOSEN=""
if [ -n "$PARTS_ARG" ]; then
  for w in $(printf '%s' "$PARTS_ARG" | tr ',;' '  ' | tr 'A-Z' 'a-z'); do
    case "$w" in all) CHOSEN="$CHOSEN $PRESENT" ;; ai|core) CHOSEN="$CHOSEN core" ;; rstudio|r|quarto|node) CHOSEN="$CHOSEN $w" ;; python) ;;
      *) say "Unknown part: $w. Use any of: rstudio, r, quarto, node, ai, all."; exit 2 ;; esac
  done
elif [ "$YES" = 1 ]; then say "Say what to remove with --components (for example --components=rstudio,quarto, or --components=all)."; exit 2
else
  say ""; say "The setup installed these on this computer. Things that were here before the setup are not listed and are never touched."
  i=0; for g in $PRESENT; do i=$((i+1)); extra=""
    [ "$g" = r ] && { n="$(printf '%s\n' "$ITEMS" | awk -F'\t' '$2 == "rpkg"' | wc -l | tr -d ' ')"; [ "$n" != 0 ] && extra=" ($n R packages)"; }
    say "  $i. $(group_name "$g")$extra"; done
  printf 'Type the numbers to remove (for example 1 3), A for all of them, or press Enter to cancel: '; read -r a || a=""
  case "$a" in a|A|all|ALL) CHOSEN="$PRESENT" ;; *)
    for n in $(printf '%s' "$a" | tr ',;' '  '); do
      case "$n" in *[!0-9]*) say "  '$n' is not a number from the list; nothing was removed."; exit 2 ;; esac
      g="$(printf '%s' "$PRESENT" | cut -d' ' -f"$n" 2>/dev/null)"
      if [ "$n" -lt 1 ] || [ -z "$g" ] || [ "$n" -gt "$(echo $PRESENT | wc -w)" ]; then say "  '$n' is not a number from the list; nothing was removed."; exit 2; fi
      CHOSEN="$CHOSEN $g"
    done ;;
  esac
fi
c=""; for g in $PRESENT; do case " $CHOSEN " in *" $g "*) c="$c $g" ;; esac; done; CHOSEN="${c# }"
REMOVE_COURSE_NOW=0
if [ -n "$COURSE" ] && [ -d "$COURSE" ]; then
  if [ "$YES" = 1 ]; then REMOVE_COURSE_NOW="$REMOVE_COURSE"
  elif [ "$DRY_RUN" = 0 ]; then
    say ""; say "Your course folder $COURSE holds your course work, notes and the Python course packages."
    printf 'To delete it too, type DELETE (this cannot be undone). Press Enter to keep it: '; read -r a || a=""
    [ "$a" = DELETE ] && REMOVE_COURSE_NOW=1
  fi
fi
if [ -z "$CHOSEN" ] && [ "$REMOVE_COURSE_NOW" = 0 ]; then say "Nothing was removed."; exit 0; fi
# The course pack holds this uninstall. If other parts the setup installed stay on this computer, the pack and its
# daily update stay too, so the student can come back and remove those parts later.
KEEP_PACK=0
case " $CHOSEN " in *" core "*)
  for g in $PRESENT; do [ "$g" = core ] && continue; case " $CHOSEN " in *" $g "*) ;; *) KEEP_PACK=1 ;; esac; done ;; esac
[ "$KEEP_PACK" = 1 ] && { say ""; say "The course pack stays until the other parts are removed, so you can run the uninstall again."; }
if [ "$YES" = 0 ] && [ "$DRY_RUN" = 0 ]; then
  what=""; for g in $CHOSEN; do what="$what; $(group_name "$g")"; done; [ "$REMOVE_COURSE_NOW" = 1 ] && what="$what; your course folder"
  say ""; printf 'Remove: %s? Your Mac password may be needed for some programs. [y/N] ' "${what#; }"; read -r a || a=""
  case "$a" in y|Y|yes|YES) ;; *) say "Nothing was removed."; exit 0 ;; esac
fi

# ---- remove ---------------------------------------------------------------------------------------------------
# order: R packages before R, uv's data before uv, the update check, programs, folders, the pack, then PATH lines
prio() { case "$1" in rpkg) echo 0 ;; uvdata) echo 1 ;; launchd|cron) echo 2 ;; brew|cask|apt) echo 3 ;; homebrew) echo 4 ;;
  dir|file|pkgdir|clt) echo 5 ;; pack) echo 6 ;; path) echo 7 ;; *) echo 8 ;; esac; }
TODO="$(printf '%s\n' "$ITEMS" | while IFS="$TAB" read -r part kind target; do
  [ "$KEEP_PACK" = 1 ] && case "$kind" in pack|launchd|cron) continue ;; esac
  case " $CHOSEN " in *" $part "*) printf '%s\t%s\t%s\t%s\n' "$(prio "$kind")" "$part" "$kind" "$target" ;; esac; done | sort -s -n -k1,1 | cut -f2-)"
[ "$REMOVE_COURSE_NOW" = 1 ] && TODO="${TODO:+$TODO
}course${TAB}dir$TAB$COURSE"
DONE=""   # lines of the record that are gone now
done_item() { DONE="$DONE
$1$TAB$2$TAB$3"; }
say ""
rp="$(printf '%s\n' "$TODO" | awk -F'\t' '$2 == "rpkg" {printf "%s'\''%s'\''", (n++ ? "," : ""), $3}')"
if [ -n "$rp" ]; then
  np="$(printf '%s\n' "$TODO" | awk -F'\t' '$2 == "rpkg"' | wc -l | tr -d ' ')"
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] remove $np R packages"
  elif ! have Rscript && [ -z "$FAKE" ]; then fail "R packages" "R is not found, so its packages cannot be removed this way"
  elif run Rscript -e "suppressWarnings(remove.packages(c($rp), lib=Sys.getenv('R_LIBS_USER')))"; then ok "R packages" "$np removed"
    while IFS="$TAB" read -r part kind target; do [ "$kind" = rpkg ] && done_item "$part" "$kind" "$target"; done <<EOF
$TODO
EOF
  else fail "R packages" "R could not remove them; see $LOG_FILE"; fi
fi
HOMEBREW_NOTE=""
while IFS="$TAB" read -r part kind target; do
  [ -n "$kind" ] || continue
  case "$kind" in rpkg|path) continue ;; esac
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] remove $kind $target"; continue; fi
  case "$kind" in
    uvdata) if have uv || [ -n "$FAKE" ]; then run uv cache clean; run uv python uninstall --all; fi
            ok "Python and downloads kept by uv" "removed"; done_item "$part" "$kind" "$target" ;;
    launchd) if [ -f "$target" ] || [ -n "$FAKE" ]; then run launchctl unload "$target"; [ -n "$FAKE" ] || rm -f "$target"; fi
             ok "Daily update check" "removed"; done_item "$part" "$kind" "$target" ;;
    cron) if [ -n "$FAKE" ] || crontab -l 2>/dev/null | grep -q "$target"; then
            if [ -n "$FAKE" ]; then echo "would run: crontab without $target" >> "$LOG_FILE"
            else crontab -l 2>/dev/null | grep -v "$target" | crontab -; fi
          fi; ok "Daily update check" "removed"; done_item "$part" "$kind" "$target" ;;
    brew|cask)
      if ! have brew && [ -z "$FAKE" ]; then fail "$target" "Homebrew is not found; remove it by hand"; continue; fi
      if [ "$kind" = cask ]; then run brew uninstall --cask "$target"; else run brew uninstall "$target"; fi \
        && { ok "$target" "removed"; done_item "$part" "$kind" "$target"; } || fail "$target" "brew could not remove it; see $LOG_FILE" ;;
    apt) run $SUDO apt-get remove -y "$target" && { ok "$target" "removed"; done_item "$part" "$kind" "$target"; } || fail "$target" "apt-get could not remove it" ;;
    homebrew) HOMEBREW_NOTE="$target"; done_item "$part" "$kind" "$target" ;;
    pkgdir|clt) # installed for the whole Mac: needs the password
      if [ ! -e "$target" ]; then done_item "$part" "$kind" "$target"; continue; fi
      if [ -n "$FAKE" ]; then echo "would run: $SUDO rm -rf $target" >> "$LOG_FILE"; rm -rf "$target"; ok "$target" "removed"; done_item "$part" "$kind" "$target"
      elif $SUDO rm -rf "$target" >> "$LOG_FILE" 2>&1; then ok "$target" "removed"; done_item "$part" "$kind" "$target"
      else fail "$target" "could not remove it"; fi ;;
    dir|file|pack)
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then done_item "$part" "$kind" "$target"; continue; fi
      if rm -rf "$target" 2>>"$LOG_FILE"; then ok "$target" "removed"; done_item "$part" "$kind" "$target"
      else fail "$target" "could not remove it (is a program from it still open?)"; fi ;;
  esac
done <<EOF
$TODO
EOF
# PATH lines the setup added to the shell start-up files, whose folders are gone now
gone=""; while IFS="$TAB" read -r part kind target; do
  [ "$kind" = path ] && [ ! -d "$target" ] && { gone="$gone
$target"; done_item "$part" "$kind" "$target"; }
done <<EOF
$ITEMS
EOF
if [ -n "$(printf '%s' "$gone" | tr -d '\n')" ] && [ "$DRY_RUN" = 0 ]; then
  for f in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    [ -f "$f" ] || continue
    cp "$f" "$f.metascience-backup"
    printf '%s\n' "$gone" | awk -v F="$f" 'NF { want["export PATH=\"" $0 ":$PATH\"  # added by MetaScience setup"] = 1 }
      END { while ((getline line < F) > 0) if (!(line in want)) print line }' > "$f.tmp" && mv "$f.tmp" "$f"
  done
  ok "PATH" "the lines the setup had added for removed folders were taken out of ~/.zprofile and ~/.bash_profile"
fi
[ -n "$HOMEBREW_NOTE" ] && say "  Homebrew ($HOMEBREW_NOTE) was installed by the setup and is left in place: other programs may use it. To remove it, see https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew"

# ---- keep the record true ------------------------------------------------------------------------------------
if [ "$DRY_RUN" = 0 ]; then
  LEFT="$(printf '%s\n' "$ITEMS" | grep -v '^[[:space:]]*$' | grep -vxF -f <(printf '%s\n' "$DONE" | grep -v '^[[:space:]]*$') 2>/dev/null)"
  [ -z "$(printf '%s' "$DONE" | tr -d '\n')" ] && LEFT="$(printf '%s\n' "$ITEMS" | grep -v '^[[:space:]]*$')"
  [ "$KEEP_PACK" = 1 ] || LEFT="$(printf '%s\n' "$LEFT" | grep -v "^core${TAB}\(pack\|launchd\|cron\)${TAB}" | grep -v '^[[:space:]]*$')"   # the setup adds those itself
  case " $CHOSEN " in *" core "*) AI_GONE=1 ;; *) AI_GONE=0 ;; esac
  if [ "$AI_GONE" = 1 ] && [ -z "$(printf '%s\n' "$LEFT" | grep -v "^course$TAB")" ]; then
    rm -rf "$STATE_DIR"          # nothing of the setup is left (a kept course folder needs no record)
  elif [ -d "$STATE_DIR" ]; then
    if [ -n "$LEFT" ]; then printf '%s\n' "$LEFT" > "$RECORD"; else rm -f "$RECORD"; fi
    # a removed part must not come back with the next update or the next run of the setup
    if [ -f "$STATE_DIR/parts.txt" ]; then
      keep=""; for p in $(cat "$STATE_DIR/parts.txt"); do
        case " $CHOSEN " in *" $p "*) continue ;; esac
        [ "$p" = none ] && continue
        [ "$p" = rstudio ] && case " $CHOSEN " in *" r "*) continue ;; esac
        keep="$keep $p"; done
      keep="${keep# }"; printf '%s\n' "${keep:-none}" > "$STATE_DIR/parts.txt"
    fi
  fi
fi
say ""
if [ "$FAILED" != 0 ]; then say "Some things could not be removed (see the FAIL lines). Log: $LOG_FILE"; exit 1; fi
say "Done."; exit 0
