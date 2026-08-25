# teeth for check 091b (the hand-written copies vs the generator)
#
# The failure this check exists for has TWO directions, and the second
# is the one that actually happens: somebody tunes the generator and
# the copies stay behind. Both are exercised, because a check that only
# watched one of them would pass the day the real drift arrived.
CANARY="seed/platform/k8s/organizations/org-canary/routes.yaml"
NTFY="seed/platform/k8s/base/observability/routes.yaml"

# The copy drifts: a rate limit somebody «adjusted» by hand.
red_1() {
    python3 - "$AEGIS_ROOT/$CANARY" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "average: 50" in t
open(p, "w").write(t.replace("average: 50", "average: 500", 1))
PY
}

# The GENERATOR moves and nobody brings the copies along. This is the
# direction the check was born for, and the one a per-file comparison
# would never see.
red_2() {
    python3 - "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "maxRequestBodyBytes: 10485760" in t
open(p, "w").write(t.replace("maxRequestBodyBytes: 10485760",
                             "maxRequestBodyBytes: 20971520", 1))
PY
}

# A whole middleware disappears from a copy: the route keeps citing it,
# traefik ignores the dangling reference in silence and the site serves
# unprotected. Check 091 catches the dangling reference; this one
# catches that the protection stopped existing.
red_3() {
    python3 - "$AEGIS_ROOT/$NTFY" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t2 = re.sub(r'---\napiVersion: traefik\.io/v1alpha1\nkind: Middleware\n'
            r'metadata:\n  name: ntfy-cuerpo\n.*?(?=\n---\n)', '', t,
            count=1, flags=re.S)
assert t2 != t
open(p, "w").write(t2)
PY
}

# The owner label is torn off: the middleware keeps working and drops
# out of every inventory `aegis check` builds by that label.
red_4() {
    python3 - "$AEGIS_ROOT/$CANARY" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "  name: canary-ritmo\n  namespace: org-canary\n  labels: {aegis.dev/part-of: aegis-organizaciones}\n"
new = "  name: canary-ritmo\n  namespace: org-canary\n"
assert old in t
open(p, "w").write(t.replace(old, new, 1))
PY
}

# Prose is not the contract: the copies deliberately do NOT transcribe
# the generator's comments, and rewording them must not turn anything
# red — a check that cries wolf about comments gets silenced.
control_1() {
    printf '\n# legitimate comment: rewritten during the translation\n' \
        >> "$AEGIS_ROOT/$CANARY"
}

# The canary's route serves `hello-aegis:80` instead of the
# `<org>-<service>:8080` convention, ON PURPOSE. Touching what is
# deliberately different must stay green, or the check would be
# demanding a uniformity the design rejected.
control_2() {
    python3 - "$AEGIS_ROOT/$CANARY" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert "{name: hello-aegis, port: 80}" in t
open(p, "w").write(t.replace("{name: hello-aegis, port: 80}",
                             "{name: hello-aegis, port: 8080}", 1))
PY
}
