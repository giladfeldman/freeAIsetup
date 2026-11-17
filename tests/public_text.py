"""This repository is public: no tracked file may name the owner's own folders or other private work.

    python tests/public_text.py            # every tracked file (the working copy)
    python tests/public_text.py FILE ...   # only these files (used to watch it fail on an old copy)

Ends with RESULT pass=N fail=N. Found 2026-11-17: TODO.md source notes named a course's lecture folders.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# folder shapes from the owner's own computer; each is a whole path segment, so ordinary words do not match
# The folder names are read at run time (the two folders this checkout sits in, and the home folder of whoever
# runs the test), so no private name is written into this public file.
OUTER = [ROOT.parent.name, ROOT.parent.parent.name]
HOME = pathlib.Path.home().name
PATTERNS = [(re.compile(r"\bLectures/\d\d-"), "a course lecture folder")] + [
    (re.compile(r"(?<![\w.-])" + re.escape(d) + r"[\\/]"), "a folder this checkout sits in") for d in OUTER] + [
    (re.compile(r"Users[\\/]" + re.escape(HOME) + r"(?![\w.-])", re.I), "this computer's home folder"),
]
SELF = pathlib.Path(__file__).resolve()


def scan(paths):
    hits = []
    for p in paths:
        if p.resolve() == SELF or not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue   # binary files (the .docx guide is built from walkthrough.md, which is scanned)
        for n, line in enumerate(text.splitlines(), 1):
            for rx, what in PATTERNS:
                if rx.search(line):
                    hits.append(f"{p.relative_to(ROOT) if p.is_relative_to(ROOT) else p}:{n}: {what}")
    return hits


def main():
    if len(sys.argv) > 1:
        paths = [pathlib.Path(a).resolve() for a in sys.argv[1:]]
    else:
        out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
        paths = [ROOT / f for f in out.splitlines()]
    # control: each pattern must fire on a planted example, so a broken pattern cannot pass silently
    planted = ["see Lectures/05-Week/x.md"] + [f"in {d}/x" for d in OUTER] + ["C:\\Users\\" + HOME + "\\x"]
    dead = [what for (rx, what), s in zip(PATTERNS, planted) if not rx.search(s)]
    hits = scan(paths)
    for h in hits:
        print("FAIL", h)
    for d in dead:
        print("FAIL control: pattern for", d, "does not fire on its planted example")
    fail = len(hits) + len(dead)
    print(f"RESULT pass={len(paths) - len(hits)} fail={fail}")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
