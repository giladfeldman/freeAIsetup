"""Bring lib/free-ai.json up to date with the free AIs the maintainer approved for the student pack.

  python tools/sync_free_ai.py            show what would change (nothing is written)
  python tools/sync_free_ai.py --write    write lib/free-ai.json; it reaches students with the next signed release (/ship)

The approvals list is public and read-only (no token). Whatever it returns must pass the pack's own checks
(lib/course_setup.free_ai_problems: never Anthropic, never a provider that needs a card, OpenRouter only :free, ...);
a list that fails them is refused and the current file is kept.
Exit codes: 0 no change or written, 2 a change is waiting (without --write), 1 the list could not be read or was refused.
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lib"))
from course_setup import FREE_AI_FILE, free_ai_problems  # noqa: E402

# the address of the approvals list; kept out of this public repository, set on the maintainer's computer
URL = os.environ.get("FREE_AI_LIST_URL", "")
KEEP = ("opencode_free", "opencode_free_eu_unavailable", "providers")


def main() -> int:
    write = "--write" in sys.argv
    if not URL:
        print("set FREE_AI_LIST_URL to the approvals list address first; lib/free-ai.json kept")
        return 1
    try:
        with urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "freeAIsetup-sync"}), timeout=30) as r:
            new = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"the gateway has no student-pack list yet (HTTP {e.code} from {URL}); lib/free-ai.json kept")
        return 1
    except Exception as e:  # network, bad JSON
        print(f"could not read the gateway list ({e}); lib/free-ai.json kept")
        return 1
    problems = free_ai_problems(new)
    if problems:
        print("REFUSED: the gateway list fails the pack's checks; lib/free-ai.json kept")
        for p in problems:
            print("  -", p)
        return 1
    old = json.loads(FREE_AI_FILE.read_text(encoding="utf-8"))
    if all(old.get(k) == new.get(k) for k in KEEP):
        print(f"no change (gateway list version {new.get('version')})")
        return 0
    for k in KEEP:
        if old.get(k) != new.get(k):
            print(f"changed: {k}")
    if not write:
        print("run with --write to update lib/free-ai.json, then release it with /ship")
        return 2
    doc = {"version": new.get("version"), "updated": new.get("updated"),
           "source": f"tools/sync_free_ai.py from {URL}", **{k: new.get(k) for k in KEEP if k in new}}
    FREE_AI_FILE.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {FREE_AI_FILE}; release it with /ship")
    return 0


if __name__ == "__main__":
    sys.exit(main())
