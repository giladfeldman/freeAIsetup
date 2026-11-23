// Run: npm test   (node --test; no network, no Cloudflare: KV, the Durable Object and the sender are fakes)
// POST /result: the anonymous result of every setup run, and the weekly digest built from those results (2026-11-24).
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { AlertGate } from "../src/index.js";
import { normalizeResult, componentOf, componentStatus, resultMeta, storeResult, digestWindow, summarizeResults,
  sendDigest, RESULT_DAY_CAP, RESULT_MAX_BYTES } from "../src/alerts.js";

function fakeKv() {   // like KV: list returns each key's metadata
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? m.get(k).v : null; },
    async put(k, v, opts = {}) {   // KV refuses metadata over 1,024 bytes (serialized), so does this fake
      if (opts.metadata && new TextEncoder().encode(JSON.stringify(opts.metadata)).length > 1024) throw new Error("KV metadata over 1024 bytes");
      m.set(k, { v, metadata: opts.metadata });
    },
    async list({ prefix = "" } = {}) {
      return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name, metadata: m.get(name).metadata })), list_complete: true };
    },
  };
}
function memStorage() { const m = new Map(); return { m, async get(k) { return m.get(k); }, async put(k, v) { m.set(k, v); } }; }
// env whose ALERTS namespace runs a real AlertGate in-process (EU jurisdiction recorded)
function gatedEnv() {
  const env = { LOGS: fakeKv(), ADMIN_NOTIFY_EMAIL: "admin@example.org", ADMIN_EMAIL_SESSION_FOLDER: "C:\\proj" };
  const gate = new AlertGate({ storage: memStorage() }, env);
  const ns = { jurisdiction(j) { ns.j = j; return ns; }, idFromName: (n) => n, get: () => gate };
  env.ALERTS = ns; env.gate = gate;
  return env;
}
const RUN = (over = {}) => ({ v: 1, platform: "windows", version: "2026.11.24.1", os: "Windows 11 Home 26100", arch: "AMD64",
  outcome: "failed", stage: "done", mode: "first", parts: "r,rstudio,python", minutes: 23,
  issues: [["FAIL", "R packages", "statcheck not found", "setup"], ["WARN", "VS Code", "not on PATH", "check"]], ...over });
const post = (body, headers = {}) => new Request("https://box.example/result", { method: "POST",
  headers: { "x-freeaisetup": "1", ...headers }, body: typeof body === "string" ? body : JSON.stringify(body) });
const results = (env, prefix = "results/") => [...env.LOGS.m.keys()].filter((k) => k.startsWith(prefix));

test("POST /result stores one key per run, through the EU gate, with the summary in its metadata", async () => {
  const env = gatedEnv();
  const r = await worker.fetch(post(RUN()), env, {});
  assert.equal(r.status, 200);
  assert.equal(await r.text(), "stored\n");
  assert.equal(env.ALERTS.j, "eu");
  const keys = results(env);
  assert.equal(keys.length, 1);
  assert.match(keys[0], /^results\/production\/\d{4}-\d{2}-\d{2}\/windows\/failed\/[0-9a-f]{8}$/);
  const md = env.LOGS.m.get(keys[0]).metadata;
  assert.equal(md.f, "R packages");
  assert.equal(md.p, "r,rstudio,python");
  assert.match(md.c, /r:f/);          // R packages failed -> the R part failed
  assert.match(md.c, /vscode:w/);     // a warning in the final check
  assert.match(md.c, /rstudio:o/);
  await worker.fetch(post(RUN(), { "x-freeaisetup-env": "local" }), env, {});
  assert.equal(results(env, "results/local/").length, 1);   // a test run is kept apart from production
});

test("POST /result refuses no header, a bad platform, a bad body, and a body over the size limit", async () => {
  const env = gatedEnv();
  assert.equal((await worker.fetch(new Request("https://box.example/result", { method: "POST", body: JSON.stringify(RUN()) }), env, {})).status, 400);
  assert.equal((await worker.fetch(post(RUN({ platform: "amiga" })), env, {})).status, 400);
  assert.equal((await worker.fetch(post("not json"), env, {})).status, 400);
  assert.equal((await worker.fetch(post(RUN({ v: 2 })), env, {})).status, 400);
  assert.equal((await worker.fetch(post(RUN({ outcome: "maybe" })), env, {})).status, 400);
  assert.equal((await worker.fetch(post(RUN({ os: "x".repeat(RESULT_MAX_BYTES) })), env, {})).status, 413);
  assert.equal(results(env).length, 0);
});

test("POST /result: past the daily cap the answer is 'capped' and nothing more is written", async () => {
  const env = gatedEnv();
  const day = new Date().toISOString().slice(0, 10);
  await env.gate.state.storage.put("rcap/production/mac", { day, n: RESULT_DAY_CAP - 1 });
  assert.equal(await (await worker.fetch(post(RUN({ platform: "mac" })), env, {})).text(), "stored\n");
  assert.equal(await (await worker.fetch(post(RUN({ platform: "mac" })), env, {})).text(), "capped\n");
  assert.equal(results(env).length, 1);
  assert.equal(await (await worker.fetch(post(RUN({ platform: "linux" })), env, {})).text(), "stored\n");   // per platform
});

test("the cap counter starts again on a new day", async () => {
  const kv = fakeKv(); const st = memStorage(); const rec = normalizeResult(JSON.stringify(RUN()), "windows").rec;
  await st.put("rcap/production/windows", { day: "2026-11-23", n: RESULT_DAY_CAP });
  assert.equal(await storeResult(kv, st, { environment: "production", platform: "windows", rec }, new Date("2026-11-23T20:00:00Z")), "capped");
  assert.equal(await storeResult(kv, st, { environment: "production", platform: "windows", rec }, new Date("2026-11-24T01:00:00Z")), "stored");
});

test("POST /result: a gate failure answers 503 and is recorded, never a silent 'stored'", async () => {
  const env = gatedEnv();
  env.ALERTS.get = () => ({ fetch: async () => { throw new Error("gate down"); } });
  const r = await worker.fetch(post(RUN()), env, {});
  assert.equal(r.status, 503);
  assert.match(JSON.parse(await env.LOGS.get("alerts/meta")).lastError, /result gate: gate down/);
});

test("normalizeResult keeps only known parts, stages and modes, clips text, and drops non-FAIL/WARN lines", () => {
  const { rec } = normalizeResult(JSON.stringify(RUN({ parts: "r, evil ,claude", stage: "hack", mode: "x", minutes: 9999,
    issues: [["OK", "Git", "fine"], ["FAIL", "a".repeat(100), "b".repeat(300), "weird"], "not a list"] })), "windows");
  assert.deepEqual(rec.parts, ["r", "claude"]);
  assert.equal(rec.stage, "install");
  assert.equal(rec.mode, "first");
  assert.equal(rec.minutes, 600);
  assert.equal(rec.issues.length, 1);
  assert.equal(rec.issues[0][1].length, 60);
  assert.equal(rec.issues[0][2].length, 200);
  assert.equal(rec.issues[0][3], "setup");
});

test("componentOf maps every part's step names, and anything unknown to core", () => {
  const cases = { "R step": "r", "R packages": "r", "RStudio": "rstudio", "Quarto": "quarto", "Python step": "python",
    "Node.js": "node", "VS Code": "vscode", "GitHub CLI": "web", "Vercel": "web", "Neon": "web", "Railway": "web",
    "Codex": "codex", "Claude Code": "claude", "Free disk space": "computer", "Smart App Control": "computer",
    "Course folder": "course", "OpenRouter key": "course", "Installer download": "installer", "Setup stopped": "stopped",
    "OpenCode": "core", "Git": "core", "uv": "core", "Something new": "core" };
  for (const [label, c] of Object.entries(cases)) assert.equal(componentOf(label), c, label);
});

test("componentStatus: chosen parts are ok only when the run reached its end; a FAIL beats a WARN", () => {
  const base = normalizeResult(JSON.stringify(RUN({ issues: [["WARN", "R step", "slow"], ["FAIL", "R packages", "x"]] })), "windows").rec;
  assert.equal(componentStatus(base).r, "failed");
  assert.equal(componentStatus(base).python, "ok");
  const early = { ...base, stage: "precheck", issues: [] };
  assert.equal(componentStatus(early).python, "not reached");
  const inst = { ...base, stage: "installer", parts: [], issues: [["FAIL", "Installer download", "x"]] };
  assert.deepEqual(componentStatus(inst), { installer: "failed" });
});

test("resultMeta stays under KV's 1,024-byte metadata limit and a '|' in a step name cannot split a failure", () => {
  const many = Array.from({ length: 60 }, (_, i) => ["FAIL", `Step ${i} ü€ ${"x".repeat(40)}`, "d"]);
  const rec = normalizeResult(JSON.stringify(RUN({ issues: many })), "windows").rec;
  const m = resultMeta(rec, new Date("2026-11-24T10:00:00Z"));
  assert.ok(new TextEncoder().encode(JSON.stringify(m)).length <= 1024);
  assert.ok(m.f.length > 0);
  const piped = normalizeResult(JSON.stringify(RUN({ issues: [["FAIL", "A|B", "x"]] })), "windows").rec;
  assert.equal(resultMeta(piped, new Date()).f.split("|").length, 1);
});

test("digestWindow: whole UTC days before today, next window starts where the last ended, never over 35 days", () => {
  const w1 = digestWindow(undefined, new Date("2026-11-16T06:00:00Z"));   // a Monday, first digest
  assert.deepEqual(w1.days, ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"]);
  const w2 = digestWindow("2026-11-16T06:00:00Z", new Date("2026-11-23T06:00:05Z"));
  assert.equal(w2.days[0], "2026-11-16");           // no gap, no overlap with w1
  assert.equal(w2.days.at(-1), "2026-11-22");
  assert.ok(!w2.days.includes("2026-11-23"));       // today is still filling: next week's digest
  assert.equal(digestWindow("2025-01-01T00:00:00Z", new Date("2026-11-23T06:00:00Z")).days.length, 35);
  // a re-run the same day covers nothing (it used to repeat the previous week: Sol review 2026-11-24)
  const again = digestWindow("2026-11-23T05:00:00Z", new Date("2026-11-23T06:00:00Z"));
  assert.equal(again.already, true); assert.equal(again.days.length, 0);
  // more than 5 weeks since the previous digest: the days left out are counted, not dropped silently
  assert.equal(digestWindow("2025-01-01T00:00:00Z", new Date("2026-11-23T06:00:00Z")).notCovered, 691 - 35);
  assert.equal(w2.notCovered, 0);
});

test("the weekly digest: runs by outcome and platform, parts chosen, each part's result, failure cards with the run key", async () => {
  const env = gatedEnv(); const sent = []; const send = async (_e, m) => sent.push(m);
  const at = (iso, over) => storeResult(env.LOGS, env.gate.state.storage, { environment: "production", platform: over.platform || "windows",
    rec: normalizeResult(JSON.stringify(RUN(over)), over.platform || "windows").rec }, new Date(iso));
  await at("2026-11-17T10:00:00Z", { outcome: "ok", issues: [], parts: "r,python" });
  await at("2026-11-18T10:00:00Z", { platform: "mac", outcome: "ok", os: "Darwin 15.1", issues: [], parts: "r" });
  await at("2026-11-19T10:00:00Z", {});                                            // failed at R packages
  await at("2026-11-20T10:00:00Z", { platform: "mac", os: "Darwin 15.1" });        // the same step failed again
  await at("2026-11-23T01:00:00Z", {});                                            // today: next week's digest
  await storeResult(env.LOGS, env.gate.state.storage, { environment: "local", platform: "windows",
    rec: normalizeResult(JSON.stringify(RUN()), "windows").rec }, new Date("2026-11-19T10:00:00Z"));   // a test: not counted
  const r = await sendDigest(env, new Date("2026-11-23T06:00:00Z"), send);
  assert.equal(r.runs, 4); assert.equal(r.ok, 2); assert.equal(r.failed, 2);
  const t = sent[0].text;
  assert.match(sent[0].subject, /Weekly digest/);
  assert.match(t, /Runs: 4: 2 ok, 2 failed, 0 stopped/);
  assert.match(t, /windows: 2 runs: 1 ok, 1 failed/);
  assert.match(t, /mac: 2 runs: 1 ok, 1 failed/);
  assert.match(t, /Windows 11 Home 26100 2/);
  assert.match(t, /r: 4 of 4/);                    // every run chose R
  assert.match(t, /r: ok 2, failed 2/);
  assert.match(t, /R packages: 2×/);
  assert.match(t, /R packages failed in 2 runs \(r; mac 1, windows 1\)/);
  assert.match(sent[0].subject, /16 Nov.22 Nov/);   // the days covered, not the midnight after them
  // the latest run key is in the failure card's own session button, so that session can read the run
  assert.ok(sent[0].html.includes(encodeURIComponent("results/production/2026-11-20/mac/failed/")));
  assert.match(sent[0].html, /Start a session on this whole digest/);
});

test("summarizeResults on an empty week says so instead of inventing numbers", () => {
  const R = summarizeResults([], {});
  assert.equal(R.runs, 0); assert.equal(R.cards.length, 0);
  assert.match(R.tables[0].rows[0][1], /^0: 0 ok/);
  assert.equal(R.tables[0].rows.at(-1)[1], "no successful run");
});

// Sol review 2026-11-24 (findings 4 and 5): each test below failed on the code of 7299bba
test("POST /result: an error page from the gate is 'not stored' (503), never 'stored'", async () => {
  const env = gatedEnv();
  env.ALERTS.get = () => ({ fetch: async () => new Response("Internal Server Error", { status: 500 }) });
  const r = await worker.fetch(post(RUN()), env, {});
  assert.equal(r.status, 503);
  assert.equal(await r.text(), "not stored\n");
  assert.match(JSON.parse(await env.LOGS.get("alerts/meta")).lastError, /result gate: gate answered 500/);
});

test("a part named many times counts once, and the largest allowed result still fits KV's metadata limit", async () => {
  const env = gatedEnv();
  const big = RUN({ parts: Array(1500).fill("r,rstudio,quarto,python,node,vscode,web,codex,claude").join(",").slice(0, 3000),
    os: "漢".repeat(60), version: "9".repeat(32), arch: "ü".repeat(16),
    issues: Array.from({ length: 60 }, (_, i) => ["FAIL", `${i} ${"€".repeat(57)}`, "d"]) });
  assert.deepEqual(normalizeResult(JSON.stringify(RUN({ parts: "r,r,r,python" })), "windows").rec.parts, ["r", "python"]);
  const r = await worker.fetch(post(big), env, {});
  assert.equal(await r.text(), "stored\n");                 // the fake KV throws past 1,024 bytes, like KV
  const md = env.LOGS.m.get(results(env)[0]).metadata;
  assert.equal(md.p, "r,rstudio,quarto,python,node,vscode,web,codex,claude");
});

test("the same step failing twice in one run is one failed run of that step", () => {
  const rec = normalizeResult(JSON.stringify(RUN({ issues: [["FAIL", "R packages", "a", "setup"], ["FAIL", "R packages", "b", "check"]] })), "windows").rec;
  const m = resultMeta(rec, new Date("2026-11-24T10:00:00Z"));
  assert.equal(m.f, "R packages");
  const R = summarizeResults([{ ...m, platform: "windows", key: "k1" }, { ...m, f: "R packages|R packages", platform: "mac", key: "k2" }], {});
  assert.match(R.tables.at(-1).rows[0][1], /^2×/);           // two runs, not three or four
});

test("the digest counts every distinct failed step, not only the 10 cards shown, and a second run the same day sends nothing", async () => {
  const env = gatedEnv(); const sent = []; const send = async (_e, m) => sent.push(m);
  for (let i = 0; i < 12; i++) {
    await storeResult(env.LOGS, env.gate.state.storage, { environment: "production", platform: "windows",
      rec: normalizeResult(JSON.stringify(RUN({ issues: [["FAIL", `Step ${i}`, "x"]] })), "windows").rec }, new Date("2026-11-18T10:00:00Z"));
  }
  const r = await sendDigest(env, new Date("2026-11-23T06:00:00Z"), send);
  assert.equal(r.issues, 12);
  assert.match(sent[0].text, /Distinct issues\W+12/);
  const again = await sendDigest(env, new Date("2026-11-23T09:00:00Z"), send);
  assert.match(again.skipped, /already sent today/);
  assert.equal(sent.length, 1);
});

test("a digest after more than 5 weeks says which days it did not cover", async () => {
  const env = gatedEnv(); const sent = []; const send = async (_e, m) => sent.push(m);
  await env.LOGS.put("alerts/meta", JSON.stringify({ lastDigest: "2026-09-01T06:00:00Z" }));
  await sendDigest(env, new Date("2026-11-23T06:00:00Z"), send);
  assert.match(sent[0].text, /48 earlier day\(s\) since the previous digest NOT covered/);
});
