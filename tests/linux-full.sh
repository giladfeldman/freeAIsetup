#!/bin/bash
# Full real install on clean Ubuntu, including the AI step with OpenCode's no-account free model.
# Run inside the test image with the student-setup folder mounted read-only at /src.
set -u
export MS_LOG_ENV=local   # test runs never count as real installs or send real alerts
cp -r /src "$HOME/student-setup"            # students run it from a downloaded copy
cd "$HOME/student-setup"
bash setup-mac.sh --yes --no-gui "$@"; rc=$?
echo "SETUP_EXIT=$rc"
if [ "$rc" != 0 ]; then echo "--- AI attempts from the setup log ---"; L=$(ls -t "${TMPDIR:-/tmp}"/metascience-setup-*.log | head -1); awk '/===== opencode run attempt/{p=1} /===== python check/{p=0} p' "$L" | tail -80; fi
echo "--- second run must be a fast repair-only pass ---"
start=$(date +%s); bash setup-mac.sh --check --skip-ai; rc2=$?; echo "CHECK_EXIT=$rc2 seconds=$(( $(date +%s) - start ))"
echo "--- report ---"; cat "$HOME/MetaScience/setup-report.txt"
[ "$rc" = 0 ] && [ "$rc2" = 0 ]
