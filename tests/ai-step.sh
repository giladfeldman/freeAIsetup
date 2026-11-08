#!/bin/bash
# Reproduces only the AI step of the check, exactly as course_setup.py runs it, for the current user.
export PATH=/opt/oc:$PATH
rm -rf "$HOME/MetaScience"; cp -r /src/course-kit "$HOME/MetaScience"
python3 /src/lib/course_setup.py config --course "$HOME/MetaScience"
cd "$HOME/MetaScience" && python3 - <<'PY'
import sys, pathlib
sys.path.insert(0, "/src/lib")
import course_setup as cs
code, out = cs.sh(["opencode", "run", "--auto", "Follow the instructions in the file check/check-task.md exactly."], cwd=pathlib.Path.cwd(), timeout=420)
print("exit", code); print(out[-3000:])
print("extract exists:", (pathlib.Path("check/out/extract.csv")).is_file())
PY
