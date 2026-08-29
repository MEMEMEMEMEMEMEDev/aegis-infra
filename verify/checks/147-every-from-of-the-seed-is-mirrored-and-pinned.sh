# title: every FROM the seed ships comes from the internal registry by digest, or is a declared exception
# origin: new in v3 — 2026-08-29, the day `aegis image` gave the FROM a source and Jenkinsfile.app a guard
check() {
# THE HOLE. The platform measures everything downstream of a FROM —
# unprivileged build, blocking scan, signature by digest, admission that
# refuses what is not signed — and nothing at all upstream of it. A base
# pulled off the internet under a bare tag does not fail: it SUCCEEDS,
# with different bytes than yesterday, because the scan looks at the
# result and the result is whatever came down this morning. It is the
# same class images.md §0 tells about one level up (`a new digest is not
# a new image`), and it hid in the one place that exists to exercise
# every path: on 2026-08-27 the canary was found pulling
# `docker.io/library/alpine:3.21` straight off the internet, and it was
# the LAST thing to stop doing so.
#
# WHAT IS DEMANDED, per FROM of every Containerfile the seed ships:
#   · the internal registry AND a 64-hex digest — the registry because
#     only what went through our scan and our key may run in a tenant,
#     the digest because a tag is a mutable pointer and what Kyverno
#     verifies is a digest;
#   · or it is a reference to an earlier STAGE of the same file, which
#     is this build's own output and not a base;
#   · or it is a double-underscore placeholder of a template that has
#     not been instantiated (check 003 owns those);
#   · or the file belongs to one of the two classes below, each of which
#     CANNOT stand on the internal registry for a structural reason, not
#     for convenience.
#
# THE TWO STRUCTURAL EXCEPTIONS, with their reason:
#   · ci-images/ — phase 50 fires this job, and phase 80 is what fires
#     the mirror. The tooling that pulls, scans and signs cannot be
#     built out of the registry it exists to fill; and nothing it
#     produces runs in a tenant namespace, which is why images.md §1
#     gives it neither scan nor signature.
#   · base-images/ — images.md §3.1, measured: the public alpine:3.22
#     carried the very libcrypto3 the mirror's blocking scan refuses, so
#     a base whose whole purpose is to run `apk upgrade` on top of it
#     could never be built from a mirror it cannot enter. Check 138
#     already demands the digest pin there; demanding the registry too
#     would make the base impossible.
#
# THE RECORTE, said out loud. Two Containerfiles in the seed pull from
# the internet today and neither is this change's to fix: the canary and
# the app template are somebody else's file in the wave that brought
# `aegis image`. They are named one by one below, and the naming has a
# LOCK: a listed path that no longer exists, or that has BECOME
# compliant, turns this check red. That is deliberate and it is check
# 199's lesson — an allowlist nobody has to shrink is an allowlist that
# ends up covering a new hole. When the canary's FROM is bumped to the
# registry, the fix is one line: delete its row from EXEMPT_TODO here.
#
# AND THE RUNTIME HALF. A static rule over the seed says nothing about
# the repo of an organization, which is where the FROMs that matter get
# written. That is why Jenkinsfile.app —the template every tenant
# pipeline is derived from— carries the from-guard stage, and why it is
# demanded here: without it, this check protects seven files and leaves
# every app on the platform uncovered.
D147=""

# Derived, never copied: if the internal registry ever changes name it
# changes in lib/common.sh and this check follows.
REG="$(sed -n 's/^REGISTRY_HOST_INTERNAL="\([^"]*\)".*/\1/p' "$LIBS/common.sh" | head -1)"
[[ -n "$REG" ]] || { fail "lib/common.sh does not declare REGISTRY_HOST_INTERNAL: there is no single source to measure a FROM against"; return; }

# The classes that cannot stand on the mirror, and the files that simply
# have not been moved yet. Both are paths relative to seed/.
EXEMPT_CLASS=("platform/ci-images/" "platform/base-images/")
EXEMPT_TODO=("canary/Containerfile" "templates/base/repos/app/Containerfile")

is_exempt_class() { local p="$1" c; for c in "${EXEMPT_CLASS[@]}"; do [[ "$p" == "$c"* ]] && return 0; done; return 1; }
is_exempt_todo()  { local p="$1" c; for c in "${EXEMPT_TODO[@]}";  do [[ "$p" == "$c"  ]] && return 0; done; return 1; }

# from_refs FILE — the base references of a Containerfile: comments
# stripped, flags skipped, and the stages of the file itself taken out
# (a ref that names an earlier stage is this build's own output). It is
# the SAME reading the from-guard stage does in the pipeline; if the two
# ever disagree, the guard is the one that runs and this check is the
# one that lies.
from_refs() {
    awk '
      { sub(/#.*/, "") }
      toupper($1) == "FROM" {
          ref = ""
          for (i = 2; i <= NF; i++) { if (substr($i, 1, 2) != "--") { ref = $i; break } }
          if (NF >= 3 && toupper($(NF-1)) == "AS") stage[tolower($NF)] = 1
          if (ref != "" && !(tolower(ref) in stage)) print ref
      }' "$1"
}

# compliant FILE — 0 when every FROM of the file is the internal
# registry by 64-hex digest (or a placeholder, or a stage of its own).
compliant() {
    local f="$1" ref d n=0
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        n=$((n+1))
        [[ "$ref" == __*__ ]] && continue
        [[ "$ref" == "$REG"/*@sha256:* ]] || return 1
        d="${ref##*@sha256:}"
        [[ ${#d} -eq 64 && "$d" =~ ^[0-9a-f]+$ ]] || return 1
    done < <(from_refs "$f")
    (( n > 0 )) || return 1     # a Containerfile with no FROM is not a compliant one
    return 0
}

N147=0 ; OK147=0
while IFS= read -r f; do
    rel="${f#"$SEED/"}"
    N147=$((N147+1))
    if is_exempt_class "$rel"; then continue; fi
    if is_exempt_todo "$rel"; then
        # THE LOCK. A row that no longer describes a hole is a row that
        # will one day cover a different one.
        compliant "$f" \
            && D147="$D147 $rel is declared in EXEMPT_TODO and every FROM in it is now the internal registry by digest: delete its row from check 147, the recorte no longer has a subject;"
        continue
    fi
    bad=""
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        [[ "$ref" == __*__ ]] && continue
        if [[ "$ref" != "$REG"/* ]]; then
            bad="$bad $ref does not come from the internal registry (nothing about it went through our scan or our key: a tenant pod using it is rejected at admission);"
            continue
        fi
        if [[ "$ref" != *@sha256:* ]]; then
            bad="$bad $ref names the registry but by TAG (a mutable pointer; what Kyverno verifies is a digest);"
            continue
        fi
        d="${ref##*@sha256:}"
        [[ ${#d} -eq 64 && "$d" =~ ^[0-9a-f]+$ ]] \
            || bad="$bad $ref carries a digest that is not 64 hex characters;"
    done < <(from_refs "$f")
    if [[ -n "$bad" ]]; then D147="$D147 $rel:$bad"; else OK147=$((OK147+1)); fi
done < <(find "$SEED" -type f -name 'Containerfile*' 2>/dev/null | sort)

(( N147 > 0 )) || D147="$D147 the seed ships no Containerfile at all: this check has no subject and is measuring nothing;"

# The declared exceptions cannot outlive their subject: a path that is
# not there any more is a rule about a file nobody has.
for p in "${EXEMPT_CLASS[@]}"; do
    [[ -d "$SEED/$p" ]] || D147="$D147 the exempt class $p does not exist under seed/: the exception has no subject;"
done
for p in "${EXEMPT_TODO[@]}"; do
    [[ -f "$SEED/$p" ]] || D147="$D147 EXEMPT_TODO names $p and there is no such file: delete the row;"
done

# ── the runtime half: the guard in the tenant template ──────────────
JT="$P/docs/protocols/templates/Jenkinsfile.app"
if [[ ! -f "$JT" ]]; then
    D147="$D147 the tenant template $JT does not exist: no organization's pipeline has a from-guard;"
else
    # ORDER IS THE PROPERTY: after detect-change, so a manifest-only
    # commit does not pay for it, and BEFORE build, so nothing is
    # extracted from an image nobody scanned.
    ln_dc="$(grep -n "stage('detect-change')" "$JT" | head -1 | cut -d: -f1)"
    ln_fg="$(grep -n "stage('from-guard')"    "$JT" | head -1 | cut -d: -f1)"
    ln_bd="$(grep -n "stage('build')"         "$JT" | head -1 | cut -d: -f1)"
    if [[ -z "$ln_fg" ]]; then
        D147="$D147 Jenkinsfile.app has no from-guard stage: every app on the platform can build on a base nobody mirrored, and the failure only shows up at admission;"
    elif [[ -z "$ln_dc" || -z "$ln_bd" ]] || (( ln_fg < ln_dc || ln_fg > ln_bd )); then
        D147="$D147 the from-guard stage of Jenkinsfile.app is not between detect-change and build (guard=$ln_fg, detect-change=$ln_dc, build=$ln_bd): after build it guards an image that already exists;"
    else
        BODY="$(awk -v a="$ln_fg" -v b="$ln_bd" 'NR>=a && NR<b' "$JT" | grep -vE '^[[:space:]]*//')"
        # Each clause is one thing the guard would stop measuring if it
        # were quietly weakened.
        grep -q '@sha256:' <<< "$BODY" \
            || D147="$D147 the from-guard does not demand a digest: a FROM by tag would pass and the build would not be reproducible;"
        grep -qE '\-eq 64' <<< "$BODY" \
            || D147="$D147 the from-guard does not check the digest's length: '@sha256:deadbeef' is not a digest and would pass;"
        grep -q 'REGISTRY' <<< "$BODY" \
            || D147="$D147 the from-guard does not contrast the reference against the internal registry;"
        grep -q 'crane manifest' <<< "$BODY" \
            || D147="$D147 the from-guard does not ask the registry whether it actually SERVES that digest (a well-formed reference to nothing still fails at pull time);"
        grep -q 'cosign verify' <<< "$BODY" \
            || D147="$D147 the from-guard does not verify the signature: mirrored and signed are two different facts, and Kyverno demands the second;"
        grep -q 'exit 1' <<< "$BODY" \
            || D147="$D147 the from-guard never fails the build: a guard that only prints is a log nobody reads;"
        grep -q 'image request' <<< "$BODY" \
            || D147="$D147 the from-guard's message does not name the command that fixes it (a build that dies without the next step is a build somebody works around);"
    fi
fi

printf '    %s Containerfiles in the seed · %s compliant · %s exempt by class · %s on the recorte\n' \
    "$N147" "$OK147" "${#EXEMPT_CLASS[@]}" "${#EXEMPT_TODO[@]}"
if [[ -n "$D147" ]]; then fail "FROMs the platform cannot vouch for:$D147"
else pass "every FROM of the seed is the internal registry by digest or a declared exception, and the tenant template refuses to build on any other"; fi
}
