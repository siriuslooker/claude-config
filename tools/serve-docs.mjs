#!/usr/bin/env node
// serve-docs.mjs — serve one or more folders of markdown documents over HTTP as
// raw markdown, for reading on a phone with a browser markdown extension.
//
// Dependency-free: Node standard library only. No node_modules, no package.json.
//
//   node serve-docs.mjs --dir <path> [--port 8899] [--host 127.0.0.1] [--open-to <cidr-or-ip>]
//   node serve-docs.mjs --dir <label>=<path> --dir <label>=<path> [options]
//   node serve-docs.mjs --self-test
//   node serve-docs.mjs --help
//
// There is no markdown parsing here and no HTML generation. Files are served as
// their raw bytes with `Content-Type: text/markdown; charset=utf-8`, which is
// what browser markdown extensions key on. The indexes are themselves markdown,
// so they render through the same extension as everything else.
//
// One --dir given as a bare path serves exactly as it always has: / is the
// document index and documents sit at /<file>.md. Give a label, or more than
// one --dir, and each project mounts under /<label>/ with a root index at /.
//
// Binds loopback by default. Widening the bind is a deliberate flag.

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import process from 'node:process';

const DEFAULT_PORT = 8899;
const DEFAULT_HOST = '127.0.0.1';

/** The entire allowlist. Anything not matching this is a 404. */
const ALLOWED_EXT = /\.md$/i;
const MARKDOWN_TYPE = 'text/markdown; charset=utf-8';

/**
 * A mount label becomes a URL path segment, so a permissive one is a traversal
 * vector. Conservative allowlist, plus explicit refusal of the dot forms the
 * character class would otherwise permit.
 */
const LABEL_RE = /^[A-Za-z0-9._-]+$/;

// ------------------------------------------------------------------ paths --

/**
 * Resolve a request path inside ONE served root.
 *
 * Returns null when the target escapes that root — via `..`, a drive-qualified
 * or UNC path, a NUL byte, or a symlink pointing outward. A path that simply
 * does not exist is NOT an escape: it comes back resolved, so the caller
 * answers 404 rather than 403.
 *
 * With several roots mounted this is called with the root of the mount named by
 * the first path segment and no other, so a traversal out of one project cannot
 * land inside another: it escapes its own root and is refused before any other
 * root is ever consulted.
 *
 * @param {string} root a real (symlink-resolved) directory path
 * @param {string} requestPath a decoded, URL-derived path, relative to the mount
 * @returns {string|null}
 */
function safeResolve(root, requestPath) {
  const rootReal = fs.realpathSync(root);
  let cleaned = String(requestPath);
  if (cleaned.includes('\0')) return null;

  // Every HTTP path begins with '/', so a leading slash means "relative to the
  // served root", not "the filesystem root". Strip it, then refuse anything
  // still absolute (a drive letter, or a UNC/backslash path on Windows).
  cleaned = cleaned.replace(/^[/\\]+/, '');
  if (cleaned === '') return null;
  if (/^[A-Za-z]:/.test(cleaned)) return null;
  if (path.isAbsolute(cleaned)) return null;

  const target = path.resolve(rootReal, cleaned);
  if (target !== rootReal && !target.startsWith(rootReal + path.sep)) return null;

  let real;
  try {
    real = fs.realpathSync(target);
  } catch {
    return target; // does not exist -> caller answers 404
  }
  // realpath followed the symlinks; the resolved target must still be inside.
  if (real !== rootReal && !real.startsWith(rootReal + path.sep)) return null;
  return real;
}

// ----------------------------------------------------------------- mounts --

/** Throws with a specific reason; returns the label when it is acceptable. */
function validateLabel(label) {
  const l = String(label);
  if (l === '') {
    throw new Error('--dir: an empty mount label is not allowed (expected <label>=<path>).');
  }
  if (l.includes('/') || l.includes('\\')) {
    throw new Error(`--dir: mount label ${JSON.stringify(l)} contains a path separator. ` +
      'A label is one URL path segment.');
  }
  if (l.includes('\0')) throw new Error('--dir: mount label contains a NUL byte.');
  if (l.includes('..')) throw new Error(`--dir: mount label ${JSON.stringify(l)} contains '..'.`);
  if (/^\.+$/.test(l)) {
    throw new Error(`--dir: mount label ${JSON.stringify(l)} is a relative-path name.`);
  }
  if (/^[A-Za-z]:/.test(l)) {
    throw new Error(`--dir: mount label ${JSON.stringify(l)} looks like a drive letter.`);
  }
  if (!LABEL_RE.test(l)) {
    throw new Error(`--dir: mount label ${JSON.stringify(l)} has characters outside [A-Za-z0-9._-].`);
  }
  return l;
}

/**
 * Split a --dir value into an optional label and a path.
 *
 * `label=path` is labelled; a value with no '=' is bare. A value that has an
 * '=' but an unusable label part is a startup error rather than a silent
 * fallback to "a bare path that happens to contain an equals sign" — that
 * fallback would hide a typo'd label as a missing directory.
 */
function parseDirSpec(spec) {
  const s = String(spec);
  const eq = s.indexOf('=');
  if (eq === -1) return { label: null, dirPath: s };
  const label = s.slice(0, eq);
  const dirPath = s.slice(eq + 1);
  validateLabel(label);
  if (dirPath === '') {
    throw new Error(`--dir ${s}: no path after the '=' (expected <label>=<path>).`);
  }
  return { label, dirPath };
}

/** Folder names too generic to tell one project from another. */
const GENERIC_DIR_NAMES = new Set(['docs', 'doc', 'documentation', 'documents', 'md', 'markdown']);

/**
 * Derive a label for an unlabelled --dir from the folder's own name — except
 * when that name is generic (`docs` and friends), where the PARENT folder's
 * name is used instead, because every project's documents live in a folder
 * called `docs` and the parent is what actually names the project. Characters
 * outside the allowlist collapse to '-'.
 */
function deriveLabel(dirPath) {
  const resolved = path.resolve(dirPath);
  let name = path.basename(resolved);
  if (GENERIC_DIR_NAMES.has(name.toLowerCase())) {
    const parent = path.basename(path.dirname(resolved));
    if (parent && !/^[A-Za-z]:\\?$/.test(parent)) name = parent;
  }
  let label = String(name).replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^[-.]+|[-.]+$/g, '');
  if (!label || !LABEL_RE.test(label) || label.includes('..')) label = 'docs';
  return label;
}

/**
 * Turn the raw --dir values into validated mounts. Throws on a bad label, a
 * duplicate label (naming both paths), or a path that is not a directory.
 */
function buildMounts(specs) {
  const mounts = [];
  const byLabel = new Map();
  for (const spec of specs) {
    const { label: explicit, dirPath } = parseDirSpec(spec);
    const dir = path.resolve(dirPath);
    if (!fs.existsSync(dir)) throw new Error(`--dir does not exist: ${dir}`);
    if (!fs.statSync(dir).isDirectory()) throw new Error(`--dir is not a directory: ${dir}`);
    const label = explicit === null ? deriveLabel(dir) : explicit;
    if (byLabel.has(label)) {
      throw new Error(
        `--dir: duplicate mount label ${JSON.stringify(label)} — ` +
        `${byLabel.get(label)} and ${dir} would both mount at /${label}/. ` +
        'Give at least one of them an explicit --dir <label>=<path>.');
    }
    byLabel.set(label, dir);
    mounts.push({ label, dir, explicit: explicit !== null });
  }
  return mounts;
}

// ------------------------------------------------------------------ index --

async function walkMarkdown(root, rel = '', acc = []) {
  const dir = path.join(root, rel);
  let entries;
  try {
    entries = await fsp.readdir(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entries) {
    if (e.name.startsWith('.') || e.name === 'node_modules') continue;
    const r = rel ? rel + '/' + e.name : e.name;
    const full = path.join(root, r);
    let st;
    try {
      st = await fsp.stat(full); // stat, not lstat: follows symlinks
    } catch {
      continue; // vanished, or a broken link
    }
    if (st.isDirectory()) {
      // Do not descend through a link that leaves the served tree.
      if (safeResolve(root, r) === null) continue;
      await walkMarkdown(root, r, acc);
    } else if (st.isFile() && ALLOWED_EXT.test(e.name)) {
      if (safeResolve(root, r) === null) continue;
      acc.push({ rel: r, mtime: st.mtimeMs, size: st.size });
    }
  }
  return acc;
}

function fmtTime(ms) {
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
    ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}

function fmtSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

/** Escape the few characters that would break a markdown link label. */
function mdLabel(s) {
  return String(s).replace(/([[\]])/g, '\\$1');
}

/**
 * Build one project's index as a markdown document, newest-modified first.
 *
 * `prefix` is the mount prefix — '' in single-project mode, '/<label>'
 * otherwise. Index links are absolute and carry it, so nothing else needs
 * rewriting when a project moves under a path prefix.
 */
async function indexMarkdown(root, prefix = '') {
  const docs = await walkMarkdown(root);
  docs.sort((a, b) => b.mtime - a.mtime);

  let out = '# Documents\n\n';
  if (!docs.length) {
    out += 'No `.md` files were found under the served directory.\n';
    if (prefix) out += '\n[All projects](/)\n';
    return out;
  }
  out += 'Newest modified first.\n\n';
  for (const d of docs) {
    const href = prefix + '/' + d.rel.split('/').map(encodeURIComponent).join('/');
    out += '- [' + mdLabel(d.rel) + '](' + href + ')  \n';
    out += '  ' + fmtTime(d.mtime) + ' · ' + fmtSize(d.size) + '\n';
  }
  out += '\n---\n\n' + docs.length + ' document' + (docs.length === 1 ? '' : 's') + '.\n';
  if (prefix) out += '\n[All projects](/)\n';
  return out;
}

/** The root index: one entry per mounted project, newest-modified project first. */
async function rootIndexMarkdown(mounts) {
  const rows = [];
  for (const m of mounts) {
    const docs = await walkMarkdown(m.root);
    let newest = 0;
    for (const d of docs) if (d.mtime > newest) newest = d.mtime;
    rows.push({ label: m.label, count: docs.length, newest });
  }
  rows.sort((a, b) => b.newest - a.newest);

  let out = '# Projects\n\n';
  if (!rows.length) {
    out += 'Nothing is mounted.\n';
    return out;
  }
  out += 'Newest modified first.\n\n';
  for (const r of rows) {
    out += '- [' + mdLabel(r.label) + '](/' + encodeURIComponent(r.label) + '/)  \n';
    out += '  ' + r.count + ' document' + (r.count === 1 ? '' : 's');
    if (r.newest) out += ' · ' + fmtTime(r.newest);
    out += '\n';
  }
  out += '\n---\n\n' + rows.length + ' project' + (rows.length === 1 ? '' : 's') + '.\n';
  return out;
}

const NOT_FOUND_MD = (what, home = '/') =>
  '# 404 — not found\n\nNo document at `' + String(what).replace(/`/g, "'") +
  '`.\n\nOnly `.md` files under the served directory are available.\n\n' +
  '[Back to the index](' + home + ')\n';

const FORBIDDEN_MD = (home = '/') =>
  '# 403 — refused\n\nThat path resolves outside the served directory.\n\n' +
  '[Back to the index](' + home + ')\n';

// ----------------------------------------------------------------- server --

/**
 * @param {object} o
 * @param {string} [o.dir] single-project mode: serve this directory at /
 * @param {Array<{label:string,dir:string}>} [o.mounts] multi-project mode
 */
function startServer({ dir, mounts, port, host, quiet = false, onListen = null }) {
  const single = !mounts || mounts.length === 0;
  const table = single
    ? [{ label: null, dir, root: fs.realpathSync(dir) }]
    : mounts.map((m) => ({ label: m.label, dir: m.dir, root: fs.realpathSync(m.dir) }));
  const byLabel = new Map(table.map((m) => [m.label, m]));
  const log = (...a) => { if (!quiet) console.log(...a); };

  const server = http.createServer(async (req, res) => {
    let pathname = req.url || '/';
    const q = pathname.indexOf('?');
    if (q !== -1) pathname = pathname.slice(0, q);
    try {
      pathname = decodeURIComponent(pathname);
    } catch {
      // leave the raw form; it will fail the allowlist or the root check
    }

    const send = (code, body, type) => {
      const buf = Buffer.isBuffer(body) ? body : Buffer.from(body, 'utf8');
      res.writeHead(code, {
        'Content-Type': type,
        'Content-Length': buf.length,
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      });
      res.end(req.method === 'HEAD' ? undefined : buf);
      log(`${req.method} ${pathname} ${code}`);
    };

    try {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        send(405, '# 405 — method not allowed\n', MARKDOWN_TYPE);
        return;
      }
      if (pathname === '/favicon.ico') {
        res.writeHead(204);
        res.end();
        log(`${req.method} ${pathname} 204`);
        return;
      }

      // --- choose the mount, and the path WITHIN it -------------------------
      let mount;
      let prefix = '';
      let subPath = pathname;

      if (single) {
        mount = table[0];
        if (pathname === '/' || pathname === '/index.md') {
          send(200, await indexMarkdown(mount.root, ''), MARKDOWN_TYPE);
          return;
        }
      } else {
        if (pathname === '/' || pathname === '/index.md') {
          send(200, await rootIndexMarkdown(table), MARKDOWN_TYPE);
          return;
        }
        const rest = pathname.replace(/^\/+/, '');
        const slash = rest.indexOf('/');
        const seg = slash === -1 ? rest : rest.slice(0, slash);
        mount = byLabel.get(seg);
        if (!mount) {
          // Not a mount — which includes '..' and every other first-segment
          // traversal attempt, so those never reach a filesystem call at all.
          send(404, NOT_FOUND_MD(pathname, '/'), MARKDOWN_TYPE);
          return;
        }
        prefix = '/' + mount.label;
        if (slash === -1) {
          // /<label> -> /<label>/ so relative links from the index resolve.
          const to = prefix + '/';
          res.writeHead(301, { Location: to, 'Cache-Control': 'no-store' });
          res.end();
          log(`${req.method} ${pathname} 301`);
          return;
        }
        subPath = rest.slice(slash); // begins with '/'
        if (subPath === '/' || subPath === '/index.md') {
          send(200, await indexMarkdown(mount.root, prefix), MARKDOWN_TYPE);
          return;
        }
      }

      const root = mount.root; // this request's root, and no other
      let relPath = subPath;
      let resolved = safeResolve(root, relPath);
      if (resolved === null) {
        send(403, FORBIDDEN_MD(prefix + '/'), MARKDOWN_TYPE);
        return;
      }

      const isFile = (p) => {
        try { return fs.statSync(p).isFile(); } catch { return false; }
      };

      // Accept the name without its extension too: /notes -> /notes.md
      if (!ALLOWED_EXT.test(relPath) || !isFile(resolved)) {
        const altRel = relPath.replace(/\/+$/, '') + '.md';
        const alt = ALLOWED_EXT.test(relPath) ? null : safeResolve(root, altRel);
        if (alt === null && !ALLOWED_EXT.test(relPath)) {
          send(403, FORBIDDEN_MD(prefix + '/'), MARKDOWN_TYPE);
          return;
        }
        if (alt && isFile(alt)) {
          resolved = alt;
          relPath = altRel;
        } else {
          send(404, NOT_FOUND_MD(pathname, prefix + '/'), MARKDOWN_TYPE);
          return;
        }
      }

      if (!ALLOWED_EXT.test(relPath) || !isFile(resolved)) {
        send(404, NOT_FOUND_MD(pathname, prefix + '/'), MARKDOWN_TYPE);
        return;
      }

      const bytes = await fsp.readFile(resolved); // raw bytes, unmodified
      send(200, bytes, MARKDOWN_TYPE);
    } catch (err) {
      send(500, '# 500 — error\n\n`' + String(err && err.message).replace(/`/g, "'") +
        '`\n', MARKDOWN_TYPE);
    }
  });

  server.listen(port, host, () => {
    const bound = server.address();
    const shownPort = bound && typeof bound === 'object' ? bound.port : port;
    const wide = host === '0.0.0.0' || host === '::' || host === '';
    if (single) {
      log(`serve-docs: serving ${table[0].root}`);
    } else {
      log(`serve-docs: serving ${table.length} projects`);
      for (const m of table) log(`serve-docs:   /${m.label}/  ->  ${m.root}`);
    }
    log(`serve-docs: bound to ${host}:${shownPort}`);
    if (wide) {
      log('serve-docs: EXPOSED to every host that can reach this machine on ' +
        'this port — no authentication, no TLS, no access log beyond stdout.');
      for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
        for (const a of addrs || []) {
          if (a.family === 'IPv4' && !a.internal) {
            log(`serve-docs:   reachable at http://${a.address}:${shownPort}/  (${name})`);
          }
        }
      }
    } else {
      log('serve-docs: loopback only — nothing outside this machine can reach ' +
        'it. Pass --host 0.0.0.0 to expose it on the local network.');
      log(`serve-docs:   http://${host === '::1' ? '[::1]' : host}:${shownPort}/`);
    }
    log('serve-docs: Ctrl-C to stop.');
    if (onListen) onListen(server);
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.error(`serve-docs: port ${port} is already in use. Pass --port <n>.`);
    } else if (err.code === 'EADDRNOTAVAIL') {
      console.error(`serve-docs: cannot bind host ${host} on this machine.`);
    } else {
      console.error('serve-docs: ' + err.message);
    }
    process.exit(1);
  });

  return server;
}

// -------------------------------------------------------------- self-test --

/** Raw request: `path` is sent verbatim, without client-side normalisation. */
function rawRequest(port, rawPath, method = 'GET') {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host: '127.0.0.1', port, path: rawPath, method },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({
          status: res.statusCode,
          type: res.headers['content-type'],
          location: res.headers.location,
          body: Buffer.concat(chunks).toString('utf8'),
        }));
      }
    );
    req.on('error', reject);
    req.end();
  });
}

async function selfTest() {
  const cases = [];
  const t = (name, ok, detail) => cases.push({ name, ok: !!ok, detail });
  const skips = [];

  // --- a temporary served tree, plus a secret OUTSIDE it -------------------
  const base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'serve-docs-')));
  const root = path.join(base, 'docs');
  const outside = path.join(base, 'outside');
  fs.mkdirSync(root);
  fs.mkdirSync(outside);
  fs.writeFileSync(path.join(outside, 'secret.md'), '# SECRET\n');

  const bodyA = '# Alpha\n\nSee [beta](beta.md). Emoji ⭐ 🔴 ⚠️ ✅ and <script>x</script>.\n';
  fs.writeFileSync(path.join(root, 'alpha.md'), bodyA, 'utf8');
  fs.writeFileSync(path.join(root, 'beta.md'), '# Beta\n');
  fs.writeFileSync(path.join(root, 'notes.txt'), 'not markdown\n');
  fs.writeFileSync(path.join(root, 'data.json'), '{}\n');
  fs.mkdirSync(path.join(root, 'sub'));
  fs.writeFileSync(path.join(root, 'sub', 'inner.md'), '# Inner\n');
  // make alpha the newest
  const now = Date.now();
  fs.utimesSync(path.join(root, 'beta.md'), new Date(now - 60000), new Date(now - 60000));
  fs.utimesSync(path.join(root, 'sub', 'inner.md'), new Date(now - 30000), new Date(now - 30000));

  // A link inside the tree pointing outward. A file symlink needs privilege on
  // Windows; a directory junction does not, so fall back to one — the escape
  // being tested is the same either way.
  let symlinkMade = false;
  let junctionMade = false;
  try {
    fs.symlinkSync(path.join(outside, 'secret.md'), path.join(root, 'escape.md'), 'file');
    symlinkMade = true;
  } catch {
    try {
      fs.symlinkSync(outside, path.join(root, 'linkdir'), 'junction');
      junctionMade = true;
    } catch {
      skips.push('link-out-of-tree (this machine allows neither a symlink nor a junction)');
    }
  }

  // --- unit: safeResolve ---------------------------------------------------
  t('traversal: ordinary file resolves', safeResolve(root, '/alpha.md') !== null);
  t('traversal: file in a subdirectory resolves', safeResolve(root, '/sub/inner.md') !== null);
  t('traversal: ../ refused', safeResolve(root, '/../outside/secret.md') === null);
  t('traversal: deep ../../ refused', safeResolve(root, '/sub/../../outside/secret.md') === null);
  t('traversal: bare ".." refused', safeResolve(root, '/..') === null);
  t('traversal: many ../ refused', safeResolve(root, '/../../../../etc/passwd') === null);
  t('traversal: backslash ..\\ refused', safeResolve(root, '/..\\outside\\secret.md') === null ||
    process.platform !== 'win32');
  t('traversal: drive-qualified path refused', safeResolve(root, '/C:/Windows/win.ini') === null);
  t('traversal: NUL byte refused', safeResolve(root, '/alpha.md\0.png') === null);
  t('traversal: leading slash means the served root, not the filesystem root',
    String(safeResolve(root, '/etc/passwd')).startsWith(root + path.sep));
  t('traversal: missing file resolves, so the caller can 404 not 403',
    safeResolve(root, '/nope.md') !== null);
  if (symlinkMade) {
    t('traversal: symlink pointing out of the tree refused',
      safeResolve(root, '/escape.md') === null);
  }
  if (junctionMade) {
    t('traversal: directory junction pointing out of the tree refused',
      safeResolve(root, '/linkdir/secret.md') === null);
  }

  // --- unit: mount-label validation ---------------------------------------
  const badLabels = [
    ['a forward slash', 'a/b'],
    ['a backslash', 'a\\b'],
    ['..', '..'],
    ['a dot-dot inside', 'a..b'],
    ['a single dot', '.'],
    ['a drive letter', 'C:'],
    ['a space', 'my project'],
    ['an empty label', ''],
    ['a percent-encoded slash', 'a%2fb'],
    ['a NUL byte', 'a\0b'],
    ['a colon', 'a:b'],
  ];
  for (const [what, label] of badLabels) {
    let threw = false;
    try { validateLabel(label); } catch { threw = true; }
    t(`label validation: ${what} rejected`, threw, JSON.stringify(label));
  }
  for (const good of ['docs', 'my-project', 'my_project', 'a.b', 'A1']) {
    let ok = true;
    try { validateLabel(good); } catch { ok = false; }
    t(`label validation: ${JSON.stringify(good)} accepted`, ok);
  }
  {
    let threw = false;
    try { buildMounts([`a/b=${root}`]); } catch { threw = true; }
    t('label validation: a bad label is a startup error, not a bare path', threw);
  }

  // --- two more projects, for the multi-project cases ----------------------
  const projB = path.join(base, 'beta-project');
  fs.mkdirSync(projB);
  fs.writeFileSync(path.join(projB, 'private.md'), '# PRIVATE\n');
  fs.writeFileSync(path.join(projB, 'readme.md'), '# B readme\n');
  const projC = path.join(base, 'proj-c', 'docs');
  fs.mkdirSync(projC, { recursive: true });
  fs.writeFileSync(path.join(projC, 'c1.md'), '# C one\n');
  // b is the newest project, then a, then c
  fs.utimesSync(path.join(projB, 'private.md'), new Date(now), new Date(now));
  fs.utimesSync(path.join(projB, 'readme.md'), new Date(now), new Date(now));
  fs.utimesSync(path.join(root, 'alpha.md'), new Date(now - 10000), new Date(now - 10000));
  fs.utimesSync(path.join(projC, 'c1.md'), new Date(now - 120000), new Date(now - 120000));

  // --- derived labels, and duplicates -------------------------------------
  t('derived label: taken from the folder name',
    deriveLabel(projB) === 'beta-project', deriveLabel(projB));
  t("derived label: a generic 'docs' folder takes its PARENT's name",
    deriveLabel(projC) === 'proj-c', deriveLabel(projC));
  {
    const m = buildMounts([projB, `alpha=${root}`]);
    t('mounts: a bare --dir still mounts, under its derived label',
      m.length === 2 && m[0].label === 'beta-project', m[0] && m[0].label);
    t('mounts: an explicit label wins over the derived one', m[1].label === 'alpha', m[1].label);
  }
  {
    let msg = '';
    try { buildMounts([projC, path.join(base, 'proj-c', 'docs')]); } catch (e) { msg = e.message; }
    t('duplicate labels are a startup error', /duplicate mount label/.test(msg), msg);
    const esc = projC.replace(/[\\^$.*+?()[\]{}|]/g, '\\$&');
    t('the duplicate error names both paths',
      (msg.match(new RegExp(esc, 'g')) || []).length >= 2, msg);
  }
  {
    let msg = '';
    try { buildMounts([`x=${root}`, `x=${projB}`]); } catch (e) { msg = e.message; }
    t('duplicate EXPLICIT labels are a startup error too',
      /duplicate mount label/.test(msg) && msg.includes(root) && msg.includes(projB), msg);
  }

  // --- the server: single-project mode (behaviour must be unchanged) -------
  const server = startServer({ dir: root, port: 0, host: '127.0.0.1', quiet: true });
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;

  try {
    const index = await rawRequest(port, '/');
    t('index: 200', index.status === 200, index.status);
    t('index: served as markdown', index.type === MARKDOWN_TYPE, index.type);
    t('index: lists every .md file',
      index.body.includes('(/alpha.md)') && index.body.includes('(/beta.md)') &&
      index.body.includes('(/sub/inner.md)'), index.body);
    t('index: excludes non-markdown files',
      !index.body.includes('notes.txt') && !index.body.includes('data.json'), index.body);
    t('index: newest modified first',
      index.body.indexOf('(/alpha.md)') < index.body.indexOf('(/sub/inner.md)') &&
      index.body.indexOf('(/sub/inner.md)') < index.body.indexOf('(/beta.md)'), index.body);
    t('index: shows a modified time and a size',
      /\d{4}-\d{2}-\d{2} \d{2}:\d{2} · \d+(\.\d+)? (B|KB|MB)/.test(index.body), index.body);
    t('single-project mode: / is the DOCUMENT index, not a project index',
      index.body.startsWith('# Documents'), index.body.slice(0, 40));
    t('single-project mode: index links carry no mount prefix',
      !/\(\/[A-Za-z0-9._-]+\/alpha\.md\)/.test(index.body), index.body);

    const doc = await rawRequest(port, '/alpha.md');
    t('document: 200', doc.status === 200, doc.status);
    t('document: content-type is text/markdown; charset=utf-8',
      doc.type === MARKDOWN_TYPE, doc.type);
    t('document: bytes are served verbatim, unrendered', doc.body === bodyA, doc.body);
    t('document: markup in the source is NOT escaped or converted',
      doc.body.includes('<script>x</script>') && !doc.body.includes('&lt;'), doc.body);
    t('document: non-ASCII survives as UTF-8', doc.body.includes('⭐ 🔴 ⚠️ ✅'), doc.body);

    const nested = await rawRequest(port, '/sub/inner.md');
    t('document: subdirectory document served', nested.status === 200 &&
      nested.body === '# Inner\n', nested.status);

    const noExt = await rawRequest(port, '/alpha');
    t('document: name without the .md extension is accepted',
      noExt.status === 200 && noExt.body === bodyA, noExt.status);

    const missing = await rawRequest(port, '/nope.md');
    t('404: missing document', missing.status === 404, missing.status);
    t('404: real page, not a stack trace',
      missing.body.startsWith('# 404') && !missing.body.includes('at Object.'), missing.body);
    t('404: still markdown', missing.type === MARKDOWN_TYPE, missing.type);

    for (const [label, p] of [
      ['.txt', '/notes.txt'],
      ['.json', '/data.json'],
      ['.md.txt suffix trick', '/alpha.md.txt'],
      ['extensionless with no .md twin', '/notes'],
    ]) {
      const r = await rawRequest(port, p);
      t(`allowlist: ${label} refused with 404`, r.status === 404, `${p} -> ${r.status}`);
    }

    const dirReq = await rawRequest(port, '/sub');
    t('no directory listing below the index', dirReq.status === 404, dirReq.status);
    const dirSlash = await rawRequest(port, '/sub/');
    t('no directory listing for a trailing slash', dirSlash.status === 404, dirSlash.status);

    // traversal over the wire, with paths the client cannot normalise away
    for (const [label, p] of [
      ['encoded ../', '/%2e%2e/outside/secret.md'],
      ['encoded ..%2f', '/..%2foutside%2fsecret.md'],
      ['raw ../', '/../outside/secret.md'],
      ['deep ../../', '/sub/../../outside/secret.md'],
      ['double-encoded backslash', '/..%5coutside%5csecret.md'],
    ]) {
      const r = await rawRequest(port, p);
      const leaked = r.body.includes('SECRET');
      t(`traversal over HTTP: ${label} refused`, r.status === 403 || r.status === 404,
        `${p} -> ${r.status}`);
      t(`traversal over HTTP: ${label} leaks nothing`, !leaked, r.body.slice(0, 120));
    }
    if (symlinkMade) {
      const r = await rawRequest(port, '/escape.md');
      t('traversal over HTTP: outward symlink refused with 403', r.status === 403, r.status);
      t('traversal over HTTP: outward symlink leaks nothing',
        !r.body.includes('SECRET'), r.body.slice(0, 120));
      t('index: outward symlink not listed', !index.body.includes('escape.md'), index.body);
    }
    if (junctionMade) {
      const r = await rawRequest(port, '/linkdir/secret.md');
      t('traversal over HTTP: outward junction refused with 403', r.status === 403, r.status);
      t('traversal over HTTP: outward junction leaks nothing',
        !r.body.includes('SECRET'), r.body.slice(0, 120));
      t('index: content behind an outward junction not listed',
        !index.body.includes('linkdir'), index.body);
    }

    const post = await rawRequest(port, '/alpha.md', 'POST');
    t('non-GET refused with 405', post.status === 405, post.status);
  } finally {
    server.close();
    await new Promise((r) => server.once('close', r));
  }

  // --- the server: multi-project mode --------------------------------------
  const mounts = buildMounts([`alpha=${root}`, `beta=${projB}`, projC]);
  const mserver = startServer({ mounts, port: 0, host: '127.0.0.1', quiet: true });
  await new Promise((r) => mserver.once('listening', r));
  const mport = mserver.address().port;

  try {
    const rootIdx = await rawRequest(mport, '/');
    t('root index: 200 markdown',
      rootIdx.status === 200 && rootIdx.type === MARKDOWN_TYPE, `${rootIdx.status} ${rootIdx.type}`);
    t('root index: is a list of projects', rootIdx.body.startsWith('# Projects'),
      rootIdx.body.slice(0, 40));
    t('root index: links every mounted project',
      rootIdx.body.includes('(/alpha/)') && rootIdx.body.includes('(/beta/)') &&
      rootIdx.body.includes('(/proj-c/)'), rootIdx.body);
    t('root index: newest-modified project first',
      rootIdx.body.indexOf('(/beta/)') < rootIdx.body.indexOf('(/alpha/)') &&
      rootIdx.body.indexOf('(/alpha/)') < rootIdx.body.indexOf('(/proj-c/)'), rootIdx.body);
    t('root index: shows a document count and a modified time',
      /2 documents · \d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(rootIdx.body), rootIdx.body);
    t('root index: lists projects, not documents',
      !rootIdx.body.includes('alpha.md') && !rootIdx.body.includes('private.md'), rootIdx.body);

    const aIdx = await rawRequest(mport, '/alpha/');
    t('project index: 200', aIdx.status === 200, aIdx.status);
    t('project index: links are prefixed with the mount label',
      aIdx.body.includes('(/alpha/alpha.md)') && aIdx.body.includes('(/alpha/sub/inner.md)'), aIdx.body);
    t("project index: lists ONLY its own project's documents",
      !aIdx.body.includes('private.md') && !aIdx.body.includes('readme.md') &&
      !aIdx.body.includes('c1.md'), aIdx.body);

    const bIdx = await rawRequest(mport, '/beta/');
    t('project index: a second project lists only its own documents',
      bIdx.body.includes('(/beta/private.md)') && !bIdx.body.includes('alpha.md'), bIdx.body);

    const cIdx = await rawRequest(mport, '/proj-c/');
    t('project index: a bare --dir is reachable under its derived label',
      cIdx.status === 200 && cIdx.body.includes('(/proj-c/c1.md)'), cIdx.status);

    const noSlash = await rawRequest(mport, '/alpha');
    t('project root without a trailing slash redirects to /<label>/',
      noSlash.status === 301 && noSlash.location === '/alpha/',
      `${noSlash.status} ${noSlash.location}`);

    const aDoc = await rawRequest(mport, '/alpha/alpha.md');
    t('mounted document: served verbatim', aDoc.status === 200 && aDoc.body === bodyA, aDoc.status);
    t('mounted document: still text/markdown', aDoc.type === MARKDOWN_TYPE, aDoc.type);
    const aNested = await rawRequest(mport, '/alpha/sub/inner.md');
    t('mounted document: subdirectory path works',
      aNested.status === 200 && aNested.body === '# Inner\n', aNested.status);
    const aNoExt = await rawRequest(mport, '/alpha/alpha');
    t('mounted document: extensionless name still accepted',
      aNoExt.status === 200 && aNoExt.body === bodyA, aNoExt.status);
    const aMissing = await rawRequest(mport, '/alpha/nope.md');
    t('mounted 404: back-link points at this project, not the root',
      aMissing.status === 404 && aMissing.body.includes('](/alpha/)'), aMissing.body);

    // A relative link inside a document — [beta](beta.md) in /alpha/alpha.md —
    // resolves to /alpha/beta.md by the browser's own URL rules. Resolve it the
    // same way the browser would, then confirm that URL serves the right file.
    const relTarget = new URL('beta.md', `http://127.0.0.1:${mport}/alpha/alpha.md`).pathname;
    t('relative link inside a document stays within its own mount',
      relTarget === '/alpha/beta.md', relTarget);
    const relDoc = await rawRequest(mport, relTarget);
    t('relative link inside a document serves the right file',
      relDoc.status === 200 && relDoc.body === '# Beta\n', relDoc.status);

    // A link that points OUT of its own project: the browser normalises it
    // before it is ever sent, so it arrives as an ordinary path naming another
    // mount — a plain cross-project link, not a traversal.
    const outLink = new URL('../beta/private.md', `http://127.0.0.1:${mport}/alpha/alpha.md`).pathname;
    t('a link out of its own project is normalised by the browser to another mount',
      outLink === '/beta/private.md', outLink);
    const outAbove = new URL('../../etc/passwd', `http://127.0.0.1:${mport}/alpha/alpha.md`).pathname;
    t('a link above every mount cannot climb past the site root',
      outAbove === '/etc/passwd', outAbove);
    const outAboveRes = await rawRequest(mport, outAbove);
    t('a link above every mount lands on an unknown label and 404s',
      outAboveRes.status === 404, outAboveRes.status);

    // --- cross-project traversal, which must never reach another root ------
    for (const [label, p] of [
      ['raw ../', '/alpha/../beta/private.md'],
      ['encoded ..%2f', '/alpha/..%2fbeta%2fprivate.md'],
      ['encoded %2e%2e/', '/alpha/%2e%2e/beta/private.md'],
      ['deep ../../', '/alpha/sub/../../beta/private.md'],
      ['leading %2e%2e', '/%2e%2e/beta/private.md'],
      ['backslash', '/alpha/..%5cbeta%5cprivate.md'],
      ['out of every root', '/alpha/../../outside/secret.md'],
      ['unknown label', '/nosuchproject/private.md'],
      ['a drive letter as the label', '/C:/Windows/win.ini'],
    ]) {
      const r = await rawRequest(mport, p);
      t(`cross-project traversal: ${label} refused`, r.status === 403 || r.status === 404,
        `${p} -> ${r.status}`);
      t(`cross-project traversal: ${label} leaks nothing`,
        !r.body.includes('PRIVATE') && !r.body.includes('SECRET'), r.body.slice(0, 120));
    }

    const foreign = await rawRequest(mport, '/alpha/private.md');
    t("another project's document is not reachable under this mount",
      foreign.status === 404 && !foreign.body.includes('PRIVATE'), foreign.status);

    const mPost = await rawRequest(mport, '/alpha/alpha.md', 'POST');
    t('multi-project: non-GET refused with 405', mPost.status === 405, mPost.status);
  } finally {
    mserver.close();
    await new Promise((r) => mserver.once('close', r));
    fs.rmSync(base, { recursive: true, force: true });
  }

  let failed = 0;
  for (const c of cases) {
    if (!c.ok) failed++;
    console.log((c.ok ? 'PASS  ' : 'FAIL  ') + c.name +
      (c.ok ? '' : '\n        got: ' + String(c.detail).slice(0, 400)));
  }
  for (const s of skips) console.log('SKIP  ' + s);
  console.log('');
  console.log(`${cases.length - failed}/${cases.length} cases passed` +
    (failed ? `, ${failed} FAILED` : '') +
    (skips.length ? `, ${skips.length} skipped` : ''));
  return failed === 0 ? 0 : 1;
}

// -------------------------------------------------------------------- CLI --

const USAGE = `
serve-docs — serve folders of markdown documents over HTTP as raw markdown.

Usage:
  node serve-docs.mjs --dir <path> [options]
  node serve-docs.mjs --dir <label>=<path> --dir <label>=<path> [options]
  node serve-docs.mjs --self-test
  node serve-docs.mjs --help

Options:
  --dir <path>          Directory of .md files to serve. Repeatable.
  --dir <label>=<path>  The same, mounted at /<label>/. A label must match
                        [A-Za-z0-9._-]+ — it becomes a URL path segment, so a
                        path separator, '..' or a drive letter is a startup
                        error, as is the same label twice.
  --port <n>         Port to listen on. Default ${DEFAULT_PORT}.
  --host <addr>      Address to bind. Default ${DEFAULT_HOST} (loopback only).
                     Use 0.0.0.0 to expose it on the local network, or a
                     specific interface address to expose only that one.
  --open-to <cidr>   Shorthand for a wider bind: implies --host 0.0.0.0 and
                     records the network you mean to expose it to. It is a
                     label printed at startup, not a firewall — no address
                     filtering is performed.
  --self-test        Run the built-in checks (path-traversal refusals including
                     cross-project ones, label validation, the extension
                     allowlist, content types, both indexes and the 404 path),
                     printing pass/fail per case, and exit non-zero on any
                     failure.
  --help             This text.

Routing:
  * ONE bare --dir behaves exactly as it always has: / is the document index,
    documents sit at /<file>.md, and nothing is prefixed.
  * Otherwise / is an index of projects, newest-modified first; each project's
    document index is at /<label>/ and its documents at /<label>/<file>.md.
  * With no label one is derived from the folder's own name — or from the
    PARENT folder's name when the folder is called docs/doc/documentation/md,
    since every project's is.

Notes:
  * Documents are served as raw bytes with 'Content-Type: text/markdown;
    charset=utf-8'. Nothing is parsed or rewritten — rendering is the browser
    markdown extension's job. Relative links between documents already work,
    because the routes mirror the directory layout under each mount.
  * Only .md files are served, plus the indexes. Everything else is a 404, and
    anything resolving outside ITS OWN project directory is a 403 — one project
    is never reachable by traversing out of another.
  * There is no authentication and no TLS. A wider bind exposes these
    documents to anyone who can reach this machine on that port.
`;

function parseArgs(argv) {
  const opts = {
    dirs: [], port: DEFAULT_PORT, host: DEFAULT_HOST, openTo: null,
    help: false, selfTest: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case '--dir': case '-d': opts.dirs.push(next()); break;
      case '--port': case '-p': opts.port = Number(next()); break;
      case '--host': opts.host = next(); break;
      case '--open-to': opts.openTo = next(); opts.host = '0.0.0.0'; break;
      case '--self-test': opts.selfTest = true; break;
      case '--help': case '-h': opts.help = true; break;
      default:
        if (a.startsWith('-')) {
          console.error(`serve-docs: unknown option ${a}`);
          console.error(USAGE);
          process.exit(2);
        }
        opts.dirs.push(a);
    }
  }
  return opts;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) { console.log(USAGE); return; }
  if (opts.selfTest) { process.exit(await selfTest()); }

  if (!opts.dirs.length) {
    console.error('serve-docs: --dir is required.');
    console.error(USAGE);
    process.exit(2);
  }
  if (opts.dirs.some((d) => d === undefined)) {
    console.error('serve-docs: --dir needs a value.');
    process.exit(2);
  }
  if (!Number.isInteger(opts.port) || opts.port < 0 || opts.port > 65535) {
    console.error('serve-docs: --port must be an integer between 1 and 65535.');
    process.exit(2);
  }
  if (opts.openTo) {
    console.log(`serve-docs: --open-to ${opts.openTo} — binding 0.0.0.0. ` +
      'This is a label, not a firewall; no address filtering is applied.');
  }

  // A single bare --dir keeps the original routing, so every invocation,
  // bookmark and relative link that works today is untouched.
  const singleBare = opts.dirs.length === 1 && !String(opts.dirs[0]).includes('=');
  if (singleBare) {
    const dir = path.resolve(opts.dirs[0]);
    if (!fs.existsSync(dir)) {
      console.error(`serve-docs: --dir does not exist: ${dir}`);
      process.exit(2);
    }
    if (!fs.statSync(dir).isDirectory()) {
      console.error(`serve-docs: --dir is not a directory: ${dir}`);
      process.exit(2);
    }
    startServer({ dir, port: opts.port, host: opts.host });
    return;
  }

  let mounts;
  try {
    mounts = buildMounts(opts.dirs);
  } catch (err) {
    console.error('serve-docs: ' + err.message);
    process.exit(2);
  }
  startServer({ mounts, port: opts.port, host: opts.host });
}

main();

export {
  safeResolve, indexMarkdown, rootIndexMarkdown, startServer, selfTest,
  buildMounts, deriveLabel, validateLabel, parseDirSpec,
};
