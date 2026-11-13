// Admin alerts for the setup log box (admin email standard: an alert as each failed setup report
// arrives, at most one per issue per 24 h and 10 a day; a digest on the 1st and 15th of each month).
// All state lives in the same KV namespace under "alerts/", next to the reports themselves.
import { AwsClient } from "aws4fetch";
import { fingerprint, shouldAlert, emailPolicy, renderIssueAlert, renderDigest } from "./admin-email.ts";

export const APP = "freeAIsetup";
const DAY_MS = 24 * 3600 * 1000;
const STATE_TTL = 200 * 24 * 3600;   // a little longer than the reports themselves (180 days)

// "FAIL  Python step            ImportError: ..." lines: setup-report.txt, the Windows setup log, the installers' own
// reports, and the Mac setup log (which indents them, may colour them and puts the detail in brackets).
// One step is listed once, so a failure shown in both the report and the log is not counted twice.
export function parseFailures(body) {
  const out = []; const seen = new Set();
  for (const raw of String(body).split(/\r?\n/)) {
    const line = raw.replace(/\x1b\[[0-9;]*m/g, "").trim();
    const m = /^FAIL\s+(\S.*?)\s{2,}(\S.*)$/.exec(line) || /^FAIL\s+(\S.*)$/.exec(line);
    if (!m) continue;
    const step = m[1].trim(); const detail = (m[2] || "").trim().replace(/^\((.*)\)$/, "$1");
    if (seen.has(step)) continue;
    seen.add(step); out.push({ step, detail });
    if (out.length >= 20) break;
  }
  return out;
}

// Owner request 2026-11-12: count successful installs. One KV key per success (no read-then-write, so two at the
// same moment cannot overwrite each other); the key holds only the day, platform, version and a random id.
export const COUNT_TTL = 400 * 24 * 3600;   // a little over a year, for year-on-year numbers
export const COUNT_DAY_CAP = 500;            // installs counted per day, per environment and platform (src/index.js)
export function countKey(environment, platform, now = new Date(), rnd = crypto.randomUUID().slice(0, 8)) {
  return `stats/${environment}/${now.toISOString().slice(0, 10)}/${platform}/${rnd}`;
}

// The originator says where it ran: students' setups send nothing (= production); tests send "local".
export function environmentOf(req) {
  const e = (req.headers.get("x-freeaisetup-env") || "production").toLowerCase().replace(/[^a-z-]/g, "").slice(0, 16);
  return e || "production";
}

export function issueFor({ key, platform, version, country, body, environment, now, state, env }) {
  const fails = parseFailures(body);
  const steps = fails.map((f) => f.step);
  const first = fails[0];
  const message = first ? `${first.step}: ${first.detail}` : "no FAIL line found in the report";
  const fp = fingerprint(APP, "setup failed", platform, message, steps.join(", "));
  const nowIso = now.toISOString();
  const count = (state?.count || 0) + 1;
  const sinceLast = state?.lastAlertedAt ? (state.countSinceAlert || 0) + 1 : undefined;
  const failList = fails.length ? fails.map((f) => `${f.step}: ${f.detail || "(no detail)"}`).join("\n") : "The report has no FAIL lines; open the full log.";
  return {
    app: APP,
    priority: "P2",   // a student's setup failed: a feature is failing for some users (standard §2)
    summary: `${platform} setup failed${steps.length ? " at " + steps.slice(0, 3).join(", ") : ""} (version ${version || "not recorded"})`,
    explanation: (version === "DEPLOY-CHECK"
      ? "This is the deploy's own confirming check, not a student: it proves that a failed report reaches you as an email. "
      : `A student's ${platform} setup finished with ${fails.length || "unknown"} failed step${fails.length === 1 ? "" : "s"} and they chose to send the report to you. `) +
      `This is report ${key.split("/").pop()}${count > 1 ? `; the same failure has now arrived ${count} times` : ""}. ` +
      `The student was offered the AI setup helper next, so it may already be fixed on their side; the report says what broke.`,
    event: "setup failed",
    message: `Report key ${key}. ${message}`,
    errorClass: platform,
    route: steps.join(", ") || "not recorded",
    requestId: key,
    firstSeen: state?.firstSeen || nowIso,
    lastSeen: nowIso,
    count,
    countSinceLastAlert: sinceLast,
    fingerprint: fp,
    environment,
    platform: "cloudflare worker",
    release: version || undefined,
    stack: failList,
    source: `student setup report (country ${country || "not recorded"})`,
    suggestedStep: `Read the full report: in the logs-worker folder run  npx wrangler kv key get "${key}" --binding LOGS --remote`,
    importance: { usersAffected: version === "DEPLOY-CHECK" ? "none (deploy check)" : count > 1 ? `${count} reports so far` : "1 student", scienceAffected: "no", moneyAffected: "no", dataAtRisk: "no" },
    adminLogUrl: env.ADMIN_LOG_URL || undefined,
  };
}

export async function sendEmail(env, { subject, html, text }) {
  if (!env.ADMIN_NOTIFY_EMAIL) throw new Error("ADMIN_NOTIFY_EMAIL is not set: no admin email can be sent");
  if (!env.SES_ACCESS_KEY_ID || !env.SES_SECRET_ACCESS_KEY || !env.SES_FROM) throw new Error("SES_ACCESS_KEY_ID / SES_SECRET_ACCESS_KEY / SES_FROM not set");
  const region = env.SES_REGION || "eu-west-1";
  const aws = new AwsClient({ accessKeyId: env.SES_ACCESS_KEY_ID, secretAccessKey: env.SES_SECRET_ACCESS_KEY, region, service: "ses" });
  const r = await aws.fetch(`https://email.${region}.amazonaws.com/v2/email/outbound-emails`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({
      FromEmailAddress: env.SES_FROM,
      Destination: { ToAddresses: env.ADMIN_NOTIFY_EMAIL.split(",").map((s) => s.trim()).filter(Boolean) },
      Content: { Simple: { Subject: { Data: subject, Charset: "UTF-8" },
        Body: { Html: { Data: html, Charset: "UTF-8" }, Text: { Data: text, Charset: "UTF-8" } } } },
    }),
  });
  if (!r.ok) throw new Error(`SES answered ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return (await r.json()).MessageId;
}

async function getJson(kv, k) { const v = await kv.get(k); return v ? JSON.parse(v) : null; }

// ---- One at a time (d-09bd19) --------------------------------------------------------------------------------
// Every alert decision reads its state (issue, day counter, muted list, alerts/meta) and writes it back. Two
// reports at the same moment would both read the old state: two emails for one issue, an 11th email past the cap,
// a lost count, a lost lastDigest. So reports and the digest all run in ONE Durable Object (AlertGate in
// src/index.js), one after the other (makeQueue), reading their state from that object's own storage, which is
// strongly consistent (consistentKv); KV stays the store the digest and the teacher read. The object keeps a
// written value only for KEEP_LOCAL_MS, the time KV may take to show a write everywhere (about 60 s), so a key
// deleted from KV by hand (the deploy check cleans up after itself) is gone for the alerts too a minute later.
export function makeQueue() {
  let tail = Promise.resolve();
  return (fn) => { const run = tail.then(fn, fn); tail = run.catch(() => {}); return run; };
}
export const KEEP_LOCAL_MS = 90 * 1000;
export function consistentKv(kv, storage, clock = Date.now) {
  return {
    async get(k) {
      const s = await storage.get(k);
      if (s && s.exp > clock()) return s.v;
      if (s) await storage.delete(k);   // KV shows the write everywhere by now: read KV
      return kv.get(k);
    },
    async put(k, v, opts = {}) {
      await kv.put(k, v, opts);
      const ttl = opts.expirationTtl ? opts.expirationTtl * 1000 : Infinity;
      await storage.put(k, { v, exp: clock() + Math.min(ttl, KEEP_LOCAL_MS) });
    },
    list: (o) => kv.list(o),
  };
}

// The digest, recording its own failure for the next digest (was inline in src/index.js scheduled()).
export async function runDigest(env, now, send = sendEmail) {
  try { return await sendDigest(env, now, send); }
  catch (e) {
    const meta = (await getJson(env.LOGS, "alerts/meta")) || {};
    meta.lastError = `${now.toISOString()} digest: ${String((e && e.message) || e).slice(0, 300)}`;
    meta.sendFailures = (meta.sendFailures || 0) + 1;
    await env.LOGS.put("alerts/meta", JSON.stringify(meta));
    console.error(meta.lastError);
    return { error: meta.lastError };
  }
}

// Called after a failed report is stored. Never throws: the student's upload must succeed regardless.
export async function onFailedReport(env, { key, platform, version, country, body, environment }, now = new Date(), send = sendEmail) {
  const kv = env.LOGS;
  const meta = (await getJson(kv, "alerts/meta")) || {};
  try {
    const fails = parseFailures(body);
    const probe = fingerprint(APP, "setup failed", platform, fails[0] ? `${fails[0].step}: ${fails[0].detail}` : "no FAIL line found in the report", fails.map((f) => f.step).join(", "));
    const stateKey = `alerts/state/${environment}/${probe}`;
    const state = await getJson(kv, stateKey);
    const issue = issueFor({ key, platform, version, country, body, environment, now, state, env });
    const dayKey = `alerts/day/${now.toISOString().slice(0, 10)}`;
    const today = (await getJson(kv, dayKey)) || { sent: 0, muted: [] };
    const policy = emailPolicy(environment, env);
    const next = { fingerprint: issue.fingerprint, summary: issue.summary, firstSeen: issue.firstSeen, lastSeen: issue.lastSeen,
      count: issue.count, countSinceAlert: (state?.countSinceAlert || 0) + 1, lastAlertedAt: state?.lastAlertedAt || null,
      lastKey: key, environment, platform, version };
    let outcome = "recorded";
    // Record the report on its issue BEFORE sending: a failed send must still leave it in the digest.
    await kv.put(stateKey, JSON.stringify(next), { expirationTtl: STATE_TTL });
    if (policy.send && shouldAlert(issue.priority, state?.lastAlertedAt ? new Date(state.lastAlertedAt) : null, today.sent, now)) {
      if (today.sent === 9) {   // the 10th email of the day says the cap is reached (standard §5)
        issue.explanation += " Alert cap reached: this is the 10th alert email today; the rest go into the fortnight digest.";
      }
      await send(env, renderIssueAlert(issue, { prefix: policy.prefix, folder: env.ADMIN_EMAIL_SESSION_FOLDER || "" }));
      today.sent += 1; next.lastAlertedAt = now.toISOString(); next.countSinceAlert = 0;
      meta.lastAlertSent = now.toISOString(); outcome = "emailed";
      await kv.put(dayKey, JSON.stringify(today), { expirationTtl: 3 * 24 * 3600 });
    } else if (policy.send && today.sent >= 10) {
      if (!today.muted.includes(issue.fingerprint)) today.muted.push(issue.fingerprint);
      await kv.put(dayKey, JSON.stringify(today), { expirationTtl: 3 * 24 * 3600 });
      outcome = "muted (daily cap)";
    } else if (policy.send) {
      outcome = "muted (same issue alerted in the last 24 h)";
    } else {
      outcome = `not emailed (${environment}, non-production)`;
    }
    await kv.put(stateKey, JSON.stringify(next), { expirationTtl: STATE_TTL });
    meta.lastReport = now.toISOString(); meta.lastOutcome = outcome;
    await kv.put("alerts/meta", JSON.stringify(meta));
    return outcome;
  } catch (e) {
    meta.lastError = `${now.toISOString()} ${String(e && e.message || e).slice(0, 300)}`;
    meta.sendFailures = (meta.sendFailures || 0) + 1;
    try { await kv.put("alerts/meta", JSON.stringify(meta)); } catch { /* KV down: nothing more we can do */ }
    console.error("alert failed:", meta.lastError);
    return "error: " + meta.lastError;
  }
}

async function listAll(kv, prefix) {
  const keys = []; let cursor;
  do {
    const r = await kv.list({ prefix, cursor });
    keys.push(...r.keys); cursor = r.list_complete ? undefined : r.cursor;
  } while (cursor);
  return keys;
}

// Fortnight digest: every report and issue since the previous digest. Sent even when quiet (it proves the alerting is alive).
export async function sendDigest(env, now = new Date(), send = sendEmail) {
  const kv = env.LOGS;
  const meta = (await getJson(kv, "alerts/meta")) || {};
  const start = meta.lastDigest ? new Date(meta.lastDigest) : new Date(now.getTime() - 15 * DAY_MS);
  const reports = [];
  for (let t = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()); t <= now.getTime(); t += DAY_MS) {
    const day = new Date(t).toISOString().slice(0, 10);
    for (const k of await listAll(kv, day + "/")) reports.push(k);
  }
  const states = [];
  for (const k of await listAll(kv, "alerts/state/production/")) {
    const s = await getJson(kv, k.name);
    if (s && new Date(s.lastSeen) >= start) states.push(s);
  }
  // successful installs (stats/production/<day>/<platform>/<id>) in the same period
  const installs = {}; let installTotal = 0;
  for (let t = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()); t <= now.getTime(); t += DAY_MS) {
    const day = new Date(t).toISOString().slice(0, 10);
    for (const k of await listAll(kv, `stats/production/${day}/`)) { const p = k.name.split("/")[3]; installs[p] = (installs[p] || 0) + 1; installTotal += 1; }
  }
  const by = (f) => reports.reduce((m, k) => { const v = f(k); m[v] = (m[v] || 0) + 1; return m; }, {});
  const plat = by((k) => k.name.split("/")[1]); const res = by((k) => k.name.split("/")[2]);
  const open = states.map((s) => ({ app: APP, priority: "P2", summary: s.summary, explanation: "", event: "setup failed",
    firstSeen: s.firstSeen, lastSeen: s.lastSeen, count: s.count, fingerprint: s.fingerprint, environment: "production",
    message: `Latest report key ${s.lastKey}`, release: s.version, adminLogUrl: env.ADMIN_LOG_URL || undefined }));
  const fmt = (o) => Object.entries(o).map(([k, v]) => `${k} ${v}`).join(", ") || "none";
  const digest = renderDigest({
    app: APP, environment: "production", periodStart: start.toISOString(), periodEnd: now.toISOString(),
    open, resolved: [], noise: [],
    numbers: [
      { label: "Successful installs", value: installTotal },
      { label: "Reports received", value: reports.length },
      { label: "Failed setups", value: res.failed || 0 },
      { label: "Distinct issues", value: states.length },
    ],
    alertingHealth: [
      { label: "Reports by platform", value: fmt(plat) },
      { label: "Successful installs by platform", value: fmt(installs) },
      { label: "Last report", value: meta.lastReport || "none yet" },
      { label: "Last alert email sent", value: meta.lastAlertSent || "none yet" },
      { label: "Alert send failures (all time)", value: String(meta.sendFailures || 0) },
      { label: "Last alert error", value: meta.lastError || "none" },
      { label: "Digest cron last run", value: meta.lastCron || "none (first digest)" },
      { label: "Previous digest", value: meta.lastDigest || "none (first digest)" },
      { label: "Resolved issues", value: "not tracked by the log box; fixes are tracked in TODO.md" },
    ],
    adminUrl: env.ADMIN_LOG_URL || undefined,
  }, { folder: env.ADMIN_EMAIL_SESSION_FOLDER || "" });
  await send(env, digest);
  meta.lastDigest = now.toISOString(); meta.lastCron = now.toISOString();
  await kv.put("alerts/meta", JSON.stringify(meta));
  return { reports: reports.length, issues: states.length, installs: installTotal, subject: digest.subject };
}
