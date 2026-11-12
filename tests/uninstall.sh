#!/bin/bash
# Mac/Linux twin of tests/uninstall.ps1, plus the part choice of setup-mac.sh. Runs in the Docker test image
# (tests/run-tests.ps1 -Only uninstall) and removes nothing real: the record points at scratch folders, and other
# programs' removers (brew, apt, launchctl, crontab, R, uv) are only named in the log (MS_TEST_FAKE_UNINSTALL).
set -u
cp -r /src /tmp/us && cd /tmp/us
W=/tmp/uw; export MS_STATE_DIR="$W/state" MS_TEST_FAKE_UNINSTALL=1
pass=0; failn=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; failn=$((failn+1)); fi; }
T="$(printf '\t')"
make_state() {
  rm -rf "$W"; mkdir -p "$W/RStudio.app" "$W/quarto/bin" "$W/node-v22" "$W/opencode-data" "$W/course" "$W/was-here-before" "$MS_STATE_DIR/pack/lib"
  : > "$W/uv"; : > "$W/was-here-before/keep.txt"; : > "$W/course/my-notes.txt"; ln -sfn "$W/node-v22" "$W/node"
  echo "r rstudio quarto python node" > "$MS_STATE_DIR/parts.txt"
  [ "${1:-}" = norecord ] && return 0
  printf '%s\n' "rstudio${T}cask${T}rstudio" "rstudio${T}pkgdir${T}$W/RStudio.app" "quarto${T}dir${T}$W/quarto" \
    "r${T}cask${T}r" "r${T}rpkg${T}statcheck" "r${T}rpkg${T}metafor" "node${T}dir${T}$W/node-v22" "node${T}file${T}$W/node" \
    "core${T}brew${T}git" "core${T}file${T}$W/uv" "core${T}uvdata${T}Python and downloads kept by uv" "core${T}dir${T}$W/opencode-data" \
    "core${T}homebrew${T}/opt/homebrew" "core${T}pack${T}$MS_STATE_DIR/pack" "core${T}cron${T}freeaisetup-update" \
    "core${T}path${T}$W/quarto/bin" "course${T}dir${T}$W/course" > "$MS_STATE_DIR/installed.tsv"
}
un() { # $1 = answers (one per line, | separated), rest = options
  local a="$1"; shift; printf '%s\n' "$a" | tr '|' '\n' | bash lib/uninstall-mac.sh "$@" > "$W/out.txt" 2>&1; echo $?
}
logof() { cat "$(sed -n 's/.*(log: \(.*\.log\)).*/\1/p' "$W/out.txt" | head -1)" 2>/dev/null; }
rec() { cat "$MS_STATE_DIR/installed.tsv" 2>/dev/null; }

# 1. one part, no questions
make_state; rc="$(un '' --parts=rstudio --yes)"
check "rstudio only: exit 0 ($rc)" '[ "$rc" = 0 ]'
check "rstudio only: brew asked to remove the cask, app folder gone" 'logof | grep -q "would run: brew uninstall --cask rstudio" && [ ! -e "$W/RStudio.app" ]'
check "rstudio only: other parts untouched" '[ -d "$W/quarto" ] && [ -d "$MS_STATE_DIR/pack" ] && [ -e "$W/uv" ]'
check "rstudio only: record no longer lists it, still lists the rest" '! rec | grep -q "^rstudio" && [ "$(rec | wc -l)" = 13 ]'
check "rstudio only: not reinstalled by the next update (parts.txt)" '[ "$(cat "$MS_STATE_DIR/parts.txt")" = "r quarto python node" ]'

# 2. everything, no questions
make_state; rc="$(un '' --parts=all --yes)"; L="$(logof)"
check "all: exit 0 ($rc)" '[ "$rc" = 0 ]'
check "all: every recorded folder and file removed" '[ ! -e "$W/RStudio.app" ] && [ ! -e "$W/quarto" ] && [ ! -e "$W/node-v22" ] && [ ! -L "$W/node" ] && [ ! -e "$W/uv" ] && [ ! -e "$W/opencode-data" ]'
check "all: brew asked for R (cask) and git (formula)" 'printf "%s" "$L" | grep -q "would run: brew uninstall --cask r$" && printf "%s" "$L" | grep -q "would run: brew uninstall git$"'
check "all: R packages removed before R" 'printf "%s" "$L" | grep -n "remove.packages(c(.statcheck.,.metafor.)" >/dev/null && [ "$(printf "%s" "$L" | grep -n "remove.packages" | cut -d: -f1 | head -1)" -lt "$(printf "%s" "$L" | grep -n "uninstall --cask r$" | cut -d: -f1 | head -1)" ]'
check "all: uv data cleaned, update check removed" 'printf "%s" "$L" | grep -q "would run: uv python uninstall --all" && printf "%s" "$L" | grep -q "would run: crontab without freeaisetup-update"'
check "all: Homebrew left in place, with how to remove it" 'grep -q "Homebrew (/opt/homebrew) was installed by the setup and is left in place" "$W/out.txt"'
check "all: what was here before is untouched, course kept" '[ -f "$W/was-here-before/keep.txt" ] && [ -f "$W/course/my-notes.txt" ]'
check "all: the state folder is gone" '[ ! -e "$MS_STATE_DIR" ]'

# 3. asked: pick 2 (R), keep course, confirm
make_state; rc="$(un '2||y')"
check "asked: lists the recorded parts in order" 'grep -q "1. RStudio" "$W/out.txt" && grep -q "2. R and the course R packages (2 R packages)" "$W/out.txt" && grep -q "5. The AI assistant" "$W/out.txt"'
check "asked: R removed, RStudio untouched" 'logof | grep -q "brew uninstall --cask r$" && [ -d "$W/RStudio.app" ]'
check "asked: removing R also drops RStudio from the parts" '[ "$(cat "$MS_STATE_DIR/parts.txt")" = "quarto python node" ]'
check "asked: course folder kept on Enter" '[ -f "$W/course/my-notes.txt" ]'

# 4. DELETE, exactly
make_state; un '|delete|y' >/dev/null
check "course: delete in small letters keeps it" '[ -f "$W/course/my-notes.txt" ]'
make_state; un '|DELETE|y' >/dev/null
check "course: DELETE removes it, nothing else" '[ ! -e "$W/course" ] && [ -d "$W/RStudio.app" ] && [ -d "$MS_STATE_DIR/pack" ]'

# 5. answers that remove nothing
make_state
rc="$(un '1||n')";              check "confirm no: nothing removed" '[ -d "$W/RStudio.app" ] && [ "$rc" = 0 ]'
rc="$(un '|')";                 check "Enter at the list: nothing removed" '[ -d "$W/RStudio.app" ] && grep -q "Nothing was removed" "$W/out.txt"'
rc="$(un '9')";                 check "a number not in the list: exit 2, nothing removed ($rc)" '[ "$rc" = 2 ] && [ -d "$W/RStudio.app" ]'
rc="$(un '' --parts=rstudoi --yes)"; check "unknown part: exit 2, nothing removed" '[ "$rc" = 2 ] && [ -d "$W/RStudio.app" ]'
rc="$(un '' --yes)";            check "--yes without --parts: exit 2" '[ "$rc" = 2 ] && [ -d "$W/RStudio.app" ]'
rc="$(un '' --parts=all --yes --dry-run)"; check "--dry-run: nothing removed" '[ "$rc" = 0 ] && [ -d "$W/RStudio.app" ] && [ -d "$MS_STATE_DIR/pack" ]'

# 6. PATH lines in the shell start-up files: only the lines for removed folders go
make_state
HOME_SAVE="$HOME"; export HOME="$W/home"; mkdir -p "$HOME"
printf '# mine\nexport PATH="%s:$PATH"  # added by MetaScience setup\nexport PATH="/opt/mine:$PATH"\n' "$W/quarto/bin" > "$HOME/.zprofile"
un '' --parts=quarto --yes >/dev/null
check "PATH: the line for the removed Quarto folder is gone, the student's own lines stay" '! grep -q "$W/quarto/bin" "$HOME/.zprofile" && grep -q "# mine" "$HOME/.zprofile" && grep -q "/opt/mine" "$HOME/.zprofile"'
export HOME="$HOME_SAVE"

# 7. no record: only the AI part (pack, update check)
make_state norecord; un '|' >/dev/null
check "no record: says so, offers only the AI part" 'grep -q "no record" "$W/out.txt" && grep -q "1. The AI assistant" "$W/out.txt" && ! grep -q "  2\. " "$W/out.txt"'

# 9. only the AI part while RStudio stays: the pack (which holds the uninstall) and its update check stay too,
#    so the student can remove RStudio later; a later run with all removes everything
make_state
printf '%s\n' "rstudio${T}cask${T}rstudio" "rstudio${T}pkgdir${T}$W/RStudio.app" "core${T}file${T}$W/uv" "core${T}dir${T}$W/opencode-data" \
  "core${T}pack${T}$MS_STATE_DIR/pack" "core${T}cron${T}freeaisetup-update" "course${T}dir${T}$W/course" > "$MS_STATE_DIR/installed.tsv"
rc="$(un '' --parts=ai --yes)"
check "ai only, RStudio stays: exit 0 ($rc)" '[ "$rc" = 0 ]'
check "ai only, RStudio stays: the rest of the AI part removed" '[ ! -e "$W/uv" ] && [ ! -e "$W/opencode-data" ]'
check "ai only, RStudio stays: RStudio, the pack and the update check stay" '[ -d "$W/RStudio.app" ] && [ -d "$MS_STATE_DIR/pack" ] && ! logof | grep -q "crontab without"'
check "ai only, RStudio stays: record still lists RStudio and the pack" '[ "$(rec | grep -c "^rstudio$T")" = 2 ] && rec | grep -q "^core${T}pack$T" && rec | grep -q "^core${T}cron$T" && ! rec | grep -q opencode-data'
check "ai only, RStudio stays: says the pack stays" 'grep -q "The course pack stays until the other parts are removed" "$W/out.txt"'
rc="$(un '' --parts=all --yes)"
check "ai only, then all: RStudio, the pack and the state folder gone ($rc)" '[ "$rc" = 0 ] && [ ! -e "$W/RStudio.app" ] && [ ! -e "$MS_STATE_DIR" ] && [ -f "$W/course/my-notes.txt" ]'

# 8. setup-mac.sh: record_install and the part choice
(
  STATE_DIR="$W/rs"; DRY_RUN=0
  eval "$(sed -n '/^record_install() {/,/^}/p' setup-mac.sh)"
  record_install quarto dir /x; record_install quarto dir /x; record_install r rpkg irr; DRY_RUN=1; record_install node brew node
)
check "record_install: tab-separated lines, no duplicate, nothing in a dry run" '[ "$(cat "$W/rs/installed.tsv")" = "$(printf "quarto\tdir\t/x\nr\trpkg\tirr")" ]'
parts_of() { # runs the part functions of setup-mac.sh; $1 = --components value or "", $2 = answers
  ( set +u; STATE_DIR="$W/ps"; DRY_RUN=0; SKIP_GUI=0; ASSUME_YES=0; CHOOSE=1; COMPONENTS="$1"; COURSE_DIR=/nonexistent; PLATFORM=linux; NO_BREW=0
    LOG_FILE=/dev/null; say() { printf '%s\n' "$*"; }; have() { command -v "$1" >/dev/null 2>&1; }
    eval "$(sed -n '/^# ---------- parts the student chooses/,/^precheck() {/p' setup-mac.sh | sed '$d')"
    choose_parts; echo "PARTS=[$PARTS]"; echo "EST=$(estimate_gb)" ) < "${2:-/dev/null}"
}
rm -rf "$W/ps"; parts_of "rstudio,python" > "$W/p.txt" 2>&1
check "--components=rstudio,python adds R (RStudio needs it), saved" 'grep -q "PARTS=\[r rstudio python\]" "$W/p.txt" && [ "$(cat "$W/ps/parts.txt")" = "r rstudio python" ]'
( parts_of "rstudio,pyton" > "$W/p.txt" 2>&1 ); check "unknown part refused" 'grep -q "Unknown part: pyton" "$W/p.txt"'
parts_of "none" > "$W/p.txt" 2>&1; check "--components=none: only the AI part, saved as none" 'grep -q "PARTS=\[\]" "$W/p.txt" && [ "$(cat "$W/ps/parts.txt")" = none ]'
rm -rf "$W/ps"
# the question is asked only at a keyboard: script gives it one, and the answers are typed into it
cat > "$W/ask.sh" <<EOF
cd /tmp/us; W=$W
$(declare -f parts_of)
parts_of "" /dev/tty
EOF
printf '3 9\n3\n' | script -qec "bash $W/ask.sh" /dev/null > "$W/p.txt" 2>&1
check "asked: a wrong answer is asked again, then 3 = Quarto only" 'grep -q "Please type only numbers" "$W/p.txt" && grep -q "PARTS=\[quarto\]" "$W/p.txt"'
check "asked: the list shows a size or 'already on this computer' per part" 'grep -Eq "1\. R and the course R packages +(about [0-9.]+ GB|already on this computer)" "$W/p.txt"'

echo "RESULT pass=$pass fail=$failn"; [ "$failn" = 0 ]
