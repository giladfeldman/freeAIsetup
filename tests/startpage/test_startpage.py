"""Tests for the Codespace start page (.devcontainer/startpage/server.py), with no real OpenRouter or OpenCode.

  python tests/startpage/test_startpage.py
Each check prints PASS/FAIL; exit code 1 if any failed.
"""
import base64
import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
TMP = pathlib.Path(tempfile.mkdtemp())
os.environ.update(MS_STARTPAGE_PORT="18600", METASCIENCE_DIR="/workspaces/MetaScience",
                  MS_FREE_AI_STATE=str(TMP / "state.json"), MS_FREE_AI_FALLBACK=str(TMP / "fallback.json"),
                  CODESPACE_NAME="test-space", GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN="app.github.dev",
                  HOME=str(TMP), USERPROFILE=str(TMP))
spec = importlib.util.spec_from_file_location("startpage", ROOT / ".devcontainer/startpage/server.py")
sp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sp)
sp.cs.KEY_DIR = TMP / "keys"   # never the real key folder
jobs, saved = [], {}
sp.run_job = lambda title, steps: jobs.append((title, steps))
sp.cs.openrouter_exchange = lambda code, verifier: "sk-or-test" if code == "good" else ""
real_save = sp.cs.save_key
sp.cs.save_key = lambda pid, key: (saved.__setitem__(pid, key), real_save(pid, key))

srv = sp.ThreadingHTTPServer(("127.0.0.1", 18600), sp.H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:18600"
FAIL = 0


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


opener = urllib.request.build_opener(NoRedirect)


def get(path, method="GET", cookie=""):
    try:
        r = opener.open(urllib.request.Request(BASE + path, method=method, data=b"" if method == "POST" else None,
                                               headers={"Cookie": cookie} if cookie else {}))
        return r.status, r.read().decode(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(), dict(e.headers)


def check(ok, what):
    global FAIL
    print(("PASS " if ok else "FAIL ") + what)
    FAIL |= not ok


code, page, _ = get("/")
check(code == 200 and 'href="/open/opencode"' in page, "page has the Open OpenCode button")
# Open OpenCode: a fake OpenCode server; the newest top-level chat in the course folder is reused, else one is made
from http.server import BaseHTTPRequestHandler as BH
made = []
class FakeOC(BH):
    chats = []
    def log_message(self, *a): pass
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        assert q["directory"] == [str(sp.COURSE)]
        data = json.dumps(FakeOC.chats).encode(); self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        made.append(self.path); data = b'{"id":"ses_new"}'
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
oc = sp.ThreadingHTTPServer(("127.0.0.1", 18601), FakeOC); threading.Thread(target=oc.serve_forever, daemon=True).start()
sp.OPENCODE_LOCAL = "http://127.0.0.1:18601"
slug = base64.urlsafe_b64encode(str(sp.COURSE).encode()).decode().rstrip("=")
code, _, h = get("/open/opencode")
check(code == 302 and h.get("Location") == f"https://test-space-4096.app.github.dev/{slug}/session/ses_new" and made,
      "Open OpenCode: no chat yet -> makes one in the course folder and opens it")
FakeOC.chats = [{"id": "ses_old", "time": {"updated": 1}}, {"id": "ses_recent", "time": {"updated": 9}},
                {"id": "ses_sub", "parentID": "ses_recent", "time": {"updated": 99}}]
made.clear(); code, _, h = get("/open/opencode")
check(code == 302 and h["Location"].endswith("/session/ses_recent") and not made, "Open OpenCode: reuses the newest chat (not a sub-task)")
oc.shutdown(); sp.OPENCODE_LOCAL = "http://127.0.0.1:1"
code, body, _ = get("/open/opencode")
check(code == 503 and "Restart OpenCode" in body, "Open OpenCode: OpenCode not running -> plain advice, no broken tab")
check("https://test-space-8787.app.github.dev/" in page, "page links RStudio")
check(page.count('target="_blank"') >= 3, "buttons open new tabs (a tap, so no pop-up blocker)")

# status: no backup, not limited -> says so
code, body, _ = get("/status")
s = json.loads(body)
check(code == 200 and s["limited"] is False and s["backups"] == [], "status: fresh Codespace = ready, no backup")
# limited with a backup
import time
(TMP / "state.json").write_text(json.dumps({"limitedUntil": time.time() * 1000 + 3600_000}))
(TMP / "fallback.json").write_text(json.dumps([{"providerID": "openrouter", "modelID": "x:free", "name": "OpenRouter: x:free", "free": True}]))
s = json.loads(get("/status")[1])
check(s["limited"] is True and s["backups"] == ["OpenRouter: x:free"] and s["until"], "status: used up + backup shown with time")
(TMP / "state.json").write_text(json.dumps({"limitedUntil": time.time() * 1000 - 1000}))
check(json.loads(get("/status")[1])["limited"] is False, "status: an expired limit counts as available again")

# OpenRouter sign-in: redirect carries the Codespace's own return address and a PKCE challenge.
# Real OpenRouter (2026-11-13) drops any ?query of the return address and appends only ?code=, so the sign-in id
# must travel in the path (and in a cookie as a second way back); every callback below is shaped that way.
def connect():
    code, _, h = get("/connect/openrouter")
    loc = h.get("Location", "")
    q = urllib.parse.parse_qs(urllib.parse.urlparse(loc).query)
    cb = (q.get("callback_url") or [""])[0]
    return code, loc, q, cb, h.get("Set-Cookie", "")
code, loc, q, cb, ck = connect()
check(code == 302 and loc.startswith("https://openrouter.ai/auth?"), "connect: sends the student to OpenRouter's sign-in")
check(cb.startswith("https://test-space-18600.app.github.dev/callback/openrouter/") and "?" not in cb,
      "connect: comes back to this start page, sign-in id in the path (OpenRouter drops ?query)")
check(q.get("code_challenge_method") == ["S256"] and q.get("code_challenge"), "connect: PKCE challenge present")
state = urllib.parse.urlparse(cb).path.rsplit("/", 1)[1]
check(ck.startswith(f"ms_or={state};") and "HttpOnly" in ck and "Secure" in ck and "SameSite=Lax" in ck,
      "connect: sign-in id also in a private cookie")

# a callback with an unknown state is refused and saves nothing
code, _, _ = get("/callback/openrouter/forged?code=good")
check(code == 400 and not saved, "callback: unknown sign-in refused, nothing saved")
code, body, _ = get("/callback/openrouter?code=good")
check(code == 400 and not saved and "unknown" in body, "callback: no id at all (no path, no cookie) refused")
# the real callback shape (path id, ?code only) saves the key and starts the follow-up job
code, body, _ = get(f"/callback/openrouter/{state}?code=good")
check(code == 200 and saved.get("openrouter") == "sk-or-test", "callback: key saved")
check((TMP / "keys").is_dir() and any((TMP / "keys").iterdir()), "callback: key written to the (test) key folder")
check(jobs and any("backups" in c for st in jobs[-1][1] for c in st), "callback: tests the new key and restarts OpenCode")
# the same state cannot be used twice
code, _, _ = get(f"/callback/openrouter/{state}?code=good")
check(code == 400, "callback: a used sign-in cannot be replayed")
# if the path were lost too, the cookie alone still finds the sign-in
saved.clear(); _, _, _, cb2, ck2 = connect()
code, _, _ = get("/callback/openrouter?code=good", cookie=ck2.split(";")[0])
check(code == 200 and saved.get("openrouter") == "sk-or-test", "callback: cookie alone finds the sign-in")
# Deny on OpenRouter: back without a code -> plain advice, nothing saved
saved.clear(); _, _, _, cb3, _ = connect()
code, body, _ = get(urllib.parse.urlparse(cb3).path)
check(code == 400 and not saved and "Connect again" in body, "callback: no code (Deny) -> plain advice, nothing saved")

code, _, h = get("/restart", "POST")
check(code == 303 and h.get("Location") == "/", "restart button starts the job and returns to the page")

srv.shutdown()
print("ALL PASS" if not FAIL else "SOME FAILED")
sys.exit(1 if FAIL else 0)
