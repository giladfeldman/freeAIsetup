#!/bin/bash
# Runs once, when the student's Codespace is created: the normal course setup, unattended.
# --no-gui: no desktop apps (RStudio and OpenCode open as browser tabs instead, see start.sh).
# --no-auto-update: a Codespace has no daily scheduler; start.sh checks for updates at every start.
cd "$(dirname "$0")/.." || exit 1
# The course folder lives next to (not inside) this repository: inside a git repository, OpenCode would treat
# the whole repository as the project and could edit the kit's own files. /workspaces survives rebuilds.
sudo mkdir -p /workspaces/MetaScience && sudo chown "$(id -u):$(id -g)" /workspaces/MetaScience
# a shortcut in the file list on the left, so students can open and download their course files there
ln -sfn /workspaces/MetaScience MetaScience
# The start page right away (not only after the setup): the link in START-HERE.md works during the 15-25 minute setup,
# and the page says the setup is still running while this marker exists. setsid -f: it must outlive this script.
SETUP_MARK="$HOME/.local/state/metascience/setup-running"   # outside the course folder: students never see it
mkdir -p "$(dirname "$SETUP_MARK")"
date -u +%FT%TZ > "$SETUP_MARK"
trap 'rm -f "$SETUP_MARK"' EXIT   # also when the setup fails or is stopped
pgrep -f "startpage/server.py" >/dev/null || setsid -f python3 .devcontainer/startpage/server.py > /tmp/startpage.log 2>&1
bash setup-mac.sh --yes --no-gui --no-auto-update 2>&1 | tee /tmp/metascience-create.log
# RStudio opens in the course folder
mkdir -p "$HOME/.config/rstudio"
printf '{ "initial_working_directory": "%s" }\n' "${METASCIENCE_DIR:-/workspaces/MetaScience}" > "$HOME/.config/rstudio/rstudio-prefs.json"
# the small relay in front of RStudio (see rstudio-nginx.conf); without it start.sh runs RStudio directly
command -v nginx >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx-light >> /tmp/metascience-create.log 2>&1 \
  || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >> /tmp/metascience-create.log 2>&1
sudo service nginx stop >/dev/null 2>&1   # the package's own web server on port 80 is not needed
exit 0   # a failed check is shown in the log and setup-report.txt; it must not stop the Codespace from opening
