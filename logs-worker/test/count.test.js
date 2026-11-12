// Run: npm test   (node --test; no network, no Cloudflare: KV is a fake)
// POST /count has a daily cap per environment and platform, so a broken or hostile caller cannot fill the KV store.
import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { COUNT_DAY_CAP } from "../src/alerts.js";

function fakeKv() {
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? m.get(k).v : null; },
    async put(k, v, opts = {}) { m.set(k, { v, opts }); },
    async list({ prefix = "" } = {}) { return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true }; },
  };
}
const post = (platform, envHeader) => new Request(`https://x.test/count?platform=${platform}&version=2026.11.12.1`, {
  method: "POST", headers: { "x-freeaisetup": "1", ...(envHeader ? { "x-freeaisetup-env": envHeader } : {}) },
});
const installs = (kv, prefix) => [...kv.m.keys()].filter((k) => k.startsWith(prefix)).length;

test("POST /count stores one key per install up to the daily cap, then answers 'counted' but stores nothing", async () => {
  const env = { LOGS: fakeKv() };
  for (let i = 0; i < COUNT_DAY_CAP + 5; i++) {
    const r = await worker.fetch(post("windows"), env, {});
    assert.equal(r.status, 200);
    assert.equal(await r.text(), "counted\n");
  }
  const day = new Date().toISOString().slice(0, 10);
  assert.equal(installs(env.LOGS, `stats/production/${day}/windows/`), COUNT_DAY_CAP);
  // the cap counter itself expires (3 days) and sits outside the stats/ prefix the digest counts
  const capKeys = [...env.LOGS.m.keys()].filter((k) => k.startsWith("countcap/"));
  assert.equal(capKeys.length, 1);
  assert.equal(env.LOGS.m.get(capKeys[0]).opts.expirationTtl, 3 * 24 * 3600);
});

test("the cap is per platform and per environment", async () => {
  const env = { LOGS: fakeKv() };
  for (let i = 0; i < COUNT_DAY_CAP; i++) await worker.fetch(post("windows"), env, {});
  await worker.fetch(post("mac"), env, {});
  await worker.fetch(post("windows", "local"), env, {});
  const day = new Date().toISOString().slice(0, 10);
  assert.equal(installs(env.LOGS, `stats/production/${day}/mac/`), 1);
  assert.equal(installs(env.LOGS, `stats/local/${day}/windows/`), 1);
});

test("POST /count still refuses a missing header or an unknown platform", async () => {
  const env = { LOGS: fakeKv() };
  assert.equal((await worker.fetch(new Request("https://x.test/count?platform=windows", { method: "POST" }), env, {})).status, 400);
  assert.equal((await worker.fetch(post("amiga"), env, {})).status, 400);
  assert.equal(env.LOGS.m.size, 0);
});
