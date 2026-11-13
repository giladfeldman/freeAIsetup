"""tools/sync_free_ai.py --write must not put the approvals list's address into lib/free-ai.json: the address is
kept out of this public repository. Serves a changed list from a local server, writes to a scratch copy.
Run: python tests/course/test_sync_free_ai.py   (ends RESULT pass=N fail=0)"""
import http.server
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import threading
from contextlib import redirect_stdout

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sync_free_ai", ROOT / "tools" / "sync_free_ai.py")
sync = importlib.util.module_from_spec(spec); spec.loader.exec_module(sync)

current = json.loads((ROOT / "lib" / "free-ai.json").read_text(encoding="utf-8"))
changed = dict(current, version=2, updated="2026-11-13",
               opencode_free=current["opencode_free"] + ["test-model-free"])
body = json.dumps(changed).encode()

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass

srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
secret_host = "private-list-host.invalid"
url = f"http://127.0.0.1:{srv.server_port}/v1/pack/free-ai?h={secret_host}"

passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  {detail}"))
    passed, failed = passed + ok, failed + (not ok)

with tempfile.TemporaryDirectory() as d:
    target = pathlib.Path(d) / "free-ai.json"
    target.write_text(json.dumps(current), encoding="utf-8")
    sync.URL, sync.FREE_AI_FILE = url, target
    argv = sys.argv; sys.argv = ["sync_free_ai.py", "--write"]
    out = io.StringIO()
    with redirect_stdout(out):
        rc = sync.main()
    sys.argv = argv
    written = target.read_text(encoding="utf-8")
    check("write: exit 0", rc == 0, f"rc={rc} {out.getvalue()}")
    check("write: the changed list is written", "test-model-free" in written)
    check("write: the list's address is not in the file", "127.0.0.1" not in written and secret_host not in written,
          json.loads(written).get("source"))
    check("write: the source still says where it came from", "sync_free_ai" in json.loads(written).get("source", ""))
srv.shutdown()
print(f"RESULT pass={passed} fail={failed}")
sys.exit(1 if failed else 0)
