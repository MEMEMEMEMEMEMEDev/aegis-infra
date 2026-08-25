# github-credential — the GitHub credential of aegis v2 (D11)

## What it is

The credential Jenkins uses to scan the app's repo
(github-branch-source) is the operator's gh SESSION TOKEN
(`gh auth token`), stored as a username+password credential
(owner + token) in the KSOPS Secret `github-token` (jenkins-system).
Phase 15 of the init picks it up, automatically.

## Why it is NOT a GitHub App (decision D11, told honestly)

v1's GitHub App (aegis-ci) required: creating it in the browser
(GitHub's manifest flow DEMANDS a web redirect — there is no
headless creation), downloading the .pem, moving it by hand,
converting it PKCS#1→PKCS#8, and noting down App ID/Installation
ID. Minting PATs through the API does not exist either (neither
classic nor fine-grained). Honest conclusion: there is no way to
automate the App 100% — so it was REPLACED by what can be
automated end to end.

## Security model (read it before objecting)

- The gh token carries the operator's session scopes (broad ones).
  It lives: (a) age-encrypted in the repo (.enc.yaml), (b) as a
  Secret in jenkins-system. It is BROADER than the App — a
  trade-off accepted explicitly for dogfooding.
- Rotation: `gh auth refresh` (or a re-login) + re-running phase 15
  with `--from 15` (make_enc_secret regenerates the .enc.yaml) +
  a sync of jenkins-secrets. A single place.
- Emergency revocation: closing the gh session at github.com/
  settings/applications revokes the token everywhere.

## Upgrade path to production (once there is an SLA)

Going back to a GitHub App (better rate limits, narrower
permissions, checks API) IS the road to production — assuming the
manual browser step ONCE, outside the init: create the App by hand,
store the key as Secret `github-app-aegis-ci` (gitHubApp), and swap
`scanCredentialsId('github-token')` → App in the values. The full
v1 design is in git (this file's history and phase 15's, pre-D11).
