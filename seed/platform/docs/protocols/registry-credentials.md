# Protocol: the registry's credentials (htpasswd + regcreds)

Settles C9/C10 in part and encodes A27: htpasswd and its 4
derivatives are ONE credential with 5 faces — they are generated
TOGETHER or they drift apart (real v1 case: 6 days of mismatch →
401 on the first push).

## Golden rule

**One origin, one process, one commit.** The init makes it
structural (`derive_htpasswd_and_regcreds` in lib/secrets.sh); by
hand, EVERYTHING in the same shell before any unset/exit.

## Manual flow (if the init is not used)

    mkdir -p /dev/shm/regcred && cd /dev/shm/regcred
    openssl rand -base64 32 | tr -d '\n' > pass    # → Bitwarden
    # htpasswd bcrypt via STDIN (never the password in argv —
    # /proc/PID/cmdline is readable):
    htpasswd -nBi aegis-dev < pass > htpasswd
    # dockerconfigjson with jq --rawfile (same idea: never argv):
    jq -n --rawfile p pass --arg u aegis-dev \
      --arg h registry.registry-system.svc.cluster.local:5000 \
      '{auths:{($h):{username:$u,password:$p,
        auth:(($u+":"+$p)|@base64)}}}' > dockerconfig.json

Afterwards, FOR EACH destination (registry-system/htpasswd + the 4
regcreds: jenkins-system, argocd, kyverno, org-personal): kubectl
--from-file → mv to the repo's path → sops -e --in-place →
roundtrip. ONE commit with the 5 files.

## Notes

- `data:` always (byte-preserving); the v1 laptop protocol used
  stringData for the htpasswd — it worked because bcrypt is ASCII
  with no folding, but v2 unifies: data/--from-file ALWAYS (a rule
  with no exceptions is worth more than the explanation of the
  exception).
- Inherited debt, taken knowingly: htpasswd is all-or-nothing (no
  pull/push separation). Trigger for splitting it: the first
  non-trusted tenant / Hetzner (token-based auth, a big lift).
- The defining test of the creds is client→server for real (a push
  and a pull), not `--get-login` and not a green plan.
