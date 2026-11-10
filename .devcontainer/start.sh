#!/bin/bash
# Runs every time the Codespace starts: OpenCode and RStudio as browser tabs first, then the course-pack update
# check in the background, so a slow or stuck update can never stop the programs from starting.
# Everything is logged to /tmp/start.log (first creation 2026-11-10 left RStudio stopped with no trace).
exec >>/tmp/start.log 2>&1
echo "== start.sh $(date -u +%FT%TZ)"
export PATH="$HOME/.local/bin:$PATH"
COURSE="${METASCIENCE_DIR:-/workspaces/MetaScience}"
PACK="${XDG_DATA_HOME:-$HOME/.local/share}/metascience/pack"
mkdir -p "$COURSE"
# RStudio Server (the rocker feature installs it; single user, no password inside the private Codespace)
if command -v rserver >/dev/null && ! pgrep -x rserver >/dev/null; then
  nohup rserver > /tmp/rstudio.log 2>&1 &
  echo "rserver started"
else
  echo "rserver: $(command -v rserver || echo 'not installed'), already running: $(pgrep -x rserver || echo no)"
fi
# OpenCode's web interface (the same assistant as the desktop app), working in the course folder
if ! pgrep -f "opencode web" >/dev/null; then
  (cd "$COURSE" && nohup opencode web --port 4096 --hostname 0.0.0.0 > /tmp/opencode-web.log 2>&1 &)
  echo "opencode web started"
fi
# Course-pack update check, in the background
if [ -x "$PACK/update/update.sh" ]; then
  (nohup bash "$PACK/update/update.sh" --auto > /tmp/update.log 2>&1 &)
  echo "update check started"
fi
exit 0
