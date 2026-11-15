"""PowerShell variable names ignore case: $l overwrites $L, $removeCourse overwrites the -RemoveCourse switch.
Both happened (2026-11-15: the VM disk measure printed install-record lines as folder paths; -RemoveCourse never
deleted the course folder). This flags every tracked .ps1 that spells one variable name two ways. It reads the
raw text, so code inside here-strings (the VM tests send whole scripts that way) is checked too.
  python tests/ps_case_names.py            -> RESULT pass=N fail=M (exit 1 on any FAIL)
  python tests/ps_case_names.py --self-test
"""
import re
import subprocess
import sys
from collections import defaultdict

VAR = re.compile(r"\$(?:script:|global:|local:|env:)?([A-Za-z_][A-Za-z0-9_]*)")


def clashes(text):
    names = defaultdict(set)
    for m in VAR.finditer(text):
        if text[m.start() - 1:m.start()] == "`":   # `$x inside a double-quoted string is literal text
            continue
        names[m.group(1).lower()].add(m.group(1))
    return {k: sorted(v) for k, v in names.items() if len(v) > 1}


def self_test():
    bad = "$L = 1\nforeach ($l in 1..2) { $l }\n"
    good = "$L = 1\nforeach ($rec in 1..2) { $rec; `$l }\n"
    ok = clashes(bad) == {"l": ["L", "l"]} and clashes(good) == {}
    print("PASS self-test" if ok else "FAIL self-test")
    return 0 if ok else 1


def main():
    if "--self-test" in sys.argv:
        return self_test()
    files = subprocess.run(["git", "ls-files", "*.ps1"], capture_output=True, text=True, check=True).stdout.split()
    if not files:
        print("FAIL no .ps1 files found (wrong folder?)")
        return 1
    fail = 0
    for f in files:
        c = clashes(open(f, encoding="utf-8-sig", errors="replace").read())
        if c:
            fail += 1
            print(f"FAIL {f}: " + "; ".join("/".join("$" + n for n in v) for v in c.values()))
    print(f"RESULT pass={len(files) - fail} fail={fail}")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
