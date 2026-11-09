"""MetaScience course setup: the cross-platform part (Windows, macOS, Linux).

The shell scripts (setup-windows.ps1, setup-mac.sh) install the base tools; this file then
  config  writes <course>/opencode.json  (default free model, optional providers, MCP tools OFF)
  keys    guided clickthrough to add optional free AI keys
  check   real end-to-end task that uses every installed tool, and prints a green/red table

Standard library only. Run with:  uv run --no-project python lib/course_setup.py <command> --course <dir>
"""
from __future__ import annotations

import argparse
import datetime as dt
import getpass
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import threading
import webbrowser

SETUP_VERSION = "2026-11-07"
KEY_DIR = pathlib.Path.home() / ".config" / "metascience" / "keys"

# Preferred default models, best first. All are OpenCode free models that need no account.
# Chosen because OpenCode's model page (checked 2026-11-07) says their provider keeps no data
# and does not train on it, and they are available in the EU.
DEFAULT_MODEL_PREFERENCE = [
    "opencode/glm-5.3-flash-free",
    "opencode/deepseek-v4.1-flash-free",
]
EU_UNAVAILABLE = ["inkling-2-small-free", "crouton-alpha-free"]

# Optional providers: id, display name, key page, model-name hints for the key test (first match wins)
PROVIDERS = [
    ("openrouter", "OpenRouter", "https://openrouter.ai/keys", [":free"]),
    ("groq", "Groq", "https://console.groq.com/keys", ["gpt-oss-120b", "gpt-oss", "llama"]),
    ("google", "Google AI Studio (Gemini)", "https://aistudio.google.com/apikey", ["flash-lite", "flash"]),
    ("nvidia", "NVIDIA (build.nvidia.com)", "https://build.nvidia.com/settings/api-keys", ["nemotron", "gpt-oss", "llama"]),
    ("mistral", "Mistral", "https://console.mistral.ai/api-keys", ["mistral-small", "small"]),
]

# MCP tools: configured but switched OFF. A student switches one on by changing "enabled" to true.
# Each entry: name -> (command list, what it does). Commands run with uvx / npx / Rscript.
MCP_SERVERS = {
    "fetch": (["uvx", "mcp-server-fetch"], "read web pages as text (official MCP reference server)"),
    "markitdown": (["uvx", "markitdown-mcp"], "convert PDF/Word/Excel files to text (Microsoft)"),
    "papers": (["uvx", "paper-search-mcp"], "search and download papers: arXiv, PubMed, Crossref, OpenAlex, Semantic Scholar (community)"),
    "zotero": (["uvx", "zotero-mcp"], "read your Zotero library; Zotero must be open (community)"),
    "browser": (["npx", "-y", "@playwright/mcp@latest"], "control a web browser: open journal pages, click, download (Microsoft)"),
    "r": (["Rscript", "-e", "mcptools::mcp_server()"], "run R code in R / RStudio (Posit)"),
}

IS_WIN = os.name == "nt"


def exe(name: str) -> str | None:
    return shutil.which(name)


FREE_LIMIT = "free usage limit reached"   # OpenCode's free models refusing this internet address


def sh(cmd: list[str], cwd: pathlib.Path | None = None, timeout: int = 120,
       stop_on: tuple[str, ...] = ()) -> tuple[int, str]:
    """Run a command, return (exit code, combined output). Never raises.
    stop_on: lower-case phrases; when an output line contains one, the command is stopped (exit 125)."""
    found = exe(cmd[0])
    if not found:
        return 127, f"{cmd[0]} not found on PATH"
    env = None
    if cwd is not None:
        # OpenCode takes its project folder from $PWD, not the real working folder; Popen(cwd=...) leaves $PWD
        # pointing where the setup was started (Codemagic Mac 2026-11-09: the AI looked in the kit's own folder).
        env = dict(os.environ, PWD=str(pathlib.Path(cwd).resolve()))
    try:
        p = subprocess.Popen([found, *cmd[1:]], cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL)
    except OSError as e:
        return 126, str(e)
    # Read output on a thread and go by the command's own exit: a leftover child process (seen with
    # `uv run` on a fresh Windows account) can hold the output pipe open long after the command ended.
    chunks: list[str] = []
    hit = threading.Event()

    def read() -> None:
        for line in iter(p.stdout.readline, ""):
            chunks.append(line)
            if stop_on and any(s in line.lower() for s in stop_on):
                hit.set()

    def kill() -> None:  # the whole process tree, not just the parent
        if os.name == "nt":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)], capture_output=True)
        else:
            p.kill()

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    import time
    end = time.monotonic() + timeout
    while p.poll() is None and not hit.is_set() and time.monotonic() < end:
        time.sleep(0.5)
    if p.poll() is not None:
        reader.join(10)
        return p.returncode, "".join(chunks)
    kill()
    reader.join(5)
    if hit.is_set():
        return 125, "".join(chunks)
    return 124, f"timed out after {timeout}s. {''.join(chunks)}"


def list_models(provider: str, cwd: pathlib.Path) -> list[str]:
    code, out = sh(["opencode", "models", provider], cwd=cwd, timeout=120)
    if code != 0:
        return []
    return [ln.strip() for ln in out.splitlines() if ln.strip().startswith(provider + "/")]


def pick(models: list[str], hints: list[str]) -> str | None:
    for h in hints:
        for m in models:
            if h in m:
                return m
    return models[0] if models else None


def key_path(pid: str) -> pathlib.Path:
    return KEY_DIR / f"{pid}.key"


# ----------------------------------------------------------------------------- config
def write_config(course: pathlib.Path, log=print) -> pathlib.Path:
    course.mkdir(parents=True, exist_ok=True)
    free = list_models("opencode", course)
    default = next((m for m in DEFAULT_MODEL_PREFERENCE if m in free), None)
    if default is None:
        # catalogue rotated: take any free model that is not EU-excluded
        default = next((m for m in free if m.endswith("-free") and not any(x in m for x in EU_UNAVAILABLE)),
                       DEFAULT_MODEL_PREFERENCE[0])
        log(f"note: preferred free models not listed; using {default}")
    cfg: dict = {
        "$schema": "https://opencode.ai/config.json",
        "model": default,
        "instructions": ["AGENTS.md"],
        "share": "disabled",
        "autoupdate": False,
        "mcp": {name: {"type": "local", "command": cmd, "enabled": False}
                for name, (cmd, _desc) in MCP_SERVERS.items()},
    }
    providers = {}
    for pid, _name, _url, _hints in PROVIDERS:
        if key_path(pid).is_file() and key_path(pid).stat().st_size > 0:
            providers[pid] = {"options": {"apiKey": "{file:" + key_path(pid).as_posix() + "}"}}
    if providers:
        cfg["provider"] = providers
    target = course / "opencode.json"
    if target.exists():
        shutil.copyfile(target, target.with_suffix(".json.bak"))
    target.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    (course / "MCP-TOOLS.txt").write_text(
        "MCP tools available in this course (all switched OFF).\n"
        "To switch one on: open opencode.json, find the tool under \"mcp\", change\n"
        "\"enabled\": false  to  \"enabled\": true, save, and restart OpenCode.\n\n"
        + "\n".join(f"  {n:<11} {d}" for n, (_c, d) in MCP_SERVERS.items()) + "\n",
        encoding="utf-8")
    log(f"wrote {target} (default model {default}; optional providers: {', '.join(providers) or 'none'})")
    return target


# ----------------------------------------------------------------------------- keys
def key_wizard(course: pathlib.Path) -> None:
    print("\nOpenCode already works with its built-in free models (no account needed).")
    print("You can add more free AI services. For each one a web page opens:")
    print("  1. sign up with your UNIVERSITY email,  2. create a key,  3. copy it,  4. paste it here.")
    print("The key is hidden while you paste. Press Enter without pasting to skip a service.\n")
    KEY_DIR.mkdir(parents=True, exist_ok=True)
    for pid, name, url, _hints in PROVIDERS:
        have = key_path(pid).is_file()
        print(f"--- {name}: {url}" + ("   (a key is already saved; Enter keeps it)" if have else ""))
        try:
            webbrowser.open(url)
        except Exception:
            pass
        key = getpass.getpass(f"Paste the {name} key, then press Enter: ").strip()
        if key:
            key_path(pid).write_text(key, encoding="utf-8")
            if not IS_WIN:
                os.chmod(key_path(pid), 0o600)
            print(f"    saved {name} key")
    write_config(course)


# ----------------------------------------------------------------------------- check
class Table:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str, str]] = []

    def add(self, status: str, item: str, detail: str = "") -> None:
        self.rows.append((status, item, detail))
        mark = {"OK": "OK  ", "WARN": "WARN", "FAIL": "FAIL"}[status]
        print(f"  {mark}  {item:<22} {detail}", flush=True)

    @property
    def failed(self) -> int:
        return sum(1 for s, _i, _d in self.rows if s == "FAIL")


def check(course: pathlib.Path, skip_ai: bool, log_file: pathlib.Path) -> int:
    t = Table()
    log = open(log_file, "a", encoding="utf-8")

    def record(name: str, code: int, out: str) -> None:
        log.write(f"\n===== {name} (exit {code}) =====\n{out}\n")
        log.flush()

    print("\nReal-task check: an AI extracts four facts from a sample article, then Python checks the")
    print("answer, R re-checks the reported statistic with statcheck, and Quarto renders a report.\n")
    for tool, args in [("git", ["--version"]), ("node", ["--version"]), ("uv", ["--version"]),
                       ("Rscript", ["--version"]), ("quarto", ["--version"]), ("opencode", ["--version"])]:
        code, out = sh([tool, *args], timeout=60)
        record(tool, code, out)
        first = out.strip().splitlines()[0] if out.strip() else ""
        if code == 0:
            t.add("OK", tool, first[:60])
        elif tool == "node":
            t.add("WARN", tool, "not found (only some MCP tools need it)")
        else:
            t.add("FAIL", tool, "not found or does not start")
            if code == 127:   # record what the search saw, so the log shows WHY it was not found
                entries = os.environ.get("PATH", "").split(os.pathsep)
                record(f"{tool} search details", code,
                       "PATH entries:\n  " + "\n  ".join(entries)
                       + "\nPATHEXT: " + os.environ.get("PATHEXT", ""))

    c = course / "check"
    out_dir = c / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in out_dir.glob("*"):
        if f.is_file():
            f.unlink()
    extract = out_dir / "extract.csv"

    def sample_answer() -> None:
        extract.write_text('field,value,quote\n"sample_size","412","412 participants"\n'
                           '"preregistered","yes","preregistered online experiment"\n'
                           '"open_data","yes","Data and analysis code are openly available"\n'
                           '"test_statistic","t(410) = 2.15, p = .032","t(410) = 2.15, p = .032"\n',
                           encoding="utf-8")

    if skip_ai:
        sample_answer()
        t.add("WARN", "AI step", "skipped on request; a ready-made answer was used")
    else:
        msg = "Follow the instructions in the file check/check-task.md exactly."
        # Free models are sometimes busy: try the default model, then the backup, before failing.
        free = list_models("opencode", course)
        tries = ([m for m in DEFAULT_MODEL_PREFERENCE if m in free] or [None])[:2]
        tries.append(tries[0])          # a third try with the first model, after a pause (free models are often briefly busy)
        # a free key the student saved is the way round "Free usage limit reached" (one per provider, after the free models)
        for pid, _name, _url, hints in PROVIDERS:
            if key_path(pid).is_file():
                m = pick(list_models(pid, course), hints)
                if m:
                    tries.append(m)
        done, out, limited, ran = None, "", False, 0
        for attempt, model in enumerate(tries, 1):
            if limited and (model is None or model.startswith("opencode/")):
                continue                # the free models already refused this computer; only saved keys are worth trying
            if attempt == 3 and not limited:
                print("  (the free AI models were busy; trying once more in 30 seconds)", flush=True)
                import time
                time.sleep(30)
            # warnings and errors go into the log, so a hang shows its reason (Codespace 2026-11-09: three silent
            # 420 s time-outs with only the model name printed)
            cmd = ["opencode", "run", "--auto", "--print-logs", "--log-level", "WARN", msg] + (["-m", model] if model else [])
            # OpenCode does not exit after "Free usage limit reached" (Codespace 2026-11-09: it then waits the full
            # 420 s, three times); stop it as soon as that line appears
            code, out = sh(cmd, cwd=course, timeout=420, stop_on=(FREE_LIMIT,))
            ran += 1
            record(f"opencode run attempt {attempt} ({model})", code, out)
            if FREE_LIMIT in out.lower() and (model is None or model.startswith("opencode/")):
                limited = True
            if extract.is_file() and extract.stat().st_size > 0:
                done = (attempt, model)
                break
        if done:
            note = "" if done[0] == 1 else f" on try {done[0]}"
            t.add("OK", "AI step", f"free model {done[1]} read the article and wrote extract.csv{note}")
        else:
            low = out.lower()
            if limited:
                keys_cmd = ("install-windows.cmd -Keys" if os.name == "nt" else "bash setup-mac.sh --keys")
                hint = ("OpenCode's free models refuse this computer's internet address today (\"Free usage limit "
                        "reached\"; common in a Codespace and on busy shared Wi-Fi). Add a free key, then the check "
                        f"runs again: {keys_cmd}")
            elif "429" in out or "rate limit" in low or "too many" in low:
                hint = "the free models are busy or rate-limited; try the check again in a few minutes"
            elif any(w in low for w in ("region", "country", "not available in your", "unsupported location", "403", "forbidden")):
                hint = ("the free models refuse this network or region; try another network or a VPN, "
                        "or add a free key with the -Keys option")
            elif any(w in low for w in ("enotfound", "econnrefused", "econnreset", "etimedout", "unable to connect",
                                        "fetch failed", "self signed certificate", "unable to get local issuer")):
                hint = ("OpenCode could not reach its AI service; check the internet connection, VPN or proxy, "
                        "then try the check again")
            else:
                hint = "see log; try the check again later"
            t.add("FAIL", "AI step", f"no extract.csv after {ran} {'try' if ran == 1 else 'tries'} ({hint})")
            sample_answer()   # still test Python, R and Quarto, so one AI outage does not hide other problems

    if extract.is_file():
        code, out = sh(["uv", "run", "--quiet", "python", "check/check.py"], cwd=course, timeout=600)
        record("python check", code, out)
        if code == 124 and (out_dir / "python-ok.txt").is_file():
            code = 0   # the check finished and wrote its marker; only the Python process was slow to exit
        t.add("OK" if code == 0 else "FAIL", "Python step",
              "AI answer verified; course packages load" if code == 0 else (out.strip().splitlines() or ["see log"])[-1][:90])
        code, out = sh(["Rscript", "check/check.R"], cwd=course, timeout=300)
        record("R check", code, out)
        t.add("OK" if code == 0 else "FAIL", "R step",
              "statcheck re-checked the reported t-test" if code == 0 else "see log")
        code, out = sh(["quarto", "render", "report.qmd", "--quiet"], cwd=c, timeout=300)
        record("quarto render", code, out)
        ok = code == 0 and (c / "report.html").is_file()
        t.add("OK" if ok else "FAIL", "Report step", "Quarto + R rendered check/report.html" if ok else "see log")

    for pid, name, _url, hints in PROVIDERS:
        if not key_path(pid).is_file():
            continue
        model = pick(list_models(pid, course), hints)
        if not model:
            t.add("FAIL", f"Key: {name}", "OpenCode lists no models for it")
            continue
        code, out = sh(["opencode", "run", "-m", model, "Reply with exactly the word PONG"], cwd=course, timeout=180)
        record(f"key {pid}", code, out)
        t.add("OK" if "PONG" in out else "FAIL", f"Key: {name}",
              f"answered ({model})" if "PONG" in out else "saved but did not answer; run the key step again")

    code, out = sh(["opencode", "mcp", "list"], cwd=course, timeout=60)
    record("mcp list", code, out)
    t.add("OK" if code == 0 else "WARN", "MCP tools", f"{len(MCP_SERVERS)} configured, all switched off" if code == 0 else "could not list")

    report = course / "setup-report.txt"
    with open(report, "w", encoding="utf-8") as r:
        r.write(f"MetaScience setup {SETUP_VERSION}  {dt.datetime.now():%Y-%m-%d %H:%M}\n")
        r.write(f"{platform.platform()}  {platform.machine()}\n\n")
        for s, i, d in t.rows:
            r.write(f"{s:<5} {i:<22} {d}\n")
    print()
    if t.failed == 0:
        print("ALL CHECKS PASSED. Your computer is ready for the course.")
    else:
        print(f"{t.failed} CHECK(S) FAILED. Run the setup again first; it repairs most problems.")
        print(f"If it still fails, show the teacher: {report}")
    print(f"Detailed log: {log_file}")
    return 1 if t.failed else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["config", "keys", "check"])
    ap.add_argument("--course", required=True)
    ap.add_argument("--skip-ai", action="store_true")
    ap.add_argument("--log", default=None)
    a = ap.parse_args()
    course = pathlib.Path(a.course).expanduser()
    if a.command == "config":
        write_config(course)
        return 0
    if a.command == "keys":
        key_wizard(course)
        return 0
    log_file = pathlib.Path(a.log) if a.log else course / "setup-check.log"
    return check(course, a.skip_ai, log_file)


if __name__ == "__main__":
    sys.exit(main())
