// Run: npm test   (node --test; no network, no Cloudflare, no SES: KV and the sender are fakes)
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseFailures, onFailedReport, sendDigest, environmentOf } from "../src/alerts.js";

function fakeKv() {
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? m.get(k) : null; },
    async put(k, v) { m.set(k, v); },
    async list({ prefix = "" } = {}) { return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true }; },
  };
}
const REPORT = "== setup-report.txt ==\nOK    git                    git version 2.56\nFAIL  Python step            ImportError: DLL load failed while importing _extra\nFAIL  R step                 package statcheck not found\n";
const env = () => ({ LOGS: fakeKv(), ADMIN_NOTIFY_EMAIL: "admin@example.org", ADMIN_EMAIL_SESSION_FOLDER: "C:\\proj", ADMIN_LOG_URL: "https://dash.example/kv" });
const rep = (key, extra = {}) => ({ key, platform: "windows", version: "2026.11.12.1", country: "AT", body: REPORT, environment: "production", ...extra });

test("parseFailures reads every FAIL line with step and detail", () => {
  assert.deepEqual(parseFailures(REPORT), [
    { step: "Python step", detail: "ImportError: DLL load failed while importing _extra" },
    { step: "R step", detail: "package statcheck not found" },
  ]);
  assert.deepEqual(parseFailures("OK all good"), []);
});

test("a production failed report sends one standard alert with the session button", async () => {
  const e = env(); const sent = [];
  const out = await onFailedReport(e, rep("2026-11-12/windows/failed/AAAAAA"), new Date("2026-11-12T10:00:00Z"), async (_e, m) => sent.push(m));
  assert.equal(out, "emailed");
  assert.equal(sent.length, 1);
  assert.match(sent[0].subject, /^\[P2 HIGH\] freeAIsetup · windows setup failed at Python step, R step/);
  assert.match(sent[0].html, /claude:\/\/code\/new\?q=/);
  assert.match(sent[0].html, /folder=C%3A%5Cproj/);
  assert.match(sent[0].text, /2026-11-12\/windows\/failed\/AAAAAA/);   // the report key, so the session can fetch it
  assert.match(sent[0].text, /Users affected: 1 student/);
});

test("the same failure within 24 h is counted, not re-sent; after 24 h it alerts with the count", async () => {
  const e = env(); const sent = []; const s = async (_e, m) => sent.push(m);
  await onFailedReport(e, rep("2026-11-12/windows/failed/AAAAAA"), new Date("2026-11-12T10:00:00Z"), s);
  const second = await onFailedReport(e, rep("2026-11-12/windows/failed/BBBBBB"), new Date("2026-11-12T12:00:00Z"), s);
  assert.equal(second, "muted (same issue alerted in the last 24 h)");
  assert.equal(sent.length, 1);
  const third = await onFailedReport(e, rep("2026-11-13/windows/failed/CCCCCC"), new Date("2026-11-13T11:00:00Z"), s);
  assert.equal(third, "emailed");
  assert.match(sent[1].text, /Occurrences: 3 \(2 since last alert\)/);
});

test("a different failure is a different issue and alerts at once", async () => {
  const e = env(); const sent = []; const s = async (_e, m) => sent.push(m);
  await onFailedReport(e, rep("k1"), new Date("2026-11-12T10:00:00Z"), s);
  await onFailedReport(e, rep("k2", { body: "FAIL  Quarto                 not found" }), new Date("2026-11-12T10:05:00Z"), s);
  assert.equal(sent.length, 2);
});

test("at most 10 alert emails a day; the 10th says the cap is reached", async () => {
  const e = env(); const sent = []; const s = async (_e, m) => sent.push(m);
  for (let i = 0; i < 12; i++) {
    await onFailedReport(e, rep(`k${i}`, { body: `FAIL  Step${"abcdefghijkl"[i]}              broke` }), new Date(`2026-11-12T10:${String(i).padStart(2, "0")}:00Z`), s);
  }
  assert.equal(sent.length, 10);
  assert.match(sent[9].text, /Alert cap reached/);
});

test("non-production (local test) reports are recorded but not emailed unless opted in", async () => {
  const e = env(); const sent = []; const s = async (_e, m) => sent.push(m);
  const out = await onFailedReport(e, rep("k1", { environment: "local" }), new Date("2026-11-12T10:00:00Z"), s);
  assert.match(out, /not emailed \(local/);
  assert.equal(sent.length, 0);
  e.ALERT_EMAILS_NON_PRODUCTION = "1";
  await onFailedReport(e, rep("k2", { environment: "local", body: "FAIL  Other   x" }), new Date("2026-11-12T10:00:00Z"), s);
  assert.match(sent[0].subject, /^\[LOCAL TEST - NOT PRODUCTION\] /);
});

test("the originator header decides the environment; students send none (= production)", () => {
  const h = (v) => ({ headers: new Headers(v ? { "x-freeaisetup-env": v } : {}) });
  assert.equal(environmentOf(h()), "production");
  assert.equal(environmentOf(h("local")), "local");
});

test("a failing sender never throws into the upload and is recorded for the digest", async () => {
  const e = env();
  const out = await onFailedReport(e, rep("k1"), new Date("2026-11-12T10:00:00Z"), async () => { throw new Error("SES answered 403"); });
  assert.match(out, /^error: .*SES answered 403/);
  const meta = JSON.parse(await e.LOGS.get("alerts/meta"));
  assert.equal(meta.sendFailures, 1);
  // the report still lands on its issue, so the digest lists it and the next report retries the alert
  const states = [...e.LOGS.m.keys()].filter((k) => k.startsWith("alerts/state/production/"));
  assert.equal(states.length, 1);
  assert.equal(JSON.parse(e.LOGS.m.get(states[0])).lastAlertedAt, null);
});

test("missing settings fail loudly (recorded), never a silent default recipient", async () => {
  const e = env(); delete e.ADMIN_NOTIFY_EMAIL;
  const out = await onFailedReport(e, rep("k1"), new Date("2026-11-12T10:00:00Z"));
  assert.match(out, /ADMIN_NOTIFY_EMAIL is not set/);
});

test("fortnight digest counts reports since the last digest and lists open issues; quiet digest still sends", async () => {
  const e = env(); const sent = []; const s = async (_e, m) => sent.push(m);
  await e.LOGS.put("2026-11-05/windows/failed/AAAAAA", REPORT);
  await e.LOGS.put("2026-11-07/mac/failed/BBBBBB", REPORT);
  await e.LOGS.put("2026-10-01/mac/failed/OLDOLD", REPORT);   // before the period: not counted
  await onFailedReport(e, rep("2026-11-05/windows/failed/AAAAAA"), new Date("2026-11-05T10:00:00Z"), async () => {});
  const r = await sendDigest(e, new Date("2026-11-15T06:00:00Z"), s);
  assert.equal(r.reports, 2);
  assert.equal(r.issues, 1);
  assert.match(sent[0].subject, /Fortnight digest .*1 open issue .*action required/);
  assert.match(sent[0].html, /Start a session on this whole digest/);
  const quiet = await sendDigest(e, new Date("2026-12-01T06:00:00Z"), s);
  assert.equal(quiet.reports, 0);
  assert.match(sent[1].subject, /all quiet/);
});

// ---- added 2026-11-12: every stop reaches the log box, Mac log lines parse, success counts ----
import worker from "../src/index.js";

test("parseFailures also reads the Mac log (indented, coloured, detail in brackets) and the installers' reports, once per step", () => {
  const mac = "  \x1b[31mFAIL\x1b[0m  Free disk space  (3 GB free, 8 GB needed)\n";
  assert.deepEqual(parseFailures(mac), [{ step: "Free disk space", detail: "3 GB free, 8 GB needed" }]);
  const inst = "== installer (install.ps1) ==\nFAIL  Installer download  no source gave a signed file list\n";
  assert.deepEqual(parseFailures(inst), [{ step: "Installer download", detail: "no source gave a signed file list" }]);
  const twice = "FAIL  R step                 see log\n== setup log ==\nFAIL  R step  see log\n";
  assert.equal(parseFailures(twice).length, 1);
});

test("the deploy check's alert says it is the deploy check, not a student", async () => {
  const e = env(); const sent = [];
  await onFailedReport(e, rep("k-deploy", { version: "DEPLOY-CHECK", body: "FAIL  Deploy check           not a student" }), new Date("2026-11-12T10:00:00Z"), async (_e, m) => sent.push(m));
  assert.match(sent[0].text, /deploy's own confirming check, not a student/);
  assert.doesNotMatch(sent[0].text, /A student's/);
});

const ctx = () => { const w = []; return { w, waitUntil: (p) => w.push(p) }; };
const post = (path, headers = {}, body = "") => new Request(`https://box.example${path}`, { method: "POST", headers: { "x-freeaisetup": "1", ...headers }, body });

test("/count stores one key per success with platform and version only, and the environment from the header", async () => {
  const e = env();
  const r = await worker.fetch(post("/count?platform=windows&version=2026.11.12.1"), e, ctx());
  assert.equal(r.status, 200);
  await worker.fetch(post("/count?platform=mac&version=2026.11.12.1", { "x-freeaisetup-env": "local" }), e, ctx());
  const keys = [...e.LOGS.m.keys()];
  assert.equal(keys.filter((k) => /^stats\/production\/\d{4}-\d{2}-\d{2}\/windows\/[0-9a-f]{8}$/.test(k)).length, 1);
  assert.equal(keys.filter((k) => k.startsWith("stats/local/")).length, 1);
  assert.equal(e.LOGS.m.get(keys.find((k) => k.startsWith("stats/production/"))), "");   // no content at all
});

test("/count refuses requests without the header or with an unknown platform", async () => {
  const e = env();
  assert.equal((await worker.fetch(new Request("https://box.example/count?platform=windows", { method: "POST" }), e, ctx())).status, 400);
  assert.equal((await worker.fetch(post("/count?platform=amiga"), e, ctx())).status, 400);
  assert.equal(e.LOGS.m.size, 0);
});

test("the digest reports successful installs of the period by platform, production only", async () => {
  const e = env(); const sent = [];
  await e.LOGS.put("stats/production/2026-11-05/windows/aaaaaaaa", "");
  await e.LOGS.put("stats/production/2026-11-06/windows/bbbbbbbb", "");
  await e.LOGS.put("stats/production/2026-11-06/mac/cccccccc", "");
  await e.LOGS.put("stats/local/2026-11-06/mac/dddddddd", "");          // a test: not counted
  await e.LOGS.put("stats/production/2026-10-01/mac/eeeeeeee", "");     // before the period: not counted
  const r = await sendDigest(e, new Date("2026-11-15T06:00:00Z"), async (_e, m) => sent.push(m));
  assert.equal(r.installs, 3);
  assert.match(sent[0].text, /windows 2, mac 1/);
});
