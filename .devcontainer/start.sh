#!/bin/bash
# Runs every time the Codespace starts: course-pack update check, then OpenCode and RStudio as browser tabs.
export PATH="$HOME/.local/bin:$PATH"
COURSE="${METASCIENCE_DIR:-/workspaces/MetaScience}"
PACK="${XDG_DATA_HOME:-$HOME/.local/share}/metascience/pack"
[ -x "$PACK/update/update.sh" ] && bash "$PACK/update/update.sh" --auto >/dev/null 2>&1
mkdir -p "$COURSE"
# OpenCode's web interface (the same assistant as the desktop app), working in the course folder
if ! pgrep -f "opencode web" >/dev/null; then
  (cd "$COURSE" && nohup opencode web --port 4096 --hostname 0.0.0.0 > /tmp/opencode-web.log 2>&1 &)
fi
# RStudio Server (the rocker feature installs it; single user, no password inside the private Codespace)
if command -v rserver >/dev/null && ! pgrep -x rserver >/dev/null; then
  nohup rserver > /tmp/rstudio.log 2>&1 &
fi
exit 0
