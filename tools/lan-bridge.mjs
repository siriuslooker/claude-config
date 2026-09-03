#!/usr/bin/env node
// lan-bridge — make a loopback-only dev site reachable from another machine.
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
// EXAMPLE
//   node lan-bridge.mjs 14965:54965 15914:55914
//     -> anything reaching this machine on 14965 is served by localhost:54965
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
      '                          <listenPort:targetPort> [<listenPort:targetPort> ...]'
  )
  process.exit(1)
}

function parseArgs(argv) {
  const opts = {
    bind: '0.0.0.0',
    targetHost: 'localhost',
    timeout: 120_000,
    preflight: true,
    pairs: [],
  }

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
    else if (arg === '-h' || arg === '--help') usage()
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

  return opts
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

const opts = parseArgs(process.argv.slice(2))

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
function rewriteLocation(value, targetPort, requestHost) {
  if (!value || !requestHost) return value
  const from = `//${opts.targetHost}:${targetPort}`
  return value.includes(from) ? value.split(from).join(`//${requestHost}`) : value
}

function startPair({ listen, target }) {
  const server = http.createServer((req, res) => {
    const requestHost = req.headers.host
    const headers = {
      ...req.headers,
      // 🔴 THE ONE LINE THAT MATTERS. Everything else here is plumbing.
      host: `${opts.targetHost}:${target}`,
      'x-forwarded-host': requestHost ?? '',
      'x-forwarded-proto': 'http',
      'x-forwarded-for': req.socket.remoteAddress ?? '',
    }

    const started = Date.now()
    const upstream = http.request(
      { host: opts.targetHost, port: target, method: req.method, path: req.url, headers },
      (up) => {
        const outHeaders = { ...up.headers }
        if (outHeaders.location) {
          outHeaders.location = rewriteLocation(outHeaders.location, target, requestHost)
        }
        console.log(
          `${stamp()} ${listen}->${target} ${req.method} ${req.url} ` +
            `${up.statusCode} ${Date.now() - started}ms`
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
  })

  // WebSocket / any other Upgrade, forwarded with the same Host rewrite. Cheap to
  // support and its absence would present as a feature that silently does nothing.
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

// ---------------------------------------------------------------------- main

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

const servers = opts.pairs.map(startPair)

const shutdown = () => {
  for (const s of servers) s.close()
  process.exit(0)
}
process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)
