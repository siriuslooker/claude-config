#!/usr/bin/env node
// lan-bridge — make a loopback-only dev site reachable from another machine,
//              and (optionally) break it on purpose.
//
// WHY THIS EXISTS. IIS Express registers its port with http.sys under a wildcard
// binding but answers ONLY for a hostname it recognises; any other Host header gets
// a bare `400 Bad Request` from http.sys before the application sees the request. So
// a site that works perfectly at http://localhost:PORT/ returns 400 to every request
// that arrives at the machine's LAN address, and there is no application-level fix.
//
// The rewrite below IS the whole mechanism: forward the request verbatim except for
// the `Host` header, which becomes the loopback name the target already accepts.
//
// WHY A BRIDGE RATHER THAN RECONFIGURING THE SITE. It is purely additive. The
// existing loopback workflow keeps working untouched, nothing needs elevation (a
// high port needs no urlacl), and the original port cannot be reused anyway — http.sys
// holds it via the wildcard registration, so binding <lan-address>:<same-port> fails
// with EACCES. A bridge must therefore listen on a DIFFERENT port, which is why the
// mapping is `listenPort:targetPort` and not just a list of ports.
//
// WHY FAULT INJECTION LIVES HERE. QA is driven from a phone, and no mobile browser has
// DevTools network throttling. Two checks need a slow or non-responding save: a save
// indicator that only appears when a save is genuinely slow, and a client-side save
// timeout that must fire, release its in-flight guard, and let autosave recover. Doing
// it in the proxy is deterministic and repeatable — "exactly 5000ms on PUT /api/save"
// rather than "slow 3G, roughly" — and the application code stays untouched.
//
// ⚠️ NO ADDRESSES LIVE IN THIS FILE. Every host, port and pairing is a runtime
// argument. This file is version-controlled in a public repository; keep it that way.
//
// Node standard library only — no dependencies, so it runs from anywhere with a Node
// on PATH and never needs an install step.
//
// USAGE
//   node lan-bridge.mjs [options] <listenPort:targetPort> [<listenPort:targetPort> ...]
//
//   --bind <address>        address to listen on            (default 0.0.0.0)
//   --target-host <name>    Host header + connect target    (default localhost)
//   --timeout <ms>          upstream socket timeout         (default 120000)
//   --skip-preflight        start even if a target is dead  (default: refuse)
//
//   fault injection — all off by default; --affect is REQUIRED to arm either fault
//   --delay <ms>            wait this long before forwarding a matching request
//   --hang                  accept a matching request and never answer it
//   --affect <pattern>      substring, or glob (* ?) matched against the whole path
//   --affect-method <verb>  further narrow by method; repeatable or comma-separated
//   --hang-max <n>          most sockets to hold at once     (default 64)
//
//   --self-test             run the built-in tests and exit
//
// EXAMPLE
//   node lan-bridge.mjs 14965:54965 15914:55914
//     -> anything reaching this machine on 14965 is served by localhost:54965
//
//   node lan-bridge.mjs --delay 5000 --affect "/api/maps/*" --affect-method PUT 14965:54965
//     -> only the save PUT is slowed; page, bundle and GETs stay fast
//
// EXIT CODES
//   0 clean shutdown   1 bad arguments   2 a target was not answering   3 listen failed

import http from 'node:http'
import net from 'node:net'

// ----------------------------------------------------------------- arguments

function usage(message) {
  if (message) console.error(`lan-bridge: ${message}\n`)
  console.error(
    'usage: node lan-bridge.mjs [--bind <address>] [--target-host <name>]\n' +
      '                          [--timeout <ms>] [--skip-preflight]\n' +
      '                          [--delay <ms>] [--hang] [--hang-max <n>]\n' +
      '                          [--affect <pattern>] [--affect-method <verb>]\n' +
      '                          <listenPort:targetPort> [<listenPort:targetPort> ...]\n' +
      '       node lan-bridge.mjs --self-test'
  )
  process.exit(1)
}

/**
 * Compile an --affect pattern into a predicate over the request path.
 *
 * A pattern containing `*` or `?` is a glob anchored to the WHOLE path (`*` = any run
 * of characters, `?` = exactly one); anything else is a plain substring test, which is
 * what you want for `--affect /api/save`. Matching is case-insensitive and runs against
 * the path only, with any query string stripped — a save that carries `?v=3` should not
 * need the pattern to know about it.
 */
function compileAffect(pattern) {
  const p = String(pattern).toLowerCase()
  if (!/[*?]/.test(p)) return (path) => path.toLowerCase().includes(p)
  const rx = new RegExp(
    '^' +
      p
        .replace(/[.+^${}()|[\]\\]/g, '\\$&')
        .replace(/\*/g, '.*')
        .replace(/\?/g, '.') +
      '$'
  )
  return (path) => rx.test(path.toLowerCase())
}

function parseArgs(argv) {
  const opts = {
    bind: '0.0.0.0',
    targetHost: 'localhost',
    timeout: 120_000,
    preflight: true,
    pairs: [],
    // fault injection
    delay: 0,
    hang: false,
    hangMax: 64,
    affect: undefined,
    affectMethods: undefined,
  }

  const methods = []

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    const next = () => {
      const v = argv[++i]
      if (v === undefined) usage(`${arg} needs a value`)
      return v
    }

    if (arg === '--bind') opts.bind = next()
    else if (arg === '--target-host') opts.targetHost = next()
    else if (arg === '--timeout') {
      opts.timeout = Number(next())
      if (!Number.isFinite(opts.timeout) || opts.timeout < 0) usage('--timeout must be a number of ms')
    } else if (arg === '--skip-preflight') opts.preflight = false
    else if (arg === '--delay') {
      opts.delay = Number(next())
      if (!Number.isFinite(opts.delay) || opts.delay < 0) usage('--delay must be a number of ms')
    } else if (arg === '--hang') opts.hang = true
    else if (arg === '--hang-max') {
      opts.hangMax = Number(next())
      if (!Number.isInteger(opts.hangMax) || opts.hangMax < 1) usage('--hang-max must be a positive integer')
    } else if (arg === '--affect') opts.affect = next()
    else if (arg === '--affect-method') {
      methods.push(
        ...next()
          .split(',')
          .map((m) => m.trim())
          .filter(Boolean)
      )
    } else if (arg === '--self-test') {
      /* handled before main; accepted here so it is never an "unknown option" */
    } else if (arg === '-h' || arg === '--help') usage()
    else if (arg.startsWith('-')) usage(`unknown option ${arg}`)
    else {
      const m = /^(\d+):(\d+)$/.exec(arg)
      if (!m) usage(`'${arg}' is not a listenPort:targetPort pair`)
      const listen = Number(m[1])
      const target = Number(m[2])
      for (const p of [listen, target]) {
        if (p < 1 || p > 65535) usage(`port ${p} is out of range`)
      }
      // A pair mapping a port onto itself is almost certainly a typo, and on Windows
      // it is the exact case that cannot work (see the EACCES note at the top).
      if (listen === target) usage(`${arg} maps a port onto itself`)
      opts.pairs.push({ listen, target })
    }
  }

  if (opts.pairs.length === 0) usage('at least one listenPort:targetPort pair is required')

  const seen = new Set()
  for (const { listen } of opts.pairs) {
    if (seen.has(listen)) usage(`listen port ${listen} appears more than once`)
    seen.add(listen)
  }

  // 🔴 A fault with no --affect is REFUSED rather than defaulted to "everything".
  // Delaying every request by 30s means the HTML and the bundle never arrive, so the
  // page you were trying to test never loads — the feature would look broken while
  // doing exactly what it was told. "Affect nothing" is the safe default, and saying
  // so at startup beats silently doing nothing.
  if ((opts.hang || opts.delay > 0) && opts.affect === undefined) {
    usage('--delay/--hang need --affect <pattern>; without it they would slow the page and bundle too')
  }
  if (opts.hang && opts.delay > 0) usage('--hang and --delay are mutually exclusive')

  opts.affectMatch = opts.affect === undefined ? () => false : compileAffect(opts.affect)
  if (methods.length > 0) opts.affectMethods = new Set(methods.map((m) => m.toUpperCase()))

  return opts
}

// Does this request qualify for the configured fault? Nothing qualifies unless a fault
// is armed AND the path matches AND (if given) the method matches.
function faultApplies(req, opts) {
  if (!opts.hang && !(opts.delay > 0)) return false
  const path = (req.url ?? '').split('?')[0]
  if (!opts.affectMatch(path)) return false
  if (opts.affectMethods && !opts.affectMethods.has(String(req.method).toUpperCase())) return false
  return true
}

// ----------------------------------------------------------------- preflight

// Refuse to start against a dead target. A bridge that starts happily and then 502s
// every request looks like a bridge defect; the actual fault is upstream, and saying
// so at startup is the difference between a five-second diagnosis and a long one.
function probe(host, port, timeoutMs = 2000) {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port })
    const done = (ok) => {
      socket.destroy()
      resolve(ok)
    }
    socket.setTimeout(timeoutMs)
    socket.once('connect', () => done(true))
    socket.once('timeout', () => done(false))
    socket.once('error', () => done(false))
  })
}

// ------------------------------------------------------------------- forward

function stamp() {
  return new Date().toISOString().slice(11, 23)
}

/**
 * Rewrite an absolute redirect that points back at the loopback origin so the client,
 * which cannot reach loopback, follows it to this bridge instead. Without this a
 * sign-in redirect sends a remote browser to its OWN machine and the trail goes cold
 * in a way that looks nothing like a proxy problem.
 *
 * The replacement origin is taken from the request's own Host header, so the bridge
 * still knows no addresses of its own.
 */
function rewriteLocation(value, targetPort, requestHost, opts) {
  if (!value || !requestHost) return value
  const from = `//${opts.targetHost}:${targetPort}`
  return value.includes(from) ? value.split(from).join(`//${requestHost}`) : value
}

function startPair({ listen, target }, opts, hung) {
  const server = http.createServer((req, res) => {
    const requestHost = req.headers.host
    const started = Date.now()
    const fault = faultApplies(req, opts)

    // ---- hang: hold the socket, answer nothing, ever.
    if (fault && opts.hang) {
      if (hung.size >= opts.hangMax) {
        console.log(
          `${stamp()} ${listen}->${target} ${req.method} ${req.url} ` +
            `FAULT hang REFUSED — ${hung.size} already held (--hang-max ${opts.hangMax})`
        )
        res.writeHead(503, { 'content-type': 'text/plain', connection: 'close' })
        res.end('lan-bridge: hang budget exhausted\n')
        return
      }
      const socket = req.socket
      hung.add(socket)
      socket.setTimeout(0) // nothing on OUR side may close it; the client must give up
      socket.once('close', () => hung.delete(socket))
      req.resume() // drain the body so the client finishes sending, then simply waits
      console.log(
        `${stamp()} ${listen}->${target} ${req.method} ${req.url} ` +
          `FAULT hang — socket held open, no response will ever be sent (${hung.size}/${opts.hangMax})`
      )
      return
    }

    const forward = () => {
      const headers = {
        ...req.headers,
        // 🔴 THE ONE LINE THAT MATTERS. Everything else here is plumbing.
        host: `${opts.targetHost}:${target}`,
        'x-forwarded-host': requestHost ?? '',
        'x-forwarded-proto': 'http',
        'x-forwarded-for': req.socket.remoteAddress ?? '',
      }

      const upstream = http.request(
        { host: opts.targetHost, port: target, method: req.method, path: req.url, headers },
        (up) => {
          const outHeaders = { ...up.headers }
          if (outHeaders.location) {
            outHeaders.location = rewriteLocation(outHeaders.location, target, requestHost, opts)
          }
          console.log(
            `${stamp()} ${listen}->${target} ${req.method} ${req.url} ` +
              `${up.statusCode} ${Date.now() - started}ms` +
              (fault ? ` (+${opts.delay}ms injected)` : '')
          )
          res.writeHead(up.statusCode ?? 502, outHeaders)
          up.pipe(res)
        }
      )

      upstream.setTimeout(opts.timeout, () => upstream.destroy(new Error('upstream timeout')))

      upstream.on('error', (err) => {
        console.log(`${stamp()} ${listen}->${target} ${req.method} ${req.url} ERR ${err.message}`)
        if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' })
        res.end(`lan-bridge: upstream ${opts.targetHost}:${target} — ${err.message}`)
      })

      req.pipe(upstream)
    }

    // ---- delay: hold the request BEFORE forwarding, not the response after it.
    // The client sees no bytes at all during the window, which is exactly what a "save
    // is slow" indicator keys off, and the upstream is never told to wait — so a 30s
    // delay does not tie up an IIS Express worker, and the status, headers and body the
    // client eventually gets are a real response rather than a fabricated one. A client
    // that gives up (the timeout case) cancels the forward, so a save nobody is
    // listening for any more is never actually performed.
    if (fault && opts.delay > 0) {
      console.log(
        `${stamp()} ${listen}->${target} ${req.method} ${req.url} FAULT delay ${opts.delay}ms before forwarding`
      )
      const timer = setTimeout(forward, opts.delay)
      res.on('close', () => clearTimeout(timer))
      return
    }

    forward()
  })

  // Node would otherwise abort a held request itself: requestTimeout defaults to 300s
  // and headersTimeout to 60s, and either turns "never answers" into "answers with a
  // 408 eventually", which is a different test. Only relaxed when a fault is armed, so
  // an ordinary bridge keeps every stock protection.
  if (opts.hang || opts.delay > 0) {
    server.requestTimeout = 0
    server.headersTimeout = 0
    server.timeout = 0
    server.keepAliveTimeout = 0
  }

  // WebSocket / any other Upgrade, forwarded with the same Host rewrite. Cheap to
  // support and its absence would present as a feature that silently does nothing.
  // Faults are deliberately NOT applied here — an upgrade is not a save.
  server.on('upgrade', (req, clientSocket, head) => {
    const headers = { ...req.headers, host: `${opts.targetHost}:${target}` }
    const upstream = http.request({
      host: opts.targetHost,
      port: target,
      method: req.method,
      path: req.url,
      headers,
    })

    upstream.on('upgrade', (upRes, upSocket, upHead) => {
      console.log(`${stamp()} ${listen}->${target} UPGRADE ${req.url} ${upRes.statusCode}`)
      const lines = Object.entries(upRes.headers).map(([k, v]) => `${k}: ${v}`)
      clientSocket.write(`HTTP/1.1 ${upRes.statusCode} ${upRes.statusMessage}\r\n${lines.join('\r\n')}\r\n\r\n`)
      if (upHead?.length) clientSocket.unshift(upHead)
      upSocket.pipe(clientSocket)
      clientSocket.pipe(upSocket)
      upSocket.on('error', () => clientSocket.destroy())
      clientSocket.on('error', () => upSocket.destroy())
    })

    upstream.on('error', (err) => {
      console.log(`${stamp()} ${listen}->${target} UPGRADE ${req.url} ERR ${err.message}`)
      clientSocket.destroy()
    })

    if (head?.length) upstream.write(head)
    upstream.end()
  })

  server.on('error', (err) => {
    console.error(`lan-bridge: cannot listen on ${opts.bind}:${listen} — ${err.message}`)
    process.exit(3)
  })

  server.listen(listen, opts.bind, () =>
    console.log(`lan-bridge: ${opts.bind}:${listen} -> ${opts.targetHost}:${target}`)
  )

  return server
}

// A slow rig that you did this to yourself is indistinguishable from a broken one
// unless the tool says so, loudly, at the top of the log.
function banner(opts) {
  if (!opts.hang && !(opts.delay > 0)) return
  const what = opts.hang ? 'HANG — accepted, never answered' : `DELAY ${opts.delay}ms before forwarding`
  const verbs = opts.affectMethods ? [...opts.affectMethods].join(',') : 'any method'
  const line = (text) => console.log(`  ##  ${text.padEnd(56)}##`)
  console.log('')
  console.log('  ############################################################')
  line('⚠️  FAULT INJECTION IS ACTIVE ON THIS BRIDGE')
  line(what)
  line(`applied to: ${verbs} ${opts.affect}`)
  line('Everything else is forwarded normally.')
  line('Slow or stuck requests here ARE ON PURPOSE.')
  console.log('  ############################################################')
  console.log('')
  if (opts.hang) {
    console.log(`lan-bridge: at most ${opts.hangMax} sockets are held at once; past that, a match gets 503.`)
    console.log('lan-bridge: browsers cap ~6 connections per origin — hang a NARROW path or the page stalls too.')
  }
}

// ---------------------------------------------------------------------- main

async function main(argv) {
  const opts = parseArgs(argv)

  const dead = []
  if (opts.preflight) {
    for (const { target } of opts.pairs) {
      if (!(await probe(opts.targetHost, target))) dead.push(target)
    }
  }

  if (dead.length > 0) {
    console.error(
      `lan-bridge: not starting — nothing is answering on ${dead
        .map((p) => `${opts.targetHost}:${p}`)
        .join(', ')}. Start the target site first, or pass --skip-preflight.`
    )
    process.exit(2)
  }

  const hung = new Set()
  const servers = opts.pairs.map((pair) => startPair(pair, opts, hung))
  banner(opts)

  const shutdown = () => {
    // A held socket has no timeout of its own, so it would keep the event loop alive
    // and SIGINT would look ignored. Destroy them explicitly, first.
    for (const s of hung) s.destroy()
    hung.clear()
    for (const s of servers) s.close()
    process.exit(0)
  }
  process.on('SIGINT', shutdown)
  process.on('SIGTERM', shutdown)
}

// ----------------------------------------------------------------- self-test

async function selfTest() {
  let pass = 0
  const failures = []
  const check = (name, ok, detail = '') => {
    if (ok) {
      pass++
      console.log(`  ok   ${name}`)
    } else {
      failures.push(`${name}${detail ? ` — ${detail}` : ''}`)
      console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`)
    }
  }

  const freePort = () =>
    new Promise((resolve) => {
      const s = net.createServer()
      s.listen(0, '127.0.0.1', () => {
        const { port } = s.address()
        s.close(() => resolve(port))
      })
    })

  // The origin echoes back exactly what it was asked, so the Host rewrite is observable.
  const origin = http.createServer((req, res) => {
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => {
      const payload = JSON.stringify({ method: req.method, url: req.url, host: req.headers.host, body })
      res.writeHead(200, { 'content-type': 'application/json', 'x-origin': 'echo' })
      res.end(payload)
    })
  })
  const originPort = await freePort()
  await new Promise((r) => origin.listen(originPort, '127.0.0.1', r))

  const request = (port, path, { method = 'GET', headers = {}, body } = {}) =>
    new Promise((resolve, reject) => {
      const req = http.request({ host: '127.0.0.1', port, path, method, headers }, (res) => {
        let text = ''
        res.on('data', (c) => (text += c))
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: text }))
      })
      req.on('error', reject)
      req.end(body)
    })

  const quiet = console.log
  const bridges = []
  const startBridge = async (flags) => {
    const listenPort = await freePort()
    const opts = parseArgs([
      ...flags,
      '--bind',
      '127.0.0.1',
      '--target-host',
      '127.0.0.1',
      `${listenPort}:${originPort}`,
    ])
    const hung = new Set()
    console.log = () => {} // the bridge is chatty by design; the test output is not
    const server = startPair({ listen: listenPort, target: originPort }, opts, hung)
    await new Promise((r) => server.once('listening', r))
    console.log = quiet
    bridges.push({ server, hung })
    return { port: listenPort, hung }
  }

  console.log('lan-bridge self-test')

  // 1. plain forwarding, unchanged — including the Host rewrite that is the whole point
  const plain = await startBridge([])
  const direct = await request(originPort, '/thing?a=1')
  const viaBridge = await request(plain.port, '/thing?a=1', { headers: { host: 'example.invalid:9999' } })
  check(
    'plain: status and body are byte-for-byte identical to the origin',
    direct.body === viaBridge.body && direct.status === viaBridge.status,
    `${direct.body} vs ${viaBridge.body}`
  )
  check(
    'plain: Host is rewritten to the loopback target',
    JSON.parse(viaBridge.body).host === `127.0.0.1:${originPort}`,
    viaBridge.body
  )
  const stripped = (h) => {
    const { date, connection, 'keep-alive': _k, 'transfer-encoding': _t, ...rest } = h
    return JSON.stringify(rest)
  }
  check('plain: response headers pass through unchanged', stripped(direct.headers) === stripped(viaBridge.headers))
  const put = await request(plain.port, '/api/save', { method: 'PUT', body: 'payload' })
  const putEcho = JSON.parse(put.body)
  check('plain: method and request body survive', putEcho.method === 'PUT' && putEcho.body === 'payload')
  const t0 = Date.now()
  await request(plain.port, '/bundle.js')
  check('plain: nothing is delayed when no flags are given', Date.now() - t0 < 200, `${Date.now() - t0}ms`)

  // 2. delay hits the matching path only
  const delayed = await startBridge(['--delay', '400', '--affect', '/api/save'])
  const d0 = Date.now()
  const dRes = await request(delayed.port, '/api/save', { method: 'PUT', body: 'x' })
  const dMs = Date.now() - d0
  check('delay: the matching request still completes normally', dRes.status === 200 && JSON.parse(dRes.body).body === 'x')
  check('delay: it took at least the delay', dMs >= 400, `${dMs}ms`)
  const f0 = Date.now()
  await request(delayed.port, '/bundle.js')
  check('affect: a non-matching path is untouched', Date.now() - f0 < 200, `${Date.now() - f0}ms`)
  const q0 = Date.now()
  await request(delayed.port, '/api/save?v=3', { method: 'PUT' })
  check('affect: a query string does not defeat the match', Date.now() - q0 >= 400)

  // 3. glob form
  const globbed = await startBridge(['--delay', '400', '--affect', '/api/maps/*'])
  const g0 = Date.now()
  await request(globbed.port, '/api/maps/42', { method: 'PUT' })
  check('affect: a glob matches', Date.now() - g0 >= 400)
  const g1 = Date.now()
  await request(globbed.port, '/api/other/42', { method: 'PUT' })
  check('affect: a glob spares a non-matching path', Date.now() - g1 < 200)

  // 4. method narrowing
  const byMethod = await startBridge(['--delay', '400', '--affect', '/api/save', '--affect-method', 'PUT'])
  const m0 = Date.now()
  await request(byMethod.port, '/api/save', { method: 'GET' })
  check('affect-method: a GET on the same path stays fast', Date.now() - m0 < 200, `${Date.now() - m0}ms`)
  const m1 = Date.now()
  await request(byMethod.port, '/api/save', { method: 'PUT' })
  check('affect-method: the named verb is still delayed', Date.now() - m1 >= 400)

  // 5. hang
  const hanging = await startBridge(['--hang', '--affect', '/api/save', '--affect-method', 'PUT'])
  let responded = false
  const hangReq = http.request({ host: '127.0.0.1', port: hanging.port, path: '/api/save', method: 'PUT' })
  hangReq.on('error', () => {})
  hangReq.on('response', () => (responded = true))
  hangReq.end('body')
  await new Promise((r) => setTimeout(r, 700))
  const socketOpen = !!hangReq.socket && !hangReq.socket.destroyed && hangReq.socket.readable
  check('hang: no response arrives inside the window', responded === false)
  check('hang: the socket is still open — not closed, not a slow 504', socketOpen)
  check('hang: the bridge is tracking the held socket', hanging.hung.size === 1, `size=${hanging.hung.size}`)
  const hf = Date.now()
  const other = await request(hanging.port, '/bundle.js')
  check('hang: other paths on the same bridge still serve', other.status === 200 && Date.now() - hf < 200)
  hangReq.destroy()
  await new Promise((r) => setTimeout(r, 150))
  check('hang: the held socket is released when the client gives up', hanging.hung.size === 0, `size=${hanging.hung.size}`)

  // 6. hang budget — the listener must not be exhaustible without notice
  const capped = await startBridge(['--hang', '--affect', '/api/save', '--hang-max', '1'])
  const held = http.request({ host: '127.0.0.1', port: capped.port, path: '/api/save', method: 'PUT' })
  held.on('error', () => {})
  held.end()
  await new Promise((r) => setTimeout(r, 200))
  const refused = await request(capped.port, '/api/save', { method: 'PUT' })
  check('hang: past --hang-max a match gets 503 rather than another held socket', refused.status === 503, `status=${refused.status}`)
  held.destroy()

  // 7. argument guards and pure helpers (no sockets)
  const realExit = process.exit
  const realError = console.error
  const refuses = (argv) => {
    let died = false
    process.exit = () => {
      throw new Error('exit')
    }
    console.error = () => {}
    try {
      parseArgs(argv)
    } catch {
      died = true
    }
    process.exit = realExit
    console.error = realError
    return died
  }
  check('args: --delay without --affect is refused', refuses(['--delay', '500', '1:2']))
  check('args: --hang without --affect is refused', refuses(['--hang', '1:2']))
  check('args: --hang together with --delay is refused', refuses(['--hang', '--delay', '5', '--affect', '/x', '1:2']))
  check(
    'args: --affect on its own arms nothing',
    faultApplies({ url: '/api/save', method: 'PUT' }, parseArgs(['--affect', '/api/save', '1:2'])) === false
  )
  check('args: a bridge with no fault flags matches no path at all', parseArgs(['1:2']).affectMatch('/anything') === false)
  check(
    'rewriteLocation still rewrites the loopback origin',
    rewriteLocation('http://localhost:5000/x', 5000, 'example.invalid:1', { targetHost: 'localhost' }) ===
      'http://example.invalid:1/x'
  )

  for (const b of bridges) {
    for (const s of b.hung) s.destroy()
    b.server.close()
  }
  origin.close()

  console.log('')
  console.log(`lan-bridge self-test: ${pass} passed, ${failures.length} failed`)
  for (const f of failures) console.log(`  - ${f}`)
  process.exit(failures.length === 0 ? 0 : 1)
}

if (process.argv.includes('--self-test')) await selfTest()
else await main(process.argv.slice(2))
