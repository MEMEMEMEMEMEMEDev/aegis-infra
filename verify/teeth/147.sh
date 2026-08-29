# teeth for check 147 (every FROM of the seed comes from the internal
# registry by digest, or is a declared exception).
# Written on 2026-08-29 with `aegis image` and the from-guard stage.
#
# The check has two halves and both are mutated here: the STATIC one
# over the seed's Containerfiles —including the lock on the recorte,
# which is the half that rots if nobody watches it— and the RUNTIME one,
# the from-guard of the tenant template, whose absence is exactly the
# shape of the hole this whole change came to close.
JT="seed/platform/docs/protocols/templates/Jenkinsfile.app"

# a Containerfile arrives in the seed pulling from the open internet.
# It is the 2026-08-27 canary bug, reintroduced somewhere new: nothing
# about that image went through our scan or our key, and the failure
# would surface at admission, in a tenant, with a message about
# signatures that says nothing about a Containerfile.
red_1() {
    cat > "$AEGIS_ROOT/seed/platform/mirror-images/Containerfile" <<'EOF'
FROM docker.io/library/busybox:1.36
CMD ["/bin/true"]
EOF
}

# the same thing one notch subtler: OUR registry, but by tag. The pull
# works, the build is green, and what it built on is whatever the tag
# pointed at this morning — while Kyverno verifies a digest.
red_2() {
    cat > "$AEGIS_ROOT/seed/platform/mirror-images/Containerfile" <<'EOF'
FROM registry.registry-system.svc.cluster.local:5000/alpine:3.21
CMD ["/bin/true"]
EOF
}

# THE LOCK on the recorte. A file declared as a known hole stops being
# one: the row now describes nothing, and the next Containerfile that
# lands on that path inherits a free pass nobody granted it. Check 199's
# lesson, applied to a different allowlist.
red_3() {
    cat > "$AEGIS_ROOT/seed/canary/Containerfile" <<'EOF'
FROM registry.registry-system.svc.cluster.local:5000/golang:1.26.6-alpine@sha256:3889b425f035be855a72fb4755265311293b6d414521f0a519d819df32222d83 AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -o /hello-aegis .

FROM registry.registry-system.svc.cluster.local:5000/alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d
COPY --from=build /hello-aegis /usr/local/bin/hello-aegis
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/hello-aegis"]
EOF
}

# the guard disappears from the tenant template. This is the hole in its
# original size: every app on the platform free to build on a base
# nobody mirrored, and the only complaint arriving at admission.
red_4() {
    python3 - "$AEGIS_ROOT/$JT" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
a = t.index("    stage('from-guard') {")
b = t.index("    stage('build') {")
open(p, "w").write(t[:a] + t[b:])
PY
}

# the guard stays but stops verifying the signature. Mirrored and signed
# are two different facts: this leaves the first measured and the second
# assumed, which is the assumption Kyverno does not share.
red_5() {
    python3 - "$AEGIS_ROOT/$JT" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert t.count("cosign verify --key from-cosign.pub") == 1
open(p, "w").write(t.replace("cosign verify --key from-cosign.pub", "true --key from-cosign.pub", 1))
PY
}

# the digest's LENGTH check is weakened. `@sha256:deadbeef` is not a
# digest and it would pass: the reference looks pinned and pins nothing.
red_6() {
    python3 - "$AEGIS_ROOT/$JT" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
assert t.count("[ ${#D} -eq 64 ]") == 1
open(p, "w").write(t.replace("[ ${#D} -eq 64 ]", "[ ${#D} -gt 0 ]", 1))
PY
}

# the guard is moved to AFTER the build. It then guards an image that
# already exists, built on the very base it was supposed to refuse.
red_7() {
    python3 - "$AEGIS_ROOT/$JT" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = t.index("    stage('from-guard') {")
b = t.index("    stage('build') {")
c = t.index("    stage('scan') {")
guard, build = t[a:b], t[b:c]
open(p, "w").write(t[:a] + build + guard + t[c:])
PY
}

# control: a comment that QUOTES a FROM from the internet — several
# Containerfiles explain in prose which base they came from and why.
# A mention is not a use; it is the class checks 22, 25, 66 and 71 paid
# for already.
control_1() {
    printf '\n# it used to say FROM docker.io/library/alpine:3.21, and §0 tells why it does not any more\n' \
        >> "$AEGIS_ROOT/seed/canary/Containerfile"
}

# control: a new Containerfile that DOES honour the rule — the positive
# path, which today has no subject in the tree and would otherwise never
# be exercised.
control_2() {
    cat > "$AEGIS_ROOT/seed/platform/mirror-images/Containerfile" <<'EOF'
FROM registry.registry-system.svc.cluster.local:5000/alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d AS base
RUN true
FROM base
CMD ["/bin/true"]
EOF
}

# control: the exempt classes may grow a member. A new ci-images tool
# still cannot be built out of the registry phase 80 has not filled yet.
control_3() {
    mkdir -p "$AEGIS_ROOT/seed/platform/ci-images/jq"
    cat > "$AEGIS_ROOT/seed/platform/ci-images/jq/Containerfile" <<'EOF'
FROM alpine:3.22
RUN apk add --no-cache jq && jq --version
EOF
}

# control: a comment added inside the from-guard stage changes nothing
# about what it measures.
control_4() {
    python3 - "$AEGIS_ROOT/$JT" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = t.index("    stage('from-guard') {")
open(p, "w").write(t[:a] + "    // a legitimate comment about the stage below\n" + t[a:])
PY
}
