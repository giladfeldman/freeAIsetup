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
bash setup-mac.sh --yes --no-gui --no-auto-update 2>&1 | tee /tmp/metascience-create.log
# RStudio opens in the course folder
mkdir -p "$HOME/.config/rstudio"
printf '{ "initial_working_directory": "%s" }\n' "${METASCIENCE_DIR:-/workspaces/MetaScience}" > "$HOME/.config/rstudio/rstudio-prefs.json"
# the small relay in front of RStudio (see rstudio-nginx.conf); without it start.sh runs RStudio directly
command -v nginx >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx-light >> /tmp/metascience-create.log 2>&1 \
  || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >> /tmp/metascience-create.log 2>&1
sudo service nginx stop >/dev/null 2>&1   # the package's own web server on port 80 is not needed
exit 0   # a failed check is shown in the log and setup-report.txt; it must not stop the Codespace from opening
