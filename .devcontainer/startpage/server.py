"""The Codespace start page: one page with big buttons, made for tablets (no terminal, no tiny icons).

Runs on port 4000 (started by create.sh before the first setup, and by start.sh at every start); START-HERE.md links to it. It shows:
  - Open OpenCode (already in the course folder), Open RStudio
  - the AI status in plain words: are the built-in free models available on this connection, which backup is used
  - Connect a free OpenRouter account: sign in, press Allow, done (the key comes back to this page by itself)
  - Restart OpenCode
Only standard Python. Listens on 127.0.0.1-reachable 0.0.0.0 inside the private Codespace; GitHub's port forwarding
lets only the Codespace's owner open it.
"""
from __future__ import annotations

import base64
import hashlib
import html
import json
import os
import pathlib
import secrets
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MS_STARTPAGE_PORT", "4000"))
HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "lib"))
import course_setup as cs  # noqa: E402

COURSE = pathlib.Path(os.environ.get("METASCIENCE_DIR", "/workspaces/MetaScience"))
STATE = pathlib.Path(os.environ.get("MS_FREE_AI_STATE", pathlib.Path.home() / ".local/state/metascience/free-ai-state.json"))
FALLBACK = pathlib.Path(os.environ.get("MS_FREE_AI_FALLBACK", cs.FALLBACK_FILE))
# written by create.sh while the first setup runs (15-25 minutes); the page says so instead of offering dead buttons
SETUP_MARK = pathlib.Path(os.environ.get("MS_SETUP_MARK", pathlib.Path.home() / ".local/state/metascience/setup-running"))
JOB_LOG = pathlib.Path("/tmp/startpage-job.log") if os.name != "nt" else pathlib.Path(os.environ.get("TEMP", ".")) / "startpage-job.log"

PKCE: dict[str, str] = {}   # state -> verifier, for the OpenRouter sign-in in progress
JOB = {"running": False, "title": "", "done": "", "ok": None}


def forwarded(port: int) -> str:
    """The address the student's browser uses for a port of this Codespace (or localhost outside one)."""
    name, dom = os.environ.get("CODESPACE_NAME"), os.environ.get("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN")
    return f"https://{name}-{port}.{dom}" if name and dom else f"http://localhost:{port}"


OPENCODE_LOCAL = os.environ.get("MS_OPENCODE_LOCAL", "http://127.0.0.1:4096")


def opencode_url() -> str | None:
    """The newest chat in the course folder (a new one if there is none), as an address the browser opens directly
    in that folder. OpenCode 1.19's web page cannot be sent to a folder by address alone (checked 2026-11-12: it goes
    to a blank 'New project' page), but an address with a chat id in that folder opens it. None: OpenCode not running.
    Generous time limits: the first request after OpenCode starts loads the folder and its add-on, which took over
    10 s in a test run (2026-11-13); a short limit showed "not running" for an OpenCode that was only starting."""
    import urllib.request
    d = urllib.parse.quote(str(COURSE))
    try:
        with urllib.request.urlopen(f"{OPENCODE_LOCAL}/session?directory={d}", timeout=60) as r:
            chats = [c for c in json.load(r) if not c.get("parentID")]
        if chats:
            sid = max(chats, key=lambda c: (c.get("time") or {}).get("updated", 0))["id"]
        else:
            req = urllib.request.Request(f"{OPENCODE_LOCAL}/session?directory={d}", data=b"{}", method="POST",
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                sid = json.load(r)["id"]
    except Exception:
        return None
    slug = base64.urlsafe_b64encode(str(COURSE).encode()).decode().rstrip("=")
    return f"{forwarded(4096)}/{slug}/session/{sid}"


def read_json(p: pathlib.Path, default):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return default


def setup_minutes() -> int | None:
    """Minutes since the first setup started, or None when it is not running."""
    try:
        minutes = int((time.time() - SETUP_MARK.stat().st_mtime) // 60)
    except OSError:
        return None
    return minutes if minutes < 120 else None   # a setup takes 15-25 minutes; an older marker is left over


def ai_status() -> dict:
    st = read_json(STATE, {})
    backups = read_json(FALLBACK, [])
    now = time.time() * 1000
    limited = (st.get("limitedUntil") or 0) > now
    keys = [name for pid, name, _u, _h in cs.PROVIDERS if cs.key_path(pid).is_file()]
    until = time.strftime("%H:%M", time.localtime(st["limitedUntil"] / 1000)) if limited else ""
    return {"limited": limited, "until": until, "backups": [b.get("name") for b in backups if isinstance(b, dict)],
            "keys": keys, "last": st.get("lastEvent", ""), "job": JOB,
            "setup": setup_minutes()}


def run_job(title: str, steps: list[list[str]]) -> None:
    def work():
        JOB.update(running=True, title=title, done="", ok=None)
        ok = True
        with open(JOB_LOG, "a", encoding="utf-8") as log:
            for cmd in steps:
                log.write(f"\n$ {' '.join(cmd)}\n"); log.flush()
                try:
                    r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=600, cwd=str(REPO))
                    ok = ok and r.returncode == 0
                except Exception as e:
                    log.write(f"failed: {e}\n"); ok = False
        JOB.update(running=False, done=time.strftime("%H:%M"), ok=ok)
    threading.Thread(target=work, daemon=True).start()


def restart_opencode_steps() -> list[list[str]]:
    return [["bash", "-c", 'pkill -f "^opencode web" ; sleep 1; bash "$0"', str(REPO / ".devcontainer/start.sh")]]


def after_new_key_steps() -> list[list[str]]:
    py = [sys.executable, str(REPO / "lib/course_setup.py")]
    return [py + ["config", "--course", str(COURSE)], py + ["backups", "--course", str(COURSE)]] + restart_opencode_steps()


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MetaScience: start here</title>
<style>
 body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;margin:0;padding:18px;background:#f5f6f8;color:#1d2330;max-width:760px}
 h1{font-size:1.5rem;margin:0 0 4px} p{line-height:1.45}
 .btn{display:block;text-decoration:none;text-align:left;font-size:1.25rem;padding:18px 20px;margin:12px 0;border-radius:14px;
      background:#fff;color:#1d2330;border:2px solid #d5d9e2;cursor:pointer;width:100%;box-sizing:border-box}
 .btn b{display:block;font-size:1.35rem} .btn span{font-size:1rem;color:#5a6275}
 .main{background:#1f6feb;border-color:#1f6feb;color:#fff} .main span{color:#e6eeff}
 .card{background:#fff;border-radius:14px;padding:16px 18px;margin:16px 0;border:2px solid #d5d9e2}
 .ok{border-color:#2da44e} .warn{border-color:#d4a72c} .bad{border-color:#cf222e}
 small{color:#5a6275}
</style></head><body>
<h1>MetaScience course</h1>
<p>Tap a button. Each one opens in a new tab; come back to this tab any time.</p>
<div id="setup" class="card warn" hidden></div>
<a class="btn main during-setup-off" href="/open/opencode" target="_blank" rel="noopener"><b>Open OpenCode (AI assistant)</b><span>Already in your course folder</span></a>
<a class="btn during-setup-off" href="{rs}" target="_blank" rel="noopener"><b>Open RStudio</b><span>R in the browser</span></a>
<div id="ai" class="card">Checking the AI status...</div>
<a class="btn during-setup-off" href="/connect/openrouter" target="_blank" rel="noopener"><b>Connect a free OpenRouter account</b>
 <span>Your own free backup for the AI: sign in (Google or GitHub is quickest), press Allow. No card, no payment.</span></a>
<form method="post" action="/restart" class="during-setup-off"><button class="btn" type="submit"><b>Restart OpenCode</b><span>If OpenCode does not open or seems stuck</span></button></form>
<div class="card"><b>Your files</b><p>They are in the MetaScience folder in the file list on the left of the Codespace window.
To download one: press and hold it there, then Download.</p>
<p><b>Money:</b> everything here is free. Never add a card anywhere, and never press "Subscribe" in OpenCode.</p></div>
<script>
async function upd(){
 try{const s=await (await fetch('status',{cache:'no-store'})).json();const el=document.getElementById('ai');
  let h='',c='ok';
  if(s.limited){c=s.backups.length?'warn':'bad';
   h='<b>The built-in free AI is used up on this internet connection</b> until about '+s.until+'.'+
     (s.backups.length?'<p>OpenCode switches to your own free account by itself: <b>'+s.backups[0]+'</b>. Nothing to do.</p>'
       :'<p>Connect a free OpenRouter account below to keep working now.</p>');}
  else{h='<b>AI: ready.</b> The built-in free models are used first.'+
     (s.backups.length?'<p>Backup if they run out: <b>'+s.backups.join(', ')+'</b> (switches by itself).</p>'
       :'<p>No backup yet. In a Codespace the built-in free AI is shared with other users and can run out: connect a free OpenRouter account below.</p>');
   if(!s.backups.length)c='warn';}
  if(s.job.running)h+='<p>Working: '+s.job.title+' ...</p>';
  else if(s.job.done)h+='<p><small>'+s.job.title+': '+(s.job.ok?'done':'did not fully work, see /tmp/startpage-job.log')+' ('+s.job.done+')</small></p>';
  if(s.setup!==null){c='warn';h='<b>AI:</b> its status shows here once the setup is finished.';}
  el.className='card '+c;el.innerHTML=h;
  const su=document.getElementById('setup');su.hidden=s.setup===null;
  if(s.setup!==null)su.innerHTML='<b>The setup is still running</b> (started '+s.setup+' minutes ago; it takes about 15-25 minutes). '+
   'Nothing to do: OpenCode and RStudio open once it is finished, and this page updates by itself.'+
   (s.setup>=45?'<p>Taking much longer than usual? In the Codespace: menu (top left) &gt; Terminal &gt; New Terminal, then paste <b>tail /tmp/metascience-create.log</b> and show the last lines to your teacher.</p>':'');
  for(const b of document.querySelectorAll('.during-setup-off'))b.style.display=s.setup===null?'':'none';
 }catch(e){}
}
upd();setInterval(upd,5000);
</script></body></html>"""

DONE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{{font-family:system-ui,sans-serif;padding:24px;font-size:1.2rem;line-height:1.5}}</style></head>
<body><h2>{title}</h2><p>{text}</p><p><a href="/">Back to the start page</a></p></body></html>"""


SETTING_UP = ("OpenCode is still being installed (the first setup takes about 15-25 minutes). The start page says when "
              "it is finished; then tap the button again.")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code: int, body: str, ctype: str = "text/html; charset=utf-8", headers: dict | None = None):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def cookie(self, name: str) -> str:
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == name:
                return v
        return ""

    def do_GET(self):  # noqa: N802
        u = urllib.parse.urlparse(self.path)
        if u.path == "/":
            return self.send(200, PAGE.replace("{rs}", html.escape(forwarded(8787) + "/")))
        if u.path == "/open/opencode":
            if setup_minutes() is not None:
                return self.send(503, DONE.format(title="Still setting up", text=SETTING_UP))
            url = opencode_url()
            if url:
                return self.send(302, "", headers={"Location": url})
            return self.send(503, DONE.format(title="OpenCode is not running yet",
                text="Right after the Codespace starts this takes up to a minute. Go back to the start page and tap "
                     "Open OpenCode again; if it still does not open, tap Restart OpenCode there."))
        if u.path == "/status":
            return self.send(200, json.dumps(ai_status()), "application/json")
        if u.path == "/connect/openrouter" and setup_minutes() is not None:
            return self.send(503, DONE.format(title="Still setting up", text=SETTING_UP))
        if u.path == "/connect/openrouter":
            verifier = secrets.token_urlsafe(64)
            state = secrets.token_urlsafe(16)
            while len(PKCE) >= 20:   # sign-ins nobody finished do not pile up
                PKCE.pop(next(iter(PKCE)))
            PKCE[state] = verifier
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
            # OpenRouter drops any ?query of the return address and adds only ?code= (real Codespace 2026-11-13), so the
            # sign-in's id travels in the path, and in a cookie as a second way back
            cb = f"{forwarded(PORT)}/callback/openrouter/{state}"
            q = urllib.parse.urlencode({"callback_url": cb, "code_challenge": challenge,
                                        "code_challenge_method": "S256", "key_label": "MetaScience course"})
            return self.send(302, "", headers={"Location": f"{cs.OPENROUTER_AUTH}?{q}",
                "Set-Cookie": f"ms_or={state}; Path=/callback; Max-Age=1800; HttpOnly; Secure; SameSite=Lax"})
        if u.path == "/callback/openrouter" or u.path.startswith("/callback/openrouter/"):
            q = urllib.parse.parse_qs(u.query)
            code = (q.get("code") or [""])[0]
            ids = [u.path[len("/callback/openrouter/"):], (q.get("s") or [""])[0], self.cookie("ms_or")]
            verifier = next((PKCE.pop(i) for i in ids if i and i in PKCE), "")
            if not code:
                return self.send(400, DONE.format(title="That did not work", text="The sign-in came back without a code "
                                 "(was Deny pressed?). Go back to the start page and tap Connect again."))
            if not verifier:
                return self.send(400, DONE.format(title="That did not work", text="This sign-in is unknown or was already "
                                 "used (for example after a restart of the Codespace). Go back to the start page and tap Connect again."))
            try:
                key = cs.openrouter_exchange(code, verifier)
            except Exception as e:
                return self.send(502, DONE.format(title="OpenRouter did not hand over the key",
                                                  text=html.escape(str(e)[:200]) + ". Tap Connect again in a minute."))
            if not key:
                return self.send(502, DONE.format(title="OpenRouter did not hand over the key", text="Tap Connect again in a minute."))
            cs.save_key("openrouter", key)
            run_job("setting up your OpenRouter account and restarting OpenCode (about 1-2 minutes)", after_new_key_steps())
            return self.send(200, DONE.format(title="Connected. Thank you!",
                text="Your free OpenRouter account is saved. The start page now tests it and restarts OpenCode (1-2 minutes). "
                     "You can close this tab. If OpenCode is open, reload its tab after that."))
        self.send(404, "not found", "text/plain")

    def do_POST(self):  # noqa: N802
        if self.headers.get("Sec-Fetch-Site", "same-origin") not in ("same-origin", "none"):
            return self.send(403, "not allowed", "text/plain")   # another web page may not press our buttons
        if self.path == "/restart" and setup_minutes() is not None:
            return self.send(503, DONE.format(title="Still setting up", text=SETTING_UP))
        if self.path == "/restart":
            if not JOB["running"]:
                run_job("restarting OpenCode", restart_opencode_steps())
            return self.send(303, "", headers={"Location": "/"})
        self.send(404, "not found", "text/plain")


class Server(ThreadingHTTPServer):
    # Python's default waiting line holds 5 connections; a browser opening the page and its parts at once can fill it,
    # and further requests are then refused (seen on Windows, d-3dd775)
    request_queue_size = 128
    daemon_threads = True


if __name__ == "__main__":
    Server(("0.0.0.0", PORT), H).serve_forever()
