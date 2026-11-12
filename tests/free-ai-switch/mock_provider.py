"""Fake AI providers for testing the free-AI switch without any real AI service.

  /zen/v1/...     acts like OpenCode's free models after the free usage is used up: HTTP 429 FreeUsageLimitError
  /backup/v1/...  acts like a working free backup account: streams a short answer
  /tired/v1/...   acts like a backup that is out of free requests: HTTP 429 rate limit
Every request is appended to the log file given as the second argument (path, model), so a test can see
which provider each message went to.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18555
LOG = sys.argv[2] if len(sys.argv) > 2 else None


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json", extra=None):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        if self.path.endswith("/models"):
            return self._send(200, json.dumps({"data": [{"id": "glm-5.3-flash-free"}, {"id": "backup-free"}]}))
        self._send(404, "{}")

    def do_POST(self):  # noqa: N802
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            body = {}
        if LOG:
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps({"path": self.path, "model": body.get("model")}) + "\n")
        if self.path.startswith("/zen/"):
            return self._send(429, json.dumps({"type": "error", "error": {"type": "FreeUsageLimitError",
                              "message": "Free usage limit reached."}}), extra={"retry-after": "22583"})
        if self.path.startswith("/tired/"):
            return self._send(429, json.dumps({"error": {"message": "Rate limit exceeded: free-models-per-day",
                              "code": 429}}))
        # a working backup: a streamed chat completion
        model = body.get("model", "backup")
        chunks = [
            {"id": "x", "object": "chat.completion.chunk", "created": int(time.time()), "model": model,
             "choices": [{"index": 0, "delta": {"role": "assistant", "content": "BACKUP-ANSWER"}, "finish_reason": None}]},
            {"id": "x", "object": "chat.completion.chunk", "created": int(time.time()), "model": model,
             "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
             "usage": {"prompt_tokens": 5, "completion_tokens": 2, "total_tokens": 7}},
        ]
        if not body.get("stream"):
            return self._send(200, json.dumps({"id": "x", "object": "chat.completion", "created": int(time.time()),
                              "model": model, "choices": [{"index": 0, "message": {"role": "assistant",
                              "content": "BACKUP-ANSWER"}, "finish_reason": "stop"}],
                              "usage": {"prompt_tokens": 5, "completion_tokens": 2, "total_tokens": 7}}))
        text = "".join(f"data: {json.dumps(c)}\n\n" for c in chunks) + "data: [DONE]\n\n"
        self._send(200, text, ctype="text/event-stream")


class Quiet(ThreadingHTTPServer):
    def handle_error(self, request, client_address):  # a client that hangs up when a test stops its server
        pass


if __name__ == "__main__":
    Quiet(("127.0.0.1", PORT), H).serve_forever()
