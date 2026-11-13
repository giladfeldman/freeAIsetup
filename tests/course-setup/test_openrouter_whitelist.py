"""The OpenRouter free-model list in opencode.json must come out non-empty on a fresh computer.

Runs lib/course_setup.write_config with the real `opencode` on PATH, inside a throw-away home folder that holds no
OpenCode sign-ins (a student's first run, a new Codespace) and a fake OpenRouter key. The model list comes from
OpenCode's catalogue, so the fake key is never sent anywhere.

Origin 2026-11-13: the list was taken in a bare temporary folder, where OpenCode does not know the key, so it found
no OpenRouter models and wrote "whitelist": [], which hides every OpenRouter model ("Provider not found").
Developer machines passed because OpenCode had its own OpenRouter sign-in stored there.

Usage: python tests/course-setup/test_openrouter_whitelist.py   (needs `opencode` on PATH; exit 0 = PASS)
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def main() -> int:
    if not shutil.which("opencode"):
        print("FAIL opencode not on PATH: this test needs the real OpenCode")
        return 1
    home = pathlib.Path(tempfile.mkdtemp(prefix="ms-orwl-"))
    try:
        for var, sub in (("HOME", ""), ("USERPROFILE", ""), ("XDG_CONFIG_HOME", ".config"),
                         ("XDG_DATA_HOME", ".local/share"), ("XDG_CACHE_HOME", ".cache"),
                         ("XDG_STATE_HOME", ".local/state")):
            os.environ[var] = str(home / sub) if sub else str(home)
        os.environ.pop("OPENROUTER_API_KEY", None)
        sys.path.insert(0, str(ROOT / "lib"))
        import course_setup as cs   # imported after HOME is set: KEY_DIR comes from the home folder

        if not str(cs.KEY_DIR).startswith(str(home)):
            print(f"FAIL key folder is not inside the test home: {cs.KEY_DIR}")
            return 1
        cs.save_key("openrouter", "sk-or-v1-test-not-a-real-key")
        course = home / "MetaScience"
        target = cs.write_config(course, log=lambda m: print("  log:", m))
        cfg = json.loads(target.read_text(encoding="utf-8"))
        wl = cfg.get("provider", {}).get("openrouter", {}).get("whitelist")
        checks = [
            ("openrouter is in the settings", "openrouter" in cfg.get("provider", {})),
            ("the free-model list is not empty", bool(wl)),
            ("every listed model is a free one", bool(wl) and all(m.endswith(":free") for m in wl)),
        ]
        listed = cs.list_models("openrouter", course)
        checks.append(("OpenCode shows OpenRouter models in the course folder", bool(listed)))
        bad = 0
        for name, ok in checks:
            print(("PASS " if ok else "FAIL ") + name)
            bad += not ok
        print(f"  whitelist: {len(wl or [])} models; listed in course folder: {len(listed)}")
        print("ALL PASS" if not bad else f"{bad} FAILED")
        return 1 if bad else 0
    finally:
        shutil.rmtree(home, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
