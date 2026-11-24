"""The privacy texts students read must describe what the log box really stores (2026-11-24: the guide's "Privacy
rules" still described the old once-per-account install count after every run began sending a result).

Reads the fields the log box keeps for each run from `normalizeResult` in logs-worker/src/alerts.js and requires
both the README's "Privacy" section and the guide's "Privacy rules" to describe every one of them, and neither to
describe the old message. A new stored field without words for it in both texts fails here.

    python tests/privacy_docs.py [--root <folder>]
"""
import argparse
import pathlib
import re
import sys

# how a student-facing text names each stored field (any one phrase is enough)
WORDS = {
    "platform": ["Windows, Mac, Linux or Codespace"],
    "version": ["version"],
    "os": ["system's name and version", "operating\nsystem's name", "operating system"],
    "arch": ["processor"],
    "outcome": ["whether it worked"],
    "stage": ["how far it got", "how\n  far it got"],
    "mode": ["first install"],
    "parts": ["optional parts"],
    "minutes": ["minutes"],
    "issues": ["failed or warned"],
}
STALE = ["once per computer account", "A count of successful installs", "says only that an install succeeded"]
REMOVED = ["user name", "computer name", "home folder", "e-mail addresses"]


def section(text, heading):
    m = re.search(r"(?m)^#+ " + re.escape(heading) + r"\s*$", text)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(r"(?m)^#{1,2} ", rest)
    return rest[: n.start()] if n else rest


def norm(s):
    return re.sub(r"\s+", " ", s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    root = pathlib.Path(ap.parse_args().root)
    passed = failed = 0

    def check(ok, name, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1; print(f"PASS {name}")
        else:
            failed += 1; print(f"FAIL {name}  {detail}")

    src = (root / "logs-worker/src/alerts.js").read_text(encoding="utf-8")
    body = re.search(r"export function normalizeResult[\s\S]*?return \{ rec: \{([\s\S]*?)\} \};", src)
    fields = re.findall(r"(?:^|[\s,{])([a-z]+)(?=[:,])", body.group(1)) if body else []
    fields = [f for f in dict.fromkeys(fields)]
    check(len(fields) >= 8, "read the stored fields from normalizeResult", ", ".join(fields))
    unknown = [f for f in fields if f not in WORDS]
    check(not unknown, "every stored field has student words in this test", "add words for: " + ", ".join(unknown))

    texts = {
        "README Privacy": section((root / "README.md").read_text(encoding="utf-8"), "Privacy"),
        "guide Privacy rules": section((root / "guide/walkthrough.md").read_text(encoding="utf-8"), "Privacy rules"),
    }
    for name, t in texts.items():
        check(len(t) > 300, f"{name}: section found", f"{len(t)} chars")
        flat = norm(t)
        missing = [f for f in fields if f in WORDS and not any(norm(w) in flat for w in WORDS[f])]
        check(not missing, f"{name}: describes every stored field", "missing: " + ", ".join(missing))
        stale = [s for s in STALE if norm(s) in flat]
        check(not stale, f"{name}: no description of the old install count", "; ".join(stale))
        gone = [r for r in REMOVED if r not in flat]
        check(not gone, f"{name}: says what is removed first", "missing: " + ", ".join(gone))
        check("MS_NO_COUNT=1" in flat, f"{name}: says how to switch it off")
    print(f"RESULT pass={passed} fail={failed}")
    return failed


if __name__ == "__main__":
    sys.exit(main())
