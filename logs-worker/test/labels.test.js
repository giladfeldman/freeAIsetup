// Run: npm test. Every step name the setups can report is read from the scripts themselves and must map to its part
// (Sol review 2026-11-24: "Vercel CLI (websites)", "R in VS Code", "Key: <provider>" and others were counted as "core",
// and the earlier test used simplified names that the scripts never write).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { componentOf } from "../src/alerts.js";

const read = (p) => fs.readFileSync(new URL(p, import.meta.url), "utf8").replace(/^﻿/, "");
const win = read("../../setup-windows.ps1"), mac = read("../../setup-mac.sh"), py = read("../../lib/course_setup.py");

function stepNames() {
  const s = new Set();
  // literal names: Ok/Warn/Fail 'x' (Windows), ok/warn/fail "x" (Mac/Linux), t.add("ST", "x" (the check)
  for (const m of win.matchAll(/\b(?:Ok|Warn|Fail)\s+(?:'([^'$]*)'|"([^"$]*)")/g)) s.add(m[1] ?? m[2]);
  for (const m of mac.matchAll(/(?:^|[\s;&|(])(?:ok|warn|fail)\s+(?:"([^"$]*)"|'([^']*)')/gm)) s.add(m[1] ?? m[2]);
  for (const m of py.matchAll(/t\.add\([^,]+,\s*"([^"{]*)"/g)) s.add(m[1]);
  // names from variables: the Windows tool tables (Ok/Fail $t.name), Not-Signed's label, the Mac tool loops and
  // npm packages (ok "${item##*:}"), and the check's tools (t.add(..., tool, ...)) and keys (f"Key: {name}")
  for (const m of win.matchAll(/@\{[^}\n]*\bcmd = '[^']*'[^}\n]*\bname = '([^']+)'/g)) s.add(m[1]);
  for (const m of win.matchAll(/@\{[^}\n]*\bname = '([^']+)'[^}\n]*\bcmd = '/g)) s.add(m[1]);
  for (const m of win.matchAll(/Not-Signed '([^']+)' \S+(?: '([^']+)')?/g)) s.add(m[2] ?? m[1]);
  // the brew tool loop (ok "$f" ...), not the uv/uvx file loop of the install record
  for (const m of mac.matchAll(/local f fp; for f in ([a-z ]+); do/g)) for (const f of m[1].trim().split(/\s+/)) s.add(f);
  assert.ok(/local f fp; for f in git node uv; do/.test(mac), "the Mac tool loop changed: update this extraction");
  for (const m of mac.matchAll(/^(?:WEB|CODEX|CLAUDE)_PKGS?="([^"]+)"/gm)) for (const it of m[1].split(/\s+/)) s.add(it.split(":").pop());
  for (const m of mac.matchAll(/npm_tools \w+ [\d.]+ "([^"]+)"/g)) s.add(m[1]);
  for (const m of py.matchAll(/\("([A-Za-z]+)", \["--version"\]\)/g)) s.add(m[1]);
  for (const m of py.matchAll(/\("([a-z]+)", "(?:web|codex|claude)"\)/g)) s.add(m[1]);
  if (/f"Key: \{name\}"/.test(py)) for (const p of JSON.parse(read("../../lib/free-ai.json")).providers) s.add(`Key: ${p.name || p.id}`);
  s.delete(""); return s;
}

// the part each real step name belongs to; a name the scripts write that is missing here fails the test
const PART = {
  // the setup itself (OpenCode, Git, uv, the pack copy, the old update job)
  "Git": "core", "git": "core", "Git, R": "core", "uv": "core", "opencode": "core", "OpenCode command line": "core",
  "OpenCode desktop app": "core", "OpenCode restarted": "core", "OpenCode settings": "core", "Pack copy": "core",
  "Updates": "core", "Old daily update task": "core", "Old daily update check": "core", "Test stop": "core",
  "R": "r", "Rscript": "r", "R on PATH": "r", "R packages": "r", "Pandoc for R": "r", "R step": "r",
  "RStudio": "rstudio", "Quarto": "quarto", "quarto": "quarto", "Report step": "quarto",
  "Python environment": "python", "Python step": "python", "Node.js": "node", "node": "node",
  "VS Code": "vscode", "VS Code add-ons": "vscode", "R in VS Code": "vscode",
  "GitHub CLI": "web", "gh": "web", "Vercel CLI (websites)": "web", "vercel": "web", "Neon CLI (databases)": "web",
  "neonctl": "web", "Railway CLI (small servers)": "web", "railway": "web", "Website tools": "web",
  "Codex": "codex", "codex": "codex", "Claude Code": "claude", "claude": "claude",
  "Windows version": "computer", "macOS version": "computer", "Free disk space": "computer", "Internet access": "computer",
  "Proxy": "computer", "Blocked site": "computer", "GitHub": "computer", "System": "computer",
  "Smart App Control": "computer", "Administrator password": "computer", "winget": "computer", "Homebrew": "computer",
  "apt": "computer", "apt packages": "computer",
  "Course folder": "course", "Course kit": "course", "Check": "course", "AI step": "course", "MCP tools": "course",
  "Automatic AI switch": "course", 
  "Setup stopped": "stopped",
};

test("every step name of the setups maps to its part (names read from the scripts, not typed here)", () => {
  const names = stepNames();
  assert.ok(names.size > 50, `only ${names.size} step names found: the extraction is broken`);   // a zero is not a pass
  for (const want of ["Vercel CLI (websites)", "R in VS Code", "Automatic AI switch", "OpenCode desktop app", "vercel"]) {
    assert.ok(names.has(want), `extraction missed ${want}`);
  }
  const keys = [...names].filter((n) => n.startsWith("Key: "));
  assert.ok(keys.length >= 2, "the AI key providers were not read from lib/free-ai.json");
  for (const k of keys) PART[k] = "course";   // one row per free AI provider (lib/free-ai.json)
  const unknown = [...names].filter((n) => !(n in PART));
  assert.deepEqual(unknown, [], "step names with no part in this test: give each one its part here and in COMPONENT_OF");
  for (const n of names) assert.equal(componentOf(n), PART[n], n);
});

test("the installers' step names belong to the installer", () => {
  for (const f of ["../../install.ps1", "../../install.sh"]) {
    const t = read(f);
    const names = [...t.matchAll(/(?:'|")(Installer [a-z ]+)(?:'|")/g)].map((m) => m[1]);
    assert.ok(names.length > 0, f);
    for (const n of names) assert.equal(componentOf(n), "installer", `${f}: ${n}`);
  }
});

test("the log box removes a login inside an address, e-mail addresses and account folders again", async () => {
  const { normalizeResult } = await import("../src/alerts.js");
  const raw = JSON.stringify({ v: 1, outcome: "failed", issues: [["FAIL", "Proxy",
    String.raw`via http://bob:s3cretpw@proxy.example:8080 for jane.doe@uni.example in C:\Users\Jane Doe\x and /Users/jane/y and /home/jdoe/z and /home/jdoe then see http://x.example/a`]] });
  const d = normalizeResult(raw, "windows").rec.issues[0][2];
  for (const bad of ["s3cretpw", "bob", "jane.doe", "Jane", "Doe", "/jane/", "jdoe"]) assert.ok(!d.includes(bad), `${bad} in: ${d}`);
  assert.match(d, /<login>@proxy\.example/); assert.match(d, /<e-mail>/);
  assert.match(d, /then see http:\/\/x\.example\/a$/);   // only the folder name goes, not the rest of the sentence
});
