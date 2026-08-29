// The suite the Containerfile's `npm test` runs. It is the image's only
// gate: if it goes red the build stops and no image is produced.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { handle } from '../src/server.js'

function collect(url) {
  const chunks = []
  const res = {
    statusCode: 0,
    writeHead(code) { this.statusCode = code; return this },
    end(body) { if (body) chunks.push(body); return this },
  }
  handle({ url }, res)
  return { status: res.statusCode, body: chunks.join('') }
}

test('/healthz answers 200 — the readinessProbe depends on it', () => {
  const r = collect('/healthz')
  assert.equal(r.status, 200)
  assert.equal(r.body, 'ok\n')
})

test('the root answers 200', () => {
  assert.equal(collect('/').status, 200)
})
