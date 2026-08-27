# teeth for check 138 (every base aegis owns keeps its contract)
# generated on 2026-08-27 and VERIFIED: every red was applied over a copy
# of the tree and the check went red; every control stayed green.
# aegis-base-nginx is the first member the seed ships; aegis-base-node
# the second, same day. Each red breaks one clause of the contract the
# member's consumers assume.
CF="seed/platform/base-images/nginx/Containerfile"
NF="seed/platform/base-images/node/Containerfile"

# The node teeth were written while the node member was still being
# authored. If the copy has no node/Containerfile, the tooth fabricates
# the minimal member that honours every clause — the same shape the
# real one takes (alpine by digest, addgroup 65532, apk add nodejs, a
# RUN that runs node, NODE_ENV, WORKDIR, EXPOSE 8080, numeric USER,
# ENTRYPOINT node) — and mutates that. When the real member is in the
# tree this is a no-op and the mutation lands on the real file.
# Verified both ways on 2026-08-27: first on the fabricated member, then
# on the real one the moment it landed (10/10, both profiles).
_node_member() {
    [[ -f "$AEGIS_ROOT/$NF" ]] && return 0
    mkdir -p "$(dirname "$AEGIS_ROOT/$NF")"
    cat > "$AEGIS_ROOT/$NF" <<'CF'
# aegis-base-node — fabricated by tooth 138 (the seed's member had not landed yet)
FROM public.ecr.aws/docker/library/alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce
RUN addgroup -g 65532 -S nonroot \
 && adduser -u 65532 -D -S -H -h /nonexistent -s /sbin/nologin -G nonroot -g nonroot nonroot \
 && apk upgrade --no-cache \
 && apk add --no-cache nodejs \
 && [ "$(id -u nonroot)" = 65532 ] && [ "$(id -g nonroot)" = 65532 ]
RUN node --version && node -e 'require("http"); require("crypto"); require("fs")'
ENV NODE_ENV=production
WORKDIR /app
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/usr/bin/node"]
CF
}

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
# FROM a BARE TAG on the internet: a mutable pointer, bytes nobody chose
red_3() {
    python3 - "$AEGIS_ROOT/$CF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^FROM \S+/alpine:3\.22\S*\s*$", "FROM alpine:3.22", t, count=1, flags=re.M)
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
# node member installs nodejs and never runs it: a runtime that does not
# load, or a core module the package left out, fails in four backends'
# pods instead of at build time. The whole `RUN node …` line goes, with
# any backslash continuation it may carry.
red_5() {
    _node_member
    python3 - "$AEGIS_ROOT/$NF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^RUN[ \t]+node[^\n]*(\\\n[^\n]*)*\n", "", t, count=1, flags=re.M)
assert n[1] == 1, "no `RUN node …` line to remove"
assert re.search(r"apk[ \t]+add[^&|;]*[ \t]nodejs(\s|$)", t)
open(p, "w").write(n[0])
PY
}
# node member runs as `nonroot` by NAME: the same admission rejection as
# `USER nginx`, on the other member — the uid is distroless's 65532 and
# the kubelet still cannot read /etc/passwd to learn it
red_6() {
    _node_member
    python3 - "$AEGIS_ROOT/$NF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^USER[ \t]+65532(:65532)?[ \t]*$", "USER nonroot", t, flags=re.M)
assert n[1] >= 1, "no `USER 65532` line to rename"
open(p, "w").write(n[0])
PY
}
# control: a LABEL is metadata, not contract
control_1() { printf 'LABEL org.opencontainers.image.vendor="aegis"\n' >> "$AEGIS_ROOT/$CF"; }

# control: the internal registry by tag is the OTHER legal shape (the
# mirror pins the source by digest; the tag is that instance's pointer)
control_2() {
    python3 - "$AEGIS_ROOT/$CF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
n = re.subn(r"^FROM \S+/alpine:3\.22\S*\s*$", "FROM registry.registry-system.svc.cluster.local:5000/alpine:3.22", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}
# control: a LABEL on the node member, same reason
control_3() { _node_member; printf 'LABEL org.opencontainers.image.vendor="aegis"\n' >> "$AEGIS_ROOT/$NF"; }

# control: ENV NODE_ENV=production moved up (a second copy right after
# the FROM, the original left in place). Where an ENV sits is not
# contract; that it is there is, and a duplicate does not remove it.
control_4() {
    _node_member
    python3 - "$AEGIS_ROOT/$NF" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
assert re.search(r"^ENV[ \t]+NODE_ENV=production[ \t]*$", t, flags=re.M), "no ENV NODE_ENV=production line"
n = re.subn(r"^(FROM[^\n]*\n)", r"\1ENV NODE_ENV=production\n", t, count=1, flags=re.M)
assert n[1] == 1
open(p, "w").write(n[0])
PY
}

# the platform's own Job back on a third-party base
red_7() {
    sed -i -E 's/^(\s*imagen:\s*)aegis-base-node\s*$/\1nodejs-distroless/' "$AEGIS_ROOT/seed/platform/services.yaml"
    grep -q 'imagen: nodejs-distroless' "$AEGIS_ROOT/seed/platform/services.yaml"
}
# a tag that is not of the scheme (a floating one)
red_8() {
    sed -i -E 's/^(\s*tag:\s*)"3\.22-[0-9]{6}"\s*$/\1"latest"/' "$AEGIS_ROOT/seed/platform/services.yaml"
    grep -q 'tag: "latest"' "$AEGIS_ROOT/seed/platform/services.yaml"
}
# control: the instance rewrote the sample with another build of the same shape
control_5() {
    sed -i -E 's/^(\s*tag:\s*)"3\.22-[0-9]{6}"\s*$/\1"3.22-000009"/; s/^(\s*digest:\s*)sha256:[0-9a-f]{64}\s*$/\1sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/' "$AEGIS_ROOT/seed/platform/services.yaml"
}
