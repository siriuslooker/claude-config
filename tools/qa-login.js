#!/usr/bin/env node
// qa-login.js — sign a QA agent's Playwright MCP browser in to a web app, unattended, without the
// agent ever reading or typing the password.
//
// USAGE
//   node ~/.claude/tools/qa-login.js --label "<credentials.json label>" --url <login page URL>
//        [--check-url <URL that requires login>] [--workspace <dir>] [--save-only]
//        [--user-selector <css>] [--pass-selector <css>] [--submit-selector <css>]
//
//   Prints exactly one line: `ok host=<host> label=<label>`, or `fail: <reason>` (exit code != 0).
//   The username and password are never printed, logged or written anywhere.
//
// HOW IT WORKS
//   1. Reads the entry with that `label` from ~/.claude/credentials.json, and refuses unless the URL's
//      host (host:port) is listed in the entry's `hosts`. --check-url must pass the same test.
//   2. Finds the RUNNING Playwright MCP browser. Every MCP browser binds a local pipe endpoint and
//      registers a descriptor in %LOCALAPPDATA%\ms-playwright\b\ (macOS ~/Library/Caches/ms-playwright/b,
//      Linux ~/.cache/ms-playwright/b) naming the endpoint, the MCP's own playwright-core and the
//      workspace it serves. The one whose workspaceDir matches --workspace (default: cwd) is used.
//   3. Connects to it with that same playwright-core (so versions always match and nothing is fetched
//      from the network), signs in inside a THROWAWAY context in that browser, optionally loads
//      --check-url to prove the session, then copies the resulting cookies into the MCP's own context.
//      The MCP's tabs are never touched; the agent simply navigates afterwards and is signed in.
//   4. Also writes the storage state to ~/.claude/.qa-sessions/<host>.storage.json (gitignored by the
//      allowlist .gitignore), usable with the MCP's --storage-state option if that is ever preferred.
//
// PREREQUISITES
//   - The Playwright MCP browser must already be OPEN — have the agent call browser_navigate first
//     (e.g. to the login page). With no open browser the helper fails with a clear reason.
//     --save-only skips the MCP entirely: it launches its own headless browser and just writes the
//     storage-state file.
//   - The MCP must have been run at least once via npx (its playwright-core is found in the npm cache
//     or from the live browser's descriptor). No global Playwright install is needed.
//
// LIMITS
//   - Generic login form only: a visible password field plus a username/email field in the same form.
//     Override with the --*-selector flags. No MFA, CAPTCHA or SSO redirects.
//   - Only cookies are transferred (cookie-session apps). localStorage-token apps are not covered.
//   - The session lasts as long as the app's auth cookie; rerun when it expires or the MCP browser is
//     closed (an --isolated MCP browser forgets everything on close).
//
// This file is in a PUBLIC repo: it must never contain a host, address, username or secret.

'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = os.homedir();
const CREDS = path.join(HOME, '.claude', 'credentials.json');
const STATE_DIR = path.join(HOME, '.claude', '.qa-sessions');

function fail(reason, code = 1) {
  process.stdout.write(`fail: ${reason}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) fail(`unexpected argument ${a}`);
    const key = a.slice(2);
    if (key === 'save-only') { out.saveOnly = true; continue; }
    const v = argv[++i];
    if (v === undefined) fail(`missing value for ${a}`);
    out[key] = v;
  }
  return out;
}

function cacheDir() {
  if (process.platform === 'win32') return process.env.LOCALAPPDATA || path.join(HOME, 'AppData', 'Local');
  if (process.platform === 'darwin') return path.join(HOME, 'Library', 'Caches');
  return process.env.XDG_CACHE_HOME || path.join(HOME, '.cache');
}

function readEntry(label) {
  let j;
  try { j = JSON.parse(fs.readFileSync(CREDS, 'utf8')); } catch (e) { fail('cannot read credentials.json'); }
  const list = Array.isArray(j) ? j : (j.credentials || []);
  const e = list.find((x) => x && x.label === label);
  if (!e) fail('no credentials entry with that label');
  if (!e.username || !e.password) fail('entry has no username/password');
  return e;
}

function hostOf(u, flag) {
  try { return new URL(u).host.toLowerCase(); } catch { fail(`${flag} is not a valid URL`); }
}

// Live MCP browser descriptors, best match first.
function descriptors(workspace) {
  const dir = process.env.PWTEST_SERVER_REGISTRY || path.join(cacheDir(), 'ms-playwright', 'b');
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return []; }
  const norm = (p) => (p ? path.resolve(p).toLowerCase() : '');
  const ws = norm(workspace);
  const out = [];
  for (const n of names) {
    const f = path.join(dir, n);
    try {
      const st = fs.statSync(f);
      if (!st.isFile()) continue;
      const d = JSON.parse(fs.readFileSync(f, 'utf8'));
      if (!d.endpoint || !d.playwrightLib) continue;
      if (norm(d.workspaceDir) !== ws) continue;
      out.push({ d, mtime: st.mtimeMs });
    } catch { /* unreadable or half-written: skip */ }
  }
  return out.sort((a, b) => b.mtime - a.mtime).map((x) => x.d);
}

// A playwright-core for --save-only: the newest one the MCP left in the npm cache.
function cachedPlaywrightCore() {
  const roots = [path.join(cacheDir(), 'npm-cache', '_npx'), path.join(HOME, '.npm', '_npx')];
  const found = [];
  for (const r of roots) {
    let ids = [];
    try { ids = fs.readdirSync(r); } catch { continue; }
    for (const id of ids) {
      const mcp = path.join(r, id, 'node_modules', '@playwright', 'mcp', 'package.json');
      const core = path.join(r, id, 'node_modules', 'playwright-core');
      try { found.push({ core, mtime: fs.statSync(mcp).mtimeMs }); fs.statSync(core); } catch { /* not an MCP install */ }
    }
  }
  found.sort((a, b) => b.mtime - a.mtime);
  return found.length ? found[0].core : null;
}

async function signIn(ctx, entry, opts) {
  const page = await ctx.newPage();
  const loginUrl = new URL(opts.url);
  const resp = await page.goto(opts.url, { waitUntil: 'load', timeout: 60000 }).catch(() => null);
  if (!resp) throw new Error('login page did not load');
  if (resp.status() >= 400) throw new Error(`login page returned ${resp.status()}`);

  const pass = page.locator(opts['pass-selector'] || 'input[type=password]:visible').first();
  if (!(await pass.count())) throw new Error('no password field on the login page');
  const form = pass.locator('xpath=ancestor::form[1]');
  const scope = (await form.count()) ? form : page;
  const user = opts['user-selector']
    ? page.locator(opts['user-selector']).first()
    : scope.locator([
      'input[autocomplete=username]:visible', 'input[type=email]:visible',
      'input[name*=user i]:visible', 'input[name*=email i]:visible', 'input[name*=login i]:visible',
      'input[type=text]:visible',
    ].join(', ')).first();
  if (!(await user.count())) throw new Error('no username field on the login page');

  await user.fill(entry.username);
  await pass.fill(entry.password);
  const submit = opts['submit-selector']
    ? page.locator(opts['submit-selector']).first()
    : scope.locator('button[type=submit]:visible, input[type=submit]:visible, button:not([type]):visible').first();
  const nav = page.waitForNavigation({ waitUntil: 'load', timeout: 30000 }).catch(() => null);
  if (await submit.count()) await submit.click(); else await pass.press('Enter');
  await nav;
  await page.waitForLoadState('load').catch(() => {});

  const after = new URL(page.url());
  if (after.pathname.toLowerCase() === loginUrl.pathname.toLowerCase()
      && (await page.locator('input[type=password]:visible').count())) {
    throw new Error('still on the login page after submitting (wrong credentials or unexpected form)');
  }

  if (opts['check-url']) {
    const r = await page.goto(opts['check-url'], { waitUntil: 'load', timeout: 60000 }).catch(() => null);
    if (!r) throw new Error('check-url did not load');
    const landed = new URL(page.url());
    if (landed.pathname.toLowerCase() === loginUrl.pathname.toLowerCase()) throw new Error('check-url redirected to the login page');
    if (r.status() >= 400) throw new Error(`check-url returned ${r.status()}`);
  }
  await page.close();
  return ctx.storageState();
}

function saveState(host, state) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  const file = path.join(STATE_DIR, `${host.replace(/[^a-z0-9.-]/gi, '_')}.storage.json`);
  fs.writeFileSync(file, JSON.stringify(state, null, 2), { encoding: 'utf8', mode: 0o600 });
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.label || !opts.url) fail('usage: --label "<label>" --url <login URL> [--check-url <URL>]');
  const entry = readEntry(opts.label);
  const hosts = (entry.hosts || []).map((h) => String(h).toLowerCase());
  const host = hostOf(opts.url, '--url');
  if (!hosts.includes(host)) fail(`host ${host} is not in that entry's hosts`);
  if (opts['check-url'] && !hosts.includes(hostOf(opts['check-url'], '--check-url'))) fail("--check-url host is not in that entry's hosts");

  let pw; let browser; let mcpCtx = null;
  if (opts.saveOnly) {
    const lib = cachedPlaywrightCore();
    if (!lib) fail('no cached Playwright MCP install found (run the Playwright MCP once)');
    pw = require(lib);
    browser = await pw.chromium.launch({ channel: 'chrome', headless: true })
      .catch(() => pw.chromium.launch({ headless: true }))
      .catch(() => fail('could not launch a browser'));
  } else {
    const ws = opts.workspace || process.cwd();
    for (const d of descriptors(ws)) {
      try {
        pw = require(d.playwrightLib);
        browser = await pw.chromium.connect(d.endpoint, { timeout: 5000 });
        mcpCtx = browser.contexts()[0] || null;
        if (mcpCtx) break;
        await browser.close().catch(() => {});
        browser = null;
      } catch { browser = null; /* stale descriptor: browser already gone */ }
    }
    if (!browser || !mcpCtx) fail('no open Playwright MCP browser for this workspace (call browser_navigate first, then rerun)', 3);
  }

  let state;
  const tmp = await browser.newContext();
  try {
    state = await signIn(tmp, entry, opts);
  } catch (e) {
    await tmp.close().catch(() => {});
    await browser.close().catch(() => {});
    // Playwright messages never carry filled values, but scrub anyway and keep only the first line.
    let msg = String((e && e.message) || e).split('\n')[0];
    for (const s of [entry.password, entry.username]) msg = msg.split(s).join('***');
    fail(msg, 2);
  }
  await tmp.close().catch(() => {});
  if (mcpCtx) await mcpCtx.addCookies(state.cookies);
  saveState(host, state);
  // On a connected browser close() only disconnects; the MCP's browser and context stay up.
  await browser.close().catch(() => {});
  process.stdout.write(`ok host=${host} label=${opts.label}\n`);
}

main().catch(() => fail('unexpected error'));
