// __ORG__-app — the initial HTTP service of the __ORG__ organization.
//
// It was born from aegis's `service-node` template and from that moment
// on it is YOURS: the template never touches it again. Zero external
// dependencies on purpose (node's stdlib serves HTTP): an empty
// dependency tree is a tree that does not rot, and nothing here has to
// be explained to Trivy.
//
// The only thing the platform asks of this process is that it listen on
// the port the contract declares (8080, and on 0.0.0.0 — a server bound
// to localhost is unreachable from the kubelet's probe and from the
// edge) and answer /healthz, which the readinessProbe polls.
import { createServer } from 'node:http'
import { hostname } from 'node:os'

export function handle(req, res) {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'text/plain' })
    return res.end('ok\n')
  }
  res.writeHead(200, { 'content-type': 'text/plain' })
  res.end(`__ORG__ — initial app of the service-node template, pod ${hostname()}\n`)
}

// Only when it is executed, so the tests can import `handle` without
// binding a port.
if (process.argv[1] && process.argv[1].endsWith('server.js')) {
  createServer(handle).listen(8080, '0.0.0.0')
}
