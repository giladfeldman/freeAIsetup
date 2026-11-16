"""Old tools kept by the setup are flagged in the check step (d-f160b5). One case per tool, with the real
first line each tool prints. Run:  python tests/course/test_min_versions.py   (exit code = failures)"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "lib"))
import course_setup as cs  # noqa: E402

CASES = [   # tool, first line of "<tool> --version", should it warn
    ("git", "git version 2.33.1.windows.1", True),
    ("git", "git version 2.34.1.windows.1", False),
    ("git", "git version 2.56.0.windows.4", False),
    ("node", "v18.20.4", True),
    ("node", "v20.0.0", False),
    ("node", "v26.12.1", False),
    ("uv", "uv 0.2.37 (d2ca79a5f 2024-08-14)", True),
    ("uv", "uv 0.3.0", False),
    ("uv", "uv 0.9.5 (d5f39331a 2025-10-21)", False),
    ("Rscript", "Rscript (R) version 4.4.0 (2024-04-24)", True),
    ("Rscript", "Rscript (R) version 4.5.0 (2025-04-11)", False),
    ("quarto", "0.9.230", True),
    ("quarto", "1.0.38", False),
    ("quarto", "1.10.18", False),
    ("code", "1.94.2", True),             # VS Code: its first line is the bare version
    ("code", "1.100.3", True),            # the R add-on 3.4.0 needs 1.101 (VS Code 1.95 got the R add-on 2.8.8)
    ("code", "1.101.0", False),
    ("code", "1.146.0", False),
    ("opencode", "0.1.0", False),          # not in the table: never a warning
    ("git", "", False),                    # unknown version: never a warning
]

fails = 0
for tool, line, warn in CASES:
    got = cs.too_old(tool, line)
    ok = bool(got) == warn
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {tool:8} {line!r:45} -> {got or 'ok'}")
# the VS Code add-on row: missing and older-than-tested add-ons, read from "code --list-extensions --show-versions"
UP = "sst-dev.opencode@1.0.0\nms-python.python@2026.10.0\nms-python.vscode-pylance@2026.4.1\nreditorsupport.r@3.4.0\n"
ADDONS = [
    ("all there and current, R chosen", UP, ("r", "vscode"), [], []),
    ("upper-case ids and Windows line ends", UP.upper().replace("\n", "\r\n"), ("r", "vscode"), [], []),
    ("R add-on missing, R chosen", UP.replace("reditorsupport.r@3.4.0\n", ""), ("r", "vscode"), ["reditorsupport.r"], []),
    ("R add-on missing, R not chosen: not wanted", UP.replace("reditorsupport.r@3.4.0\n", ""), ("vscode",), [], []),
    ("Python add-on older than tested", UP.replace("2026.10.0", "2025.2.0"), ("r", "vscode"), [], ["ms-python.python"]),
    ("R add-on 2.8.8 (an old VS Code)", UP.replace("3.4.0", "2.8.8"), ("r", "vscode"), [], ["reditorsupport.r"]),
    ("newer than tested is fine", UP.replace("2026.10.0", "2027.1.0"), ("r", "vscode"), [], []),
    ("an unreadable version is left alone", UP.replace("1.0.0", "nightly"), ("r", "vscode"), [], []),
    ("VS Code did not answer: all wanted missing", "", ("vscode",), ["sst-dev.opencode", "ms-python.python"], []),
]
for name, listing, parts, want_missing, want_old in ADDONS:
    missing, old = cs.code_addon_rows(listing, parts)
    ok = missing == want_missing and [o.split()[0] for o in old] == want_old
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}  add-ons: {name} -> missing {missing}, old {old}")
# the log may be sent to the teacher: only the course's add-ons in it, the student's own as a count
LOG_IN = "sst-dev.opencode@1.0.0\nsomeone.private-tool@2.0.0\nMS-Python.Python@2026.10.0\nacme.employer-vpn@1.1.0\n"
got = cs.course_addon_log(LOG_IN)
logcase = ("sst-dev.opencode@1.0.0" in got and "MS-Python.Python@2026.10.0" in got and "someone" not in got
           and "acme" not in got and "(+ 2 other add-ons, not listed)" in got)
print(("PASS" if logcase else "FAIL") + " log: only the course add-ons, the student's own as a count")
fails += 0 if logcase else 1
print(f"RESULT pass={len(CASES) + len(ADDONS) + 1 - fails} fail={fails}")
sys.exit(fails)
