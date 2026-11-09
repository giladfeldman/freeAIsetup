// Receives a student's setup log (only after the student said yes) and keeps it for 180 days.
// Write-only: there is no way to read logs through this address. The teacher reads them with
// `wrangler kv key list/get` using his own Cloudflare login (see README.md).
const MAX_BYTES = 1_500_000;          // a full setup log is ~100-400 KB
const KEEP_SECONDS = 180 * 24 * 3600; // deleted automatically after 180 days
const PLATFORMS = new Set(["windows", "mac", "linux", "codespace"]);

function code() {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // no 0/O/1/I: easy to read aloud
  const b = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(b, (x) => a[x % a.length]).join("");
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method !== "POST" || url.pathname !== "/upload") {
      return new Response("freeAIsetup log upload. Nothing to see here.\n", { status: 404 });
    }
    if (req.headers.get("x-freeaisetup") !== "1") return new Response("missing header\n", { status: 400 });
    const len = Number(req.headers.get("content-length") || "0");
    if (len > MAX_BYTES) return new Response("too large\n", { status: 413 });
    const body = await req.text();
    if (!body || body.length > MAX_BYTES) return new Response("empty or too large\n", { status: 413 });
    const platform = (url.searchParams.get("platform") || "").toLowerCase();
    const version = (url.searchParams.get("version") || "").replace(/[^0-9A-Za-z._-]/g, "").slice(0, 32);
    const result = (url.searchParams.get("result") || "").replace(/[^a-z-]/g, "").slice(0, 16);
    if (!PLATFORMS.has(platform)) return new Response("bad platform\n", { status: 400 });
    const day = new Date().toISOString().slice(0, 10);
    const id = code();
    const key = `${day}/${platform}/${result || "unknown"}/${id}`;
    await env.LOGS.put(key, body, {
      expirationTtl: KEEP_SECONDS,
      metadata: { version, platform, result, country: req.cf?.country || "", bytes: body.length },
    });
    return new Response(id + "\n", { headers: { "content-type": "text/plain" } });
  },
};
