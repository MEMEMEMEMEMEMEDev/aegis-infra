// write-digest.mjs — pins the overlay's images BY DIGEST.
//
// Usage:  node ci/write-digest.mjs <image>=<digest> [<image>=<digest> ...]
//
// WHY BY DIGEST AND NOT BY TAG. Kyverno rewrites the image, adding the
// verified digest to it when it admits the pod. With a TAG in git, what
// is deployed and what is desired differ ALWAYS, and to keep ArgoCD from
// sitting OutOfSync forever the `image` field had to be ignored — which
// TURNED OFF the auto-sync: if the only difference is the image and the
// image is ignored, ArgoCD sees nothing to do and nothing gets deployed.
// Measured on 2026-08-03: 4 syncs in 8 days, all of them for structural
// changes, none for a new image.
//
// With the digest in git Kyverno's mutation is a no-op (verified at
// admission: input identical to output), there is no drift, nothing has
// to be ignored, and the auto-sync comes back.
//
// It is a file and not a heredoc inside the Jenkinsfile on purpose: an
// indented heredoc never ends, and Groovy's `sh '''...'''` fights with
// the script's quotes. Here it can also be tested without CI.
import { readFileSync, writeFileSync } from 'node:fs'

const OVERLAY_FILE = process.env.OVERLAY ?? 'k8s/overlays/dev/kustomization.yaml'

const byImage = new Map()
for (const arg of process.argv.slice(2)) {
  const i = arg.indexOf('=')
  if (i < 0) {
    console.error(`argument without an '=': ${arg}`)
    process.exit(2)
  }
  const name = arg.slice(0, i)
  const digest = arg.slice(i + 1)
  // An empty or malformed digest would write rubbish into git and
  // leave the pod in ImagePullBackOff. It stops here.
  if (!/^sha256:[0-9a-f]{64}$/.test(digest)) {
    console.error(`invalid digest for ${name}: ${JSON.stringify(digest)}`)
    process.exit(2)
  }
  byImage.set(name, digest)
}
if (byImage.size === 0) {
  console.error('nothing to write')
  process.exit(2)
}

const lines = readFileSync(OVERLAY_FILE, 'utf8').split('\n')
const written = new Set()
let awaiting = null

const out = lines.map((line) => {
  const m = line.match(/^(\s*)-\s*name:\s*(\S+)\s*$/)
  if (m) {
    awaiting = byImage.has(m[2]) ? m[2] : null
    return line
  }
  // What gets replaced is the line that FOLLOWS the `name:` that
  // matched. It works both for `newTag:` (the first deploy) and for
  // `digest:` (every one after), so running it twice changes nothing.
  if (awaiting && /^\s*(newTag|digest):/.test(line)) {
    const indent = line.match(/^\s*/)[0]
    const replacement = `${indent}digest: ${byImage.get(awaiting)}`
    written.add(awaiting)
    awaiting = null
    return replacement
  }
  return line
})

// If an image does not appear in the overlay, the deploy would stay on
// the old version WITH NOBODY SAYING SO. That is exactly the kind of
// silent failure this change exists to eliminate, so it stops here.
const missing = [...byImage.keys()].filter((n) => !written.has(n))
if (missing.length) {
  console.error(`I could not find these images in ${OVERLAY_FILE}:`)
  for (const n of missing) console.error(`  - ${n}`)
  process.exit(1)
}

writeFileSync(OVERLAY_FILE, out.join('\n'))
for (const [n, d] of byImage) console.log(`  ${n} -> ${d}`)
