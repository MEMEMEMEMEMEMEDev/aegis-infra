// build.mjs — the placeholder build: it copies src/ to dist/.
//
// It exists so the template BUILDS AND DEPLOYS the day it is
// instantiated, with an empty dependency tree (nothing to scan, nothing
// to rot), and so the Containerfile's BUILD_CMD/OUT_DIR pair has
// something real to point at from the first build.
//
// It is meant to be REPLACED. Run `npm create astro@latest`, or vite,
// or the Angular CLI, inside this repo: that overwrites package.json
// and this file, and the only thing you may have to touch in the
// Containerfile is the two ARGs at the top.
import { cp, rm } from 'node:fs/promises'

await rm('dist', { recursive: true, force: true })
await cp('src', 'dist', { recursive: true })
console.log('dist/ written from src/')
