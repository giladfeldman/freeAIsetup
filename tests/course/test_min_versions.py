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
    ("opencode", "0.1.0", False),          # not in the table: never a warning
    ("git", "", False),                    # unknown version: never a warning
]

fails = 0
for tool, line, warn in CASES:
    got = cs.too_old(tool, line)
    ok = bool(got) == warn
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {tool:8} {line!r:45} -> {got or 'ok'}")
print(f"RESULT pass={len(CASES) - fails} fail={fails}")
sys.exit(fails)
