#!/bin/bash
# Mac/Linux twin of tests/uninstall.ps1, plus the part choice of setup-mac.sh. Runs in the Docker test image
# (tests/run-tests.ps1 -Only uninstall) and removes nothing real: the record points at scratch folders, and other
# programs' removers (brew, apt, launchctl, crontab, R, uv) are only named in the log (MS_TEST_FAKE_UNINSTALL).
set -u
{ mkdir -p /tmp/us && tar -C /src --exclude=./.claude/worktrees --exclude=./logs-worker/node_modules -cf - . | tar -C /tmp/us -xf -; } && cd /tmp/us
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
  local a="$1"; shift; rm -f "${TMPDIR:-/tmp}"/metascience-uninstall-*.log  # a run in the same second shares the log name
  printf '%s\n' "$a" | tr '|' '\n' | bash lib/uninstall-mac.sh "$@" > "$W/out.txt" 2>&1; echo $?
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
# a list saved as "all" (by hand; the setup saves each part): removing R takes R and RStudio out of it
make_state; echo all > "$MS_STATE_DIR/parts.txt"; rc="$(un '' --parts=r --yes)"
check "saved all, R removed: each other part kept, R and RStudio gone" '[ "$(cat "$MS_STATE_DIR/parts.txt")" = "quarto python node vscode web codex claude" ]'

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

# 10. each word works with each entry point (2026-11-13: on Windows -Parts was ignored through the setup)
make_state; rc="$(un '' --components=rstudio --yes)"
check "uninstaller with --components=rstudio: exit 0, RStudio gone, quarto stays ($rc)" '[ "$rc" = 0 ] && [ ! -e "$W/RStudio.app" ] && [ -d "$W/quarto" ]'
make_state; rc="$(un '' --yes)"
check "--yes without parts: the message names --components ($rc)" '[ "$rc" = 2 ] && grep -q -- "--components" "$W/out.txt"'
make_state; cp lib/uninstall-mac.sh setup-mac.sh VERSION "$MS_STATE_DIR/pack/" 2>/dev/null; cp lib/uninstall-mac.sh "$MS_STATE_DIR/pack/lib/"
bash "$MS_STATE_DIR/pack/setup-mac.sh" --uninstall --parts=rstudio --yes > "$W/out.txt" 2>&1; rc=$?
check "setup-mac.sh --uninstall --parts=rstudio: exit 0, RStudio gone ($rc)" '[ "$rc" = 0 ] && [ ! -e "$W/RStudio.app" ] && [ -d "$W/quarto" ]'
# --remove-course reaches the uninstaller through the setup (it was not passed on; found 2026-11-15)
make_state; cp lib/uninstall-mac.sh setup-mac.sh VERSION "$MS_STATE_DIR/pack/" 2>/dev/null; cp lib/uninstall-mac.sh "$MS_STATE_DIR/pack/lib/"
bash "$MS_STATE_DIR/pack/setup-mac.sh" --uninstall --parts=rstudio --yes --remove-course > "$W/out.txt" 2>&1; rc=$?
check "setup-mac.sh --uninstall --yes --remove-course: the course folder is deleted ($rc)" '[ "$rc" = 0 ] && [ ! -e "$W/course" ]'

# 11. a folder the setup put on PATH goes once it is empty (Windows VM 2026-11-15: uv's .local\bin stayed, with its
#     PATH entry); one holding anything else stays, and so does an empty one the student already had (no 'pathdir'
#     record: the setup only put it on PATH; d-c97c73)
make_state; mkdir -p "$W/localbin" "$W/keepbin" "$W/ownbin"; : > "$W/localbin/uv2"; : > "$W/keepbin/other"
printf '%s\n' "core${T}file${T}$W/localbin/uv2" "core${T}path${T}$W/localbin" "core${T}pathdir${T}$W/localbin" "core${T}path${T}$W/keepbin" "core${T}pathdir${T}$W/keepbin" "core${T}path${T}$W/ownbin" >> "$MS_STATE_DIR/installed.tsv"
rc="$(un '' --parts=all --yes)"
check "all: a PATH folder the setup made, empty now, is removed ($rc)" '[ "$rc" = 0 ] && [ ! -e "$W/localbin" ]'
check "all: a PATH folder holding something else stays" '[ -f "$W/keepbin/other" ]'
check "all: an empty PATH folder the student already had stays" '[ -d "$W/ownbin" ]'

# 8. setup-mac.sh: record_install and the part choice
(
  STATE_DIR="$W/rs"; DRY_RUN=0
  eval "$(sed -n '/^record_install() {/,/^}/p' setup-mac.sh)"
  record_install quarto dir /x; record_install quarto dir /x; record_install r rpkg irr; DRY_RUN=1; record_install node brew node
)
check "record_install: tab-separated lines, no duplicate, nothing in a dry run" '[ "$(cat "$W/rs/installed.tsv")" = "$(printf "quarto\tdir\t/x\nr\trpkg\tirr")" ]'
# add_path records 'pathdir' only for a folder made during this run (d-c97c73): the uninstall removes only those
(
  STATE_DIR="$W/pd"; DRY_RUN=0; HOME="$W/pdhome"; mkdir -p "$HOME" "$W/pd-old"
  eval "$(sed -n '/^record_install() {/,/^}/p; /^add_path() {/,/^}/p' setup-mac.sh)"
  RUN_START=$(( $(date +%s) + 3600 )); add_path "$W/pd-old" core     # made "before" this run (start set an hour ahead)
  RUN_START=$(( $(date +%s) - 2 )); mkdir -p "$W/pd-new"; add_path "$W/pd-new" core
)
check "add_path: a folder made in this run gets a pathdir record" 'grep -qxF "$(printf "core\tpathdir\t%s" "$W/pd-new")" "$W/pd/installed.tsv"'
check "add_path: a folder that was here before gets none (both get a path record)" '! grep -qF "pathdir	$W/pd-old" "$W/pd/installed.tsv" && grep -qxF "$(printf "core\tpath\t%s" "$W/pd-old")" "$W/pd/installed.tsv"'
parts_of() { # runs the part functions of setup-mac.sh; $1 = --components value or "", $2 = answers
  ( set +u; STATE_DIR="$W/ps"; DRY_RUN=0; SKIP_GUI="${PO_NOGUI:-0}"; ASSUME_YES="${PO_YES:-0}"; CHOOSE="${PO_CHOOSE:-1}"; COMPONENTS="$1"
    COURSE_DIR=/nonexistent; PLATFORM="${PO_PLATFORM:-linux}"; NO_BREW=0; FROM_UPDATE="${PO_FROM_UPDATE:-0}"
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
printf '3 9\n3\nno\nno\nno\n' | script -qec "bash $W/ask.sh" /dev/null > "$W/p.txt" 2>&1
check "asked: a wrong answer is asked again, then 3 = Quarto only" 'grep -q "Please type only numbers" "$W/p.txt" && grep -q "PARTS=\[quarto\]" "$W/p.txt"'
check "asked: the list shows a size or 'already on this computer' per part" 'grep -Eq "1\. R and the course R packages +(about [0-9.]+ GB|already on this computer)" "$W/p.txt"'

# 12. VS Code (added 2026-11-16): offered on a Mac only, never added by an update, its add-ons go first on removal
rm -rf "$W/ps"; parts_of "all" > "$W/p.txt" 2>&1
check "Linux, --components=all: VS Code is not offered (all = every part, the three optional ones too)" 'grep -q "PARTS=\[r rstudio quarto python node web codex claude\]" "$W/p.txt"'
rm -rf "$W/ps"; PO_PLATFORM=mac parts_of "all" > "$W/p.txt" 2>&1
check "Mac, --components=all: VS Code included" 'grep -q "PARTS=\[r rstudio quarto python node vscode web codex claude\]" "$W/p.txt"'
rm -rf "$W/ps"; PO_PLATFORM=mac PO_YES=1 PO_CHOOSE=0 parts_of "" > "$W/p.txt" 2>&1
check "Mac, --yes, first run: VS Code and the website tools included, Codex and Claude Code not (their default is no)" 'grep -q "PARTS=\[r rstudio quarto python node vscode web\]" "$W/p.txt"'
rm -rf "$W/ps"; PO_PLATFORM=mac PO_YES=1 PO_CHOOSE=0 PO_FROM_UPDATE=1 parts_of "" > "$W/p.txt" 2>&1
check "Mac, an update of an older setup (no parts.txt): VS Code not added" 'grep -q "PARTS=\[r rstudio quarto python node\]" "$W/p.txt"'
rm -rf "$W/ps"; mkdir -p "$W/ps"; echo "r rstudio quarto python node" > "$W/ps/parts.txt"; PO_PLATFORM=mac PO_YES=1 PO_CHOOSE=0 parts_of "" > "$W/p.txt" 2>&1
check "Mac, parts chosen before VS Code existed: VS Code not added" 'grep -q "PARTS=\[r rstudio quarto python node\]" "$W/p.txt"'
rm -rf "$W/ps"; PO_PLATFORM=mac PO_NOGUI=1 parts_of "all" > "$W/p.txt" 2>&1
check "Mac, --no-gui: neither RStudio nor VS Code" 'grep -q "PARTS=\[r quarto python node web codex claude\]" "$W/p.txt"'
# a parts list saved by an older setup ("all", the three extras not yet answered) never brings Codex or Claude Code
rm -rf "$W/ps"; mkdir -p "$W/ps"; echo all > "$W/ps/parts.txt"; PO_PLATFORM=mac PO_YES=1 PO_CHOOSE=0 parts_of "" > "$W/p.txt" 2>&1
check "Mac, older 'all' with --yes: no Codex or Claude Code" 'grep -q "PARTS=\[r rstudio quarto python node vscode web\]" "$W/p.txt"'
rm -rf "$W/ps"; PO_PLATFORM=mac PO_YES=1 PO_CHOOSE=0 parts_of "" > "$W/p.txt" 2>&1
check "Mac, --yes, first run: its parts are saved (a later check and update know them)" '[ "$(cat "$W/ps/parts.txt")" = "r rstudio quarto python node vscode web" ]'
rm -rf "$W/ps"; PO_PLATFORM=mac PO_YES=1 PO_CHOOSE=0 PO_NOGUI=1 parts_of "" > "$W/p.txt" 2>&1
check "Mac, --yes --no-gui, first run: saved without RStudio and VS Code" '[ "$(cat "$W/ps/parts.txt")" = "r quarto python node web" ]'
{ echo "cd /tmp/us; W=$W"; declare -f parts_of; echo 'PO_PLATFORM=mac PO_CHOOSE=0 parts_of "" /dev/tty'; } > "$W/ask3.sh"
rm -rf "$W/ps"; mkdir -p "$W/ps"; echo "r web" > "$W/ps/parts.txt"; printf 'no\nno\nno\n' | script -qec "bash $W/ask3.sh" /dev/null > "$W/p.txt" 2>&1
check "Mac, saved 'r web', answers no/no/no: the website tools are not kept (Node.js, which they brought, stays)" 'grep -q "PARTS=\[r node\]" "$W/p.txt"'
rm -rf "$W/ps"; mkdir -p "$W/ps"; echo all > "$W/ps/parts.txt"; printf 'yes\nno\n\n\n\n' | script -qec "bash $W/ask3.sh" /dev/null > "$W/p.txt" 2>&1
check "Mac, older 'all', answers yes/no/(Enter x3): asked once, website tools only" 'grep -q "offers three more optional parts" "$W/p.txt" && grep -q "PARTS=\[r rstudio quarto python node vscode web\]" "$W/p.txt" && [ -f "$W/ps/asked.txt" ]'
{ echo "cd /tmp/us; W=$W"; declare -f parts_of; echo 'PO_PLATFORM=$1 parts_of "" /dev/tty'; } > "$W/ask2.sh"
rm -rf "$W/ps"; printf '7\n6\nno\nno\nno\n' | script -qec "bash $W/ask2.sh mac" /dev/null > "$W/p.txt" 2>&1
check "Mac, asked: VS Code is number 6, 7 is refused" 'grep -Eq "6\. VS Code \(code editor; OpenCode, Python and R add-ons\) +about 1\.0 GB" "$W/p.txt" && grep -q "0 to 6" "$W/p.txt" && grep -q "PARTS=\[vscode\]" "$W/p.txt"'
rm -rf "$W/ps"; printf '6\n\nno\nno\nno\n' | script -qec "bash $W/ask2.sh linux" /dev/null > "$W/p.txt" 2>&1
check "Linux, asked: VS Code not in the list, 6 is refused" '! grep -q "VS Code" "$W/p.txt" && grep -q "0 to 5" "$W/p.txt"'

make_state; mkdir -p "$W/dotvscode"; echo "r rstudio quarto python node vscode" > "$MS_STATE_DIR/parts.txt"
printf '%s\n' "vscode${T}vsext${T}sst-dev.opencode" "vscode${T}vsext${T}ms-python.python" "vscode${T}cask${T}visual-studio-code" \
  "vscode${T}dir${T}$W/dotvscode" >> "$MS_STATE_DIR/installed.tsv"
rc="$(un '' --parts=vscode --yes)"; L="$(logof)"
check "vscode: exit 0 ($rc)" '[ "$rc" = 0 ]'
check "vscode: each recorded add-on removed with VS Code's own command" '[ "$(printf "%s\n" "$L" | grep -c "would run: code --uninstall-extension \(sst-dev.opencode\|ms-python.python\)$")" = 2 ]'
check "vscode: the add-ons before VS Code itself, which goes as a Homebrew cask" 'printf "%s" "$L" | grep -q "would run: brew uninstall --cask visual-studio-code" && [ "$(printf "%s\n" "$L" | grep -n "uninstall-extension" | head -1 | cut -d: -f1)" -lt "$(printf "%s\n" "$L" | grep -n "visual-studio-code" | head -1 | cut -d: -f1)" ]'
check "vscode: its settings folder gone, everything else untouched" '[ ! -e "$W/dotvscode" ] && [ -d "$W/RStudio.app" ] && [ -d "$MS_STATE_DIR/pack" ]'
check "vscode: record and parts no longer list it" '! rec | grep -q "^vscode" && [ "$(cat "$MS_STATE_DIR/parts.txt")" = "r rstudio quarto python node" ]'
make_state; un '|' >/dev/null
check "vscode: not offered when the setup did not add anything to VS Code" '! grep -q "VS Code" "$W/out.txt"'
make_state; V="$W/vsc"; mkdir -p "$V/ext/sst-dev.opencode-1.0.0" "$V/ext/ms-python.python-2026.10.0" "$V/ext/someone.mine-1.0.0"
printf '%s\n' "vscode${T}vsext${T}sst-dev.opencode" "vscode${T}vsext${T}ms-python.python" >> "$MS_STATE_DIR/installed.tsv"
export MS_TEST_CODE_DIR="$V" MS_TEST_NO_CODE=1; rc="$(un '' --parts=vscode --yes)"; unset MS_TEST_CODE_DIR MS_TEST_NO_CODE
check "vscode gone: the recorded add-on folders deleted ($rc)" '[ "$rc" = 0 ] && [ ! -e "$V/ext/sst-dev.opencode-1.0.0" ] && [ ! -e "$V/ext/ms-python.python-2026.10.0" ]'
check "vscode gone: an add-on the student added stays, VS Code itself not touched" '[ -d "$V/ext/someone.mine-1.0.0" ] && ! logof | grep -q visual-studio-code'

echo "RESULT pass=$pass fail=$failn"; [ "$failn" = 0 ]
