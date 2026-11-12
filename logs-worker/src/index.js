// Receives a student's setup log (only after the student said yes) and keeps it for 180 days.
// Write-only: there is no way to read logs through this address. The teacher reads them with
// `wrangler kv key list/get` using his own Cloudflare login (see README.md).
// A failed report also triggers an admin alert email (src/alerts.js).
import { onFailedReport, environmentOf, sendDigest, countKey, COUNT_TTL, COUNT_DAY_CAP } from "./alerts.js";

const MAX_BYTES = 1_500_000;         // a full setup log is ~100-400 KB
const KEEP_SECONDS = 180 * 24 * 3600; // deleted automatically after 180 days
const PLATFORMS = new Set(["windows", "mac", "linux", "codespace"]);

function code() {
  const a = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // no 0/O/1/I: easy to read aloud
  const b = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(b, (x) => a[x % a.length]).join("");
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    if (req.method === "POST" && url.pathname === "/count") {
      // A successful install: only the platform and pack version arrive; no body, no name, no address is stored.
      if (req.headers.get("x-freeaisetup") !== "1") return new Response("missing header\n", { status: 400 });
      const platform = (url.searchParams.get("platform") || "").toLowerCase();
      if (!PLATFORMS.has(platform)) return new Response("bad platform\n", { status: 400 });
      const version = (url.searchParams.get("version") || "").replace(/[^0-9A-Za-z._-]/g, "").slice(0, 32);
      // Daily cap per environment and platform, so a broken or hostile caller cannot fill the store. Past the cap
      // the answer is the same ("counted"), but nothing is written. The cap counter is read and rewritten, so two
      // installs at the same moment may let one extra through; that is fine for a cap.
      const environment = environmentOf(req);
      const capKey = `countcap/${environment}/${new Date().toISOString().slice(0, 10)}/${platform}`;
      const sofar = Number((await env.LOGS.get(capKey)) || "0");
      if (sofar < COUNT_DAY_CAP) {
        await env.LOGS.put(countKey(environment, platform), "", { expirationTtl: COUNT_TTL, metadata: { version } });
        await env.LOGS.put(capKey, String(sofar + 1), { expirationTtl: 3 * 24 * 3600 });
      }
      return new Response("counted\n", { headers: { "content-type": "text/plain" } });
    }
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
    if (result === "failed") {
      // The alert runs after the answer: the student gets the code at once, whatever SES does.
      ctx.waitUntil(onFailedReport(env, { key, platform, version, country: req.cf?.country || "", body, environment: environmentOf(req) }));
    }
    return new Response(id + "\n", { headers: { "content-type": "text/plain" } });
  },

  // Cron on the 1st and 15th of each month (wrangler.toml): the fortnight digest.
  async scheduled(event, env, ctx) {
    const now = new Date(event.scheduledTime);
    ctx.waitUntil((async () => {
      try { await sendDigest(env, now); }
      catch (e) {
        const meta = JSON.parse((await env.LOGS.get("alerts/meta")) || "{}");
        meta.lastError = `${now.toISOString()} digest: ${String((e && e.message) || e).slice(0, 300)}`;
        meta.sendFailures = (meta.sendFailures || 0) + 1;
        await env.LOGS.put("alerts/meta", JSON.stringify(meta));
        console.error(meta.lastError);
      }
    })());
  },
};
