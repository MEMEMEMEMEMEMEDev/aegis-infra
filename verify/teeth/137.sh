# teeth for check 137 (ci-images builds every Containerfile it ships)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# The seed built two of its four tooling images until 2026-08-27: a
# directory that looks like an image and never becomes one.
CI="seed/platform/ci-images"

# a fifth image appears with no build_push: it never gets pushed
red_1() {
    mkdir -p "$AEGIS_ROOT/$CI/foo"
    printf 'FROM registry.registry-system.svc.cluster.local:5000/alpine:3.22\nRUN true\n' > "$AEGIS_ROOT/$CI/foo/Containerfile"
}
# the node line disappears: the directory stays, the image stops existing
red_2() {
    python3 - "$AEGIS_ROOT/$CI/Jenkinsfile" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^\s*build_push\s+node\s.*\n", "", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# control: a comment naming a build_push that does not exist is not a call
control_1() {
    python3 - "$AEGIS_ROOT/$CI/Jenkinsfile" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
anchor = "          build_push cosign aegis-ci-cosign cosign\n"
assert anchor in t
open(p, "w").write(t.replace(anchor, "          # (do not add: build_push zzz aegis-ci-zzz zzz is the retired one)\n" + anchor, 1))
PY
}
