"""A stand-in for the teacher's log box, for the exit-path tests (tests/exit-paths.ps1, tests/exit-paths.sh).

Records every POST (path, headers that matter, body) as one JSON line, answers uploads with the code TESTID,
and serves the signed release manifest from this checkout so the installers can be tested without GitHub.
GET /m/manifest.json and /m/manifest.sig  -> release/manifest.json and .sig of this checkout (genuinely signed)
GET /bad/<path>                          -> wrong bytes (a file that fails its checksum)
Run:  python tests/fake_logbox.py <port> <record.jsonl>
"""
import http.server
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PORT, RECORD = int(sys.argv[1]), pathlib.Path(sys.argv[2])


class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes) -> None:
        self.send_response(code)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0]
        if path.startswith("/m/manifest."):
            f = ROOT / "release" / path.rsplit("/", 1)[1]
            return self._send(200, f.read_bytes()) if f.is_file() else self._send(404, b"")
        if path.startswith("/bad/"):
            return self._send(200, b"not the file you are looking for")
        self._send(404, b"")

    def do_POST(self):  # noqa: N802
        n = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        rec = {"path": self.path, "x-freeaisetup": self.headers.get("x-freeaisetup"),
               "env": self.headers.get("x-freeaisetup-env"), "body": body}
        with RECORD.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
        self._send(200, b"TESTID\n" if self.path.startswith("/upload") else b"counted\n")

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
