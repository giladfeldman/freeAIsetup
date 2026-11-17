#!/bin/bash
# Full real install on clean Ubuntu, including the AI step with OpenCode's no-account free model.
# Run inside the test image with the student-setup folder mounted read-only at /src.
set -u
export MS_LOG_ENV=local   # test runs never count as real installs or send real alerts
{ mkdir -p "$HOME/student-setup" && tar -C /src --exclude=./.claude/worktrees --exclude=./logs-worker/node_modules -cf - . | tar -C "$HOME/student-setup" -xf -; }            # students run it from a downloaded copy
cd "$HOME/student-setup"
bash setup-mac.sh --yes --no-gui "$@"; rc=$?
echo "SETUP_EXIT=$rc"
if [ "$rc" != 0 ]; then echo "--- AI attempts from the setup log ---"; L=$(ls -t "${TMPDIR:-/tmp}"/metascience-setup-*.log | head -1); awk '/===== opencode run attempt/{p=1} /===== python check/{p=0} p' "$L" | tail -80; fi
echo "--- second run must be a fast repair-only pass ---"
start=$(date +%s); bash setup-mac.sh --check --skip-ai > /tmp/check2.txt 2>&1; rc2=$?; cat /tmp/check2.txt; echo "CHECK_EXIT=$rc2 seconds=$(( $(date +%s) - start ))"
# the same shell has not read the start-up files the install wrote: the check still finds the tools in the folders
# the setup added (2026-11-17: Node.js and the website tools were "not found", and the website tools not checked)
rc3=0; for t in node gh vercel neonctl railway; do
  if grep -Eq "^ *OK +$t " /tmp/check2.txt; then echo "PASS second check finds $t"; else echo "FAIL second check finds $t"; rc3=1; fi; done
echo "--- report ---"; cat "$HOME/MetaScience/setup-report.txt"
[ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$rc3" = 0 ]
