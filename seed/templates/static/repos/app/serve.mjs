// serve.mjs — what serves this front: node's standard library and
// nothing else.
//
// WHY NOT nginx, WHICH IS WHAT THE PLATFORM'S OWN FRONTS RUN ON. Because
// of what the runtime FROM of this file's Containerfile is allowed to
// be. `aegis app new` resolves every template FROM against the internal
// registry, and `aegis image from` only answers for an image that sits
// there under an EXACT tag and carries a signature — which today means a
// destination of mirror-images/images.txt. aegis-base-nginx, the base
// the platform owns and its own static fronts stand on, is tagged
// `<alpine minor>-<build number>`: the number is born in each instance's
// registry, so the seed cannot name the tag, and there is no floating
// alias to ask for («No floating tag, ever» — base-images/Jenkinsfile).
// The honest alternatives were a third-party nginx pinned to a tag
// nobody in this tree has measured, or this: the node runtime that IS
// mirrored, scanned and signed, serving files with zero dependencies.
// Serving files is the smaller thing to get right of the two.
//
// SWITCHING TO aegis-base-nginx LATER IS ONE LINE and the README says
// which. It is worth doing the day this repo's build has run once: from
// `aegis org apply` onwards the repo is listed in
// base-images/consumers.txt, so the base-images job rewrites that FROM's
// digest for you on every rebuild of the base — which is the whole
// reason the platform's fronts moved onto it.

import { createServer } from 'node:http'
import { createReadStream } from 'node:fs'
import { stat } from 'node:fs/promises'
import { dirname, extname, join, normalize, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

// THE ONE KNOB, and it is the same decision nginx's `try_files` was:
//   true  — SINGLE-PAGE APP (React, Vue, Angular). A deep link like
//           /orders/7 is a route the browser resolves, not a file, so
//           what is missing has to come back as index.html.
//   false — MULTI-PAGE build (Astro, and any generator that emits one
//           .html per route). Leave it false there, or a real typo
//           answers 200 with the home page and lies to both the visitor
//           and the uptime probe.
const SPA_FALLBACK = true

// Resolved from THIS file and not from the working directory: the
// runtime image's ENTRYPOINT is node itself, so the cwd of the process
// is whatever the image declared, and a relative root would serve
// nothing with an error about a path nobody wrote.
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), 'public')

// Only what a browser asks for by default. An extension that is not
// here is served as a download rather than guessed at: a wrong
// Content-Type on a .js is a page that half-loads with no error in the
// server log.
const TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.avif': 'image/avif',
    '.ico': 'image/x-icon',
    '.txt': 'text/plain; charset=utf-8',
    '.xml': 'application/xml; charset=utf-8',
    '.webmanifest': 'application/manifest+json',
    '.woff2': 'font/woff2',
    '.woff': 'font/woff',
    '.map': 'application/json; charset=utf-8',
}

// THE PATH GUARD, and it is the only security-relevant line in this
// file. `/../../etc/passwd` and its percent-encoded spellings all become
// an absolute path after normalize(); what makes them harmless is
// comparing the RESOLVED path against ROOT and refusing anything that
// does not start inside it. Doing that check on the raw URL instead —
// looking for '..' in the text — is the version that gets bypassed.
function underRoot(pathname) {
    let decoded
    try {
        decoded = decodeURIComponent(pathname)
    } catch {
        return null             // a malformed % escape is not a path
    }
    if (decoded.includes('\0')) return null
    const abs = resolve(ROOT, '.' + normalize(decoded))
    return abs === ROOT || abs.startsWith(ROOT + sep) ? abs : null
}

async function fileFor(abs) {
    try {
        const s = await stat(abs)
        if (s.isDirectory()) return await fileFor(join(abs, 'index.html'))
        return s.isFile() ? abs : null
    } catch {
        return null
    }
}

function send(res, code, body, type = 'text/plain; charset=utf-8') {
    res.writeHead(code, { 'content-type': type, 'content-length': Buffer.byteLength(body) })
    res.end(body)
}

const server = createServer(async (req, res) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
        res.writeHead(405, { allow: 'GET, HEAD' })
        return res.end()
    }
    const pathname = new URL(req.url, 'http://localhost').pathname
    // The endpoint the readinessProbe polls. Answered before anything
    // touches the filesystem, so it keeps saying 200 while the site
    // itself is being replaced.
    if (pathname === '/healthz') return send(res, 200, 'ok\n')

    const abs = underRoot(pathname)
    if (abs === null) return send(res, 400, 'bad request\n')

    let file = await fileFor(abs)
    if (file === null && SPA_FALLBACK) file = await fileFor(join(ROOT, 'index.html'))
    if (file === null) return send(res, 404, 'not found\n')

    const type = TYPES[extname(file).toLowerCase()] || 'application/octet-stream'
    res.writeHead(200, { 'content-type': type })
    if (req.method === 'HEAD') return res.end()
    const stream = createReadStream(file)
    // A read that dies mid-response cannot be turned into a status code
    // — the headers are already gone. Dropping the socket is what tells
    // the client the body is incomplete; leaving it open is what makes
    // the browser hang for a minute and blame the network.
    stream.on('error', () => res.destroy())
    stream.pipe(res)
})

// 0.0.0.0 and not localhost: the probe and the edge both come from
// OUTSIDE the process, and a server bound to the loopback starts
// perfectly and is never reached by either. 8080 because the tenant
// NetworkPolicy admits edge -> 8080 and nothing else.
server.listen(8080, '0.0.0.0', () => console.log('serving %s on :8080', ROOT))

// SIGTERM is what the kubelet sends first. Without this handler node
// exits on the grace period's SIGKILL instead, cutting in-flight
// responses on every rollout.
process.on('SIGTERM', () => server.close(() => process.exit(0)))
