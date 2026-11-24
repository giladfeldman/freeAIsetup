"""Nothing of this kit may run on its own: no tracked file creates, starts or relies on a scheduled task, a login
item, a crontab line or a start-up entry (owner, 2026-11-24: "definitely nothing running in the background because of
us"). Older setups added a daily update task that opened a terminal window on students' computers; the setup, the
updater and the uninstallers now only remove it.

    python tests/no_background.py [--root <folder>]

Allowed, by file and line: the VM test harness (it runs its own 'mstest-*' tasks inside a throwaway test machine,
never on a student's computer) and the rollback refusal, which names the old code as text to recognise it.
"""
import argparse
import pathlib
import re
import subprocess
import sys

# each pattern adds or starts something that runs without the student starting it
PATTERNS = [
    ("schtasks /create", re.compile(r"schtasks(\.exe)?\b.*(/create|'/create')", re.I)),
    ("Register/Start-ScheduledTask", re.compile(r"\b(Register|Start|New)-ScheduledTask", re.I)),
    ("launchctl load/bootstrap", re.compile(r"\blaunchctl\s+(load|bootstrap|submit|kickstart|enable)\b")),
    ("adds a crontab line", re.compile(r"crontab\s+-l\s*;|echo .*\|\s*crontab\s+-")),
    ("writes a LaunchAgent", re.compile(r"(>|tee|cp|cat\s*>).*LaunchAgents/|LaunchAgents/[^\s\"']*\.plist[\"']?\s*<<")),
    ("Windows Run key / Startup folder", re.compile(r"CurrentVersion\\+Run\b|Start Menu\\+Programs\\+Startup|shell:startup", re.I)),
    ("systemd timer", re.compile(r"systemctl\s+(--user\s+)?enable|\.timer\b")),
]
# (file, text the line must contain) pairs that are allowed
ALLOWED = [
    ("tests/vm/real-install.ps1", "ScheduledTask"),        # VM harness, inside the test machine
    ("tests/vm/run-case.ps1", "ScheduledTask"),
    ("update/update.ps1", "$adds = @(@{ f = 'setup-windows.ps1'; t = \"@('/create', '/tn'\""),   # rollback refusal markers
    ("update/update.sh", "grep -qF \"@('/create', '/tn'\""),
    ("tests/update/test_update.py", "marker"),            # the refusal test plants the old code's lines
    ("tests/update/test_update.py", '("setup-mac.sh", '),
    ("tests/no_background.py", ""),                       # this file
]


def scan(root):
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split()
    files = [f for f in files if f.endswith((".ps1", ".sh", ".py", ".cmd", ".bat", ".js", ".json", ".plist", ".toml"))]
    hits = []
    for f in files:
        p = pathlib.Path(root) / f
        if not p.is_file():
            continue
        for n, line in enumerate(p.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            for name, rx in PATTERNS:
                if rx.search(line) and not any(f == af and at in line for af, at in ALLOWED):
                    hits.append(f"{f}:{n}: {name}: {line.strip()[:110]}")
    return files, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    a = ap.parse_args()
    passed = failed = 0
    files, hits = scan(a.root)
    for ok, name, detail in (
        (len(files) > 50, "the scan saw the repository's scripts", f"{len(files)} files"),
        (not hits, "no tracked file creates or starts a background job", "\n  ".join(hits)),
    ):
        if ok:
            passed += 1; print(f"PASS {name}")
        else:
            failed += 1; print(f"FAIL {name}\n  {detail}")
    # control: every pattern must fire on the old code it exists for
    samples = {
        "schtasks /create": "$code = Run-Native 'schtasks.exe' @('/create', '/tn', \"x\", '/xml')",
        "Register/Start-ScheduledTask": "Start-ScheduledTask -TaskName 'MetaScience pack update'",
        "launchctl load/bootstrap": 'launchctl unload "$plist"; launchctl load "$plist"',
        "adds a crontab line": "( crontab -l; echo \"30 12 * * * bash x --auto # freeaisetup-update\" ) | crontab -",
        "writes a LaunchAgent": 'cat > "$HOME/Library/LaunchAgents/org.x.plist" <<EOF',
        "Windows Run key / Startup folder": r"New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name x",
        "systemd timer": "systemctl --user enable freeaisetup.timer",
    }
    missed = [n for n, rx in PATTERNS if not rx.search(samples[n])]
    if missed:
        failed += 1; print("FAIL control: a pattern does not fire on its sample: " + ", ".join(missed))
    else:
        passed += 1; print(f"PASS control: all {len(PATTERNS)} patterns fire on their samples")
    print(f"RESULT pass={passed} fail={failed}")
    return failed


if __name__ == "__main__":
    sys.exit(main())
