# v2 secrets convention

Consolidates the rules that lived scattered in v1 (settles C4/C7/C8).

## Classification

- **TYPE 1** (known): public certs, domains, host keys,
  pins, account IDs → declarative in git, from an official source.
- **TYPE 2** (secret): tokens, private keys, passwords → SOPS+age,
  a flow with the operator. Sub-classes: T2-A (self-generable:
  `openssl rand`, `ssh-keygen`, `age-keygen`, `cosign
  generate-key-pair`) and T2-E (issued by a third party).
- **NEVER TOFU** (trust on first use): StrictHostKeyChecking=no,
  insecure-skip-tls-verify, accept-first-connection and keyscan
  in init containers are all forbidden.

## Hard rules (each one was born out of an incident)

1. K8s Secrets through byte-preserving `data:` (`kubectl create
   secret --from-file --dry-run=client -o yaml`). NEVER a
   hand-built `stringData`: YAML folding adds 1 byte and breaks
   HMACs.
2. **SOPS: `mv` to the repo path FIRST, `sops -e --in-place`
   AFTER.** The creation_rule matches by path_regex; /dev/shm does
   not match. ALWAYS validate with a `sops -d | head -c1` roundtrip.
3. Cleartext material ONLY in tmpfs (/dev/shm), chmod 700, shred on
   the way out. Never /tmp, never the repo, never the home.
4. Secrets NEVER in argv (`/proc/PID/cmdline` is readable):
   `--from-file`, `htpasswd -nBi` (stdin), `jq --rawfile`.
5. Never print values — not even base64. Shape checks: length ONLY
   (`wc -c` over a file). `kubectl get secret <n>` without `-o`.
6. Shared credentials (htpasswd↔regcreds, HMAC↔webhook): ONE
   origin, derivation in the SAME process, ONE commit.
7. A Secret's `type` is IMMUTABLE: to change it, `kubectl delete` +
   selfHeal recreates it from git. Never a permanent Replace=true
   on the App.
8. KSOPS generators: an EXPLICIT LIST of files. An App that is
   Synced+Healthy does NOT guarantee the Secrets — ALWAYS validate
   `kubectl get secret` after the sync.
9. The age key: a custom path (`~/.config/sops/age/aegis.key`),
   never `keys.txt`; `SOPS_AGE_KEY_FILE` exported EXPLICITLY in
   every non-interactive shell (direnv does not reach in there).
10. The deliberate-exposure exception: the CEREMONY (age, cosign)
    shows the value ONCE for the operator to back up, with a RED
    gate before and roundtrip validation after. It is the only one.
11. The irreplaceable ones (age, cosign, write key): a VALIDATED
    backup (a canary encrypted/signed with the backed-up copy), not
    a verbal confirmation.
12. On the host side: python3+pyyaml, not yq. Revert/cleanup steps
    NEVER with `&&`.
