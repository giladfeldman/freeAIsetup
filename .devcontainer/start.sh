#!/bin/bash
# Runs every time the Codespace starts: OpenCode and RStudio as browser tabs first, then the course-pack update
# check in the background, so a slow or stuck update can never stop the programs from starting.
# Everything is logged to /tmp/start.log.
#
# Every program is started with setsid -f (its own session): the Codespace ends whatever this script started
# when the script exits. OpenCode web vanished that way on the first start of a new Codespace (2026-11-10:
# "opencode web started" in the log, no process, empty log); RStudio survived only because it detaches itself.
exec >>/tmp/start.log 2>&1
echo "== start.sh $(date -u +%FT%TZ)"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"
COURSE="${METASCIENCE_DIR:-/workspaces/MetaScience}"
PACK="${XDG_DATA_HOME:-$HOME/.local/share}/metascience/pack"
mkdir -p "$COURSE"
# The start page (port 4000): big buttons for tablets, the AI status, OpenRouter sign-in. It opens inside the
# Codespace window (devcontainer.json: openPreview), so no pop-up blocker is involved.
if ! pgrep -f "startpage/server.py" >/dev/null; then
  setsid -f python3 "$HERE/startpage/server.py" > /tmp/startpage.log 2>&1
  echo "start page started on 4000"
fi
# RStudio Server (the rocker feature installs it; single user, no password inside the private Codespace).
# Behind the Codespaces proxy RStudio's sign-in redirect points at localhost:8787, so RStudio listens on 8788
# and a small relay on 8787 (rstudio-nginx.conf) makes its redirects relative. No nginx: RStudio on 8787 directly.
if command -v rserver >/dev/null && ! pgrep -x rserver >/dev/null; then
  if command -v nginx >/dev/null; then
    setsid -f rserver --www-port=8788 --www-address=127.0.0.1 > /tmp/rstudio.log 2>&1
    pgrep -f "nginx -c $HERE/rstudio-nginx.conf" >/dev/null || setsid -f nginx -c "$HERE/rstudio-nginx.conf" -e /tmp/rstudio-nginx-error.log
    echo "rserver started on 8788 behind the relay on 8787"
  else
    setsid -f rserver > /tmp/rstudio.log 2>&1
    echo "rserver started on 8787 (no relay: nginx missing)"
  fi
else
  echo "rserver: $(command -v rserver || echo 'not installed'), already running: $(pgrep -x rserver | tr '\n' ' ')"
fi
# OpenCode's web interface (the same assistant as the desktop app), working in the course folder
if command -v opencode >/dev/null && ! pgrep -f "^opencode web" >/dev/null; then
  (cd "$COURSE" && setsid -f opencode web --port 4096 --hostname 0.0.0.0 > /tmp/opencode-web.log 2>&1)
  echo "opencode web started"
fi
# Course-pack update check, in the background
if [ -x "$PACK/update/update.sh" ]; then
  setsid -f bash "$PACK/update/update.sh" --auto > /tmp/update.log 2>&1
  echo "update check started"
fi
# Self-check of what the student opens (the setup's own check tests the command line, not these pages)
sleep 8
for p in 4000 4096 8787; do
  r="$(curl -s -o /dev/null -m 10 -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$p/")"
  echo "port $p: ${r:-no answer}"
done
exit 0
