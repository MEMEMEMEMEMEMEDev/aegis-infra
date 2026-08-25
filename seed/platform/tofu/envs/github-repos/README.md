# RETIRED — D10 (2026-07-07)

This env is NOT used. The GitHub side left tofu entirely:
- working repos: phase 12 of the init CREATES them (gh repo create,
  idempotent through the `aegis-v2-disposable` marker)
- settings (B4 delete_branch_on_merge=false, squash): gh api PATCH
  in phase 12, with a real gate against the API
- ArgoCD webhook (+HMAC): gh api --input in phase 15 (the secret
  never touches argv)

Why: with the repos pre-created by gh, tofu here contributed only an
extra state, a PAT of its own (removed from the flow) and the problem
of importing existing repos. gh api does the same thing, idempotently
and without state. tofu v2 is left Cloudflare-only.

The .tf files stay as `.retired-d10` (history, not active config).
