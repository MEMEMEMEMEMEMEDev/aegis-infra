# teeth for check 138 (every base aegis owns keeps its contract)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# aegis-base-nginx is the member the seed ships; each red breaks one
# clause of the contract its consumers assume.
CF="seed/platform/base-images/nginx/Containerfile"

# USER by name: PSS restricted cannot prove runAsNonRoot and rejects the pod
red_1() {
    python3 - "$AEGIS_ROOT/$CF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^USER 101\s*$", "USER nginx", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# no EXPOSE: the image starts on whatever port and never receives a request
red_2() {
    python3 - "$AEGIS_ROOT/$CF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^EXPOSE 8080\s*\n", "", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# FROM the internet: a base standing on a digest nobody mirrored or signed
red_3() {
    python3 - "$AEGIS_ROOT/$CF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^FROM \S+/alpine:3\.22\s*$", "FROM alpine:3.22", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# the END sentinel goes: aegis-org has no closed block to rewrite
red_4() {
    python3 - "$AEGIS_ROOT/seed/platform/base-images/consumers.txt" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "# --- END DERIVED ---\n"
assert old in t
open(p, "w").write(t.replace(old, "", 1))
PY
}
# control: a LABEL is metadata, not contract
control_1() { printf 'LABEL org.opencontainers.image.vendor="aegis"\n' >> "$AEGIS_ROOT/$CF"; }
