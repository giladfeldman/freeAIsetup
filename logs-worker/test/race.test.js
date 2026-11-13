// Run: npm test. Two reports (or a report and the digest) arriving at the same moment (d-09bd19).
// Every alert decision reads state from KV and writes it back. Without one place that handles them one after the
// other, both read the same old state and the second write wins. Each case runs twice: straight onFailedReport /
// sendDigest (the control: it MUST show the race, otherwise the test cannot see it) and through the AlertGate
// Durable Object that src/index.js uses (must not).
import { test } from "node:test";
import assert from "node:assert/strict";
import { onFailedReport, sendDigest, consistentKv, KEEP_LOCAL_MS } from "../src/alerts.js";
import worker, { AlertGate } from "../src/index.js";

const tick = () => new Promise((r) => setTimeout(r, 5));
function slowKv() {   // like KV: a read and a write each take a moment, so two requests interleave
  const m = new Map();
  return {
    m,
    async get(k) { await tick(); return m.has(k) ? m.get(k) : null; },
    async put(k, v) { await tick(); m.set(k, v); },
    async list({ prefix = "" } = {}) { await tick(); return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true }; },
  };
}
function memStorage() {   // the Durable Object's own storage
  const m = new Map();
  return { async get(k) { return m.get(k); }, async put(k, v) { m.set(k, v); }, async delete(k) { m.delete(k); } };
}
const baseEnv = () => ({ LOGS: slowKv(), ADMIN_NOTIFY_EMAIL: "admin@example.org", ADMIN_EMAIL_SESSION_FOLDER: "C:\\proj" });
const rep = (key, body = "FAIL  Python step            DLL load failed") =>
  ({ key, platform: "windows", version: "2026.11.13.1", country: "AT", body, environment: "production" });
const NOW = "2026-11-13T10:00:00Z";

// the two ways to run the same work; each returns { env, sent, report(args), digest() }
function direct() {
  const env = baseEnv(); const sent = []; const send = async (_e, m) => { await tick(); sent.push(m); };
  return { env, sent, report: (a) => onFailedReport(env, a, new Date(NOW), send), digest: () => sendDigest(env, new Date(NOW), send) };
}
function gated() {
  const env = baseEnv(); const sent = [];
  const gate = new AlertGate({ storage: memStorage() }, env);
  gate.send = async (_e, m) => { await tick(); sent.push(m); };
  const call = (job) => gate.fetch(new Request("https://gate/", { method: "POST", body: JSON.stringify(job) })).then((r) => r.text());
  return { env, sent, report: (a) => call({ kind: "report", args: a, now: NOW }), digest: () => call({ kind: "digest", now: NOW }) };
}
const json = (env, k) => JSON.parse(env.LOGS.m.get(k) || "null");

const CASES = {
  "same failure twice at once: one alert email, not two": async (w) => {
    await Promise.all([w.report(rep("k1")), w.report(rep("k2"))]);
    return w.sent.length === 1;
  },
  "same failure twice at once: the issue counts 2 occurrences": async (w) => {
    await Promise.all([w.report(rep("k1")), w.report(rep("k2"))]);
    const k = [...w.env.LOGS.m.keys()].find((x) => x.startsWith("alerts/state/production/"));
    return json(w.env, k).count === 2;
  },
  "9 emails sent today, two new failures at once: only the 10th goes out": async (w) => {
    await w.env.LOGS.put("alerts/day/2026-11-13", JSON.stringify({ sent: 9, muted: [] }));
    await Promise.all([w.report(rep("a", "FAIL  StepA   broke")), w.report(rep("b", "FAIL  StepB   broke"))]);
    return w.sent.length === 1 && json(w.env, "alerts/day/2026-11-13").sent === 10;
  },
  "cap reached, two new failures at once: both are listed as muted": async (w) => {
    await w.env.LOGS.put("alerts/day/2026-11-13", JSON.stringify({ sent: 10, muted: [] }));
    await Promise.all([w.report(rep("a", "FAIL  StepA   broke")), w.report(rep("b", "FAIL  StepB   broke"))]);
    return json(w.env, "alerts/day/2026-11-13").muted.length === 2;
  },
  "the digest and a report at once: both keep what they wrote in alerts/meta": async (w) => {
    await Promise.all([w.digest(), w.report(rep("k1"))]);
    const meta = json(w.env, "alerts/meta");
    return meta.lastDigest === new Date(NOW).toISOString() && meta.lastReport === new Date(NOW).toISOString();
  },
};

for (const [name, run] of Object.entries(CASES)) {
  test(name, async () => {
    assert.equal(await run(direct()), false, "control: without the gate the race must show (else this test cannot see it)");
    assert.equal(await run(gated()), true, "through the gate");
  });
}

test("the upload sends a failed report to the gate (EU), and answers the student at once", async () => {
  const env = baseEnv(); const jobs = [];
  const ns = { jurisdiction(j) { ns.j = j; return ns; }, idFromName: (n) => n, get: () => ({ fetch: async (r) => { jobs.push(await r.json()); return new Response("ok"); } }) };
  env.ALERTS = ns;
  const w = []; const ctx = { waitUntil: (p) => w.push(p) };
  const r = await worker.fetch(new Request("https://box.example/upload?platform=windows&result=failed&version=1", { method: "POST", headers: { "x-freeaisetup": "1" }, body: "FAIL  X  y" }), env, ctx);
  assert.equal(r.status, 200);
  await Promise.all(w);
  assert.equal(ns.j, "eu");
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].kind, "report");
  assert.match(jobs[0].args.key, /^\d{4}-\d{2}-\d{2}\/windows\/failed\//);
});

test("an alert gate that cannot be reached never fails the student's upload, and is recorded", async () => {
  for (const ALERTS of [undefined, { jurisdiction() { throw new Error("boom"); } }]) {
    const env = baseEnv(); env.ALERTS = ALERTS;
    const w = []; const ctx = { waitUntil: (p) => w.push(p) };
    const r = await worker.fetch(new Request("https://box.example/upload?platform=windows&result=failed&version=1", { method: "POST", headers: { "x-freeaisetup": "1" }, body: "FAIL  X  y" }), env, ctx);
    assert.equal(r.status, 200);
    await Promise.all(w);
    assert.match(json(env, "alerts/meta").lastError, /alert gate/);
  }
});

test("the gate keeps its own copy only while KV may lag; a key deleted from KV is gone after that", async () => {
  const kv = slowKv(); let t = 1_000_000; const c = consistentKv(kv, memStorage(), () => t);
  await c.put("alerts/state/production/x", "A", { expirationTtl: 3600 });
  kv.m.delete("alerts/state/production/x");                 // e.g. the deploy check cleaning up after itself
  assert.equal(await c.get("alerts/state/production/x"), "A");   // within the window: the gate's own copy
  t += KEEP_LOCAL_MS + 1;
  assert.equal(await c.get("alerts/state/production/x"), null);  // after it: what KV says
  kv.m.set("k", "old"); await c.put("k", "new", { expirationTtl: 30 }); kv.m.set("k", "old");   // a lagging KV read
  assert.equal(await c.get("k"), "new");
});
